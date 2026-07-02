//
//  BackupManager.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Zip

struct BackupManifest: Codable {
	var version: Int
	var createdAt: Date
	var appVersion: String
	var includesTweaks: Bool
	var selectedCertUUID: String?
	var certificates: [Cert]
	var sources: [Source]

	struct Cert: Codable {
		var uuid: String
		var nickname: String?
		var password: String?
		var expiration: Date
		var ppq: Bool
	}

	struct Source: Codable {
		var identifier: String
		var name: String?
		var url: URL
		var iconURL: URL?
	}
}

struct BackupRestoreSummary {
	var certificates: Int
	var certificatesSkipped: Int
	var sources: Int
	var sourcesSkipped: Int
	var settings: Bool
	var tweaks: Bool

	var skipped: Int { certificatesSkipped + sourcesSkipped }
}

@MainActor
final class BackupManager {
	static let shared = BackupManager()
	private let _fm = FileManager.default

	/// Backs up any key in the app's namespaces; only device/install-specific keys are excluded.
	private static let _settingPrefixes = ["Feather.", "feather.", "RyukSign.", "signing_options"]
	private static let _settingDenylist: Set<String> = [
		"feather.selectedCert",              // restored by uuid remap, not by raw index
		"RyukSign.premiumSourceHosts",       // premium activation is install-bound
		"RyukSign.defaultImportFolderName",
		"RyukSign.defaultImportFolderBookmark", // security-scoped, dead on another install
		"Feather.downloadBubblePositionX",
		"Feather.downloadBubblePositionY",
	]

	static func isBackupableSettingKey(_ key: String) -> Bool {
		guard _settingPrefixes.contains(where: { key.hasPrefix($0) }) else { return false }
		if _settingDenylist.contains(key) { return false }
		if key.hasPrefix("Feather.certHash.") { return false }
		return true
	}

	func makeBackup(password: String) async throws -> URL {
		let staging = _fm.uniqueTemporaryDirectory("RyukBackup")
		try _fm.createDirectory(at: staging, withIntermediateDirectories: true)
		defer { try? _fm.removeItem(at: staging) }

		let certs = Storage.shared.getAllCertificates()
		let certsDir = staging.appendingPathComponent("certs")
		var certEntries: [BackupManifest.Cert] = []
		for cert in certs {
			guard
				let uuid = cert.uuid,
				let p12 = Storage.shared.getFile(.certificate, from: cert),
				let provision = Storage.shared.getFile(.provision, from: cert)
			else { continue }

			let dst = certsDir.appendingPathComponent(uuid)
			try _fm.createDirectory(at: dst, withIntermediateDirectories: true)
			try _fm.copyItem(at: p12, to: dst.appendingPathComponent("certificate.p12"))
			try _fm.copyItem(at: provision, to: dst.appendingPathComponent("certificate.mobileprovision"))
			certEntries.append(.init(
				uuid: uuid,
				nickname: cert.nickname,
				password: cert.password,
				expiration: cert.expiration ?? Date(),
				ppq: cert.ppQCheck
			))
		}

		let selectedIndex = UserDefaults.standard.integer(forKey: "feather.selectedCert")
		let selectedUUID = (selectedIndex >= 0 && selectedIndex < certs.count) ? certs[selectedIndex].uuid : nil

		let sources: [BackupManifest.Source] = Storage.shared.getSources().compactMap { source in
			guard let url = source.sourceURL, let identifier = source.identifier else { return nil }
			guard !RyukSignAPI.isPremiumSource(url) else { return nil }
			return .init(identifier: identifier, name: source.name, url: url, iconURL: source.iconURL)
		}

		var settings: [String: Any] = [:]
		for (key, value) in UserDefaults.standard.dictionaryRepresentation() where Self.isBackupableSettingKey(key) {
			settings[key] = value
		}
		let settingsData = try PropertyListSerialization.data(fromPropertyList: settings, format: .binary, options: 0)
		try settingsData.write(to: staging.appendingPathComponent("settings.plist"))

		var includesTweaks = false
		if _fm.fileExists(atPath: _fm.tweaksLibrary.path) {
			try _fm.copyItem(at: _fm.tweaksLibrary, to: staging.appendingPathComponent("tweaks"))
			includesTweaks = true
		}

		let manifest = BackupManifest(
			version: 1,
			createdAt: Date(),
			appVersion: Bundle.main.version,
			includesTweaks: includesTweaks,
			selectedCertUUID: selectedUUID,
			certificates: certEntries,
			sources: sources
		)
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted]
		try encoder.encode(manifest).write(to: staging.appendingPathComponent("manifest.json"))

