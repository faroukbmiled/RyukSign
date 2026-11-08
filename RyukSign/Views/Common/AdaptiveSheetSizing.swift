//
//  AdaptiveSheetSizing.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI

extension View {
	/// iPad and the unfolded iPhone Duo otherwise get a small fixed form
	/// sheet. Phones keep `detents`.
	func adaptiveSheetSizing(phone detents: Set<PresentationDetent> = []) -> some View {
		modifier(AdaptiveSheetSizing(detents: detents))
	}
}

private struct AdaptiveSheetSizing: ViewModifier {
	let detents: Set<PresentationDetent>

	@ViewBuilder
	func body(content: Content) -> some View {
		if DuoDisplay.usesLargeScreenLayout {
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
