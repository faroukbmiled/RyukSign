//
//  AppUpdateChecker.swift
//  RyukSign
//

import Foundation
import Combine
import CoreData
import AltSourceKit

struct AppUpdate: Identifiable, Sendable {
	struct Candidate: Identifiable, Sendable {
		let sourceID: String
		let sourceName: String
		let repository: ASRepository
		let app: ASRepository.App

		var id: String { sourceID + "/" + app.currentUniqueId }
		var version: String { app.currentVersion ?? "" }

		func matches(_ pin: AppOrigin) -> Bool {
			sourceID == pin.source && app.name == pin.name
		}
	}

	let id: String
	let name: String
	let installedVersion: String
	let libraryUUID: String
	let libraryUUIDs: [String]
	let candidates: [Candidate]
	let isPinned: Bool

	var best: Candidate { candidates[0] }

	func scoped(to sourceIDs: Set<String>) -> AppUpdate? {
		let scoped = candidates.filter { sourceIDs.contains($0.sourceID) }
		guard !scoped.isEmpty else { return nil }
		return AppUpdate(
			id: id,
			name: name,
			installedVersion: installedVersion,
			libraryUUID: libraryUUID,
			libraryUUIDs: libraryUUIDs,
			candidates: scoped,
			isPinned: isPinned && scoped[0].id == best.id
		)
	}
}

@MainActor
final class AppUpdateChecker: ObservableObject {
	static let shared = AppUpdateChecker()
	static let newestKey = "RyukSign.updateToNewest"
	static let singleSourceKey = "RyukSign.updateSingleSourceDirectly"
	static let launchCheckKey = "RyukSign.checkUpdatesOnLaunch"
	static let groupKey = "RyukSign.groupUpdatesByApp"

	@Published private(set) var updates: [AppUpdate] = []
	@Published private(set) var pins: [String: AppOrigin]

	private(set) var libraryKeys: Set<String> = []
	private var _byLibraryUUID: [String: AppUpdate] = [:]
	private var _sourceIDs: [String: String] = [:]
	private var _didPrune = false
	private var _task: Task<Void, Never>?
	private var _cancellables = Set<AnyCancellable>()
	private let _trigger = PassthroughSubject<Void, Never>()

	private static let _pinsKey = "RyukSign.updatePins"

	var updateCount: Int { updates.count }

	private init() {
		pins = UserDefaults.standard.data(forKey: Self._pinsKey)
			.flatMap { try? JSONDecoder().decode([String: AppOrigin].self, from: $0) } ?? [:]

		let library = NotificationCenter.default
			.publisher(for: .NSManagedObjectContextObjectsDidChange, object: Storage.shared.context)
			.filter(Self._touchesLibrary)
			.map { _ in }

		Publishers.MergeMany(
			SourcesViewModel.shared.$sources.map { _ in }.eraseToAnyPublisher(),
			library.eraseToAnyPublisher(),
			NotificationCenter.default.publisher(for: .skippedUpdatesChanged).map { _ in }.eraseToAnyPublisher(),
			NotificationCenter.default.publisher(for: AppOrigins.didChange).map { _ in }.eraseToAnyPublisher(),
			_trigger.eraseToAnyPublisher()
		)
		.debounce(for: .milliseconds(300), scheduler: RunLoop.main)
		.sink { [weak self] in self?._recompute() }
		.store(in: &_cancellables)
	}

	// MARK: Queries

	func update(for app: AppInfoPresentable) -> AppUpdate? {
		app.uuid.flatMap { _byLibraryUUID[$0] }
	}

	func updates(in sourceIDs: Set<String>) -> [AppUpdate] {
		updates.compactMap { $0.scoped(to: sourceIDs) }
	}

	func libraryApp(for update: AppUpdate) -> AppInfoPresentable? {
		Storage.shared.app(withUuid: update.libraryUUID)
	}

	func origin(for app: ASRepository.App, version: String? = nil) -> AppOrigin? {
		_sourceIDs[app.currentUniqueId].map {
			AppOrigin(source: $0, appID: app.id, name: app.name, version: version ?? app.currentVersion)
		}
	}

	// MARK: Actions

	func isAutomatic(_ update: AppUpdate) -> Bool {
		let defaults = UserDefaults.standard
		return update.isPinned
			|| defaults.bool(forKey: Self.newestKey)
			|| (update.candidates.count == 1 && defaults.object(forKey: Self.singleSourceKey) as? Bool ?? true)
	}

	/// False: caller should show the picker.
	@discardableResult
	func autoUpdate(_ update: AppUpdate) -> Bool {
		guard isAutomatic(update) else { return false }
		DownloadManager.shared.startDownload(for: update.best.app)
		return true
	}

	func pin(_ candidate: AppUpdate.Candidate?, for key: String) {
		pins[key] = candidate.map {
			AppOrigin(source: $0.sourceID, appID: $0.app.id, name: $0.app.name, version: nil)
		}
		UserDefaults.standard.set(try? JSONEncoder().encode(pins), forKey: Self._pinsKey)
		_trigger.send()
	}

	func isPinned(_ candidate: AppUpdate.Candidate, for key: String) -> Bool {
		pins[key].map(candidate.matches) ?? false
	}

	// MARK: Compute

