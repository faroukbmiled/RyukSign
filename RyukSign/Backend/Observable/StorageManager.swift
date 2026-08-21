//
//  StorageManager.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Nuke

// MARK: - Category
enum StorageCategory: String, CaseIterable, Identifiable {
	case signed
	case imported
	case archives
	case tweaks
	case certificates
	case caches
	case logs
	case temporary
	case leftovers
	case other

	var id: String { rawValue }

	/// Cleared by "Free Up Space" — none of it is content the user put here.
	static let safeToClear: [StorageCategory] = [.caches, .logs, .temporary, .leftovers]

	/// Categories the user can open and delete item by item.
	var isBrowsable: Bool {
		switch self {
		case .signed, .imported, .archives, .leftovers: true
		default: false
		}
	}
}

// MARK: - Report
struct StorageUsage: Identifiable {
	let category: StorageCategory
	let size: Int64
	let count: Int

	var id: String { category.id }
}

struct StorageReport {
	let usages: [StorageUsage]
	let total: Int64
	let deviceFree: Int64

	var reclaimable: Int64 {
		usages
			.filter { StorageCategory.safeToClear.contains($0.category) }
			.reduce(0) { $0 + $1.size }
	}
}

struct StorageEntry: Identifiable, SortableItem {
	let id: String
	let name: String
	let version: String?
	let size: Int64
	let date: Date
	let url: URL
	/// Set when the entry is a library app, whose deletion also has to drop the Core Data row.
	let appUuid: String?

	var sortName: String { name }
	var sortDate: Date { date }
	var sortSize: Int64 { size }
}

// MARK: - Manager
@MainActor
final class StorageManager: ObservableObject {
	static let shared = StorageManager()

	@Published private(set) var report: StorageReport?
	@Published private(set) var entries: [StorageCategory: [StorageEntry]] = [:]

	private var _scan: Task<Void, Never>?

	private init() {}

	/// Rescans in the background; the published report stays up until it lands, so revisits never flash a loader.
	func refresh() {
		_scan?.cancel()
		_scan = Task {
			let library = _librarySnapshot()
			let scanned = await Task.detached(priority: .utility) { StorageScanner.scan(library) }.value
			guard !Task.isCancelled else { return }
			report = scanned
		}
	}

	func refreshEntries(for category: StorageCategory) async {
		let library = _librarySnapshot()
		entries[category] = await Task.detached(priority: .utility) {
			StorageScanner.entries(for: category, library)
		}.value
	}

	func delete(_ items: [StorageEntry]) {
		let uuids = Set(items.compactMap(\.appUuid))
		if !uuids.isEmpty {
			Storage.shared.deleteApps(Storage.shared.getAllApps().filter { uuids.contains($0.uuid ?? "") })
		}

		for item in items where item.appUuid == nil {
			try? FileManager.default.removeItem(at: item.url)
		}

		let removed = Set(items.map(\.id))
		entries = entries.mapValues { $0.filter { !removed.contains($0.id) } }
		refresh()
	}

	func clear(_ categories: [StorageCategory]) async {
		let library = _librarySnapshot()
		await Task.detached(priority: .utility) {
			for category in categories { StorageScanner.clear(category, library) }
		}.value

		for category in categories { entries[category] = nil }
		refresh()
	}

	private func _librarySnapshot() -> LibrarySnapshot {
		let storage = Storage.shared

		let apps = storage.getAllApps().reduce(into: [String: AppDescriptor]()) { result, app in
			guard let uuid = app.uuid else { return }
			result[uuid] = AppDescriptor(
				name: app.name ?? .localized("Unknown"),
				version: app.version,
				date: app.date ?? .distantPast,
				isSigned: app.isSigned
			)
		}

		let certificates = (try? storage.context.fetch(CertificatePair.fetchRequest()))?
			.compactMap(\.uuid) ?? []

		return LibrarySnapshot(apps: apps, certificates: Set(certificates))
	}
}

// MARK: - Manager extension: temp purging
extension StorageManager {
	/// Drops every scratch file, including downloads still waiting to be imported.
	nonisolated static func purgeTemporary() {
		StorageScanner.purge(contentsOf: FileManager.default.temporaryDirectory)
	}

	/// Drops scratch directories orphaned by a crash or a kill mid-job.
	nonisolated static func purgeStaleTemporary() {
		let fm = FileManager.default
		guard let items = try? fm.contentsOfDirectory(
			at: fm.temporaryDirectory,
			includingPropertiesForKeys: [.contentModificationDateKey]
		) else {
			return
		}

		let staging = fm.downloadStaging.lastPathComponent
		for item in items {
			// A background download can finish while the app is dead, so staged IPAs get a day to be imported.
			if item.lastPathComponent == staging {
				StorageScanner.purge(contentsOf: item, olderThan: 24 * 60 * 60)
			} else {
				try? fm.removeItem(at: item)
			}
		}
	}
}

// MARK: - Library snapshot
struct AppDescriptor {
	let name: String
	let version: String?
	let date: Date
	let isSigned: Bool
}

struct LibrarySnapshot {
	let apps: [String: AppDescriptor]
	let certificates: Set<String>

	func owns(_ uuid: String, signed: Bool) -> Bool {
		apps[uuid]?.isSigned == signed
	}
}

