//
//  EntitlementsManager.swift
//  RyukSign
//
//  Library of reusable custom entitlements files. Persisted as a JSON manifest,
//  same layout as TweakManager, one plist per entry under Documents/Entitlements/<id>/.
//

import Foundation
import OSLog

// MARK: - Model

struct EntitlementsFile: Codable, Identifiable, Equatable {
	let id: UUID
	var name: String
	let createdAt: Date

	init(id: UUID = UUID(), name: String, createdAt: Date = Date()) {
		self.id = id
		self.name = name
		self.createdAt = createdAt
	}
}

// MARK: - Manager

final class EntitlementsManager: ObservableObject {
	static let shared = EntitlementsManager()

	@Published private(set) var files: [EntitlementsFile]

	private let _fm = FileManager.default
	private var _manifestURL: URL { _fm.entitlementsLibrary.appendingPathComponent("library.json") }

	private init() {
		self.files = []
		_load()
	}

	// MARK: Persistence

	private func _load() {
		guard let data = try? Data(contentsOf: _manifestURL) else { return }
		files = TweakManager.decodeLenientArray(EntitlementsFile.self, from: data)
	}

	private func _save() {
		do {
			try _fm.createDirectoryIfNeeded(at: _fm.entitlementsLibrary)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted]
			let data = try encoder.encode(files)
			try data.write(to: _manifestURL, options: .atomic)
		} catch {
			Logger.misc.error("EntitlementsManager save failed: \(error.localizedDescription)")
		}
		objectWillChange.send()
	}

	// MARK: Disk layout

	func fileURL(for entry: EntitlementsFile) -> URL {
		_fm.entitlementsLibrary(entry.id.uuidString).appendingPathComponent("entitlements.plist")
	}

	func entry(for url: URL) -> EntitlementsFile? {
		files.first { fileURL(for: $0) == url }
	}

	// MARK: Content

	func load(_ entry: EntitlementsFile) -> [String: Any] {
		(NSDictionary(contentsOf: fileURL(for: entry)) as? [String: Any]) ?? [:]
	}

	func save(_ entry: EntitlementsFile, dict: [String: Any]) {
		_write(dict, for: entry)
	}

	// MARK: Mutations

	@discardableResult
	func addBlank(name: String) -> EntitlementsFile {
		add(name: name, dict: [:])
	}

	@discardableResult
	func add(name: String, dict: [String: Any]) -> EntitlementsFile {
		let entry = EntitlementsFile(name: name)
		_write(dict, for: entry)
		files.insert(entry, at: 0)
		_save()
		return entry
	}

	/// Reads a picked file and stores its entitlements as a new library entry (never the source file itself).
	@discardableResult
	func addImported(name: String, from sourceURL: URL) -> EntitlementsFile? {
		guard let dict = EntitlementsManager.parseEntitlements(from: sourceURL) else { return nil }
		return add(name: name, dict: dict)
	}

	/// Reads entitlements from a plist/`.entitlements` file, any `.mobileprovision`, or a JSON export.
	static func parseEntitlements(from url: URL) -> [String: Any]? {
		let needsScope = url.startAccessingSecurityScopedResource()
		defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

		if let dict = NSDictionary(contentsOf: url) as? [String: Any] {
			return dict
		}
		if url.pathExtension.lowercased() == "mobileprovision" {
			return CertificateReader(url).decoded?.Entitlements.map { $0.mapValues { $0.value } }
		}
		if let data = try? Data(contentsOf: url) {
			return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
		}
		return nil
	}

	func rename(_ id: UUID, to name: String) {
		guard let index = files.firstIndex(where: { $0.id == id }) else { return }
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		files[index].name = trimmed
		_save()
	}

	func delete(_ id: UUID) {
		guard let index = files.firstIndex(where: { $0.id == id }) else { return }
		try? _fm.removeFileIfNeeded(at: _fm.entitlementsLibrary(id.uuidString))
		files.remove(at: index)
		_save()
	}

	private func _write(_ dict: [String: Any], for entry: EntitlementsFile) {
		guard let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) else { return }
		try? _fm.createDirectoryIfNeeded(at: _fm.entitlementsLibrary(entry.id.uuidString))
		try? data.write(to: fileURL(for: entry), options: .atomic)
	}
}
