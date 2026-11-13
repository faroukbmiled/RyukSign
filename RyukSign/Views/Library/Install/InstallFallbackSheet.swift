//
//  InstallFallbackSheet.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

private struct InstallFallbackSheet: ViewModifier {
	@ObservedObject var installer: AppInstaller

	func body(content: Content) -> some View {
		content.sheet(item: Binding(
			get: { installer.fallbackPage.map(Page.init) },
			set: { installer.fallbackPage = $0?.url }
		)) { page in
			SafariRepresentableView(url: page.url).ignoresSafeArea()
		}
	}

	private struct Page: Identifiable {
		let url: URL
		var id: URL { url }
	}
}

extension View {
	func installFallbackSheet(_ installer: AppInstaller) -> some View {
		modifier(InstallFallbackSheet(installer: installer))
	}
}
