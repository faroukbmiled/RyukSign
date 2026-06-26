//
//  TweakAnalyzer.swift
//  RyukSign
//
//  Inspects a tweak file (.dylib/.framework/.deb/.bundle/.appex) and reports what it
//  is, what it links against, where it should be injected, and whether anything it
//  needs (e.g. CydiaSubstrate) is missing — so the user knows if an app will work or
//  crash, and RyukSign can auto-pick a sensible injection path.
//

import Foundation
import ZsignSwift
import OSLog

// MARK: - Model

/// One thing a tweak links against / requires.
struct TweakDependency: Identifiable, Equatable {
	let id = UUID()
	let name: String
	/// `true`/`false` when we can check against the target app, `nil` at library level.
	let satisfiedByApp: Bool?
	/// Missing this likely crashes the app.
	let critical: Bool

	static func == (lhs: TweakDependency, rhs: TweakDependency) -> Bool {
		lhs.name == rhs.name && lhs.satisfiedByApp == rhs.satisfiedByApp && lhs.critical == rhs.critical
	}
}

/// The result of inspecting one tweak file.
struct TweakAnalysis: Equatable {
	var fileType: TweakFileType
	/// One-line plain-English description of what this is.
	var summary: String
	/// Where it lands inside the signed `.app`.
	var placement: String
	/// Raw load-command names (dylib/framework binaries).
	var linkedLibraries: [String]
	/// Notable dependencies worth surfacing.
	var dependencies: [TweakDependency]
	/// File install paths discovered inside a `.deb`.
	var debInstallPaths: [String]
	var needsSubstrate: Bool
	var usesRpath: Bool
	/// Suggested injection settings RyukSign can apply (nil for non-injectable types).
	var recommendedPath: Options.InjectPath?
	var recommendedFolder: Options.InjectFolder?
	/// Hard problems ("will likely crash").
	var warnings: [String]
	/// Soft hints ("good to know").
	var notes: [String]

	/// True when there's a recommended path/folder the user can one-tap apply.
	var hasRecommendation: Bool { recommendedPath != nil && recommendedFolder != nil }
}

// MARK: - Analyzer

enum TweakAnalyzer {
	private static let _fm = FileManager.default

	/// Substrate identifiers a tweak can link against.
	private static let _substrateNeedles = ["cydiasubstrate", "libsubstrate", "/library/frameworks/cydiasubstrate"]

	/// Inspects a tweak file. `appURL` (the `.app` being signed) lets us tell whether a
	/// dependency like CydiaSubstrate is already present; pass nil for a library-level look.
	static func analyze(fileURL: URL, type: TweakFileType, appURL: URL? = nil) async -> TweakAnalysis {
		switch type {
		case .dylib: 		return _analyzeMacho(at: fileURL, type: .dylib, placement: nil, appURL: appURL)
		case .framework: 	return _analyzeFramework(at: fileURL, appURL: appURL)
		case .bundle: 		return _analyzeBundle(at: fileURL)
		case .appex: 		return _analyzeAppex(at: fileURL)
		case .deb: 			return await _analyzeDeb(at: fileURL, appURL: appURL)
		case .other:
			return TweakAnalysis(
				fileType: .other, summary: .localized("Unknown file."), placement: "",
				linkedLibraries: [], dependencies: [], debInstallPaths: [],
				needsSubstrate: false, usesRpath: false,
				recommendedPath: nil, recommendedFolder: nil, warnings: [], notes: []
			)
		}
	}

	// MARK: dylib / framework

