//
//  DylibHandler.swift
//  feather
//
//  Created by samara on 8/17/24.
//  Copyright (c) 2024 Samara M (khcrysalis)
//

import Foundation
import ZsignSwift
import OSLog

class TweakHandler {
	private let _fileManager = FileManager.default

	private let _app: URL
	private var _options: Options
	/// Legacy injection files + ellekit when needed.
	private var _urls: [URL]

	init(
		app: URL,
		options: Options = OptionsManager.shared.options
	) {
		self._app = app
		self._options = options
		self._urls = options.injectionFiles
	}

	/// Enabled tweak specs for this sign.
	private var _enabledSpecs: [TweakInjectionSpec] {
		(_options.tweakInjections ?? []).filter { $0.enabled }
	}

	private var _hasAnyInjection: Bool {
		!_options.injectionFiles.isEmpty || !_enabledSpecs.isEmpty
	}

	/// Bundled document picker fix
	private var _filePickerFixURL: URL? {
		guard _options.fixFilePicker else { return nil }
		guard let url = Bundle.main.url(forResource: "FilePickerFix", withExtension: "dylib") else {
			SigningLog.shared.error(.localized("File picker fix is unavailable"))
			return nil
		}
		return url
	}

	/// `Frameworks/` can be absent from apps, so the parent has to exist before the move.
	private func _place(_ url: URL, at destination: URL) throws {
		try _fileManager.createDirectoryIfNeeded(at: destination.deletingLastPathComponent())
		// The move silently drops a same-named file.
		if _fileManager.fileExists(atPath: destination.path) {
			SigningLog.shared.error(.localized("Kept the existing %@ — another tweak ships a file with that name", arguments: destination.lastPathComponent))
		}
		try _fileManager.moveFileIfNeeded(from: url, to: destination)
	}

	/// Suffixes `-2`, `-3`… so two tweaks can ship the same dylib name.
	private func _uniqueDylibDestination(_ destination: URL) -> URL {
		guard _fileManager.fileExists(atPath: destination.path) else { return destination }

		let directory = destination.deletingLastPathComponent()
		let base = destination.deletingPathExtension().lastPathComponent
		let ext = destination.pathExtension

		var index = 2
		var candidate = destination
		repeat {
			candidate = directory.appendingPathComponent("\(base)-\(index).\(ext)")
			index += 1
		} while _fileManager.fileExists(atPath: candidate.path)

		SigningLog.shared.info(.localized("Renamed %1$@ to %2$@ — that name was already taken", arguments: destination.lastPathComponent, candidate.lastPathComponent))
		return candidate
	}

	private func _checkEllekit() async throws {
		let frameworksPath = _app.appendingPathComponent("Frameworks").appendingPathComponent("CydiaSubstrate.framework")

		func addEllekit() async throws {
			if let ellekitURL = Bundle.main.url(forResource: "ellekit", withExtension: "deb") {
				self._urls.insert(ellekitURL, at: 0)
			} else {
				Logger.misc.info("ellekit.deb not found in the app bundle")
			}

			try _fileManager.createDirectoryIfNeeded(at: _app.appendingPathComponent("Frameworks"))
		}
		// we should check if CydiaSubstrate.framework exists, if it doesn't
		// just add ellekit
		// experiment_replaceSubstrateWithEllekit:
		// 	for this version, we need to replace CydiaSubstrate.framework with
		//	our own version containing ElleKit
		// other:
		// 	just return if it exists, should work fine
		if _fileManager.fileExists(atPath: frameworksPath.path) {
			if _options.experiment_replaceSubstrateWithEllekit {
				SigningLog.shared.info(.localized("Replacing Substrate with ElleKit"))
				try _fileManager.removeFileIfNeeded(at: frameworksPath)
				try await addEllekit()
			} else {
				return
			}
		} else {
			guard _hasAnyInjection else { return }
			try await addEllekit()
		}
	}

