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

	// MARK: - Repos

	static let reposListURL = URL(string: "https://raw.githubusercontent.com/faroukbmiled/RyukSign/refs/heads/main/repos.json")!

	// MARK: - Keychain Device UUID

	private static let keychainService = "com.ryuksign.deviceuuid"
	private static let keychainAccount = "deviceUUID"

	/// Device UUID in Keychain (survives reinstalls).
	static var deviceUUID: String? {
		if let existingUUID = getKeychainUUID() {
			return existingUUID
		}

		let newUUID = UUID().uuidString
		if saveKeychainUUID(newUUID) {
			return newUUID
		}

		// Fallback to vendor ID if Keychain fails
		return UIDevice.current.identifierForVendor?.uuidString
	}

	private static func getKeychainUUID() -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: keychainService,
			kSecAttrAccount as String: keychainAccount,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]

		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)

		guard status == errSecSuccess,
			  let data = result as? Data,
			  let uuid = String(data: data, encoding: .utf8) else {
			return nil
		}

		return uuid
	}

	private static func saveKeychainUUID(_ uuid: String) -> Bool {
		guard let data = uuid.data(using: .utf8) else { return false }

		let deleteQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: keychainService,
			kSecAttrAccount as String: keychainAccount
		]
		SecItemDelete(deleteQuery as CFDictionary)

		let addQuery: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: keychainService,
			kSecAttrAccount as String: keychainAccount,
			kSecValueData as String: data,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]

		let status = SecItemAdd(addQuery as CFDictionary, nil)
		return status == errSecSuccess
	}

	// MARK: - Premium State (Keychain-persisted)

	private static let premiumStateService = "com.ryuksign.premium"
	private static let premiumStateAccount = "isPremium"
	private static let premiumURLsAccount = "premiumURLs"

	/// Premium activation state (survives reinstall via Keychain).
	static var isPremium: Bool {
		get { _getKeychainString(service: premiumStateService, account: premiumStateAccount) == "true" }
		set {
			if newValue {
				_saveKeychainString("true", service: premiumStateService, account: premiumStateAccount)
			} else {
				_deleteKeychainItem(service: premiumStateService, account: premiumStateAccount)
			}
		}
	}

	/// Save premium repo URLs to keychain for reinstall recovery.
	static func savePremiumURLsToKeychain(_ urls: [URL]) {
		let strings = urls.map { $0.absoluteString }
		guard let data = try? JSONEncoder().encode(strings) else { return }
		guard let encoded = String(data: data, encoding: .utf8) else { return }
		_saveKeychainString(encoded, service: premiumStateService, account: premiumURLsAccount)
	}

	static func getSavedPremiumURLs() -> [URL]? {
		guard let encoded = _getKeychainString(service: premiumStateService, account: premiumURLsAccount),
			  let data = encoded.data(using: .utf8),
			  let strings = try? JSONDecoder().decode([String].self, from: data) else {
			return nil
		}
		let urls = strings.compactMap { URL(string: $0) }
		return urls.isEmpty ? nil : urls
	}

	static func clearPremiumKeychain() {
		_deleteKeychainItem(service: premiumStateService, account: premiumStateAccount)
		_deleteKeychainItem(service: premiumStateService, account: premiumURLsAccount)
	}

	/// Keychain has premium but UserDefaults doesn't (reinstall scenario).
	static var hasKeychainPremiumButNotLocal: Bool {
		return isPremium && premiumSourceHosts.isEmpty
	}

	// MARK: - Generic Keychain Helpers

	private static func _getKeychainString(service: String, account: String) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]
		var result: AnyObject?
		let status = SecItemCopyMatching(query as CFDictionary, &result)
		guard status == errSecSuccess,
			  let data = result as? Data,
			  let string = String(data: data, encoding: .utf8) else {
			return nil
		}
		return string
	}

	private static func _saveKeychainString(_ string: String, service: String, account: String) {
		guard let data = string.data(using: .utf8) else { return }
		_deleteKeychainItem(service: service, account: account)
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account,
			kSecValueData as String: data,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]
		SecItemAdd(query as CFDictionary, nil)
	}

	private static func _deleteKeychainItem(service: String, account: String) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: service,
			kSecAttrAccount as String: account
		]
		SecItemDelete(query as CFDictionary)
	}

	// MARK: - Migration

	/// Migrates existing premium users to keychain persistence.
	/// Idempotent: safe to call on every launch — no-op once keychain is populated.
	static func migrateIfNeeded() {
		let hosts = premiumSourceHosts
		guard !hosts.isEmpty, !isPremium else { return }

		// Premium hosts in UserDefaults but nothing in keychain — old version.
		isPremium = true

		let sources = Storage.shared.getSources()
		let premiumURLs = sources.compactMap { $0.sourceURL }.filter { url in
			guard let host = url.host?.lowercased() else { return false }
			return hosts.contains(host)
		}

		if !premiumURLs.isEmpty {
			savePremiumURLsToKeychain(premiumURLs)
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
