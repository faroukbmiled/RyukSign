//
//  TweakExtractor.swift
//  RyukSign
//
//  Pulls injectable artifacts (.dylib / .framework / .bundle / .deb) out of an
//  existing .app bundle or an .ipa/.tipa archive so they can be imported into the
//  Tweak Manager. Callers are responsible for cleaning up any returned work dir.
//

import Foundation
import Zip
import OSLog

/// A single injectable artifact discovered inside an app or archive.
struct TweakCandidate: Identifiable, Equatable {
	let id = UUID()
	/// On-disk location (inside a temp work dir for IPA scans, or inside the app for library scans).
	let url: URL
	/// File/bundle name, e.g. `Reveal.dylib` or `Orion.framework`.
	let name: String
	let type: TweakFileType
	let size: Int64
	/// Path relative to the scanned `.app`, for display/disambiguation.
	let relativePath: String
	/// Containing folder relative to the app/archive root ("" means the root).
	let folder: String

	static func == (lhs: TweakCandidate, rhs: TweakCandidate) -> Bool {
		lhs.id == rhs.id
	}
}

enum TweakExtractorError: Error, LocalizedError {
	case payloadNotFound
	case extractionFailed(String)

	var errorDescription: String? {
		switch self {
		case .payloadNotFound:
			return "No .app was found inside the archive."
		case .extractionFailed(let message):
			return message
		}
	}
}

enum TweakExtractor {
	private static let _fm = FileManager.default

	/// File/bundle extensions we consider injectable tweak material. `.appex` is an app
	/// extension (placed in PlugIns/), the rest are dylib/deb/framework/bundle tweaks.
	private static let _injectableExtensions: Set<String> = ["dylib", "framework", "bundle", "deb", "appex"]

	// MARK: - Public entry points

	/// Scans an already-extracted `.app` directory (e.g. a Library app). Nothing to clean up.
	static func candidates(inApp appURL: URL) -> [TweakCandidate] {
		_scan(appURL, appRoot: appURL)
	}

	/// Scans any directory tree for injectable artifacts (used for uploaded .zip archives).
	static func candidates(inDirectory directory: URL) -> [TweakCandidate] {
		_scan(directory, appRoot: directory)
	}

	/// Unzips `archive` into a fresh temp dir and scans it. Caller MUST delete the returned dir.
	static func extract(fromZip archive: URL) async throws -> (workDir: URL, candidates: [TweakCandidate]) {
		let workDir = _fm.temporaryDirectory
			.appendingPathComponent("FeatherZipExtract_\(UUID().uuidString)", isDirectory: true)
		do {
			try _fm.createDirectoryIfNeeded(at: workDir)
			try await _unzip(archive, to: workDir)
		} catch {
			try? _fm.removeItem(at: workDir)
			throw TweakExtractorError.extractionFailed(error.localizedDescription)
		}
		return (workDir, _scan(workDir, appRoot: workDir))
	}

	/// Unzips an IPA/TIPA into a fresh temp work dir and scans its `.app`.
	/// - Returns: the work dir (caller MUST delete it once done importing) and the found candidates.
	static func extract(fromIPA ipaURL: URL, progress: ((Double) -> Void)? = nil) async throws -> (workDir: URL, candidates: [TweakCandidate]) {
		let workDir = _fm.temporaryDirectory
			.appendingPathComponent("FeatherTweakExtract_\(UUID().uuidString)", isDirectory: true)

		let needsScope = ipaURL.startAccessingSecurityScopedResource()
		defer { if needsScope { ipaURL.stopAccessingSecurityScopedResource() } }

		do {
			try _fm.createDirectoryIfNeeded(at: workDir)

			let ext = ipaURL.pathExtension.lowercased()
			if ext == "ipa" { Zip.addCustomFileExtension("ipa") }
			if ext == "tipa" { Zip.addCustomFileExtension("tipa") }

			// Copy locally first so we hold a stable, accessible source.
			let localCopy = workDir.appendingPathComponent(ipaURL.lastPathComponent)
			try _fm.copyItem(at: ipaURL, to: localCopy)

			try await _unzip(localCopy, to: workDir, progress: progress)
			try? _fm.removeItem(at: localCopy)
		} catch let error as TweakExtractorError {
			try? _fm.removeItem(at: workDir)
			throw error
		} catch {
			try? _fm.removeItem(at: workDir)
			throw TweakExtractorError.extractionFailed(error.localizedDescription)
		}

		guard let appURL = _firstApp(in: workDir.appendingPathComponent("Payload"))
				?? _firstApp(in: workDir) else {
			try? _fm.removeItem(at: workDir)
			throw TweakExtractorError.payloadNotFound
		}

		return (workDir, _scan(appURL, appRoot: appURL))
	}

