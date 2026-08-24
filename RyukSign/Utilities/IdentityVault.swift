//
//  IdentityVault.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Security

/// Keychain survives reinstalls but gets wiped by dev tooling and restores, so every
/// value is mirrored to disk and defaults, and a missing tier heals on the next read.
enum IdentityVault {
	enum Key: String {
		case deviceUUID
		case premiumActive
		case premiumURLs

		var service: String {
			switch self {
			case .deviceUUID: return "com.ryuksign.deviceuuid"
			case .premiumActive, .premiumURLs: return "com.ryuksign.premium"
			}
		}

		var account: String {
			switch self {
			case .deviceUUID: return "deviceUUID"
			case .premiumActive: return "isPremium"
			case .premiumURLs: return "premiumURLs"
			}
		}

		var defaultsKey: String { "RyukSign.vault.\(rawValue)" }
	}

	private static let _lock = NSLock()
	private static var _cache: [Key: String] = [:]

	static func read(_ key: Key) -> String? {
		_lock.lock()
		defer { _lock.unlock() }

		if let cached = _cache[key] { return cached }

		let tiers = [_keychainValue(key), _fileValue(key), _defaultsValue(key)]
		guard let value = tiers.compactMap({ $0 }).first else { return nil }

		if tiers.contains(where: { $0 != value }) {
			_writeAllTiers(key, value)
		}

		_cache[key] = value
		return value
	}

	static func write(_ key: Key, _ value: String) {
		_lock.lock()
		defer { _lock.unlock() }

		_cache[key] = value
		_writeAllTiers(key, value)
	}

	static func delete(_ key: Key) {
		_lock.lock()
		defer { _lock.unlock() }

		_cache[key] = nil
		_deleteKeychainValue(key)
		_writeFile(key, nil)
		UserDefaults.standard.removeObject(forKey: key.defaultsKey)
	}

	private static func _writeAllTiers(_ key: Key, _ value: String) {
		_writeKeychainValue(key, value)
		_writeFile(key, value)
		UserDefaults.standard.set(value, forKey: key.defaultsKey)
	}

	// MARK: - Keychain Tier

	private static func _keychainValue(_ key: Key) -> String? {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: key.service,
			kSecAttrAccount as String: key.account,
			kSecReturnData as String: true,
			kSecMatchLimit as String: kSecMatchLimitOne
		]

		var result: AnyObject?
		guard
			SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
			let data = result as? Data
		else {
			return nil
		}

		return String(data: data, encoding: .utf8)
	}

	private static func _writeKeychainValue(_ key: Key, _ value: String) {
		guard let data = value.data(using: .utf8) else { return }

		_deleteKeychainValue(key)

		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: key.service,
			kSecAttrAccount as String: key.account,
			kSecValueData as String: data,
			kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
		]

		SecItemAdd(query as CFDictionary, nil)
	}

	private static func _deleteKeychainValue(_ key: Key) {
		let query: [String: Any] = [
			kSecClass as String: kSecClassGenericPassword,
			kSecAttrService as String: key.service,
			kSecAttrAccount as String: key.account
		]

		SecItemDelete(query as CFDictionary)
	}

	// MARK: - File Tier

	private static var _fileURL: URL? {
		guard let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
			return nil
		}

		let directory = support.appendingPathComponent("RyukSign", isDirectory: true)

		if !FileManager.default.fileExists(atPath: directory.path) {
			try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		}

		return directory.appendingPathComponent("identity.json")
	}

	private static func _fileContents() -> [String: String] {
		guard
			let url = _fileURL,
			let data = try? Data(contentsOf: url),
			let contents = try? JSONDecoder().decode([String: String].self, from: data)
		else {
			return [:]
		}

		return contents
	}

	private static func _fileValue(_ key: Key) -> String? {
		_fileContents()[key.rawValue]
	}

	private static func _writeFile(_ key: Key, _ value: String?) {
		guard let url = _fileURL else { return }

		var contents = _fileContents()
		contents[key.rawValue] = value

		guard let data = try? JSONEncoder().encode(contents) else { return }
		try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
	}

	// MARK: - UserDefaults Tier

	private static func _defaultsValue(_ key: Key) -> String? {
		UserDefaults.standard.string(forKey: key.defaultsKey)
	}
}