	public func getInputFiles() async throws {
		Logger.misc.info("Attempting to inject")

		let filePickerFix = _filePickerFixURL

		if !_options.experiment_replaceSubstrateWithEllekit {
			guard _hasAnyInjection || filePickerFix != nil else { return }
		}

		try await _checkEllekit()

		let baseTmpDir = _fileManager.uniqueTemporaryDirectory("FeatherTweak")
		try _fileManager.createDirectoryIfNeeded(at: baseTmpDir)

		if let filePickerFix {
			let staged = baseTmpDir.appendingPathComponent(filePickerFix.lastPathComponent)
			try _fileManager.copyItem(at: filePickerFix, to: staged)
			_urls.append(staged)
		}

		// Legacy job: injectionFiles + ellekit, extensions only when injectIntoExtensions.
		if !_urls.isEmpty {
			let names = try await _runJob(
				urls: _urls,
				baseTmpDir: baseTmpDir,
				path: _options.injectPath,
				folder: _options.injectFolder
			)
			_injectIntoTargets(
				dylibNames: names,
				targeting: _options.injectIntoExtensions ? .all : .mainOnly,
				path: _options.injectPath,
				folder: _options.injectFolder
			)
			for name in names {
				SigningLog.shared.info(.localized("Injected %@", arguments: name), category: "inject")
			}
		}

		// Managed specs: each file carries its own config + targeting, processed
		// independently so one bad file doesn't abort the sign.
		for spec in _enabledSpecs {
			for file in spec.files where file.enabled {
				do {
					try await _processSpecFile(file, spec: spec, baseTmpDir: baseTmpDir)
				} catch {
					SigningLog.shared.error(.localized("Failed to inject %@", arguments: file.fileName), category: "inject")
					SigningLog.shared.info(">>> \(error.localizedDescription)", category: "inject")
				}
			}
		}
	}

	/// Stages one tweak file, then places (.appex) or injects it.
	private func _processSpecFile(_ file: TweakInjectionFile, spec: TweakInjectionSpec, baseTmpDir: URL) async throws {
		let path = file.config.resolvedPath(global: _options.injectPath)
		let folder = file.config.resolvedFolder(global: _options.injectFolder)

		// Copy into temp first so the persistent library file isn't moved away.
		let staged = baseTmpDir.appendingPathComponent(UUID().uuidString)
		try _fileManager.createDirectoryIfNeeded(at: staged)
		let stagedFile = staged.appendingPathComponent(file.fileURL.lastPathComponent)
		try _fileManager.copyItem(at: file.fileURL, to: stagedFile)

		// App extensions are placed in PlugIns/ and signed with the app, not injected.
		if file.fileType == .appex || stagedFile.pathExtension.lowercased() == "appex" {
			try _handleAppex(at: stagedFile)
			SigningLog.shared.info(.localized("Placed extension %@", arguments: file.fileName), category: "inject")
			return
		}

		let names = try await _runJob(urls: [stagedFile], baseTmpDir: baseTmpDir, path: path, folder: folder)
		_injectIntoTargets(dylibNames: names, targeting: file.config.targeting, path: path, folder: folder)
		SigningLog.shared.info(.localized("Injected %@", arguments: file.fileName), category: "inject")
	}

	// MARK: - App extensions (.appex)

	/// Drops an appex into PlugIns/ and rewrites its bundle id under the host app id so iOS
	/// accepts it and zsign signs it with the bundle (same path as an in-IPA appex).
	private func _handleAppex(at url: URL) throws {
		let pluginsDir = _app.appendingPathComponent("PlugIns")
		try _fileManager.createDirectoryIfNeeded(at: pluginsDir)

		var destination = pluginsDir.appendingPathComponent(url.lastPathComponent)
		// Avoid clobbering an extension the app already ships with that exact name.
		if _fileManager.fileExists(atPath: destination.path) {
			let base = url.deletingPathExtension().lastPathComponent
			destination = pluginsDir.appendingPathComponent("\(base)-\(UUID().uuidString.prefix(6)).appex")
		}
		try _fileManager.moveFileIfNeeded(from: url, to: destination)
		_rewriteAppexBundleId(at: destination)
	}

