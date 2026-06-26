//
//  TabEnum.swift
//  feather
//
//  Created by samara on 22.03.2025.
//
import SwiftUI
import NimbleViews

enum TabEnum: String, CaseIterable, Hashable, Codable {
	case sources
	case library
	case tweaks
	case settings
	case certificates

	var title: String {
		switch self {
		case .sources:     	return .localized("Sources")
		case .library: 		return .localized("Library")
		case .tweaks: 		return .localized("Tweaks")
		case .settings: 	return .localized("Settings")
		case .certificates:	return .localized("Certificates")
		}
	}

	var icon: String {
		switch self {
		case .sources: 		return "globe.desk"
		case .library: 		return "square.grid.2x2"
		case .tweaks: 		return "wrench.and.screwdriver"
		case .settings: 	return "gearshape.2"
		case .certificates: return "person.text.rectangle"
		}
	}

	@ViewBuilder
	static func view(for tab: TabEnum) -> some View {
		switch tab {
		case .sources: SourcesView()
		case .library: LibraryView()
		case .tweaks: TweaksView()
		case .settings: SettingsView()
		case .certificates: NBNavigationView(.localized("Certificates")) { CertificatesView() }
		}
	}

	static var defaultTabs: [TabEnum] {
		return [
			.sources,
			.library,
			.tweaks,
			.settings
		]
	}
	
	static var customizableTabs: [TabEnum] {
		return [
			.certificates
		]
	}
}
