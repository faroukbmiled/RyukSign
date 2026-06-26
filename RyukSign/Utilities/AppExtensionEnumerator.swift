//
//  AppExtensionEnumerator.swift
//  RyukSign
//
//  Lists the .appex bundles inside an app so the user can pick injection targets.
//

import Foundation

enum AppExtensionEnumerator {
	/// Returns the appex bundle names (e.g. "MyWidget.appex") inside an app bundle's
	/// PlugIns and Extensions directories. Mirrors TweakHandler._discoverAppExtensions.
	static func appexNames(in appBundle: URL) -> [String] {
		appexBundles(in: appBundle).map { $0.lastPathComponent }
	}

	static func appexBundles(in appBundle: URL) -> [URL] {
		let fm = FileManager.default
		var result: [URL] = []

		for sub in ["PlugIns", "Extensions"] {
			let directory = appBundle.appendingPathComponent(sub)
			guard fm.fileExists(atPath: directory.path) else { continue }

			guard let contents = try? fm.contentsOfDirectory(
				at: directory,
				includingPropertiesForKeys: nil,
				options: [.skipsHiddenFiles]
			) else { continue }

			result.append(contentsOf: contents.filter {
				$0.pathExtension.lowercased() == "appex" && $0.hasDirectoryPath
			})
		}

		return result
	}

	/// Resolves the on-disk appex names for a library app (imported or signed).
	static func appexNames(for app: AppInfoPresentable) -> [String] {
		guard let appBundle = Storage.shared.getAppDirectory(for: app) else { return [] }
		return appexNames(in: appBundle)
	}
}
