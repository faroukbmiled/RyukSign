//
//  BackupManager.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Zip

struct BackupComponents: OptionSet, Hashable, Codable {
	let rawValue: Int

	static let certificates = BackupComponents(rawValue: 1 << 0)
	static let sources = BackupComponents(rawValue: 1 << 1)
	static let settings = BackupComponents(rawValue: 1 << 2)
	static let tweaks = BackupComponents(rawValue: 1 << 3)

	static let ordered: [BackupComponents] = [.certificates, .sources, .settings, .tweaks]

	init(rawValue: Int) { self.rawValue = rawValue }

	init(from decoder: Decoder) throws {
		rawValue = try decoder.singleValueContainer().decode(Int.self)
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		try container.encode(rawValue)
	}

	var title: String {
		switch self {
		case .certificates: .localized("Certificates")
		case .sources: .localized("Sources")
		case .settings: .localized("Settings")
		case .tweaks: .localized("Tweaks")
		default: ""
		}
	}

	var icon: String {
		switch self {
		case .certificates: "checkmark.seal"
		case .sources: "globe.desk"
		case .settings: "gear"
		case .tweaks: "wrench.and.screwdriver"
		default: "questionmark"
		}
	}
}

struct BackupManifest: Codable {
	var version: Int
	var createdAt: Date
	var appVersion: String
	var contents: BackupComponents?
	var includesTweaks: Bool?
	var counts: [String: Int]?
	var selectedCertUUID: String?
	var certificates: [Cert]
	var sources: [Source]

	struct Cert: Codable {
		var uuid: String
		var nickname: String?
		var password: String?
		var expiration: Date
		var ppq: Bool
	}

	struct Source: Codable {
		var identifier: String
		var name: String?
		var url: URL
		var iconURL: URL?
	}

	var storedContents: BackupComponents {
		if let contents { return contents }
		var inferred: BackupComponents = [.settings]
		if !certificates.isEmpty { inferred.insert(.certificates) }
		if !sources.isEmpty { inferred.insert(.sources) }
		if includesTweaks == true { inferred.insert(.tweaks) }
		return inferred
	}

	func count(of component: BackupComponents) -> Int? {
		switch component {
		case .certificates: certificates.count
		case .sources: sources.count
		default: counts?[String(component.rawValue)]
		}
	}
}

final class BackupArchive: Identifiable {
	let id = UUID()
	let manifest: BackupManifest
	fileprivate let root: URL
	private let _work: URL

	fileprivate init(manifest: BackupManifest, root: URL, work: URL) {
		self.manifest = manifest
		self.root = root
		self._work = work
	}

	deinit {
		try? FileManager.default.removeItem(at: _work)
	}

	var contents: BackupComponents { manifest.storedContents }
}

struct BackupRestoreSummary {
	private(set) var restored: BackupComponents = []
	private var _added: [BackupComponents: Int] = [:]
	private var _skipped: [BackupComponents: Int] = [:]

	mutating func record(_ component: BackupComponents, added: Int, skipped: Int) {
		restored.insert(component)
		_added[component] = added
		_skipped[component] = max(0, skipped)
	}

	var lines: [String] {
		BackupComponents.ordered.compactMap { component in
			guard restored.contains(component) else { return nil }
			let added = _added[component] ?? 0
			let skipped = _skipped[component] ?? 0
			return skipped > 0
			? .localized("%@: %lld added, %lld skipped", arguments: component.title, added, skipped)
			: .localized("%@: %lld added", arguments: component.title, added)
		}
	}
}

@MainActor
final class BackupManager {
	static let shared = BackupManager()
	private let _fm = FileManager.default

	enum Failure: LocalizedError {
		case empty

		var errorDescription: String? {
			String.localized("Nothing to back up.")
		}
	}

	/// Backs up any key in the app's namespaces; only device/install-specific keys are excluded.
	private static let _settingPrefixes = ["Feather.", "feather.", "RyukSign.", "signing_options"]
	private static let _settingDenylist: Set<String> = [
		"feather.selectedCert",              // restored by uuid remap, not by raw index
		"RyukSign.premiumSourceHosts",       // premium activation is install-bound
		"RyukSign.defaultImportFolderName",
		"RyukSign.defaultImportFolderBookmark", // security-scoped, dead on another install
		"Feather.downloadBubblePositionX",
		"Feather.downloadBubblePositionY",
	]

