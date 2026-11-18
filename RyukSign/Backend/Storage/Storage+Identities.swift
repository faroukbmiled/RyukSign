//
//  Storage+Identities.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

struct AppIdentity: Identifiable {
	let identifier: String
	let app: AppInfoPresentable
	let isInstalled: Bool

	var id: String { identifier }
}

extension Storage {
	func identities(for app: AppInfoPresentable) -> [AppIdentity] {
		let key = Self._bundleKey(of: app)
		let name = app.name?.lowercased()
		let origins = AppOrigins.shared.all
		let sourceAppID = app.uuid.flatMap { origins[$0]?.appID }

		let related = getAllApps().filter { other in
			(key != nil && Self._bundleKey(of: other) == key)
			|| (name?.isEmpty == false && other.name?.lowercased() == name)
			|| (sourceAppID != nil && other.uuid.flatMap { origins[$0]?.appID } == sourceAppID)
		}
		return Self._ranked(related)
	}

	/// Signing a fresh import under this keeps it updating the copy already on the device.
	func previousIdentifier(for app: AppInfoPresentable) -> String? {
		guard !app.isSigned, let key = Self._bundleKey(of: app) else { return nil }

		let signed = ((try? context.fetch(Signed.fetchRequest())) ?? []).filter { Self._bundleKey(of: $0) == key }
		guard Set(signed.compactMap(\.identifier)).count > 1 else { return signed.first?.identifier }
		return Self._ranked(signed).first?.identifier
	}

	private static func _ranked(_ apps: [AppInfoPresentable]) -> [AppIdentity] {
		var installed: [String: Bool] = [:]
		var seen: Set<String> = []

		return apps
			.compactMap { app -> AppIdentity? in
				guard let identifier = app.identifier, !identifier.isEmpty else { return nil }

				let isInstalled = installed[identifier] ?? (InstalledAppState.current(for: identifier) != nil)
				installed[identifier] = isInstalled
				return AppIdentity(identifier: identifier, app: app, isInstalled: isInstalled)
			}
			.sorted { lhs, rhs in
				if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled }
				if lhs.app.isSigned != rhs.app.isSigned { return lhs.app.isSigned }
				return (lhs.app.date ?? .distantPast) > (rhs.app.date ?? .distantPast)
			}
			.filter { seen.insert($0.identifier).inserted }
	}

	private static func _bundleKey(of app: AppInfoPresentable) -> String? {
		app.originalIdentifier ?? app.identifier
	}
}
