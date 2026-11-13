//
//  InstalledAppState.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

struct InstalledAppState: Equatable, CustomStringConvertible {
	let version: String?
	let build: String?
	let teamID: String?
	let bundlePath: String?

	var description: String {
		"version=\(version ?? "?") build=\(build ?? "?") team=\(teamID ?? "?") bundle=\(bundlePath.map { URL(fileURLWithPath: $0).deletingLastPathComponent().lastPathComponent } ?? "?")"
	}

	static func current(for bundleID: String) -> InstalledAppState? {
		guard
			let className = String(data: Data(base64Encoded: "TFNBcHBsaWNhdGlvblByb3h5")!, encoding: .utf8), // LSApplicationProxy
			let selectorName = String(data: Data(base64Encoded: "YXBwbGljYXRpb25Qcm94eUZvcklkZW50aWZpZXI6")!, encoding: .utf8), // applicationProxyForIdentifier:
			let proxyClass = NSClassFromString(className) as? NSObject.Type,
			proxyClass.responds(to: NSSelectorFromString(selectorName)),
			let proxy = proxyClass.perform(NSSelectorFromString(selectorName), with: bundleID)?.takeUnretainedValue() as? NSObject
		else { return nil }

		// Fresh installs show up as placeholders before installd commits them.
		if let appState = proxy.read("appState") as? NSObject {
			if appState.read("isInstalled") as? Bool == false { return nil }
			if appState.read("isPlaceholder") as? Bool == true { return nil }
		}

		let state = InstalledAppState(
			version: proxy.read("shortVersionString") as? String,
			build: proxy.read("bundleVersion") as? String,
			teamID: proxy.read("teamID") as? String,
			bundlePath: (proxy.read("bundleURL") as? URL)?.path
		)
		return state.version == nil && state.bundlePath == nil ? nil : state
	}
}

private extension NSObject {
	func read(_ key: String) -> Any? {
		responds(to: NSSelectorFromString(key)) ? value(forKey: key) : nil
	}
}
