//
//  AppArchiver.swift
//  RyukSign
//
//  Shared "app bundle -> IPA" zipping, used by the installer and the Web Manager server.
//

import Foundation
import Zip

enum AppArchiver {
	/// Zips a prepared `Payload/` directory into an IPA at `ipaURL`.
	static func zip(
		payload: URL,
		to ipaURL: URL,
		compression: ZipCompression,
		progress: ((Double) -> Void)? = nil
	) throws {
		let fm = FileManager.default
		let zipURL = ipaURL.deletingPathExtension().appendingPathExtension("zip")
		try? fm.removeItem(at: zipURL)
		try ArchiveBackend.current.engine.zip(directory: payload, to: zipURL, compression: compression, progress: progress)
		try? fm.removeItem(at: ipaURL)
		try fm.moveItem(at: zipURL, to: ipaURL)
	}

	/// Wraps an `.app` bundle in `Payload/` and zips it into an IPA at `ipaURL`.
	static func archive(
		appDir: URL,
		to ipaURL: URL,
		compression: ZipCompression,
		progress: ((Double) -> Void)? = nil
	) throws {
		let fm = FileManager.default
		let work = fm.uniqueTemporaryDirectory("FeatherArchive")
		let payload = work.appendingPathComponent("Payload")
		defer { try? fm.removeItem(at: work) }

		try fm.createDirectoryIfNeeded(at: payload)
		try fm.copyItem(at: appDir, to: payload.appendingPathComponent(appDir.lastPathComponent))
		try zip(payload: payload, to: ipaURL, compression: compression, progress: progress)
	}
}
