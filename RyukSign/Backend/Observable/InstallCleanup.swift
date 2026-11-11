//
//  InstallCleanup.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import UIKit
import NimbleExtensions

/// What to do with older versions of an app once a newer one has installed.
enum OldVersionCleanup: String, CaseIterable, Identifiable {
	case ask, delete, keep

	var id: String { rawValue }

	var label: String {
		switch self {
		case .ask: .localized("Ask")
		case .delete: .localized("Always Delete")
		case .keep: .localized("Always Keep")
		}
	}
}

/// Which library copies of an older version get deleted.
enum OldVersionScope: String, CaseIterable, Identifiable {
	case both, signed, imported

	var id: String { rawValue }

	var label: String {
		switch self {
		case .both: .localized("Signed & Imported")
		case .signed: .localized("Signed Only")
		case .imported: .localized("Imported Only")
		}
	}

	func includes(_ app: AppInfoPresentable) -> Bool {
		switch self {
		case .both: true
		case .signed: app.isSigned
		case .imported: !app.isSigned
		}
	}
}

@MainActor
enum InstallCleanup {
	static let deleteKey = "Feather.deleteAppAfterInstall"
	static let clearCacheKey = "Feather.clearCacheAfterInstall"
	static let oldVersionsKey = "RyukSign.oldVersionCleanup"
	static let oldVersionsScopeKey = "RyukSign.oldVersionCleanupScope"
	private static let pendingKey = "Feather.installCleanupPending"

	/// Deleting now would pull the app out from under the card still showing it. On disk so a kill
	/// before `flush()` still cleans up.
	static func stage(_ app: AppInfoPresentable) {
		guard let uuid = app.uuid, !_pending.contains(uuid) else { return }
		_pending.append(uuid)
	}

	/// Only safe once the install UI is gone.
	static func flush() {
		let uuids = _pending
		guard !uuids.isEmpty else { return }
		_pending = []

		let defaults = UserDefaults.standard

		// Resolved first: the delete below can remove the very app the older versions are compared against.
		let stale = _staleVersions(of: uuids)

		if defaults.bool(forKey: deleteKey) {
			let apps = Storage.shared.getAllApps().filter { uuids.contains($0.uuid ?? "") }
			Storage.shared.deleteApps(apps)
		}

		if defaults.bool(forKey: clearCacheKey) {
			StorageManager.purgeCaches()
		}

		_handleStale(stale)
	}

	private static var _pending: [String] {
		get { UserDefaults.standard.stringArray(forKey: pendingKey) ?? [] }
		set { UserDefaults.standard.set(newValue, forKey: pendingKey) }
	}

	// MARK: - Old versions

	private static var _mode: OldVersionCleanup {
		OldVersionCleanup(rawValue: UserDefaults.standard.string(forKey: oldVersionsKey) ?? "") ?? .ask
	}

	private static var _scope: OldVersionScope {
		OldVersionScope(rawValue: UserDefaults.standard.string(forKey: oldVersionsScopeKey) ?? "") ?? .both
	}

	/// Library copies of the same app with a strictly older version than the one just installed.
	/// Matched on the original identifier only, since this deletes files.
	private static func _staleVersions(of uuids: [String]) -> [AppInfoPresentable] {
		guard _mode != .keep else { return [] }

		let all = Storage.shared.getAllApps()
		var seen = Set<String>()
		var stale: [AppInfoPresentable] = []

		for installed in all where uuids.contains(installed.uuid ?? "") {
			guard let identifier = installed.originalIdentifier, !identifier.isEmpty else { continue }

			for other in all where other.originalIdentifier == identifier {
				guard
					let uuid = other.uuid,
					!uuids.contains(uuid),
					AppUpdateChecker.shared.hasUpdate(installedVersion: other.version, sourceVersion: installed.version),
					seen.insert(uuid).inserted
				else { continue }

				stale.append(other)
			}
		}

		return stale
	}

	private static func _handleStale(_ stale: [AppInfoPresentable]) {
		guard !stale.isEmpty else { return }

		switch _mode {
		case .keep:
			break
		case .delete:
			_delete(stale.map { (uuid: $0.uuid ?? "", isSigned: $0.isSigned) }, scope: _scope)
		case .ask:
			_ask(stale)
		}
	}

	/// Re-resolved by uuid: the objects may be gone by the time the user answers.
	private static func _delete(_ refs: [(uuid: String, isSigned: Bool)], scope: OldVersionScope) {
		let wanted = Set(refs.filter { ref in
			switch scope {
			case .both: true
			case .signed: ref.isSigned
			case .imported: !ref.isSigned
			}
		}.map(\.uuid))
		guard !wanted.isEmpty else { return }

		Storage.shared.deleteApps(Storage.shared.getAllApps().filter { wanted.contains($0.uuid ?? "") })
	}

	private static func _ask(_ stale: [AppInfoPresentable]) {
		let refs = stale.map { (uuid: $0.uuid ?? "", isSigned: $0.isSigned) }
		let signed = stale.filter(\.isSigned)
		let imported = stale.filter { !$0.isSigned }

		func size(_ apps: [AppInfoPresentable]) -> Int64 {
			apps.reduce(0) { total, app in
				total + (Storage.shared.getUuidDirectory(for: app).map { FileManager.default.allocatedSize(at: $0) } ?? 0)
			}
		}

		var scopes: [OldVersionScope] = []
		if !signed.isEmpty && !imported.isEmpty { scopes.append(.both) }
		if !signed.isEmpty { scopes.append(.signed) }
		if !imported.isEmpty { scopes.append(.imported) }

		let sizes: [OldVersionScope: Int64] = [
			.both: size(stale),
			.signed: size(signed),
			.imported: size(imported)
		]

		// The configured scope goes first so it reads as the suggested one.
		let preferred = _scope
		scopes.sort { ($0 == preferred ? 0 : 1) < ($1 == preferred ? 0 : 1) }

		let names = Array(Set(stale.compactMap(\.name))).sorted().prefix(3).joined(separator: ", ")

		// Waits for the install card to finish leaving, or the alert presents onto a dying view.
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
			// No UI yet (cold launch): keep everything rather than delete unasked.
			guard let presenter = UIApplication.topViewController() else { return }

			var actions: [UIAlertAction] = scopes.map { scope in
				let title = scopes.count == 1
					? String.localized("Delete (%@)", arguments: (sizes[scope] ?? 0).formattedFileSize)
					: String.localized("Delete %@ (%@)", arguments: scope.label, (sizes[scope] ?? 0).formattedFileSize)
				return UIAlertAction(title: title, style: .destructive) { _ in
					_delete(refs, scope: scope)
				}
			}
			actions.append(UIAlertAction(title: .localized("Keep"), style: .cancel, handler: nil))

			UIAlertController.showAlert(
				presenter,
				title: .localized("Delete Previous Versions?"),
				message: .localized(
					"Older versions of %@ are still stored (%lld signed, %lld imported). You can change this in Settings > Storage.",
					arguments: names, signed.count, imported.count
				),
				actions: actions
			)
		}
	}
}
