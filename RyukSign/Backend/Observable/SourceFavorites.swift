//
//  SourceFavorites.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

final class SourceFavorites: ObservableObject {
	static let shared = SourceFavorites()

	private static let _key = "RyukSign.favoriteSources"

	@Published private(set) var identifiers: Set<String>

	private init() {
		identifiers = Set(UserDefaults.standard.stringArray(forKey: Self._key) ?? [])
	}

	func contains(_ source: AltSource) -> Bool {
		source.identifier.map(identifiers.contains) ?? false
	}

	func toggle(_ source: AltSource) {
		guard let id = source.identifier else { return }
		if !identifiers.insert(id).inserted { identifiers.remove(id) }
		UserDefaults.standard.set(Array(identifiers), forKey: Self._key)
	}
}