	static func isBackupableSettingKey(_ key: String) -> Bool {
		guard _settingPrefixes.contains(where: { key.hasPrefix($0) }) else { return false }
		if _settingDenylist.contains(key) { return false }
		if key.hasPrefix("Feather.certHash.") { return false }
		return true
	}

	func availableComponents() -> (components: BackupComponents, counts: [BackupComponents: Int]) {
		let counts: [BackupComponents: Int] = [
			.certificates: Storage.shared.getAllCertificates().count,
			.sources: Storage.shared.getSources().count,
			.tweaks: TweakManager.shared.tweaks.count,
			.settings: UserDefaults.standard.dictionaryRepresentation().keys.filter(Self.isBackupableSettingKey).count,
		]
		var components: BackupComponents = []
		for (component, count) in counts where count > 0 { components.insert(component) }
		return (components, counts)
	}

	func makeBackup(password: String, components: BackupComponents) async throws -> URL {
		let staging = _fm.uniqueTemporaryDirectory("RyukBackup")
		try _fm.createDirectory(at: staging, withIntermediateDirectories: true)
		defer { try? _fm.removeItem(at: staging) }

		var written: BackupComponents = []
		var counts: [String: Int] = [:]
		var certEntries: [BackupManifest.Cert] = []
		var sources: [BackupManifest.Source] = []
		var selectedUUID: String?

		if components.contains(.certificates) {
			let certs = Storage.shared.getAllCertificates()
			let certsDir = staging.appendingPathComponent("certs")
			for cert in certs {
				guard
					let uuid = cert.uuid,
					let p12 = Storage.shared.getFile(.certificate, from: cert),
					let provision = Storage.shared.getFile(.provision, from: cert)
				else { continue }

				let dst = certsDir.appendingPathComponent(uuid)
				try _fm.createDirectory(at: dst, withIntermediateDirectories: true)
				try _fm.copyItem(at: p12, to: dst.appendingPathComponent("certificate.p12"))
				try _fm.copyItem(at: provision, to: dst.appendingPathComponent("certificate.mobileprovision"))
				certEntries.append(.init(
					uuid: uuid,
					nickname: cert.nickname,
					password: cert.password,
					expiration: cert.expiration ?? Date(),
					ppq: cert.ppQCheck
				))
			}

			let selectedIndex = UserDefaults.standard.integer(forKey: "feather.selectedCert")
			selectedUUID = (selectedIndex >= 0 && selectedIndex < certs.count) ? certs[selectedIndex].uuid : nil
			if !certEntries.isEmpty { written.insert(.certificates) }
		}

		if components.contains(.sources) {
			sources = Storage.shared.getSources().compactMap { source in
				guard let url = source.sourceURL, let identifier = source.identifier else { return nil }
				guard !RyukSignAPI.isPremiumSource(url) else { return nil }
				return .init(identifier: identifier, name: source.name, url: url, iconURL: source.iconURL)
			}
			if !sources.isEmpty { written.insert(.sources) }
		}

		if components.contains(.settings) {
			var settings: [String: Any] = [:]
			for (key, value) in UserDefaults.standard.dictionaryRepresentation() where Self.isBackupableSettingKey(key) {
				settings[key] = value
			}
			if !settings.isEmpty {
				let data = try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
				try data.write(to: staging.appendingPathComponent("settings.plist"))
				counts[String(BackupComponents.settings.rawValue)] = settings.count
				written.insert(.settings)
			}
		}

		if components.contains(.tweaks), _fm.fileExists(atPath: _fm.tweaksLibrary.path) {
			try _fm.copyItem(at: _fm.tweaksLibrary, to: staging.appendingPathComponent("tweaks"))
			counts[String(BackupComponents.tweaks.rawValue)] = TweakManager.shared.tweaks.count
			written.insert(.tweaks)
		}

		guard !written.isEmpty else { throw Failure.empty }

		let manifest = BackupManifest(
			version: 2,
			createdAt: Date(),
			appVersion: Bundle.main.version,
			contents: written,
			includesTweaks: written.contains(.tweaks),
			counts: counts,
			selectedCertUUID: selectedUUID,
			certificates: certEntries,
			sources: sources
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted]
		try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"))

		let packDir = _fm.uniqueTemporaryDirectory("RyukBackupPack")
		try _fm.createDirectory(at: packDir, withIntermediateDirectories: true)
		defer { try? _fm.removeItem(at: packDir) }
		let packURL = packDir.appendingPathComponent("pack.zip")

		let packed = try await Task.detached(priority: .userInitiated) {
			try Zip.zipFiles(paths: [staging], zipFilePath: packURL, password: nil, progress: nil)
			return try BackupCrypto.seal(try Data(contentsOf: packURL), password: password)
		}.value

		let outDir = _fm.uniqueTemporaryDirectory("RyukBackupOut")
		try _fm.createDirectory(at: outDir, withIntermediateDirectories: true)
		let file = outDir.appendingPathComponent("RyukSign-Backup-\(Self._stamp()).ryukbackup")
		try packed.write(to: file)
		return file
	}