	// MARK: - Internal

	private static func _unzip(_ archive: URL, to destination: URL, progress: ((Double) -> Void)? = nil) async throws {
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			DispatchQueue.global(qos: .utility).async {
				do {
					try Zip.unzipFile(archive, destination: destination, overwrite: true, password: nil, progress: progress)
					continuation.resume()
				} catch {
					continuation.resume(throwing: error)
				}
			}
		}
	}

	private static func _firstApp(in directory: URL) -> URL? {
		guard let contents = try? _fm.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: nil,
			options: [.skipsHiddenFiles]
		) else { return nil }
		return contents.first { $0.pathExtension.lowercased() == "app" && $0.hasDirectoryPath }
	}

	/// Recursively walks `root`, recording injectable artifacts. Does NOT descend into a
	/// `.framework`/`.bundle` once matched (it's imported whole), nor follow symlinks.
	private static func _scan(_ root: URL, appRoot: URL) -> [TweakCandidate] {
		var results: [TweakCandidate] = []
		_walk(root, appRoot: appRoot, into: &results)
		// Stable, readable ordering: by type then name.
		return results.sorted {
			$0.type.rawValue == $1.type.rawValue
				? $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
				: $0.type.rawValue < $1.type.rawValue
		}
	}

	private static func _walk(_ directory: URL, appRoot: URL, into results: inout [TweakCandidate]) {
		guard let contents = try? _fm.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey],
			options: []
		) else { return }

		for url in contents {
			let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
			if values?.isSymbolicLink == true { continue }

			let ext = url.pathExtension.lowercased()
			let isDir = values?.isDirectory ?? url.hasDirectoryPath

			if _injectableExtensions.contains(ext) {
				// framework/bundle are directories taken whole; dylib/deb are files.
				if let candidate = _makeCandidate(url, appRoot: appRoot) {
					results.append(candidate)
				}
				// Don't descend into a matched bundle/framework.
				continue
			}

			if isDir {
				_walk(url, appRoot: appRoot, into: &results)
			}
		}
	}

	private static func _makeCandidate(_ url: URL, appRoot: URL) -> TweakCandidate? {
		let type = TweakFileType(fileExtension: url.pathExtension)
		guard type != .other else { return nil }

		let relative = url.path
			.replacingOccurrences(of: appRoot.deletingLastPathComponent().path + "/", with: "")

		// Folder relative to the app/archive root ("" => root).
		let parent = url.deletingLastPathComponent().path
		var folder = parent.hasPrefix(appRoot.path) ? String(parent.dropFirst(appRoot.path.count)) : parent
		if folder.hasPrefix("/") { folder.removeFirst() }

		return TweakCandidate(
			url: url,
			name: url.lastPathComponent,
			type: type,
			size: directorySize(at: url),
			relativePath: relative,
			folder: folder
		)
	}

	/// Size of a file, or the recursive total for a directory (framework/bundle).
	static func directorySize(at url: URL) -> Int64 {
		_fm.allocatedSize(at: url)
	}
}
