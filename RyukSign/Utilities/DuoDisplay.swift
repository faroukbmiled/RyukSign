//
//  DuoDisplay.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit

enum DuoDisplay {
	static func supportedOrientations(for window: UIWindow?) -> UIInterfaceOrientationMask {
		guard UIDevice.current.userInterfaceIdiom == .phone else { return .all }
		return isUnfolded(window) ? .allButUpsideDown : .portrait
	}

	static func isUnfolded(_ window: UIWindow? = nil) -> Bool {
		guard UIDevice.current.userInterfaceIdiom == .phone else { return false }

		let bounds = (window?.windowScene ?? _activeScene)?.screen.bounds ?? .zero
		return min(bounds.width, bounds.height) > 600
	}

	static func refreshSupportedOrientations() {
		guard UIDevice.current.userInterfaceIdiom == .phone else { return }

		for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
			scene.windows.forEach { $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations() }
		}
	}

	private static var _activeScene: UIWindowScene? {
		let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
		return scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
	}
}
