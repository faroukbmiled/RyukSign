//
//  TweakModels.swift
//  RyukSign
//
//  Extracted from TweakManager.swift for maintainability.
//

import Foundation
import NimbleExtensions
import Zip
import OSLog

enum TweakFileType: String, Codable, Equatable {
	case dylib
	case deb
	case framework
	case bundle
	/// Not injected via a load command — dropped into `PlugIns/` and re-signed as a child of the host.
	case appex
	case other

	init(fileExtension ext: String) {
		switch ext.lowercased() {
		case "dylib": self = .dylib
		case "deb": self = .deb
		case "framework": self = .framework
		case "bundle": self = .bundle
		case "appex": self = .appex
		default: self = .other
		}
	}

	var systemImage: String {
		switch self {
		case .dylib: 		return "doc.badge.gearshape"
		case .deb: 			return "shippingbox"
		case .framework: 	return "square.stack.3d.up"
		case .bundle: 		return "cube"
		case .appex: 		return "puzzlepiece.extension.fill"
		case .other: 		return "doc"
		}
	}

	var displayName: String {
		switch self {
		case .dylib: 		return "Dylib"
		case .deb: 			return "Debian Package"
		case .framework: 	return "Framework"
		case .bundle: 		return "Bundle"
		case .appex: 		return "App Extension"
		case .other: 		return "File"
		}
	}

	/// App extensions are placed, not injected, so they skip path/folder/targeting config.
	var isInjectable: Bool { self != .appex && self != .other }
}

/// Where a tweak's dylib load command should be written.
enum ExtensionTargeting: Codable, Equatable {
	case mainOnly
	/// Main binary + every app extension.
	case all
	/// Main binary + only the named extensions (appex bundle names).
	case selected([String])
}

/// Per-tweak injection config. When `useCustom` is false, the global
/// `Options.injectPath`/`injectFolder` are used.
struct TweakInjectConfig: Codable, Equatable {
	var useCustom: Bool
	var injectPath: Options.InjectPath?
	var injectFolder: Options.InjectFolder?
	var targeting: ExtensionTargeting

	static let `default` = TweakInjectConfig(
		useCustom: false,
		injectPath: nil,
		injectFolder: nil,
		targeting: .mainOnly
	)
}

/// User-created folder for organising the library. Cosmetic only — no effect on injection.
struct TweakFolder: Codable, Identifiable, Equatable {
	var id: UUID
	var name: String
	var dateAdded: Date

	init(id: UUID = UUID(), name: String, dateAdded: Date = Date()) {
		self.id = id
		self.name = name
		self.dateAdded = dateAdded
	}
}

/// One file in a tweak version. A version can bundle several (e.g. a `.deb` plus
/// two `.dylib`s), each with its own injection config.
struct TweakComponent: Codable, Identifiable, Equatable {
	var id: UUID
	var fileName: String
	var fileType: TweakFileType
	var fileSize: Int64
	var isEnabled: Bool
	/// Per-file override; `nil` inherits the tweak's `config`.
	var config: TweakInjectConfig?

	init(
		id: UUID = UUID(),
		fileName: String,
		fileType: TweakFileType,
		fileSize: Int64,
		isEnabled: Bool = true,
		config: TweakInjectConfig? = nil
	) {
		self.id = id
		self.fileName = fileName
		self.fileType = fileType
		self.fileSize = fileSize
		self.isEnabled = isEnabled
		self.config = config
	}
}

struct TweakVersion: Codable, Identifiable, Equatable {
	var id: UUID
	var label: String
	var dateAdded: Date
	/// Always at least one.
	var components: [TweakComponent]

	init(
		id: UUID = UUID(),
		label: String,
		dateAdded: Date = Date(),
		components: [TweakComponent]
	) {
		self.id = id
		self.label = label
		self.dateAdded = dateAdded
		self.components = components
	}

	// MARK: Derived

	var primaryComponent: TweakComponent? { components.first }
	/// Drives the row icon.
	var fileType: TweakFileType { primaryComponent?.fileType ?? .other }
	var fileSize: Int64 { components.reduce(0) { $0 + $1.fileSize } }
	var enabledComponents: [TweakComponent] { components.filter { $0.isEnabled } }
	/// Single file name, or "N files".
	var displaySummary: String {
		switch components.count {
		case 0: 	return ""
		case 1: 	return components[0].fileName
		default: 	return String.localized("%lld files", arguments: components.count)
		}
	}

