//
//  InfoPlistPlan.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

/// Everything signing writes into an app's Info.plist, so the editor can show the same changes the signer applies.
enum InfoPlistPlan {
	static func managedChanges(for options: Options) -> [String: Any] {
		var changes: [String: Any] = [:]

		if options.fileSharing { changes["UISupportsDocumentBrowser"] = true }
		if options.itunesFileSharing { changes["UIFileSharingEnabled"] = true }
		if options.proMotion { changes["CADisableMinimumFrameDurationOnPhone"] = true }
		if options.gameMode { changes["GCSupportsGameMode"] = true }
		if options.ipadFullscreen { changes["UIRequiresFullScreen"] = true }

		if options.appAppearance != .default {
			changes["UIUserInterfaceStyle"] = options.appAppearance.rawValue
		}
		if options.minimumAppRequirement != .default {
			changes["MinimumOSVersion"] = options.minimumAppRequirement.rawValue
		}

		if options.experiment_disableLiquidGlass { changes["UIDesignRequiresCompatibility"] = true }
		if options.experiment_supportLiquidGlass { changes["UIDesignRequiresCompatibility"] = false }

		if let identifier = options.appIdentifier {
			changes["CFBundleIdentifier"] = identifier
		}
		if let name = options.appName {
			changes["CFBundleDisplayName"] = name
			changes["CFBundleName"] = name
		}
		if let version = options.appVersion {
			changes["CFBundleShortVersionString"] = version
			changes["CFBundleVersion"] = version
		}

		return changes
	}

	static func managedRemovals(for options: Options) -> [String] {
		// The device allowlist would pin the app to the models it shipped for.
		var keys = ["UISupportedDevices"]
		if options.removeURLScheme { keys.append("CFBundleURLTypes") }
		return keys
	}

	/// User overrides go last so they win over anything the options above decided.
	static func apply(_ options: Options, to dictionary: NSMutableDictionary) {
		for (key, value) in managedChanges(for: options) {
			dictionary.setObject(value, forKey: key as NSCopying)
		}
		for key in managedRemovals(for: options) {
			dictionary.removeObject(forKey: key)
		}
		for (key, value) in options.infoPlistOverrideDict {
			dictionary.setObject(value, forKey: key as NSCopying)
		}
		for key in options.infoPlistRemovals ?? [] {
			dictionary.removeObject(forKey: key)
		}
	}
}

// MARK: - Merged view

/// An app's Info.plist as the editor sees it: what the bundle ships, what the options will change,
/// and what the user overrode on top.
struct MergedInfoPlist {
	enum Status {
		case original
		case managed
		case overridden
		case removed
	}

	static let backgroundModesKey = "UIBackgroundModes"

	let original: [String: Any]
	let overrides: [String: Any]
	let removals: [String]
	let managed: [String: Any]
	let managedRemovals: [String]

	init(original: [String: Any], options: Options) {
		self.original = original
		self.overrides = options.infoPlistOverrideDict
		self.removals = options.infoPlistRemovals ?? []
		self.managed = InfoPlistPlan.managedChanges(for: options)
		self.managedRemovals = InfoPlistPlan.managedRemovals(for: options)
	}

	var keys: [String] {
		Set(original.keys).union(overrides.keys).sorted()
	}

	var changedCount: Int {
		keys.filter { status(for: $0) != .original }.count
	}

	var backgroundModes: [String] {
		guard !removals.contains(Self.backgroundModesKey) else { return [] }
		return (overrides[Self.backgroundModesKey] ?? original[Self.backgroundModesKey]) as? [String] ?? []
	}

	/// The bundle's plist with every option already applied; user edits are diffed against this, not the raw original.
	var baseline: [String: Any] {
		var dict = original
		for (key, value) in managed { dict[key] = value }
		for key in managedRemovals { dict.removeValue(forKey: key) }
		return dict
	}

	var effective: [String: Any] {
		var dict = baseline
		for (key, value) in overrides { dict[key] = value }
		for key in removals { dict.removeValue(forKey: key) }
		return dict
	}

	func value(for key: String) -> Any? {
		overrides[key] ?? managed[key] ?? original[key]
	}

	func status(for key: String) -> Status {
		if removals.contains(key) { return .removed }

		if let value = overrides[key] {
			return PlistDiff.match(key: key, value: value, against: original) == .matches ? .original : .overridden
		}

		if managedRemovals.contains(key), original[key] != nil { return .removed }

		if let value = managed[key] {
			return PlistDiff.match(key: key, value: value, against: original) == .matches ? .original : .managed
		}

		return .original
	}

	func isEdited(_ key: String) -> Bool {
		overrides[key] != nil || removals.contains(key)
	}
}

// MARK: - Extension: Overrides
extension Options {
	var infoPlistOverrideDict: [String: Any] {
		get {
			guard
				let data = infoPlistOverrides,
				let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
			else {
				return [:]
			}
			return dict
		}
		set {
			infoPlistOverrides = newValue.isEmpty
				? nil
				: try? PropertyListSerialization.data(fromPropertyList: newValue, format: .xml, options: 0)
		}
	}

	var infoPlistChangeCount: Int {
		infoPlistOverrideDict.count + (infoPlistRemovals?.count ?? 0)
	}
}