	private static func _analyzeMacho(at machoURL: URL, type: TweakFileType, placement: String?, appURL: URL?) -> TweakAnalysis {
		let loads = Zsign.listDylibs(appExecutable: machoURL.path)
		let lowered = loads.map { $0.lowercased() }

		let needsSubstrate = lowered.contains { l in _substrateNeedles.contains { l.contains($0) } }
		let usesRpath = lowered.contains { $0.hasPrefix("@rpath") }

		// Substrate is handled via notes, not a "missing" row: RyukSign auto-adds ElleKit
		// when the app lacks Substrate, so it's never actually a crash-causing miss.
		var deps: [TweakDependency] = []
		// Surface any other framework it loads (Orion, etc.) — these the user may need to add.
		for load in loads {
			guard load.lowercased().contains(".framework/") else { continue }
			let fwName = _frameworkName(fromLoad: load)
			guard !fwName.isEmpty, fwName.lowercased() != "cydiasubstrate" else { continue }
			deps.append(TweakDependency(
				name: fwName,
				satisfiedByApp: appURL.map { _appHasFramework($0, named: fwName) },
				critical: false
			))
		}

		// Recommended injection: rpath tweaks live in Frameworks; plain dylibs at the executable.
		let recPath: Options.InjectPath = usesRpath ? .rpath : .executable_path
		let recFolder: Options.InjectFolder = usesRpath ? .frameworks : .root

		var warnings: [String] = []
		var notes: [String] = []
		if needsSubstrate {
			if let app = appURL, _appHasSubstrate(app) {
				notes.append(.localized("Hooks via CydiaSubstrate — the app already includes it."))
			} else {
				notes.append(.localized("Hooks via CydiaSubstrate. The app doesn't include it, so RyukSign adds ElleKit (a Substrate replacement) automatically when signing."))
			}
		}
		if loads.isEmpty {
			warnings.append(.localized("Couldn't read this binary's load commands (it may be encrypted or not a Mach-O)."))
		}

		let kind = type == .framework ? String.localized("Framework") : String.localized("Dynamic library")
		let summary = needsSubstrate
			? String.localized("%@ that hooks via CydiaSubstrate.", arguments: kind)
			: String.localized("%@.", arguments: kind)

		return TweakAnalysis(
			fileType: type,
			summary: summary,
			placement: placement ?? (recFolder == .frameworks
				? .localized("Injected into the app binary; file copied to Frameworks/.")
				: .localized("Injected into the app binary; file copied to the app root.")),
			linkedLibraries: loads,
			dependencies: deps,
			debInstallPaths: [],
			needsSubstrate: needsSubstrate,
			usesRpath: usesRpath,
			recommendedPath: recPath,
			recommendedFolder: recFolder,
			warnings: warnings,
			notes: notes
		)
	}

	private static func _analyzeFramework(at frameworkURL: URL, appURL: URL?) -> TweakAnalysis {
		guard let exe = Bundle(url: frameworkURL)?.executableURL else {
			return TweakAnalysis(
				fileType: .framework,
				summary: .localized("Framework (couldn't read its executable)."),
				placement: .localized("Copied to Frameworks/ and injected into the app binary."),
				linkedLibraries: [], dependencies: [], debInstallPaths: [],
				needsSubstrate: false, usesRpath: false,
				recommendedPath: .rpath, recommendedFolder: .frameworks,
				warnings: [.localized("This framework has no readable executable.")], notes: []
			)
		}
		var analysis = _analyzeMacho(at: exe, type: .framework, placement: .localized("Copied to Frameworks/ and injected into the app binary."), appURL: appURL)
		// Frameworks always resolve from Frameworks/ via rpath.
		analysis.recommendedPath = .rpath
		analysis.recommendedFolder = .frameworks
		return analysis
	}

	// MARK: bundle

	private static func _analyzeBundle(at url: URL) -> TweakAnalysis {
		TweakAnalysis(
			fileType: .bundle,
			summary: .localized("Resource bundle (images, prefs, assets)."),
			placement: .localized("Copied to the app root. Not injected — it's loaded by a dylib/framework."),
			linkedLibraries: [],
			dependencies: [],
			debInstallPaths: [],
			needsSubstrate: false,
			usesRpath: false,
			recommendedPath: nil,
			recommendedFolder: nil,
			warnings: [],
			notes: [.localized("Pair this with the tweak that reads it — a bundle alone does nothing.")]
		)
	}

	// MARK: appex

	private static func _analyzeAppex(at url: URL) -> TweakAnalysis {
		var summary = String.localized("App extension.")
		var notes: [String] = [
			.localized("Placed in PlugIns/ and re-signed as an extension of the host app (its bundle id becomes a child of the app's)."),
		]

		if
			let info = NSDictionary(contentsOf: url.appendingPathComponent("Info.plist")),
			let ext = info["NSExtension"] as? [String: Any],
			let pointId = ext["NSExtensionPointIdentifier"] as? String
		{
			summary = String.localized("%@ app extension.", arguments: _extensionKind(pointId))
			notes.append(String.localized("Extension point: %@", arguments: pointId))
		}

		return TweakAnalysis(
			fileType: .appex,
			summary: summary,
			placement: .localized("PlugIns/ — bundled and signed with the app."),
			linkedLibraries: [],
			dependencies: [],
			debInstallPaths: [],
			needsSubstrate: false,
			usesRpath: false,
			recommendedPath: nil,
			recommendedFolder: nil,
			warnings: [],
			notes: notes
		)
	}

