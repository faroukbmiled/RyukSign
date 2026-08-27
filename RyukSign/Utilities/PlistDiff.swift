//
//  PlistDiff.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

/// Compares plist entries against a reference set, such as what a certificate's provisioning
/// profile grants or an app's untouched Info.plist.
enum PlistDiff {
	enum Match {
		case matches
		case missing
		case differs
	}

	static func match(key: String, value: Any, against reference: [String: Any]) -> Match {
		guard let referenceValue = reference[key] else { return .missing }
		return _equal(value, referenceValue) ? .matches : .differs
	}

	/// Count of entries that don't cleanly match; `nil` reference (no certificate selected) flags nothing.
	static func flaggedCount(in dict: [String: Any], against reference: [String: Any]?) -> Int {
		guard let reference else { return 0 }
		return dict.reduce(into: 0) { count, entry in
			if match(key: entry.key, value: entry.value, against: reference) != .matches { count += 1 }
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