	// MARK: Migration

	// Older libraries stored one file per version — decode the new `components` array
	// or synthesize a single component from the legacy keys.
	enum CodingKeys: String, CodingKey {
		case id, label, dateAdded, components
		case fileName, fileType, fileSize // legacy single-file
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		self.label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
		self.dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()

		if let comps = try c.decodeIfPresent([TweakComponent].self, forKey: .components) {
			self.components = comps
		} else if
			let fileName = try c.decodeIfPresent(String.self, forKey: .fileName),
			let fileType = try c.decodeIfPresent(TweakFileType.self, forKey: .fileType)
		{
			let fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
			self.components = [TweakComponent(fileName: fileName, fileType: fileType, fileSize: fileSize)]
		} else {
			self.components = []
		}
	}

	func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		try c.encode(id, forKey: .id)
		try c.encode(label, forKey: .label)
		try c.encode(dateAdded, forKey: .dateAdded)
		try c.encode(components, forKey: .components)
	}
}

struct ManagedTweak: Codable, Identifiable, Equatable {
	var id: UUID
	var name: String
	var notes: String?
	var dateAdded: Date
	var isEnabled: Bool
	var versions: [TweakVersion]
	/// `nil` resolves to the most recently added version.
	var selectedVersionId: UUID?
	/// Inject into every app that gets signed.
	var injectByDefault: Bool
	/// Allow list when `injectByDefault` is off, exclusion list when it is on.
	var autoInjectBundleIds: [String]
	/// Library-level injection defaults.
	var config: TweakInjectConfig
	/// `nil` = uncategorized. Optional so pre-folders libraries still decode.
	var folderId: UUID?

	init(
		id: UUID = UUID(),
		name: String,
		notes: String? = nil,
		dateAdded: Date = Date(),
		isEnabled: Bool = true,
		versions: [TweakVersion] = [],
		selectedVersionId: UUID? = nil,
		injectByDefault: Bool = false,
		autoInjectBundleIds: [String] = [],
		config: TweakInjectConfig = .default,
		folderId: UUID? = nil
	) {
		self.id = id
		self.name = name
		self.notes = notes
		self.dateAdded = dateAdded
		self.isEnabled = isEnabled
		self.versions = versions
		self.selectedVersionId = selectedVersionId
		self.injectByDefault = injectByDefault
		self.autoInjectBundleIds = autoInjectBundleIds
		self.config = config
		self.folderId = folderId
	}

	/// The active version (selected, else newest by date).
	var activeVersion: TweakVersion? {
		if
			let selectedVersionId,
			let match = versions.first(where: { $0.id == selectedVersionId })
		{
			return match
		}
		return versions.sorted { $0.dateAdded > $1.dateAdded }.first
	}

	var hasAutoRule: Bool {
		injectByDefault || !autoInjectBundleIds.isEmpty
	}

	func autoInjects(into bundleId: String?) -> Bool {
		guard let bundleId else { return injectByDefault }
		let listed = autoInjectBundleIds.contains { $0.caseInsensitiveCompare(bundleId) == .orderedSame }
		return injectByDefault ? !listed : listed
	}
}

/// One resolved file inside a sign-time injection, with its effective config.
struct TweakInjectionFile: Codable, Equatable, Identifiable {
	var id: UUID
	var fileURL: URL
	var fileName: String
	var fileType: TweakFileType
	var enabled: Bool
	var config: TweakInjectConfig

	init(
		id: UUID = UUID(),
		fileURL: URL,
		fileName: String,
		fileType: TweakFileType,
		enabled: Bool = true,
		config: TweakInjectConfig
	) {
		self.id = id
		self.fileURL = fileURL
		self.fileName = fileName
		self.fileType = fileType
		self.enabled = enabled
		self.config = config
	}
}

/// A resolved injection for one sign — a tweak (or ad-hoc pick) and its files.
/// Lives only on the per-sign working copy of `Options`.
struct TweakInjectionSpec: Codable, Equatable, Identifiable {
	var id: UUID
	var displayName: String
	var enabled: Bool
	var isManaged: Bool
	var files: [TweakInjectionFile]