	/// Sets the appex `CFBundleIdentifier` to `<hostId>.<suffix>` (required parent/child);
	/// host id is the app's final Info.plist id, already written by `SigningHandler`.
	private func _rewriteAppexBundleId(at appex: URL) {
		let infoURL = appex.appendingPathComponent("Info.plist")
		guard
			let info = NSDictionary(contentsOf: infoURL)?.mutableCopy() as? NSMutableDictionary
		else { return }

		let hostId = _options.appIdentifier
			?? (NSDictionary(contentsOf: _app.appendingPathComponent("Info.plist"))?["CFBundleIdentifier"] as? String)
		guard let hostId, !hostId.isEmpty else { return }

		let rawSuffix = appex.deletingPathExtension().lastPathComponent
		let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-")
		var suffix = String(rawSuffix.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
		while suffix.contains("--") { suffix = suffix.replacingOccurrences(of: "--", with: "-") }
		suffix = suffix.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
		if suffix.isEmpty { suffix = "extension" }

		info["CFBundleIdentifier"] = "\(hostId).\(suffix)"
		info.write(to: infoURL, atomically: true)
		Logger.misc.info("Placed app extension \(appex.lastPathComponent) as \(hostId).\(suffix)")
	}

	// MARK: - Job pipeline

	/// Injects each input (dylib/deb) into the MAIN binary; returns injected dylib names for targeting.
	private func _runJob(
		urls: [URL],
		baseTmpDir: URL,
		path: Options.InjectPath,
		folder: Options.InjectFolder
	) async throws -> [String] {
		var collected: [String] = []
		var directoriesToCheck: [URL] = []

		for url in urls {
			switch url.pathExtension.lowercased() {
			case "dylib":
				if let name = try await _handleDylib(at: url, path: path, folder: folder) {
					collected.append(name)
				}
			case "deb":
				directoriesToCheck.append(contentsOf: try await _handleDeb(at: url, baseTmpDir: baseTmpDir))
			case "framework":
				// Drop into Frameworks/, add load command; return load name for targeting.
				let destinationURL = _app.appendingPathComponent("Frameworks").appendingPathComponent(url.lastPathComponent)
				try _place(url, at: destinationURL)
				try await _handleDylib(framework: destinationURL)
				if let fexe = Bundle(url: destinationURL)?.executableURL?.lastPathComponent {
					collected.append("\(destinationURL.lastPathComponent)/\(fexe)")
				}
			case "bundle":
				// Resource bundle — copy into the app root, nothing to inject.
				let destinationURL = _app.appendingPathComponent(url.lastPathComponent)
				try _fileManager.moveFileIfNeeded(from: url, to: destinationURL)
			default:
				Logger.misc.warning("Unsupported file type: \(url.lastPathComponent), skipping.")
			}
		}

		if !directoriesToCheck.isEmpty {
			let toInject = try await _collectFromDirectories(directoriesToCheck)
			if !toInject.isEmpty {
				collected.append(contentsOf: try await _handleExtractedContents(at: toInject, path: path, folder: folder))
			}
		}

		return collected
	}

	// MARK: - Inject (main binary)

	// Inject imported dylib into the main binary; returns injected name.
	@discardableResult
	private func _handleDylib(
		at url: URL,
		path: Options.InjectPath,
		folder: Options.InjectFolder
	) async throws -> String? {
		var destinationURL = _app
		var injectFolder = folder

		// check for "/Frameworks/", then append the destinationUrl
		if folder == .frameworks {
			destinationURL = destinationURL.appendingPathComponent("Frameworks")
		}

		// We check for "@rpath" and "/Frameworks/", if they're both enabled force
		// the inject folder to be root "/" instead, as the @rpath is already in
		// frameworks
		if path == .rpath && folder == .frameworks {
			injectFolder = .root
		}

		destinationURL = _uniqueDylibDestination(destinationURL.appendingPathComponent(url.lastPathComponent))

		try _place(url, at: destinationURL)

		guard let appexe = Bundle(url: _app)?.executableURL else {
			return nil
		}

		// change paths because some tweaks hardlink, which is not ideal.
		_ = Zsign.changeDylibPath(
			appExecutable: destinationURL.path,
			for: "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
			with: "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
		)
		// inject if there's a valid app main executable
		_ = Zsign.injectDyLib(
			appExecutable: appexe.path,
			with: "\(path.rawValue)\(injectFolder.rawValue)\(destinationURL.lastPathComponent)"
		)

		return destinationURL.lastPathComponent
	}

	// Inject imported framework dir (main binary only).
	private func _handleDylib(framework: URL) async throws {
		guard
			let fexe = Bundle(url: framework)?.executableURL,
			let appexe = Bundle(url: _app)?.executableURL
		else {
			return
		}

		_ = Zsign.changeDylibPath(
			appExecutable: fexe.path,
			for: "/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate",
			with: "@rpath/CydiaSubstrate.framework/CydiaSubstrate"
		)
		_ = Zsign.injectDyLib(
			appExecutable: appexe.path,
			with: "@executable_path/Frameworks/\(framework.lastPathComponent)/\(fexe.lastPathComponent)"
		)
	}

	// Handle extracted deb contents (dylibs, frameworks, bundles). Returns injected dylib names.
	private func _handleExtractedContents(
		at urls: [URL],
		path: Options.InjectPath,
		folder: Options.InjectFolder
	) async throws -> [String] {
		var collected: [String] = []
		for url in urls {
			switch url.pathExtension.lowercased() {
			case "dylib":
				if let name = try await _handleDylib(at: url, path: path, folder: folder) {
					collected.append(name)
				}
			case "framework":
				let destinationURL = _app.appendingPathComponent("Frameworks").appendingPathComponent(url.lastPathComponent)
				try _place(url, at: destinationURL)
				try await _handleDylib(framework: destinationURL)
			case "bundle":
				let destinationURL = _app.appendingPathComponent(url.lastPathComponent)
				try _fileManager.moveFileIfNeeded(from: url, to: destinationURL)
			default:
				Logger.misc.warning("Unsupported file type: \(url.lastPathComponent), skipping.")
			}
		}
		return collected
	}

	// MARK: - deb extraction

	// Extract imported deb file, returns the extracted data directories to scan.
	private func _handleDeb(at url: URL, baseTmpDir: URL) async throws -> [URL] {
		let uniqueSubDir = baseTmpDir.appendingPathComponent(UUID().uuidString)
		try _fileManager.createDirectoryIfNeeded(at: uniqueSubDir)

		var directories: [URL] = []

		let handler = try AR(with: url)
		let arFiles = try await handler.extract()

		for arFile in arFiles {
			let outputPath = uniqueSubDir.appendingPathComponent(arFile.name)
			try arFile.content.write(to: outputPath)

			if ["data.tar.lzma", "data.tar.gz", "data.tar.xz", "data.tar.bz2"].contains(arFile.name) {
				var fileToProcess = outputPath
				try extractFile(at: &fileToProcess)
				try extractFile(at: &fileToProcess)
				directories.append(fileToProcess)
			}
		}

		return directories
	}

	// Read extracted deb directories, locate all necessary contents to copy over to the .app
	private func _collectFromDirectories(_ urls: [URL]) async throws -> [URL] {
		enum DirectoryType: String {
			case frameworks = "Frameworks"
			case dynamicLibraries = "MobileSubstrate/DynamicLibraries"
			case applicationSupport = "Application Support"
		}

		let directoryPaths: [DirectoryType: [String]] = [
			.frameworks: ["Library/Frameworks/", "var/jb/Library/Frameworks/"],
			.dynamicLibraries: ["Library/MobileSubstrate/DynamicLibraries/", "var/jb/Library/MobileSubstrate/DynamicLibraries/"],
			.applicationSupport: ["Library/Application Support/", "var/jb/Library/Application Support/"]
		]

		var result: [URL] = []

		for baseURL in urls {
			for (directoryType, paths) in directoryPaths {
				for path in paths {
					let directoryURL = baseURL.appendingPathComponent(path)

					guard _fileManager.fileExists(atPath: directoryURL.path) else {
						Logger.misc.warning("Directory does not exist: \(directoryURL.path). Skipping.")
						continue
					}

					switch directoryType {
					case .dynamicLibraries:
						result.append(contentsOf: try await _locateDylibFiles(in: directoryURL))
					case .frameworks:
						result.append(contentsOf: try await _locateFrameworkDirectories(in: directoryURL))
					case .applicationSupport:
						result.append(contentsOf: try await _searchForBundles(in: directoryURL))
					}
				}
			}
		}

		return result
	}

	// MARK: - Extension targeting

	// Discovers all .appex bundles in the app's PlugIns and Extensions directories
	private func _discoverAppExtensions() -> [URL] {
		AppExtensionEnumerator.appexBundles(in: _app)
	}

	/// Injects the given dylib names into the targeted extensions.
	private func _injectIntoTargets(
		dylibNames: [String],
		targeting: ExtensionTargeting,
		path: Options.InjectPath,
		folder: Options.InjectFolder
	) {
		guard !dylibNames.isEmpty else { return }

		let targets: [URL]
		switch targeting {
		case .mainOnly:
			return
		case .all:
			targets = _discoverAppExtensions()
		case .selected(let names):
			targets = _discoverAppExtensions().filter { names.contains($0.lastPathComponent) }
		}

		guard !targets.isEmpty else {
			Logger.misc.info("No matching app extensions found for injection")
			return
		}

		Logger.misc.info("Injecting into \(targets.count) app extension(s)")

		for extensionURL in targets {
			for dylibName in dylibNames {
				_injectIntoExtension(extensionURL: extensionURL, dylibName: dylibName, path: path, folder: folder)
			}
		}
	}

	// Injects a dylib into an extension's executable
	private func _injectIntoExtension(
		extensionURL: URL,
		dylibName: String,
		path: Options.InjectPath,
		folder: Options.InjectFolder
	) {
		guard
			let extensionBundle = Bundle(url: extensionURL),
			let extensionExecutable = extensionBundle.executableURL
		else {
			Logger.misc.warning("Skipping \(extensionURL.lastPathComponent): couldn't read bundle")
			return
		}

		// Framework load-names always resolve inside Frameworks/, regardless of inject folder.
		let isFramework = dylibName.contains(".framework/")

		var injectFolder = folder
		if path == .rpath && folder == .frameworks {
			injectFolder = .root
		}

		let injectPath: String
		if path == .rpath {
			injectPath = "@rpath/\(dylibName)"
		} else if isFramework || injectFolder == .frameworks {
			injectPath = "@executable_path/../../Frameworks/\(dylibName)"
		} else {
			injectPath = "@executable_path/../../\(dylibName)"
		}

		let success = Zsign.injectDyLib(
			appExecutable: extensionExecutable.path,
			with: injectPath
		)

		if success {
			Logger.misc.info("Injected \(dylibName) into extension: \(extensionURL.lastPathComponent)")
		} else {
			Logger.misc.warning("Failed to inject into extension: \(extensionURL.lastPathComponent)")
		}
	}
}

// MARK: - Find correct files in debs
extension TweakHandler {
	private func _searchForBundles(in directory: URL) async throws -> [URL] {
		let fileManager = FileManager.default
		let allFiles = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

		let bundleDirectories = allFiles.filter { url in
			let attributes = try? fileManager.attributesOfItem(atPath: url.path)
			let isSymlink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
			return url.pathExtension.lowercased() == "bundle" && url.hasDirectoryPath && !isSymlink
		}

		var result: [URL] = bundleDirectories

		let directoriesToSearch = allFiles.filter { url in
			let attributes = try? fileManager.attributesOfItem(atPath: url.path)
			let isSymlink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
			return url.hasDirectoryPath && !bundleDirectories.contains(url) && !isSymlink
		}

		for dirURL in directoriesToSearch {
			result.append(contentsOf: try await _searchForBundles(in: dirURL))
		}

		return result
	}

	private func _locateDylibFiles(in directory: URL) async throws -> [URL] {
		let fileManager = FileManager.default
		let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [])

		return files.filter { url in
			let attributes = try? fileManager.attributesOfItem(atPath: url.path)
			let isSymlink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
			return url.pathExtension.lowercased() == "dylib" && !isSymlink
		}
	}

	private func _locateFrameworkDirectories(in directory: URL) async throws -> [URL] {
		let fileManager = FileManager.default
		let files = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

		return files.filter { url in
			let attributes = try? fileManager.attributesOfItem(atPath: url.path)
			let isSymlink = attributes?[.type] as? FileAttributeType == .typeSymbolicLink
			return url.pathExtension.lowercased() == "framework" && url.hasDirectoryPath && !isSymlink
		}
	}
}

enum TweakHandlerError: Error {
	case unsupportedFileExtension(String)
	case decompressionFailed(String)
	case missingFile(String)
	case noAccess
}
