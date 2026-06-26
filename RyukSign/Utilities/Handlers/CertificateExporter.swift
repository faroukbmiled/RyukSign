//
//  CertificateExporter.swift
//  RyukSign
//
//  Bundles a certificate's p12 + mobileprovision + password into one zip, for the
//  in-app share sheet and the Web Manager download. Call on the main actor (reads CoreData).
//

import Foundation
import Zip

enum CertificateExporter {
	static func makeZip(for cert: CertificatePair) -> URL? {
		guard
			let p12 = Storage.shared.getFile(.certificate, from: cert),
			let provision = Storage.shared.getFile(.provision, from: cert)
		else { return nil }

		let name = cert.nickname ?? Storage.shared.getProvisionFileDecoded(for: cert)?.Name ?? "Certificate"
		let safe = (name as NSString).lastPathComponent.replacingOccurrences(of: "/", with: "_")
		let fm = FileManager.default
		let dir = fm.uniqueTemporaryDirectory("CertExport")
		let zipURL = dir.appendingPathComponent("\(safe).zip")

		do {
			try fm.createDirectoryIfNeeded(at: dir)
			try fm.copyItem(at: p12, to: dir.appendingPathComponent("\(safe).p12"))
			try fm.copyItem(at: provision, to: dir.appendingPathComponent("\(safe).mobileprovision"))
			try Data((cert.password ?? "").utf8).write(to: dir.appendingPathComponent("password.txt"))
			try Zip.zipFiles(
				paths: [
					dir.appendingPathComponent("\(safe).p12"),
					dir.appendingPathComponent("\(safe).mobileprovision"),
					dir.appendingPathComponent("password.txt")
				],
				zipFilePath: zipURL,
				password: nil,
				progress: nil
			)
			return zipURL
		} catch {
			return nil
		}
	}
}