	// MARK: deb

	private static func _analyzeDeb(at url: URL, appURL: URL?) async -> TweakAnalysis {
		let workDir = _fm.uniqueTemporaryDirectory("TweakAnalyze")
		defer { try? _fm.removeItem(at: workDir) }

		var depends: [String] = []
		var packageDesc = ""
		var installPaths: [String] = []
		var dylibCount = 0, frameworkCount = 0, bundleCount = 0
		var needsSubstrate = false

		do {
			try _fm.createDirectory(at: workDir, withIntermediateDirectories: true)
			let arFiles = try await AR(with: url).extract()

			for arFile in arFiles {
				let out = workDir.appendingPathComponent(arFile.name)
				try? arFile.content.write(to: out)

				if arFile.name.hasPrefix("control.tar") {
					if let control = _readControl(fromTar: out) {
						depends = _parseList(control["depends"])
						packageDesc = control["description"] ?? control["name"] ?? ""
					}
				} else if arFile.name.hasPrefix("data.tar") {
					var file = out
					try? extractFile(at: &file) // decompress
					try? extractFile(at: &file) // untar → directory
					let found = _scanDebData(file)
					installPaths = found.paths
					dylibCount = found.dylibs
					frameworkCount = found.frameworks
					bundleCount = found.bundles
					needsSubstrate = found.substrate
				}
			}
		} catch {
			FileLogger.error("Analyze deb \(url.lastPathComponent) failed: \(error.localizedDescription)", category: "analyze")
		}

		needsSubstrate = needsSubstrate || depends.contains { d in
			let l = d.lowercased()
			return l.contains("substrate") || l.contains("substitute") || l.contains("libhooker") || l.contains("ellekit")
		}

		var deps: [TweakDependency] = []
		if needsSubstrate {
			deps.append(TweakDependency(name: "CydiaSubstrate", satisfiedByApp: appURL.map { _appHasSubstrate($0) }, critical: true))
		}
		for dep in depends where !dep.lowercased().contains("substrate") && !dep.lowercased().contains("firmware") {
			deps.append(TweakDependency(name: dep, satisfiedByApp: nil, critical: false))
		}

		var parts: [String] = []
		if dylibCount > 0 { parts.append(String.localized("%lld dylibs", arguments: dylibCount)) }
		if frameworkCount > 0 { parts.append(String.localized("%lld frameworks", arguments: frameworkCount)) }
		if bundleCount > 0 { parts.append(String.localized("%lld bundles", arguments: bundleCount)) }
		let contents = parts.isEmpty ? String.localized("no injectable contents found") : parts.joined(separator: ", ")
		let summary = packageDesc.isEmpty
			? String.localized("Debian package (%@).", arguments: contents)
			: String.localized("%@", arguments: packageDesc)

		var notes: [String] = [.localized("RyukSign unpacks the .deb and injects each dylib/framework and copies bundles automatically.")]
		if needsSubstrate {
			if let app = appURL, _appHasSubstrate(app) {
				notes.append(.localized("Needs CydiaSubstrate — the app already includes it."))
			} else {
				notes.append(.localized("Needs CydiaSubstrate. The app doesn't include it, so RyukSign adds ElleKit automatically when signing."))
			}
		}

		return TweakAnalysis(
			fileType: .deb,
			summary: summary,
			placement: String.localized("Contents: %@", arguments: contents),
			linkedLibraries: [],
			dependencies: deps,
			debInstallPaths: installPaths,
			needsSubstrate: needsSubstrate,
			usesRpath: false,
			// The deb pipeline picks each file's own location; defaults are fine.
			recommendedPath: nil,
			recommendedFolder: nil,
			warnings: dylibCount + frameworkCount + bundleCount == 0
				? [.localized("No dylibs/frameworks/bundles found inside — this may not be an injectable tweak.")]
				: [],
			notes: notes
		)
	}

	// MARK: - Helpers

