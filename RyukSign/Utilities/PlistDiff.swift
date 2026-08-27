//
//  EntitlementsDiff.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

/// Compares a set of entitlements against what a certificate's provisioning profile actually grants.
enum EntitlementsDiff {
	enum Match {
		/// Present in the profile with the same value.
		case granted
		/// The profile doesn't grant this key at all.
		case notGranted
		/// The profile grants this key, but with a different value.
		case valueMismatch
	}

	static func match(key: String, value: Any, against granted: [String: Any]) -> Match {
		guard let grantedValue = granted[key] else { return .notGranted }
		return _equal(value, grantedValue) ? .granted : .valueMismatch
	}

	/// Count of entries that don't cleanly match; `nil` granted (no certificate selected) flags nothing.
	static func flaggedCount(in dict: [String: Any], against granted: [String: Any]?) -> Int {
		guard let granted else { return 0 }
		return dict.reduce(into: 0) { count, entry in
			if match(key: entry.key, value: entry.value, against: granted) != .granted { count += 1 }
		}
	}

	static func grantedEntitlements(for certificate: CertificatePair?) -> [String: Any]? {
		guard
			let certificate,
			let entitlements = Storage.shared.getProvisionFileDecoded(for: certificate)?.Entitlements
		else { return nil }
		return entitlements.mapValues { $0.value }
	}

	/// NSString/NSNumber/NSArray/NSDictionary all implement `isEqual:` correctly, including nested arrays/dicts.
	private static func _equal(_ a: Any, _ b: Any) -> Bool {
		(a as? NSObject)?.isEqual(b as? NSObject) ?? false
	}
}
