//
//  TweakManager.swift
//  RyukSign
//
//  Library of reusable tweaks (.dylib/.deb/.framework/.bundle) with versions and
//  auto-inject rules. Persisted as a JSON manifest, not CoreData, to stay clear of
//  the CoreData store's destroy-and-recreate corruption fallback.
//

import Foundation
import NimbleExtensions
import Zip
import OSLog

// MARK: - Models

final class TweakManager: ObservableObject {
	static let shared = TweakManager()

	@Published private(set) var tweaks: [ManagedTweak]
	@Published private(set) var folders: [TweakFolder]

	private let _fm = FileManager.default
	private var _manifestURL: URL { _fm.tweaksLibrary.appendingPathComponent("library.json") }
	private var _foldersURL: URL { _fm.tweaksLibrary.appendingPathComponent("folders.json") }

	private init() {
		self.tweaks = []
		self.folders = []
		_load()
		_loadFolders()
		_purgeExportTemp()
	}

	/// Remove leftover export/extract scratch dirs from previous sessions.
	private func _purgeExportTemp() {
		let prefixes = ["TweakExport_", "TweakFolderExport_", "FeatherTweakExtract_", "FeatherZipExtract_"]
		guard let items = try? _fm.contentsOfDirectory(at: _fm.temporaryDirectory, includingPropertiesForKeys: nil) else { return }
		for item in items where prefixes.contains(where: { item.lastPathComponent.hasPrefix($0) }) {
			try? _fm.removeItem(at: item)
		}
	}

	// MARK: Persistence

	private func _load() {
		guard let data = try? Data(contentsOf: _manifestURL) else { return }
		self.tweaks = TweakManager.decodeLenientArray(ManagedTweak.self, from: data)
	}