	private static func _appHasSubstrate(_ appURL: URL) -> Bool {
		_fm.fileExists(atPath: appURL.appendingPathComponent("Frameworks/CydiaSubstrate.framework").path)
	}

	private static func _appHasFramework(_ appURL: URL, named name: String) -> Bool {
		let n = name.hasSuffix(".framework") ? name : "\(name).framework"
		return _fm.fileExists(atPath: appURL.appendingPathComponent("Frameworks/\(n)").path)
	}

	/// "@rpath/Orion.framework/Orion" → "Orion".
	private static func _frameworkName(fromLoad load: String) -> String {
		guard let range = load.range(of: ".framework/") else { return "" }
		let before = String(load[..<range.lowerBound])
		return before.split(separator: "/").last.map(String.init) ?? ""
	}

	/// Decompresses + untars a control.tar.* and returns its parsed `control` fields (lowercased keys).
	private static func _readControl(fromTar tarURL: URL) -> [String: String]? {
		var file = tarURL
		try? extractFile(at: &file) // decompress (.gz/.xz/.lzma) → .tar (no-op if already .tar)
		try? extractFile(at: &file) // untar → directory
		guard file.hasDirectoryPath else { return nil }

		// The control file may be at ./control or control.
		let candidates = [file.appendingPathComponent("control"), file.appendingPathComponent("./control")]
		guard
			let controlURL = candidates.first(where: { _fm.fileExists(atPath: $0.path) }),
			let text = try? String(contentsOf: controlURL, encoding: .utf8)
		else { return nil }

		var fields: [String: String] = [:]
		for line in text.components(separatedBy: .newlines) {
			guard let colon = line.firstIndex(of: ":") else { continue }
			let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
			if !key.isEmpty { fields[key] = value }
		}
		return fields
	}

	/// "mobilesubstrate, firmware (>= 1.0), preferenceloader" → ["mobilesubstrate", "firmware", "preferenceloader"]
	private static func _parseList(_ value: String?) -> [String] {
		guard let value, !value.isEmpty else { return [] }
		return value.split(separator: ",").map {
			var s = $0.trimmingCharacters(in: .whitespaces)
			if let paren = s.firstIndex(of: "(") { s = String(s[..<paren]).trimmingCharacters(in: .whitespaces) }
			return s
		}.filter { !$0.isEmpty }
	}

	/// Walks an extracted deb data tree, recording injectable items + their install paths.
	private static func _scanDebData(_ root: URL) -> (paths: [String], dylibs: Int, frameworks: Int, bundles: Int, substrate: Bool) {
		var paths: [String] = []
		var dylibs = 0, frameworks = 0, bundles = 0
		var substrate = false

		guard let en = _fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
			return ([], 0, 0, 0, false)
		}
		for case let url as URL in en {
			let ext = url.pathExtension.lowercased()
			let rel = url.path.replacingOccurrences(of: root.path + "/", with: "")
			switch ext {
			case "dylib":
				dylibs += 1
				paths.append("/" + rel)
				if rel.lowercased().contains("mobilesubstrate/dynamiclibraries") { substrate = true }
				en.skipDescendants()
			case "framework":
				frameworks += 1
				paths.append("/" + rel)
				en.skipDescendants()
			case "bundle":
				bundles += 1
				paths.append("/" + rel)
				en.skipDescendants()
			default:
				break
			}
		}
		return (paths, dylibs, frameworks, bundles, substrate)
	}

	/// Maps an NSExtensionPointIdentifier to a friendly name.
	private static func _extensionKind(_ pointId: String) -> String {
		switch pointId {
		case "com.apple.Safari.web-extension", "com.apple.Safari.extension": return String.localized("Safari")
		case "com.apple.Safari.content-blocker": return String.localized("Safari content blocker")
		case "com.apple.share-services": return String.localized("Share")
		case "com.apple.widget-extension", "com.apple.widgetkit-extension": return String.localized("Widget")
		case "com.apple.intents-service", "com.apple.intents-ui-service": return String.localized("Siri/Intents")
		case "com.apple.usernotifications.content-extension": return String.localized("Notification")
		case "com.apple.keyboard-service": return String.localized("Keyboard")
		case "com.apple.fileprovider-nonui", "com.apple.fileprovider-actionsui": return String.localized("File Provider")
		case "com.apple.networkextension.packet-tunnel": return String.localized("Network (VPN)")
		default: return String.localized("App")
		}
	}
}
