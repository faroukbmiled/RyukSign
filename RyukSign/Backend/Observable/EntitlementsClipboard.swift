//
//  EntitlementsClipboard.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

/// In-session clipboard for moving entries between files, this only needs to survive navigating between two editors.
final class EntitlementsClipboard: ObservableObject {
	static let shared = EntitlementsClipboard()

	@Published private(set) var entries: [String: Any] = [:]

	private init() {}

	func set(_ entries: [String: Any]) {
		self.entries = entries
	}
}