	func open(_ url: URL, password: String) async throws -> BackupArchive {
		let data = try Data(contentsOf: url)
		let work = _fm.uniqueTemporaryDirectory("RyukRestore")
		try _fm.createDirectory(at: work, withIntermediateDirectories: true)

		do {
			let extractDir = work.appendingPathComponent("extract")
			try await Task.detached(priority: .userInitiated) {
				let plaintext = try BackupCrypto.unseal(data, password: password)
				let packURL = work.appendingPathComponent("pack.zip")
				try plaintext.write(to: packURL)
				try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
				try Zip.unzipFile(packURL, destination: extractDir, overwrite: true, password: nil)
			}.value

			guard let root = _findRoot(in: extractDir) else { throw BackupCrypto.Failure.badFormat }
			let manifestData = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
			let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)
			return BackupArchive(manifest: manifest, root: root, work: work)
		} catch {
			try? _fm.removeItem(at: work)
			throw error
		}
	}

	func restore(_ archive: BackupArchive, components: BackupComponents) -> BackupRestoreSummary {
		let manifest = archive.manifest
		let root = archive.root
		let wanted = components.intersection(archive.contents)
		var summary = BackupRestoreSummary()

		if wanted.contains(.certificates) {
			var added = 0
			var skipped = 0
			let existing = Set(Storage.shared.getAllCertificates().compactMap { $0.uuid })
			for cert in manifest.certificates {
				if existing.contains(cert.uuid) { skipped += 1; continue }
				let srcDir = root.appendingPathComponent("certs").appendingPathComponent(cert.uuid)
				guard _fm.fileExists(atPath: srcDir.path) else { continue }
				let dstDir = _fm.certificates(cert.uuid)
				do {
					try _fm.removeFileIfNeeded(at: dstDir)
					try _fm.copyItem(at: srcDir, to: dstDir)
				} catch {
					continue
				}
				Storage.shared.addCertificate(
					uuid: cert.uuid,
					password: cert.password,
					nickname: cert.nickname,
					ppq: cert.ppq,
					expiration: cert.expiration
				) { _ in }
				added += 1
			}
			summary.record(.certificates, added: added, skipped: skipped)

			if
				let uuid = manifest.selectedCertUUID,
				let index = Storage.shared.getAllCertificates().firstIndex(where: { $0.uuid == uuid })
			{
				UserDefaults.standard.set(index, forKey: "feather.selectedCert")
			}
		}

		if wanted.contains(.sources) {
			var added = 0
			var skipped = 0
			for source in manifest.sources {
				if Storage.shared.sourceExists(source.identifier) { skipped += 1; continue }
				Storage.shared.addSource(source.url, name: source.name, identifier: source.identifier, iconURL: source.iconURL) { _ in }
				added += 1
			}
			summary.record(.sources, added: added, skipped: skipped)
		}

		if
			wanted.contains(.settings),
			let data = try? Data(contentsOf: root.appendingPathComponent("settings.plist")),
			let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
		{
			var added = 0
			for (key, value) in dict where Self.isBackupableSettingKey(key) {
				UserDefaults.standard.set(value, forKey: key)
				added += 1
			}
			summary.record(.settings, added: added, skipped: 0)
		}

		let tweaksDir = root.appendingPathComponent("tweaks")
		if wanted.contains(.tweaks), _fm.fileExists(atPath: tweaksDir.path) {
			let added = TweakManager.shared.mergeFromBackup(tweaksDir: tweaksDir)
			summary.record(.tweaks, added: added, skipped: (manifest.count(of: .tweaks) ?? added) - added)
		}

		return summary
	}

	private func _findRoot(in dir: URL) -> URL? {
		if _fm.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) { return dir }
		guard let items = try? _fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
		return items.first { _fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
	}

	private static func _stamp() -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyyMMdd-HHmm"
		return formatter.string(from: Date())
	}
}
