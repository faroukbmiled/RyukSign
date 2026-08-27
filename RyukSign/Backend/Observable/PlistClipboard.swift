//
//  PlistClipboard.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

/// In-session clipboard for moving entries between editors, this only needs to survive navigating between two screens.
final class PlistClipboard: ObservableObject {
	static let shared = PlistClipboard()

	@Published private(set) var entries: [String: Any] = [:]

	private init() {}

	func set(_ entries: [String: Any]) {
		self.entries = entries
	}
}
