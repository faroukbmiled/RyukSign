//
//  NBHaptic.swift
//  NimbleKit
//
//  Tiny wrapper around UIFeedbackGenerator so tactile feedback is one call site.
//

#if canImport(UIKit)
import UIKit

public enum NBHaptic {
	/// A light tap — for primary button presses (install, get, update, sign).
	public static func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
		let generator = UIImpactFeedbackGenerator(style: style)
		generator.prepare()
		generator.impactOccurred()
	}

	/// A semantic notification — for success/warning/error outcomes.
	public static func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
		let generator = UINotificationFeedbackGenerator()
		generator.prepare()
		generator.notificationOccurred(type)
	}

	/// A selection change — for toggles / pickers.
	public static func selection() {
		let generator = UISelectionFeedbackGenerator()
		generator.prepare()
		generator.selectionChanged()
	}
}
#endif
