//
//  ImportFolder.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import UniformTypeIdentifiers
import NimbleViews

enum ImportFolder: String, CaseIterable, Identifiable {
	case certificates
	case apps
	case tweaks
	case entitlements
	case pairing
	case backups
	case icons

	var id: String { rawValue }

	var bookmarkKey: String { "RyukSign.importFolderBookmark.\(rawValue)" }
	var nameKey: String { "RyukSign.importFolderName.\(rawValue)" }

	var title: String {
		switch self {
		case .certificates: .localized("Certificates")
		case .apps: .localized("Apps")
		case .tweaks: .localized("Tweaks")
		case .entitlements: .localized("Entitlements")
		case .pairing: .localized("Pairing Files")
		case .backups: .localized("Backups")
		case .icons: .localized("App Icons")
		}
	}

	var icon: String {
		switch self {
		case .certificates: "checkmark.seal"
		case .apps: "app.badge"
		case .tweaks: "wrench.and.screwdriver"
		case .entitlements: "list.bullet.rectangle"
		case .pairing: "cable.connector"
		case .backups: "externaldrive"
		case .icons: "photo"
		}
	}

	var folderName: String? {
		let name = UserDefaults.standard.string(forKey: nameKey) ?? ""
		return name.isEmpty ? nil : name
	}

	func clear() {
		UserDefaults.standard.removeObject(forKey: bookmarkKey)
		UserDefaults.standard.removeObject(forKey: nameKey)
	}
}

extension FileImporterRepresentableView {
	init(
		allowedContentTypes: [UTType],
		allowsMultipleSelection: Bool = false,
		folder: ImportFolder,
		onDocumentsPicked: @escaping ([URL]) -> Void
	) {
		self.init(
			allowedContentTypes: allowedContentTypes,
			allowsMultipleSelection: allowsMultipleSelection,
			folderBookmarkKey: folder.bookmarkKey,
			onDocumentsPicked: onDocumentsPicked
		)
	}
}
