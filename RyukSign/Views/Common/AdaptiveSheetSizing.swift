//
//  AdaptiveSheetSizing.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI

extension View {
	/// iPad otherwise gets a small fixed form sheet. Phones keep `detents`.
	func adaptiveSheetSizing(phone detents: Set<PresentationDetent> = []) -> some View {
		modifier(AdaptiveSheetSizing(detents: detents))
	}
}

private struct AdaptiveSheetSizing: ViewModifier {
	let detents: Set<PresentationDetent>

	// A sheet's own size class is always compact, even on the unfolded Duo.
	@ViewBuilder
	func body(content: Content) -> some View {
		if UIDevice.current.userInterfaceIdiom == .pad || DuoDisplay.isUnfolded() {
			if #available(iOS 18, *) {
				content.presentationSizing(.page)
			} else {
				content.presentationDetents([.large])
			}
		} else if !detents.isEmpty {
			content.presentationDetents(detents)
		} else {
			content
		}
	}
}