// MARK: - Scanner
private enum StorageScanner {
	static let fm = FileManager.default

	/// A managed directory split into what the library still references and what it doesn't.
	struct Partition {
		var size: Int64 = 0
		var count = 0
		var orphans: [URL] = []
		var orphanSize: Int64 = 0
	}

	static func scan(_ library: LibrarySnapshot) -> StorageReport {
		let signed = partition(fm.signed) { library.owns($0, signed: true) }
		let imported = partition(fm.unsigned) { library.owns($0, signed: false) }
		let certificates = partition(fm.certificates) { library.certificates.contains($0) }

		let inbox = contents(of: fm.webManagerInbox)
		let leftoverSize = signed.orphanSize + imported.orphanSize + certificates.orphanSize
			+ inbox.reduce(0) { $0 + fm.allocatedSize(at: $1) }
		let leftoverCount = signed.orphans.count + imported.orphans.count + certificates.orphans.count + inbox.count

		var usages: [StorageUsage] = [
			StorageUsage(category: .signed, size: signed.size, count: signed.count),
			StorageUsage(category: .imported, size: imported.size, count: imported.count),
			StorageUsage(category: .leftovers, size: leftoverSize, count: leftoverCount),
			StorageUsage(category: .certificates, size: certificates.size, count: certificates.count),
			measure(.archives, fm.archives),
			measure(.tweaks, fm.tweaksLibrary),
			measure(.logs, fm.logs),
			measure(.temporary, fm.temporaryDirectory),
			measure(.caches, cachesDirectory)
		]

		let total = fm.allocatedSize(at: URL.documentsDirectory)
			+ fm.allocatedSize(at: libraryDirectory)
			+ fm.allocatedSize(at: fm.temporaryDirectory)

		let accounted = usages.reduce(0) { $0 + $1.size }
		usages.append(StorageUsage(category: .other, size: max(0, total - accounted), count: 0))

		return StorageReport(
			usages: usages.filter { $0.size > 0 },
			total: total,
			deviceFree: fm.availableImportantCapacity(at: URL.documentsDirectory) ?? 0
		)
	}

	static func entries(for category: StorageCategory, _ library: LibrarySnapshot) -> [StorageEntry] {
		switch category {
		case .signed, .imported:
			let signed = category == .signed
			return contents(of: signed ? fm.signed : fm.unsigned).compactMap { url in
				let uuid = url.lastPathComponent
				guard let app = library.apps[uuid], app.isSigned == signed else { return nil }
				return StorageEntry(
					id: uuid,
					name: app.name,
					version: app.version,
					size: fm.allocatedSize(at: url),
					date: app.date,
					url: url,
					appUuid: uuid
				)
			}
		case .archives:
			return contents(of: fm.archives).map(fileEntry)
		case .leftovers:
			return leftovers(library).map(fileEntry)
		default:
			return []
		}
	}

	static func clear(_ category: StorageCategory, _ library: LibrarySnapshot) {
		switch category {
		case .caches:
			URLCache.shared.removeAllCachedResponses()
			HTTPCookieStorage.shared.removeCookies(since: .distantPast)
			(ImagePipeline.shared.configuration.dataCache as? DataCache)?.removeAll()
			ImagePipeline.shared.configuration.imageCache?.removeAll()
		case .logs:
			FileLogger.clear()
		case .temporary:
			purge(contentsOf: fm.temporaryDirectory)
		case .leftovers:
			for url in leftovers(library) { try? fm.removeItem(at: url) }
		case .archives:
			purge(contentsOf: fm.archives)
		default:
			break
		}
	}

	static func leftovers(_ library: LibrarySnapshot) -> [URL] {
		partition(fm.signed) { library.owns($0, signed: true) }.orphans
		+ partition(fm.unsigned) { library.owns($0, signed: false) }.orphans
		+ partition(fm.certificates) { library.certificates.contains($0) }.orphans
		+ contents(of: fm.webManagerInbox)
	}

	static func purge(contentsOf directory: URL, olderThan age: TimeInterval? = nil) {
		for url in contents(of: directory) {
			if
				let age,
				let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
				Date().timeIntervalSince(modified) < age
			{
				continue
			}
			try? fm.removeItem(at: url)
		}
	}

	private static func partition(_ directory: URL, isKnown: (String) -> Bool) -> Partition {
		var partition = Partition()

		for url in contents(of: directory) {
			let size = fm.allocatedSize(at: url)
			if isKnown(url.lastPathComponent) {
				partition.size += size
				partition.count += 1
			} else {
				partition.orphans.append(url)
				partition.orphanSize += size
			}
		}

		return partition
	}

	private static func contents(of directory: URL) -> [URL] {
		(try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
	}

	private static func measure(_ category: StorageCategory, _ directory: URL) -> StorageUsage {
		StorageUsage(
			category: category,
			size: fm.allocatedSize(at: directory),
			count: contents(of: directory).count
		)
	}

	private static func fileEntry(_ url: URL) -> StorageEntry {
		StorageEntry(
			id: url.path,
			name: url.lastPathComponent,
			version: nil,
			size: fm.allocatedSize(at: url),
			date: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast,
			url: url,
			appUuid: nil
		)
	}

	private static var cachesDirectory: URL {
		fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
	}

	private static var libraryDirectory: URL {
		fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
	}
}
