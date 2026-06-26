//
//  SkippedUpdatesManager.swift
//  RyukSign
//
//  Bundle IDs the user has muted for update checks (excluded from the count/badge
//  and Updates tab, but still updatable manually).
//

import Foundation
import Combine

final class SkippedUpdatesManager: ObservableObject {
	static let shared = SkippedUpdatesManager()

	static let defaultsKey = "Feather.skippedUpdateBundleIDs"

	/// Muted bundle IDs. Mutated on the main thread (drives UI).
	@Published private(set) var bundleIDs: Set<String>

	private init() {
		bundleIDs = Self.persisted
	}

	/// Snapshot from UserDefaults — safe off the main thread.
	static var persisted: Set<String> {
		Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
	}

	var sortedBundleIDs: [String] {
		bundleIDs.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
	}

	func isIgnored(_ bundleID: String?) -> Bool {
		guard let bundleID, !bundleID.isEmpty else { return false }
		return bundleIDs.contains(bundleID)
	}

	func ignore(_ bundleID: String?) {
		guard let bundleID, !bundleID.isEmpty else { return }
		bundleIDs.insert(bundleID)
		_persist()
	}

	func resume(_ bundleID: String?) {
		guard let bundleID else { return }
		bundleIDs.remove(bundleID)
		_persist()
	}

	func toggle(_ bundleID: String?) {
		guard let bundleID, !bundleID.isEmpty else { return }
		if bundleIDs.contains(bundleID) {
			bundleIDs.remove(bundleID)
		} else {
			bundleIDs.insert(bundleID)
		}
		_persist()
	}

	private func _persist() {
		UserDefaults.standard.set(Array(bundleIDs), forKey: Self.defaultsKey)
		NotificationCenter.default.post(name: .skippedUpdatesChanged, object: nil)
	}
}

extension Notification.Name {
	static let skippedUpdatesChanged = Notification.Name("Feather.skippedUpdatesChanged")
}
