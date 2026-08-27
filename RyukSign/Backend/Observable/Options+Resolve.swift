//
//  Options+Resolve.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

// MARK: - Extension: Per-app resolution
extension Options {
	/// Must run per app; sharing one result would sign every app with the same bundle identifier.
	func resolved(for app: AppInfoPresentable) -> Options {
		var options = self

		if let identifier = _resolvedIdentifier(for: app) {
			options.appIdentifier = identifier
		}

		if
			let currentName = app.name,
			let newName = displayNames[currentName]
		{
			options.appName = newName
		}

		if options.tweakInjections == nil {
			options.tweakInjections = Options.autoInjectSpecs(for: app)
		}

		return options
	}

	/// Drops everything customized for one app: identity, entitlements selection, Info.plist edits and tweaks.
	mutating func resetPerApp(for app: AppInfoPresentable) {
		appName = nil
		appIdentifier = nil
		appVersion = nil
		appEntitlementsFile = nil
		infoPlistOverrides = nil
		infoPlistRemovals = nil
		tweakInjections = Options.autoInjectSpecs(for: app)
	}

	/// Saved options minus the per-app fields, so a batch cannot hand every app one identity.
	static var batchBase: Options {
		var options = OptionsManager.shared.options
		options.appName = nil
		options.appIdentifier = nil
		options.appVersion = nil
		options.tweakInjections = nil
		return options
	}

	static func autoInjectSpecs(for app: AppInfoPresentable) -> [TweakInjectionSpec] {
		let appex = AppExtensionEnumerator.appexNames(for: app)
		return TweakManager.shared.resolveAutoInject(forBundleId: app.identifier)
			.compactMap { TweakManager.shared.injectionSpec(for: $0, availableAppex: appex) }
	}

	private func _resolvedIdentifier(for app: AppInfoPresentable) -> String? {
		guard let identifier = app.identifier else { return nil }

		if let mapped = identifiers[identifier] {
			return mapped
		}

		switch ppqProtection {
		case .disabled: return nil
		case .default: return "\(identifier).\(ppqString)"
		case .ryuk: return "\(Options._ppqTransform(identifier)).\(ppqString)"
		}
	}

	private static func _ppqTransform(_ identifier: String) -> String {
		let modified = identifier
			.replacingOccurrences(of: "google", with: "ryu", options: .caseInsensitive)
			.replacingOccurrences(of: "facebook", with: "ryu", options: .caseInsensitive)
			.replacingOccurrences(of: "ios", with: "anox", options: .caseInsensitive)

		switch modified.filter({ $0 == "." }).count {
		case 2...:
			guard let firstDot = modified.firstIndex(of: ".") else { return "ryuk." + modified }
			return "ryuk" + modified[firstDot...]
		case 1:
			return "ryuk." + modified
		default:
			return "ryuk.app." + modified
		}
	}
}
