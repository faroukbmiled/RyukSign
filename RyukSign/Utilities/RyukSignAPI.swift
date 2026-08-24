//
//  RyukSignAPI.swift
//  RyukSign
//
//  RyukSign configuration and constants
//

import Foundation
import UIKit
import Security

enum RyukSignAPI {
	// MARK: - Contact

	static let telegramUsername = "@axryuk"
	static let telegramURL = URL(string: "https://t.me/axryuk")!
	static let contactSuffix = "Contact \(telegramUsername) on Telegram"

	// MARK: - API

	static let apiBaseURL = "https://ryuksign.com/api"
	/// Key validation (POST, consumes key).
	static let apiValidateEndpoint = "\(apiBaseURL)/validate"
	/// URL preview (GET, doesn't consume key).
	static let apiURLsEndpoint = "\(apiBaseURL)/urls"
	static let apiHealthEndpoint = "\(apiBaseURL)/health"

	// MARK: - API Models

	struct URLsResponse: Decodable {
		struct Item: Decodable {
			let url: String
		}

		let urls: [Item]?
	}

	struct ErrorResponse: Decodable {
		let detail: String
	}

	// MARK: - Repos

	static let reposListURL = URL(string: "https://raw.githubusercontent.com/faroukbmiled/RyukSign/refs/heads/main/repos.json")!

	// MARK: - Device Identity

	static var deviceUUID: String? {
		if let existing = IdentityVault.read(.deviceUUID) {
			return existing
		}

		let uuid = UUID().uuidString
		IdentityVault.write(.deviceUUID, uuid)
		return uuid
	}

	@discardableResult
	static func adoptDeviceUUID(_ uuid: String) -> Bool {
		let trimmed = uuid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
		guard UUID(uuidString: trimmed) != nil else { return false }

		IdentityVault.write(.deviceUUID, trimmed)
		return true
	}

	// MARK: - Premium State

	static var isPremium: Bool {
		get { IdentityVault.read(.premiumActive) == "true" }
		set {
			if newValue {
				IdentityVault.write(.premiumActive, "true")
			} else {
				IdentityVault.delete(.premiumActive)
			}
		}
	}

	static func savePremiumURLs(_ urls: [URL]) {
		let strings = urls.map { $0.absoluteString }
		guard
			let data = try? JSONEncoder().encode(strings),
			let encoded = String(data: data, encoding: .utf8)
		else {
			return
		}

		IdentityVault.write(.premiumURLs, encoded)
	}

	static func getSavedPremiumURLs() -> [URL]? {
		guard
			let encoded = IdentityVault.read(.premiumURLs),
			let data = encoded.data(using: .utf8),
			let strings = try? JSONDecoder().decode([String].self, from: data)
		else {
			return nil
		}

		let urls = strings.compactMap { URL(string: $0) }
		return urls.isEmpty ? nil : urls
	}

	static func clearPremiumIdentity() {
		IdentityVault.delete(.premiumActive)
		IdentityVault.delete(.premiumURLs)
	}

	/// Activation survived in the vault but this install has no premium sources.
	static var hasStoredPremiumButNotLocal: Bool {
		isPremium && premiumSourceHosts.isEmpty
	}

	// MARK: - Migration

	/// Rebuilds the vault from this install, so a wiped keychain doesn't cost premium access.
	static func migrateIfNeeded() {
		let hosts = premiumSourceHosts
		guard !hosts.isEmpty else { return }

		if !isPremium {
			isPremium = true
		}

		guard getSavedPremiumURLs() == nil else { return }

		let premiumURLs = Storage.shared.getSources().compactMap { $0.sourceURL }.filter { url in
			guard let host = url.host?.lowercased() else { return false }
			return hosts.contains(host)
		}

		if !premiumURLs.isEmpty {
			savePremiumURLs(premiumURLs)
		}
	}

	// MARK: - Premium Sources Storage (UserDefaults)

	private static let premiumSourcesKey = "RyukSign.premiumSourceHosts"

	static var premiumSourceHosts: Set<String> {
		get {
			let array = UserDefaults.standard.stringArray(forKey: premiumSourcesKey) ?? []
			return Set(array)
		}
		set {
			UserDefaults.standard.set(Array(newValue), forKey: premiumSourcesKey)
		}
	}

	static func registerPremiumSource(_ url: URL) {
		guard let host = url.host?.lowercased() else { return }
		var hosts = premiumSourceHosts
		hosts.insert(host)
		premiumSourceHosts = hosts
	}

	static func registerPremiumSources(_ urls: [URL]) {
		var hosts = premiumSourceHosts
		for url in urls {
			if let host = url.host?.lowercased() {
				hosts.insert(host)
			}
		}
		premiumSourceHosts = hosts
	}

	static func isPremiumSource(_ url: URL) -> Bool {
		guard let host = url.host?.lowercased() else { return false }
		return premiumSourceHosts.contains(host)
	}

	/// Unregister a premium source host once no remaining source uses it.
	static func unregisterPremiumSourceIfNeeded(_ url: URL, remainingSourceURLs: [URL]) {
		guard let host = url.host?.lowercased() else { return }
		guard premiumSourceHosts.contains(host) else { return }

		let otherSourcesWithSameHost = remainingSourceURLs.filter { sourceURL in
			guard let sourceHost = sourceURL.host?.lowercased() else { return false }
			return sourceHost == host
		}

		if otherSourcesWithSameHost.isEmpty {
			var hosts = premiumSourceHosts
			hosts.remove(host)
			premiumSourceHosts = hosts
		}
	}

	static func authHeaders(for url: URL) -> [String: String] {
		guard isPremiumSource(url), let uuid = deviceUUID else {
			return [:]
		}
		return ["ryukSignUUID": uuid]
	}

	/// Lets the server trim the payload instead of downloading the whole catalog first.
	@MainActor
	static func catalogURL(for url: URL) -> URL {
		guard isPremiumSource(url) else { return url }

		let items = PremiumFilterPreferences.shared.queryItems
		guard
			!items.isEmpty,
			var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
		else {
			return url
		}

		components.queryItems = (components.queryItems ?? []) + items
		return components.url ?? url
	}

	static func applyAuthHeaders(to request: inout URLRequest) {
		guard let url = request.url, isPremiumSource(url), let uuid = deviceUUID else {
			return
		}
		request.setValue(uuid, forHTTPHeaderField: "ryukSignUUID")
	}

	// MARK: - Excluded Sources

	private static let excludedSourcesKey = "RyukSign.excludedSourceIdentifiers"

	/// Set of source identifiers excluded from "All Repositories"
	static var excludedSourceIdentifiers: Set<String> {
		get {
			let array = UserDefaults.standard.stringArray(forKey: excludedSourcesKey) ?? []
			return Set(array)
		}
		set {
			UserDefaults.standard.set(Array(newValue), forKey: excludedSourcesKey)
		}
	}

	static func isSourceExcluded(_ identifier: String) -> Bool {
		excludedSourceIdentifiers.contains(identifier)
	}

	static func setSourceExcluded(_ identifier: String, excluded: Bool) {
		var ids = excludedSourceIdentifiers
		if excluded {
			ids.insert(identifier)
		} else {
			ids.remove(identifier)
		}
		excludedSourceIdentifiers = ids
	}

	// MARK: - Helper Methods

	static func openTelegram() {
		UIApplication.shared.open(telegramURL)
	}

	static func errorMessage(_ message: String, includeContact: Bool = false) -> String {
		if includeContact {
			return "\(message)\n\n\(contactSuffix)"
		}
		return message
	}
}
