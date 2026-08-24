//
//  Color+userTint.swift
//  RyukSign
//
//  Created by Ryuk on 24.08.2026.
//

import SwiftUI
import AltSourceKit

extension Color {
	static let defaultUserTintHex = "#B496DC"

	static var userTint: Color {
		Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? defaultUserTintHex)
	}

	/// Darker sibling of the user's tint for secondary states.
	static var userTintDeep: Color {
		Color(uiColor: UIColor(userTint).darkened())
	}
}

private extension UIColor {
	func darkened() -> UIColor {
		var hue: CGFloat = 0
		var saturation: CGFloat = 0
		var brightness: CGFloat = 0
		var alpha: CGFloat = 0

		guard getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha) else { return self }

		return UIColor(
			hue: hue,
			saturation: min(saturation * 1.1, 1),
			// Floor keeps a near-black tint from vanishing into a dark background.
			brightness: min(max(brightness * 0.62, 0.32), 0.78),
			alpha: alpha
		)
	}
}
