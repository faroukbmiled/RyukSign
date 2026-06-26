//
//  KeyboardDismiss.swift
//  RyukSign
//
//  Lets the keyboard be dismissed by scrolling the list or tapping a Done button
//  above the keyboard, so text fields inside Forms/Lists never trap the user.
//

import SwiftUI
import UIKit

extension UIApplication {
	/// Resigns the current first responder (dismisses the keyboard).
	func endEditing() {
		sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
	}
}

extension View {
	/// Apply to a Form/List screen that contains text fields. Scrolling the list
	/// dismisses the keyboard interactively, and a Done button is shown above it.
	func dismissableKeyboard() -> some View {
		self
			.scrollDismissesKeyboard(.interactively)
			.toolbar {
				ToolbarItemGroup(placement: .keyboard) {
					Spacer()
					Button {
						UIApplication.shared.endEditing()
					} label: {
						Text(String.localized("Done")).fontWeight(.semibold)
					}
				}
			}
	}
}