		let packDir = _fm.uniqueTemporaryDirectory("RyukBackupPack")
		try _fm.createDirectory(at: packDir, withIntermediateDirectories: true)
		defer { try? _fm.removeItem(at: packDir) }
		let packURL = packDir.appendingPathComponent("pack.zip")

		let encrypted = try await Task.detached(priority: .userInitiated) {
			try Zip.zipFiles(paths: [staging], zipFilePath: packURL, password: nil, progress: nil)
			return try BackupCrypto.encrypt(try Data(contentsOf: packURL), password: password)
		}.value

		let outDir = _fm.uniqueTemporaryDirectory("RyukBackupOut")
		try _fm.createDirectory(at: outDir, withIntermediateDirectories: true)
		let file = outDir.appendingPathComponent("RyukSign-Backup-\(Self._stamp()).ryukbackup")
		try encrypted.write(to: file)
		return file
	}

	func restore(from url: URL, password: String) async throws -> BackupRestoreSummary {
		let data = try Data(contentsOf: url)
		let work = _fm.uniqueTemporaryDirectory("RyukRestore")
		try _fm.createDirectory(at: work, withIntermediateDirectories: true)
		defer { try? _fm.removeItem(at: work) }

		let extractDir = work.appendingPathComponent("extract")
		try await Task.detached(priority: .userInitiated) {
			let plaintext = try BackupCrypto.decrypt(data, password: password)
			let packURL = work.appendingPathComponent("pack.zip")
			try plaintext.write(to: packURL)
			try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
			try Zip.unzipFile(packURL, destination: extractDir, overwrite: true, password: nil)
		}.value

		guard let root = _findRoot(in: extractDir) else { throw BackupCrypto.Failure.badFormat }

		let manifestData = try Data(contentsOf: root.appendingPathComponent("manifest.json"))
		let manifest = try JSONDecoder().decode(BackupManifest.self, from: manifestData)

		var certCount = 0
		var certSkipped = 0
		let existingCertUUIDs = Set(Storage.shared.getAllCertificates().compactMap { $0.uuid })
		for cert in manifest.certificates {
			if existingCertUUIDs.contains(cert.uuid) { certSkipped += 1; continue }
			let srcDir = root.appendingPathComponent("certs").appendingPathComponent(cert.uuid)
			guard _fm.fileExists(atPath: srcDir.path) else { continue }
			let dstDir = _fm.certificates(cert.uuid)
			do {
				try _fm.removeFileIfNeeded(at: dstDir)
				try _fm.copyItem(at: srcDir, to: dstDir)
			} catch {
				continue
			}
			Storage.shared.addCertificate(
				uuid: cert.uuid,
				password: cert.password,
				nickname: cert.nickname,
				ppq: cert.ppq,
				expiration: cert.expiration
			) { _ in }
			certCount += 1
		}

		var sourceCount = 0
		var sourceSkipped = 0
		for source in manifest.sources {
			if Storage.shared.sourceExists(source.identifier) { sourceSkipped += 1; continue }
			Storage.shared.addSource(source.url, name: source.name, identifier: source.identifier, iconURL: source.iconURL) { _ in }
			sourceCount += 1
		}

		var settingsRestored = false
		if
			let data = try? Data(contentsOf: root.appendingPathComponent("settings.plist")),
			let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
		{
			for (key, value) in dict where Self.isBackupableSettingKey(key) {
				UserDefaults.standard.set(value, forKey: key)
			}
			settingsRestored = true
		}

		if
			let uuid = manifest.selectedCertUUID,
			let index = Storage.shared.getAllCertificates().firstIndex(where: { $0.uuid == uuid })
		{
			UserDefaults.standard.set(index, forKey: "feather.selectedCert")
		}

		var tweaksRestored = false
		let tweaksDir = root.appendingPathComponent("tweaks")
		if manifest.includesTweaks, _fm.fileExists(atPath: tweaksDir.path) {
			TweakManager.shared.mergeFromBackup(tweaksDir: tweaksDir)
			tweaksRestored = true
		}

		return .init(
			certificates: certCount,
			certificatesSkipped: certSkipped,
			sources: sourceCount,
			sourcesSkipped: sourceSkipped,
			settings: settingsRestored,
			tweaks: tweaksRestored
		)
	}

	private func _findRoot(in dir: URL) -> URL? {
		if _fm.fileExists(atPath: dir.appendingPathComponent("manifest.json").path) { return dir }
		guard let items = try? _fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { return nil }
		return items.first { _fm.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }
	}

	private static func _stamp() -> String {
		let formatter = DateFormatter()
		formatter.locale = Locale(identifier: "en_US_POSIX")
		formatter.dateFormat = "yyyyMMdd-HHmm"
		return formatter.string(from: Date())
	}
}
