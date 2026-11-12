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
	enum OlderVersions: String, CaseIterable {
		case ask, delete, keep

		var title: String {
			switch self {
			case .ask: .localized("Ask")
			case .delete: .localized("Delete")
			case .keep: .localized("Keep")
			}
		}
	}

	enum OlderVersionsScope: String, CaseIterable {
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

	static let deleteKey = "Feather.deleteAppAfterInstall"
	static let clearCacheKey = "Feather.clearCacheAfterInstall"
	static let olderVersionsKey = "RyukSign.olderVersionsAfterInstall"
	static let olderVersionsScopeKey = "RyukSign.olderVersionsScope"
	private static let pendingKey = "Feather.installCleanupPending"

	// Persisted so a kill before flush() still cleans up.
	static func stage(_ app: AppInfoPresentable) {
		guard let uuid = app.uuid, !_pending.contains(uuid) else { return }
		_pending.append(uuid)
	}

	// Only safe once the install UI is gone; pending is cleared last so a kill reruns it on launch.
	static func flush() {
		let uuids = _pending
		guard !uuids.isEmpty else { return }
		defer { _pending = [] }

		let defaults = UserDefaults.standard
		let apps = Storage.shared.getAllApps()
		let older = _olderVersions(of: uuids, in: apps)

		if defaults.bool(forKey: deleteKey) {
			Storage.shared.deleteApps(apps.filter { uuids.contains($0.uuid ?? "") })
		}

		if defaults.bool(forKey: clearCacheKey) {
			StorageManager.purgeCaches()
		}

		switch _olderVersionsMode {
		case .delete: Storage.shared.deleteApps(older)
		case .ask: _confirmDeleting(older)
		case .keep: break
		}
	}

	private static var _pending: [String] {
		get { UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] }
		set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
	}

	// MARK: Older versions

	private static var _olderVersionsMode: OlderVersions {
		OlderVersions(rawValue: UserDefaults.standard.string(forKey: olderVersionsKey) ?? "") ?? .ask
	}

	// Bundle id only: a name match could delete an unrelated app.
	private static func _olderVersions(of uuids: [String], in apps: [AppInfoPresentable]) -> [AppInfoPresentable] {
		guard _olderVersionsMode != .keep else { return [] }

		let scope = OlderVersionsScope(rawValue: UserDefaults.standard.string(forKey: olderVersionsScopeKey) ?? "") ?? .all
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
				return sameApp && AppUpdateChecker.isNewerVersion(new.version ?? "", than: version)
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
				title: .localized("Delete Older Versions?"),
				message: .localized("Older versions of %@ use %@.", arguments: names, size.formattedFileSize),
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