	init(
		id: UUID = UUID(),
		displayName: String,
		enabled: Bool = true,
		isManaged: Bool,
		files: [TweakInjectionFile]
	) {
		self.id = id
		self.displayName = displayName
		self.enabled = enabled
		self.isManaged = isManaged
		self.files = files
	}

	// Tolerate the old single-file shape (`fileURL` + `config`) so a stale per-sign
	// value never breaks `Options` decoding.
	enum CodingKeys: String, CodingKey {
		case id, displayName, enabled, isManaged, files
		case fileURL, config // legacy single-file
	}

	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		self.displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
		self.enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
		self.isManaged = try c.decodeIfPresent(Bool.self, forKey: .isManaged) ?? true

		if let files = try c.decodeIfPresent([TweakInjectionFile].self, forKey: .files) {
			self.files = files
		} else if
			let url = try c.decodeIfPresent(URL.self, forKey: .fileURL),
			let config = try c.decodeIfPresent(TweakInjectConfig.self, forKey: .config)
		{
			self.files = [TweakInjectionFile(
				fileURL: url,
				fileName: url.lastPathComponent,
				fileType: TweakFileType(fileExtension: url.pathExtension),
				enabled: true,
				config: config
			)]
		} else {
			self.files = []
		}
	}

	func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		try c.encode(id, forKey: .id)
		try c.encode(displayName, forKey: .displayName)
		try c.encode(enabled, forKey: .enabled)
		try c.encode(isManaged, forKey: .isManaged)
		try c.encode(files, forKey: .files)
	}

	var enabledFiles: [TweakInjectionFile] { files.filter { $0.enabled } }
}

// MARK: - Tolerant decoding
// A field missing from older saved data defaults on its own instead of dropping the record.

extension TweakFolder {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
		dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
	}
}

extension TweakInjectConfig {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		useCustom = try c.decodeIfPresent(Bool.self, forKey: .useCustom) ?? false
		injectPath = try c.decodeIfPresent(Options.InjectPath.self, forKey: .injectPath)
		injectFolder = try c.decodeIfPresent(Options.InjectFolder.self, forKey: .injectFolder)
		targeting = try c.decodeIfPresent(ExtensionTargeting.self, forKey: .targeting) ?? .mainOnly
	}
}

extension TweakComponent {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? ""
		fileType = try c.decodeIfPresent(TweakFileType.self, forKey: .fileType) ?? .other
		fileSize = try c.decodeIfPresent(Int64.self, forKey: .fileSize) ?? 0
		isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
		config = try c.decodeIfPresent(TweakInjectConfig.self, forKey: .config)
	}
}

extension TweakInjectionFile {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		fileURL = try c.decode(URL.self, forKey: .fileURL)
		fileName = try c.decodeIfPresent(String.self, forKey: .fileName) ?? fileURL.lastPathComponent
		fileType = try c.decodeIfPresent(TweakFileType.self, forKey: .fileType) ?? TweakFileType(fileExtension: fileURL.pathExtension)
		enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
		config = try c.decodeIfPresent(TweakInjectConfig.self, forKey: .config) ?? .default
	}
}

extension ManagedTweak {
	init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
		name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
		notes = try c.decodeIfPresent(String.self, forKey: .notes)
		dateAdded = try c.decodeIfPresent(Date.self, forKey: .dateAdded) ?? Date()
		isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
		versions = try c.decodeIfPresent([TweakVersion].self, forKey: .versions) ?? []
		selectedVersionId = try c.decodeIfPresent(UUID.self, forKey: .selectedVersionId)
		injectByDefault = try c.decodeIfPresent(Bool.self, forKey: .injectByDefault) ?? false
		autoInjectBundleIds = try c.decodeIfPresent([String].self, forKey: .autoInjectBundleIds) ?? []
		config = try c.decodeIfPresent(TweakInjectConfig.self, forKey: .config) ?? .default
		folderId = try c.decodeIfPresent(UUID.self, forKey: .folderId)
	}
}

// MARK: - Model extension: sorting
extension ManagedTweak: SortableItem {
	var sortName: String { name }
	var sortDate: Date { dateAdded }
	var sortSize: Int64 { activeVersion?.fileSize ?? 0 }
}