	private func _save() {
		do {
			try _fm.createDirectoryIfNeeded(at: _fm.tweaksLibrary)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted]
			let data = try encoder.encode(tweaks)
			try data.write(to: _manifestURL, options: .atomic)
		} catch {
			Logger.misc.error("TweakManager save failed: \(error.localizedDescription)")
		}
		objectWillChange.send()
	}

	private func _loadFolders() {
		guard let data = try? Data(contentsOf: _foldersURL) else { return }
		self.folders = TweakManager.decodeLenientArray(TweakFolder.self, from: data)
	}

	private func _saveFolders() {
		do {
			try _fm.createDirectoryIfNeeded(at: _fm.tweaksLibrary)
			let encoder = JSONEncoder()
			encoder.outputFormatting = [.prettyPrinted]
			let data = try encoder.encode(folders)
			try data.write(to: _foldersURL, options: .atomic)
		} catch {
			Logger.misc.error("TweakManager folders save failed: \(error.localizedDescription)")
		}
		objectWillChange.send()
	}

	// MARK: Folders

	/// Tweaks in the given folder (`nil` = uncategorized).
	func tweaks(inFolder folderId: UUID?) -> [ManagedTweak] {
		tweaks.filter { $0.folderId == folderId }
	}

	func tweakCount(inFolder folderId: UUID?) -> Int {
		tweaks.reduce(0) { $0 + ($1.folderId == folderId ? 1 : 0) }
	}

	func folder(_ id: UUID?) -> TweakFolder? {
		guard let id else { return nil }
		return folders.first { $0.id == id }
	}

	@discardableResult
	func addFolder(name: String) -> TweakFolder {
		let folder = TweakFolder(name: _uniqueFolderName(name))
		folders.append(folder)
		_saveFolders()
		return folder
	}

	func renameFolder(_ id: UUID, to name: String) {
		guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
		let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !trimmed.isEmpty else { return }
		folders[index].name = _uniqueFolderName(trimmed, excluding: id)
		_saveFolders()
	}

	/// Unique folder name among siblings, appending " 2", " 3"… on collision.
	private func _uniqueFolderName(_ desired: String, excluding id: UUID? = nil) -> String {
		var base = desired.trimmingCharacters(in: .whitespacesAndNewlines)
		if base.isEmpty { base = .localized("New Folder") }
		let taken = Set(folders.filter { $0.id != id }.map { $0.name.lowercased() })
		guard taken.contains(base.lowercased()) else { return base }
		var n = 2
		while taken.contains("\(base) \(n)".lowercased()) { n += 1 }
		return "\(base) \(n)"
	}

	/// Deletes a folder; its tweaks fall back to uncategorized (never deleted).
	func deleteFolder(_ id: UUID) {
		var touched = false
		for index in tweaks.indices where tweaks[index].folderId == id {
			tweaks[index].folderId = nil
			touched = true
		}
		folders.removeAll { $0.id == id }
		if touched { _save() }
		_saveFolders()
	}

	/// Moves tweaks into a folder (`nil` = uncategorized).
	func moveTweaks(_ ids: Set<UUID>, toFolder folderId: UUID?) {
		var touched = false
		for index in tweaks.indices where ids.contains(tweaks[index].id) {
			tweaks[index].folderId = folderId
			touched = true
		}
		if touched { _save() }
	}

	// MARK: Disk layout

	/// `Documents/Tweaks/<tweakID>/<versionID>/`
	func versionDirectory(forTweak tweakId: UUID, version: TweakVersion) -> URL {
		_fm.tweaksLibrary(tweakId.uuidString).appendingPathComponent(version.id.uuidString)
	}

	func fileURL(forTweak tweakId: UUID, version: TweakVersion, component: TweakComponent) -> URL {
		versionDirectory(forTweak: tweakId, version: version)
			.appendingPathComponent(component.fileName)
	}

	func fileURL(forTweak tweak: ManagedTweak, version: TweakVersion, component: TweakComponent) -> URL {
		fileURL(forTweak: tweak.id, version: version, component: component)
	}

	func fileURLs(forTweak tweakId: UUID, version: TweakVersion) -> [URL] {
		version.components.map { fileURL(forTweak: tweakId, version: version, component: $0) }
	}

	// MARK: Mutations

	@discardableResult
	func addTweak(name: String, from fileURL: URL, versionLabel: String = "1.0") -> ManagedTweak? {
		addTweak(name: name, fromFiles: [fileURL], versionLabel: versionLabel)
	}

	/// Imports several picked files as one tweak (a multi-file version).
	@discardableResult
	func addTweak(name: String, fromFiles fileURLs: [URL], versionLabel: String = "1.0") -> ManagedTweak? {
		guard let first = fileURLs.first else { return nil }
		let tweakId = UUID()
		let versionId = UUID()
		let stored = _storeComponents(fileURLs, forTweak: tweakId, versionId: versionId, existing: [])
		guard !stored.isEmpty else { return nil }

		let tweak = ManagedTweak(
			id: tweakId,
			name: name.isEmpty ? first.deletingPathExtension().lastPathComponent : name,
			versions: [TweakVersion(id: versionId, label: versionLabel, components: stored)],
			selectedVersionId: versionId
		)
		tweaks.insert(tweak, at: 0)
		_save()
		return tweak
	}

	@discardableResult
	func addVersion(to tweakId: UUID, from fileURL: URL, label: String) -> TweakVersion? {
		addVersion(to: tweakId, fromFiles: [fileURL], label: label)
	}

	/// Adds another version (one or more files) to an existing tweak.
	@discardableResult
	func addVersion(to tweakId: UUID, fromFiles fileURLs: [URL], label: String) -> TweakVersion? {
		guard let index = tweaks.firstIndex(where: { $0.id == tweakId }) else { return nil }
		let versionId = UUID()
		let stored = _storeComponents(fileURLs, forTweak: tweakId, versionId: versionId, existing: [])
		guard !stored.isEmpty else { return nil }

		let version = TweakVersion(id: versionId, label: label, components: stored)
		tweaks[index].versions.append(version)
		tweaks[index].selectedVersionId = versionId
		_save()
		return version
	}

	@discardableResult
	func addComponents(to tweakId: UUID, versionId: UUID, fromFiles fileURLs: [URL]) -> [TweakComponent] {
		guard
			let tIndex = tweaks.firstIndex(where: { $0.id == tweakId }),
			let vIndex = tweaks[tIndex].versions.firstIndex(where: { $0.id == versionId })
		else { return [] }

		let existing = tweaks[tIndex].versions[vIndex].components
		let stored = _storeComponents(fileURLs, forTweak: tweakId, versionId: versionId, existing: existing)
		guard !stored.isEmpty else { return [] }

		tweaks[tIndex].versions[vIndex].components.append(contentsOf: stored)
		_save()
		return stored
	}

	/// Removes a component (and its file); removing the last one deletes the version.
	func deleteComponent(_ componentId: UUID, versionId: UUID, from tweakId: UUID) {
		guard
			let tIndex = tweaks.firstIndex(where: { $0.id == tweakId }),
			let vIndex = tweaks[tIndex].versions.firstIndex(where: { $0.id == versionId }),
			let component = tweaks[tIndex].versions[vIndex].components.first(where: { $0.id == componentId })
		else { return }

		let version = tweaks[tIndex].versions[vIndex]
		try? _fm.removeFileIfNeeded(at: fileURL(forTweak: tweakId, version: version, component: component))
		tweaks[tIndex].versions[vIndex].components.removeAll { $0.id == componentId }

		if tweaks[tIndex].versions[vIndex].components.isEmpty {
			deleteVersion(versionId, from: tweakId)
		} else {
			_save()
		}
	}

	func mutateComponent(_ componentId: UUID, versionId: UUID, in tweakId: UUID, _ change: (inout TweakComponent) -> Void) {
		guard
			let tIndex = tweaks.firstIndex(where: { $0.id == tweakId }),
			let vIndex = tweaks[tIndex].versions.firstIndex(where: { $0.id == versionId }),
			let cIndex = tweaks[tIndex].versions[vIndex].components.firstIndex(where: { $0.id == componentId })
		else { return }
		change(&tweaks[tIndex].versions[vIndex].components[cIndex])
		_save()
	}

	func deleteTweak(_ id: UUID) {
		guard let index = tweaks.firstIndex(where: { $0.id == id }) else { return }
		try? _fm.removeFileIfNeeded(at: _fm.tweaksLibrary(id.uuidString))
		tweaks.remove(at: index)
		_save()
	}

	/// Single batched mutation — deleting one-by-one fired `tweaks` (+ `.animation`)
	/// repeatedly mid-edit and crashed the list diff.
	func deleteTweaks(_ ids: Set<UUID>) {
		guard !ids.isEmpty else { return }
		for id in ids {
			try? _fm.removeFileIfNeeded(at: _fm.tweaksLibrary(id.uuidString))
		}
		tweaks.removeAll { ids.contains($0.id) }
		_save()
	}

	/// Adds only tweaks/folders whose id isn't already present; existing ones are untouched.
	func mergeFromBackup(tweaksDir: URL) {
		if let data = try? Data(contentsOf: tweaksDir.appendingPathComponent("library.json")) {
			let incoming = TweakManager.decodeLenientArray(ManagedTweak.self, from: data)
			let existing = Set(tweaks.map { $0.id })
			for tweak in incoming where !existing.contains(tweak.id) {
				let src = tweaksDir.appendingPathComponent(tweak.id.uuidString)
				let dst = _fm.tweaksLibrary(tweak.id.uuidString)
				if !_fm.fileExists(atPath: dst.path), _fm.fileExists(atPath: src.path) {
					try? _fm.createDirectoryIfNeeded(at: _fm.tweaksLibrary)
					try? _fm.copyItem(at: src, to: dst)
				}
				guard _fm.fileExists(atPath: dst.path) else { continue }
				tweaks.append(tweak)
			}
			_save()
		}

		if let data = try? Data(contentsOf: tweaksDir.appendingPathComponent("folders.json")) {
			let incoming = TweakManager.decodeLenientArray(TweakFolder.self, from: data)
			let existing = Set(folders.map { $0.id })
			for folder in incoming where !existing.contains(folder.id) {
				folders.append(folder)
			}
			_saveFolders()
		}
	}

	/// Wipes the entire tweak library — all tweaks, folders, and files on disk.
	func resetLibrary() {
		tweaks = []
		folders = []
		try? _fm.removeFileIfNeeded(at: _fm.tweaksLibrary)
	}

	func deleteVersion(_ versionId: UUID, from tweakId: UUID) {
		guard let index = tweaks.firstIndex(where: { $0.id == tweakId }) else { return }
		if let version = tweaks[index].versions.first(where: { $0.id == versionId }) {
			try? _fm.removeFileIfNeeded(
				at: _fm.tweaksLibrary(tweakId.uuidString).appendingPathComponent(version.id.uuidString)
			)
		}
		tweaks[index].versions.removeAll { $0.id == versionId }
		if tweaks[index].selectedVersionId == versionId {
			tweaks[index].selectedVersionId = tweaks[index].versions.last?.id
		}
		_save()
	}

	func setSelectedVersion(_ versionId: UUID, for tweakId: UUID) {
		guard let index = tweaks.firstIndex(where: { $0.id == tweakId }) else { return }
		tweaks[index].selectedVersionId = versionId
		_save()
	}

	/// Replaces a tweak's metadata; versions are managed separately.
	func update(_ tweak: ManagedTweak) {
		guard let index = tweaks.firstIndex(where: { $0.id == tweak.id }) else { return }
		tweaks[index] = tweak
		_save()
	}

	func mutate(_ id: UUID, _ change: (inout ManagedTweak) -> Void) {
		guard let index = tweaks.firstIndex(where: { $0.id == id }) else { return }
		change(&tweaks[index])
		_save()
	}

	func tweak(_ id: UUID) -> ManagedTweak? {
		tweaks.first { $0.id == id }
	}

	// MARK: Queries

	/// Tweaks that should auto-inject when signing the given bundle id.
	func resolveAutoInject(forBundleId bundleId: String?) -> [ManagedTweak] {
		tweaks.filter { tweak in
			guard tweak.isEnabled, tweak.activeVersion != nil else { return false }
			if tweak.injectByDefault { return true }
			if let bundleId, tweak.autoInjectBundleIds.contains(bundleId) { return true }
			return false
		}
	}

	/// Tweaks set to inject into every sign (drives the tab badge).
	var defaultInjectCount: Int {
		tweaks.filter { $0.isEnabled && $0.injectByDefault && $0.activeVersion != nil }.count
	}

	/// Sign-time spec from a tweak's active version: one file per component with its
	/// effective config (component override else tweak default); "selected" targeting
	/// is constrained to the app's real extensions.
	func injectionSpec(for tweak: ManagedTweak, availableAppex: [String]) -> TweakInjectionSpec? {
		guard let version = tweak.activeVersion else { return nil }
		let files: [TweakInjectionFile] = version.components.map { component in
			var config = component.config ?? tweak.config
			if case .selected(let names) = config.targeting {
				config.targeting = .selected(names.filter { availableAppex.contains($0) })
			}
			return TweakInjectionFile(
				fileURL: fileURL(forTweak: tweak.id, version: version, component: component),
				fileName: component.fileName,
				fileType: component.fileType,
				enabled: component.isEnabled,
				config: config
			)
		}
		guard !files.isEmpty else { return nil }
		return TweakInjectionSpec(id: tweak.id, displayName: tweak.name, isManaged: true, files: files)
	}

	// MARK: Internal

	/// Copies source files into a version directory, returning components. File names
	/// are kept (importers derive the name from them); collisions are de-duped (`Name 2.dylib`).
	private func _storeComponents(
		_ sources: [URL],
		forTweak tweakId: UUID,
		versionId: UUID,
		existing: [TweakComponent]
	) -> [TweakComponent] {
		let destDir = _fm.tweaksLibrary(tweakId.uuidString).appendingPathComponent(versionId.uuidString)
		do {
			try _fm.createDirectoryIfNeeded(at: destDir)
		} catch {
			Logger.misc.error("TweakManager store failed to create dir: \(error.localizedDescription)")
			return []
		}

		var taken = Set(existing.map { $0.fileName.lowercased() })
		var result: [TweakComponent] = []

		for source in sources {
			let needsScope = source.startAccessingSecurityScopedResource()
			defer { if needsScope { source.stopAccessingSecurityScopedResource() } }

			let fileName = _uniqueFileName(source.lastPathComponent, taken: taken)
			let dest = destDir.appendingPathComponent(fileName)
			do {
				try _fm.copyItem(at: source, to: dest)
			} catch {
				Logger.misc.error("TweakManager store failed for \(fileName): \(error.localizedDescription)")
				continue
			}
			taken.insert(fileName.lowercased())
			result.append(TweakComponent(
				fileName: fileName,
				fileType: TweakFileType(fileExtension: source.pathExtension),
				// Handles files and directory bundles (.framework/.bundle/.appex).
				fileSize: TweakExtractor.directorySize(at: dest)
			))
		}

		if result.isEmpty, existing.isEmpty {
			try? _fm.removeFileIfNeeded(at: destDir)
		}
		return result
	}

	/// Appends " 2", " 3"… before the extension on collision (keeps the suffix intact).
	private func _uniqueFileName(_ desired: String, taken: Set<String>) -> String {
		guard taken.contains(desired.lowercased()) else { return desired }
		let url = URL(fileURLWithPath: desired)
		let ext = url.pathExtension
		let base = url.deletingPathExtension().lastPathComponent
		var n = 2
		while true {
			let candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
			if !taken.contains(candidate.lowercased()) { return candidate }
			n += 1
		}
	}

	// MARK: - Export

	/// Shareable URL. A single plain file is shared via temp copy; a directory bundle
	/// or multi-file version is zipped (can't share a folder). Nil if no files.
	func exportableURL(for tweak: ManagedTweak, version: TweakVersion) -> URL? {
		let sources = fileURLs(forTweak: tweak.id, version: version)
			.filter { _fm.fileExists(atPath: $0.path) }
		guard !sources.isEmpty else { return nil }

		// Export from a temp copy so library files are never moved/altered.
		let exportDir = _fm.uniqueTemporaryDirectory("TweakExport")
		do {
			try _fm.createDirectoryIfNeeded(at: exportDir)

			if sources.count == 1 {
				let source = sources[0]
				let isDir = (try? source.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
				if !isDir {
					let dest = exportDir.appendingPathComponent(source.lastPathComponent)
					try _fm.copyItem(at: source, to: dest)
					return dest
				}
			}

			// Directory bundle or multiple files → one zip named after the tweak.
			let safeName = tweak.name.replacingOccurrences(of: "/", with: "_")
			let zipURL = exportDir.appendingPathComponent("\(safeName.isEmpty ? "Tweak" : safeName).zip")
			try Zip.zipFiles(paths: sources, zipFilePath: zipURL, password: nil, progress: nil)
			return zipURL
		} catch {
			Logger.misc.error("TweakManager export failed: \(error.localizedDescription)")
			return nil
		}
	}

	/// Shareable URLs for a set of tweaks (each active version).
	func exportableURLs(forTweakIds ids: Set<UUID>) -> [URL] {
		tweaks
			.filter { ids.contains($0.id) }
			.compactMap { tweak in
				guard let version = tweak.activeVersion else { return nil }
				return exportableURL(for: tweak, version: version)
			}
	}

	/// Zips a folder's active-version files into one archive.
	func exportFolder(_ folderId: UUID) -> URL? {
		let items = tweaks(inFolder: folderId).flatMap { tweak -> [URL] in
			guard let version = tweak.activeVersion else { return [] }
			return fileURLs(forTweak: tweak.id, version: version).filter { _fm.fileExists(atPath: $0.path) }
		}
		guard !items.isEmpty else { return nil }

		let name = folder(folderId)?.name ?? "Tweaks"
		let safeName = name.replacingOccurrences(of: "/", with: "_")
		let exportDir = _fm.uniqueTemporaryDirectory("TweakFolderExport")
		let zipURL = exportDir.appendingPathComponent("\(safeName).zip")
		do {
			try _fm.createDirectoryIfNeeded(at: exportDir)
			try Zip.zipFiles(paths: items, zipFilePath: zipURL, password: nil, progress: nil)
			return zipURL
		} catch {
			Logger.misc.error("TweakManager folder export failed: \(error.localizedDescription)")
			return nil
		}
	}
}

// MARK: - Lenient array decoding

private struct _FailableElement<T: Decodable>: Decodable {
	let value: T?
	init(from decoder: Decoder) throws {
		value = try? T(from: decoder)
	}
}

extension TweakManager {
	/// Drops only the entries that fail to decode instead of losing the whole file.
	static func decodeLenientArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T] {
		if let all = try? JSONDecoder().decode([T].self, from: data) { return all }
		guard let elements = try? JSONDecoder().decode([_FailableElement<T>].self, from: data) else { return [] }
		return elements.compactMap { $0.value }
	}
}
