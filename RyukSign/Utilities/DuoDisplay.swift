//
//  DuoDisplay.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit

/// iPhone Duo support. Unfolded, the Duo's inner display is a phone screen
/// whose longer side exceeds any single-panel iPhone; folded, its cover
/// display is phone-sized. Classifying by the screen keeps ordinary iPhones
/// and iPad untouched without relying on a device identifier.
enum DuoDisplay {
	/// Points. The tallest single-panel iPhone is under 960pt.
	static let wideCanvasThreshold: CGFloat = 1000

	static func isUnfolded(_ screen: UIScreen?) -> Bool {
		guard
			UIDevice.current.userInterfaceIdiom == .phone,
			let bounds = screen?.bounds
		else {
			return false
		}
		return max(bounds.width, bounds.height) > wideCanvasThreshold
	}

	/// The screen hosting the app's foreground scene.
	static var isUnfolded: Bool {
		isUnfolded(_activeScreen)
	}

	/// iPad, or an unfolded Duo, both of which get the large-screen layouts.
	static var usesLargeScreenLayout: Bool {
		UIDevice.current.userInterfaceIdiom == .pad || isUnfolded
	}

	static func supportedOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
		if UIDevice.current.userInterfaceIdiom == .pad {
			return .all
		}
		let screen = window?.windowScene?.screen ?? _activeScreen
		return isUnfolded(screen) ? .allButUpsideDown : .portrait
	}

	/// UIKit only asks for orientations again when told to, so a window that
	/// folds onto the cover display would otherwise keep landscape.
	static func refreshSupportedOrientations() {
		guard UIDevice.current.userInterfaceIdiom == .phone else { return }
		for scene in UIApplication.shared.connectedScenes {
			guard let scene = scene as? UIWindowScene else { continue }
			for window in scene.windows {
				window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
			}
		}
	}

	private static var _activeScreen: UIScreen? {
		let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
		return scene?.screen
	}
}
