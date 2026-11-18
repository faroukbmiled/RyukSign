//
//  InstallCleanup.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit
import NimbleExtensions

@MainActor
enum InstallCleanup {
	enum OtherVersions: String, CaseIterable {
		case keep, ask, delete

		var title: String {
			switch self {
			case .keep: .localized("Keep")
			case .ask: .localized("Ask Each Time")
			case .delete: .localized("Delete")
			}
		}
	}

	enum OtherVersionsScope: String, CaseIterable {
		case all, signed, imported

		var title: String {
			switch self {
			case .all: .localized("Signed & Imported")
			case .signed: .localized("Signed Only")
			case .imported: .localized("Imported Only")
			}
		}

		func includes(_ app: AppInfoPresentable) -> Bool {
			switch self {
			case .all: true
			case .signed: app.isSigned
			case .imported: !app.isSigned
			}
		}
	}

	enum VersionMatch: String, CaseIterable, Identifiable {
		case older, same, newer

		var id: Self { self }

		var key: String {
			switch self {
			case .older: "RyukSign.cleanupOlderVersions"
			case .same: "RyukSign.cleanupSameVersion"
			case .newer: "RyukSign.cleanupNewerVersions"
			}
		}

		var isOnByDefault: Bool { self == .older }

		var isIncluded: Bool {
			UserDefaults.standard.object(forKey: key) as? Bool ?? isOnByDefault
		}

		var title: String {
			switch self {
			case .older: .localized("Older")
			case .same: .localized("Same")
			case .newer: .localized("Newer")
			}
		}

		var subtitle: String {
			switch self {
			case .older: .localized("Deletes older versions of the app")
			case .same: .localized("Deletes copies with the same version")
			case .newer: .localized("Deletes newer versions of the app")
			}
		}

		static var summary: String {
			let included = allCases.filter(\.isIncluded)
			switch included.count {
			case 0: return .localized("None")
			case allCases.count: return .localized("All")
			default: return included.map(\.title).joined(separator: ", ")
			}
		}
	}

	static let deleteKey = "Feather.deleteAppAfterInstall"
	static let clearCacheKey = "Feather.clearCacheAfterInstall"
	static let otherVersionsKey = "RyukSign.olderVersionsAfterInstall"
	static let otherVersionsScopeKey = "RyukSign.olderVersionsScope"
	private static let pendingKey = "Feather.installCleanupPending"

	// Persisted so a kill before flush() still cleans up.
	static func stage(_ app: AppInfoPresentable) {
		guard let uuid = app.uuid, !_pending.contains(uuid) else { return }
		_pending.append(uuid)
	}

	// Queued apps wait for the next flush.
	static func flush() {
		let shown = Set(InstallQueue.shared.apps.compactMap(\.base.uuid))
		let uuids = _pending.filter { !shown.contains($0) }
		guard !uuids.isEmpty else { return }
		defer { _pending = _pending.filter(shown.contains) }

		let defaults = UserDefaults.standard
		let apps = Storage.shared.getAllApps()
		let others = _otherVersions(of: uuids, in: apps).filter { !shown.contains($0.uuid ?? "") }

		if defaults.bool(forKey: deleteKey) {
			Storage.shared.deleteApps(apps.filter { uuids.contains($0.uuid ?? "") })
		}

		if defaults.bool(forKey: clearCacheKey) {
			StorageManager.purgeCaches()
		}

		switch _otherVersionsMode {
		case .delete: Storage.shared.deleteApps(others)
		case .ask: _confirmDeleting(others)
		case .keep: break
		}
	}

	private static var _pending: [String] {
		get { UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] }
		set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
	}

	// MARK: Other versions

	private static var _otherVersionsMode: OtherVersions {
		OtherVersions(rawValue: UserDefaults.standard.string(forKey: otherVersionsKey) ?? "") ?? .keep
	}

	// Bundle id only: a name match could delete an unrelated app.
	private static func _otherVersions(of uuids: [String], in apps: [AppInfoPresentable]) -> [AppInfoPresentable] {
		guard _otherVersionsMode != .keep else { return [] }

		let defaults = UserDefaults.standard
		let scope = OtherVersionsScope(rawValue: defaults.string(forKey: otherVersionsScopeKey) ?? "") ?? .all
		let matches = Set(VersionMatch.allCases.filter(\.isIncluded))
		let installed = apps.filter { uuids.contains($0.uuid ?? "") }

		return apps.filter { app in
			guard
				let uuid = app.uuid,
				!uuids.contains(uuid),
				let version = app.version,
				scope.includes(app)
			else {
				return false
			}

			return installed.contains { new in
				let sameApp = app.isSigned
					? app.identifier != nil && app.identifier == new.identifier
					: app.originalIdentifier != nil && app.originalIdentifier == new.originalIdentifier
				guard sameApp else { return false }

				let installedVersion = new.version ?? ""
				if AppUpdateChecker.isNewerVersion(installedVersion, than: version) { return matches.contains(.older) }
				if AppUpdateChecker.isNewerVersion(version, than: installedVersion) { return matches.contains(.newer) }
				return matches.contains(.same)
			}
		}
	}

	private static func _confirmDeleting(_ apps: [AppInfoPresentable]) {
		guard !apps.isEmpty else { return }

		let uuids = Set(apps.compactMap(\.uuid))
		let size = apps.reduce(Int64(0)) { total, app in
			total + (Storage.shared.getUuidDirectory(for: app).map(FileManager.default.allocatedSize) ?? 0)
		}
		let names = Set(apps.compactMap(\.name)).sorted().joined(separator: ", ")

		// Presenting while the install card animates out drops the alert.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
			guard let presenter = UIApplication.topViewController() else { return }

			UIAlertController.showAlert(
				presenter,
				title: .localized("Delete Other Versions?"),
				message: .localized("Other versions of %@ use %@.", arguments: names, size.formattedFileSize),
				actions: [
					UIAlertAction(title: .localized("Keep"), style: .cancel),
					UIAlertAction(title: .localized("Delete"), style: .destructive) { _ in
						Storage.shared.deleteApps(Storage.shared.getAllApps().filter { uuids.contains($0.uuid ?? "") })
					}
				]
			)
		}
	}
}
