//
//  NBMetrics.swift
//  NimbleKit
//
//  Central design tokens (corner radii, spacing) so values aren't copy-pasted
//  across the app. The iOS 26 "Liquid Glass" sizes live here in one place.
//

import SwiftUI

public enum NBRadius {
	/// Large rounded surfaces: sheets, the install card, certificate cells, sheet buttons.
	/// 28 on iOS 26 (Liquid Glass), 12 below.
	public static var large: CGFloat {
		if #available(iOS 26.0, *) { 28 } else { 12 }
	}

	/// List-row card background.
	public static let card: CGFloat = 18

	/// Standard control / inline surface corner.
	public static let medium: CGFloat = 12
}

public enum NBSpacing {
	/// Horizontal spacing inside list rows (icon ↔ text ↔ accessory).
	public static let row: CGFloat = 18

	/// Inset padding for a card-style list row in regular width.
	public static let cellPadding: CGFloat = 12
}