	private func _recompute() {
		let sources = SourcesViewModel.shared.sources.compactMap { source, repo in
			source.identifier.map { SourceSnapshot(id: $0, name: source.name ?? repo.name ?? "", repository: repo) }
		}
		let origins = AppOrigins.shared.all
		let library = Storage.shared.getAllApps().compactMap { LibraryEntry($0, origins: origins) }

		if !_didPrune, !library.isEmpty {
			_didPrune = true
			AppOrigins.shared.prune(keeping: Set(library.map(\.uuid)))
		}

		let input = Input(
			sources: sources,
			library: library,
			ignored: SkippedUpdatesManager.shared.bundleIDs,
			pins: pins
		)

		_task?.cancel()
		_task = Task {
			let result = await Task.detached(priority: .utility) { Self._compute(input) }.value
			guard !Task.isCancelled else { return }

			_sourceIDs = result.sourceIDs
			libraryKeys = result.libraryKeys
			_byLibraryUUID = result.updates.reduce(into: [:]) { map, update in
				for uuid in update.libraryUUIDs { map[uuid] = update }
			}
			updates = result.updates
		}
	}

	private static func _touchesLibrary(_ note: Notification) -> Bool {
		[NSInsertedObjectsKey, NSDeletedObjectsKey, NSUpdatedObjectsKey].contains { key in
			(note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0 is Signed || $0 is Imported } == true
		}
	}

	private struct SourceSnapshot: Sendable {
		let id: String
		let name: String
		let repository: ASRepository
	}

	private struct LibraryEntry: Sendable {
		let uuid: String
		let key: String
		let name: String
		let version: String
		let origin: AppOrigin?

		// Tweaked builds misreport their bundle version.
		var installedVersion: String { origin?.version ?? version }

		init?(_ app: AppInfoPresentable, origins: [String: AppOrigin]) {
			guard
				let uuid = app.uuid,
				let key = app.originalIdentifier ?? app.identifier, !key.isEmpty,
				let version = app.version
			else {
				return nil
			}
			self.uuid = uuid
			self.key = key
			self.name = app.name ?? key
			self.version = version
			self.origin = origins[uuid]
		}
	}

	private struct Input: Sendable {
		let sources: [SourceSnapshot]
		let library: [LibraryEntry]
		let ignored: Set<String>
		let pins: [String: AppOrigin]
	}

	private struct Output: Sendable {
		let updates: [AppUpdate]
		let sourceIDs: [String: String]
		let libraryKeys: Set<String>
	}

	private struct Group {
		let key: String
		let entries: [LibraryEntry]
		let top: LibraryEntry
		var candidates: [AppUpdate.Candidate] = []
	}

	nonisolated private static func _compute(_ input: Input) -> Output {
		var groups: [String: Group] = Dictionary(grouping: input.library, by: \.key).mapValues { entries in
			let top = entries.max { isNewerVersion($1.installedVersion, than: $0.installedVersion) }!
			return Group(key: top.key, entries: entries, top: top)
		}

		var keysByAppID: [String: [String]] = [:]
		for group in groups.values {
			for id in Set([group.key] + group.entries.compactMap(\.origin?.appID)) {
				keysByAppID[id, default: []].append(group.key)
			}
		}

		var sourceIDs: [String: String] = [:]
		for source in input.sources {
			for app in source.repository.apps {
				sourceIDs[app.currentUniqueId] = source.id

				guard let keys = app.id.flatMap({ keysByAppID[$0] }) else { continue }

				let candidate = AppUpdate.Candidate(sourceID: source.id, sourceName: source.name, repository: source.repository, app: app)
				for key in keys { groups[key]?.candidates.append(candidate) }
			}
		}

		let updates = groups.values.compactMap { group -> AppUpdate? in
			let ignored = input.ignored.contains(group.key) || group.entries.contains { $0.origin?.appID.map(input.ignored.contains) == true }
			guard !ignored else { return nil }

			var seen: Set<String> = []
			var candidates = group.candidates
				.filter { isNewerVersion($0.version, than: group.top.installedVersion) && seen.insert($0.id).inserted }
				.sorted(by: _isPreferred)

			let pin = input.pins[group.key]
			let pinnedExists = pin.map { pin in group.candidates.contains { $0.matches(pin) } } ?? false
			if let pin, pinnedExists {
				guard let index = candidates.firstIndex(where: { $0.matches(pin) }) else { return nil }
				candidates.insert(candidates.remove(at: index), at: 0)
			}

			guard !candidates.isEmpty else { return nil }

			return AppUpdate(
				id: group.key,
				name: group.top.name,
				installedVersion: group.top.installedVersion,
				libraryUUID: group.top.uuid,
				libraryUUIDs: group.entries.map(\.uuid),
				candidates: candidates,
				isPinned: pinnedExists
			)
		}
		.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

		return Output(updates: updates, sourceIDs: sourceIDs, libraryKeys: Set(groups.keys))
	}

	nonisolated private static func _isPreferred(_ lhs: AppUpdate.Candidate, _ rhs: AppUpdate.Candidate) -> Bool {
		if isNewerVersion(lhs.version, than: rhs.version) { return true }
		if isNewerVersion(rhs.version, than: lhs.version) { return false }
		return (lhs.app.currentDate?.date ?? .distantPast) > (rhs.app.currentDate?.date ?? .distantPast)
	}

	// MARK: Versions

	// "1.2 (tweak 3.0)" reads as 1.2.
	nonisolated static func isNewerVersion(_ new: String, than old: String) -> Bool {
		let lhs = _components(new)
		let rhs = _components(old)

		for i in 0..<max(lhs.count, rhs.count) {
			let a = i < lhs.count ? lhs[i] : 0
			let b = i < rhs.count ? rhs[i] : 0
			if a != b { return a > b }
		}
		return false
	}

	nonisolated private static func _components(_ version: String) -> [Int] {
		version
			.drop { !($0.isASCII && $0.isNumber) }
			.prefix { ($0.isASCII && $0.isNumber) || $0 == "." }
			.split(separator: ".")
			.compactMap { Int($0) }
	}
}
