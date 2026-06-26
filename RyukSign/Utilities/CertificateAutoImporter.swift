//
//  CertificateAutoImporter.swift
//  RyukSign
//
//  Auto-imports bundled certificates with hash-based change detection
//

import Foundation
import SwiftUI
import UIKit
import OSLog
import CommonCrypto

class CertificateAutoImporter {
	static let shared = CertificateAutoImporter()

	private init() {}

	/// Import certificates from signing-assets folder using hash-based change detection
	func importBundledCertificatesIfNeeded() {
		guard let signingAssetsURL = Bundle.main.url(forResource: "signing-assets", withExtension: nil)
		else {
			Logger.misc.info("No signing-assets folder found in bundle")
			return
		}

		// Off the main thread so app launch isn't blocked.
		DispatchQueue.global(qos: .utility).async {
			do {
				let folderContents = try FileManager.default.contentsOfDirectory(
					at: signingAssetsURL,
					includingPropertiesForKeys: nil,
					options: .skipsHiddenFiles
				)

				// Distribution last so it imports last and becomes the default.
				let sortedFolders = folderContents.sorted { url1, url2 in
					let name1 = url1.lastPathComponent.lowercased()
					let name2 = url2.lastPathComponent.lowercased()

					let isDistribution1 = name1.contains("distribution") || name1.contains("dist")
					let isDistribution2 = name2.contains("distribution") || name2.contains("dist")

					if isDistribution1 != isDistribution2 {
						return !isDistribution1
					}
					return name1 < name2
				}

				for folderURL in sortedFolders {
					guard folderURL.hasDirectoryPath else { continue }

					let certName = folderURL.lastPathComponent
					let hashKey = "Feather.certHash.\(certName)"

					// Fast path: compare against the stored hash before doing the import work.
					let storedHash = UserDefaults.standard.string(forKey: hashKey)

					if storedHash != nil {
						let p12Url = folderURL.appendingPathComponent("cert.p12")
						let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
						let passwordUrl = folderURL.appendingPathComponent("cert.txt")

						guard
							FileManager.default.fileExists(atPath: p12Url.path),
							FileManager.default.fileExists(atPath: provisionUrl.path),
							FileManager.default.fileExists(atPath: passwordUrl.path)
						else {
							Logger.misc.warning("Skipping \(certName): missing required files")
							continue
						}

						guard let password = try? String(contentsOf: passwordUrl, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
							Logger.misc.warning("Skipping \(certName): failed to read password")
							continue
						}

						let certHash = self.calculateCertificateHash(p12: p12Url, provision: provisionUrl, password: password)

						if certHash == storedHash {
							Logger.misc.info("Skipping \(certName): already imported (hash match)")
							continue
						}
					}

					// Slow path: no stored hash (first import) or hash changed (re-import).
					let p12Url = folderURL.appendingPathComponent("cert.p12")
					let provisionUrl = folderURL.appendingPathComponent("cert.mobileprovision")
					let passwordUrl = folderURL.appendingPathComponent("cert.txt")

					guard
						FileManager.default.fileExists(atPath: p12Url.path),
						FileManager.default.fileExists(atPath: provisionUrl.path),
						FileManager.default.fileExists(atPath: passwordUrl.path)
					else {
						Logger.misc.warning("Skipping \(certName): missing required files")
						continue
					}

					guard let password = try? String(contentsOf: passwordUrl, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines) else {
						Logger.misc.warning("Skipping \(certName): failed to read password")
						continue
					}

					let certHash = self.calculateCertificateHash(p12: p12Url, provision: provisionUrl, password: password)

					guard FR.checkPasswordForCertificate(for: p12Url, with: password, using: provisionUrl) else {
						Logger.misc.warning("Skipping \(certName): invalid certificate or password")
						continue
					}

					// On a hash change, update the existing cert rather than deleting it.
					var existingCert: CertificatePair?
					if storedHash != nil {
						Logger.misc.info("Hash changed for \(certName), updating existing certificate")
						existingCert = DispatchQueue.main.sync {
							let allCerts = Storage.shared.getAllCertificates()
							return allCerts.first(where: { $0.nickname == certName })
						}
					}

					if let existingCert = existingCert {
						// Update in place to preserve relationships.
						self.updateCertificate(
							cert: existingCert,
							p12URL: p12Url,
							provisionURL: provisionUrl,
							password: password
						) { error in
							if let error = error {
								Logger.misc.error("Failed to update \(certName): \(error.localizedDescription)")
								DispatchQueue.main.async {
									let generator = UINotificationFeedbackGenerator()
									generator.notificationOccurred(.error)
									UIAlertController.showAlertWithOk(
										title: .localized("Certificate Update Failed"),
										message: error.localizedDescription
									)
								}
							} else {
								Logger.misc.info("Successfully updated certificate: \(certName)")
								// Store hash so we don't re-update next launch.
								UserDefaults.standard.set(certHash, forKey: hashKey)

								DispatchQueue.main.async {
									let generator = UINotificationFeedbackGenerator()
									generator.notificationOccurred(.success)
								}
							}
						}
					} else {
						FR.handleCertificateFiles(
							p12URL: p12Url,
							provisionURL: provisionUrl,
							p12Password: password,
							certificateName: certName,
							isDefault: true
						) { error in
							if let error = error {
								Logger.misc.error("Failed to import \(certName): \(error.localizedDescription)")
								DispatchQueue.main.async {
									let generator = UINotificationFeedbackGenerator()
									generator.notificationOccurred(.error)
									UIAlertController.showAlertWithOk(
										title: .localized("Certificate Import Failed"),
										message: error.localizedDescription
									)
								}
							} else {
								Logger.misc.info("Successfully imported certificate: \(certName)")
								// Store hash so we don't re-import next launch.
								UserDefaults.standard.set(certHash, forKey: hashKey)

								DispatchQueue.main.async {
									let generator = UINotificationFeedbackGenerator()
									generator.notificationOccurred(.success)
								}
							}
						}
					}
				}
			} catch {
				Logger.misc.error("Failed to list signing-assets: \(error)")
			}
		}
	}

	// Stable hash of the cert files to detect changes.
	private func calculateCertificateHash(p12: URL, provision: URL, password: String) -> String {
		// Deterministic concatenation, not Hasher (which is seeded per-launch).
		var hashComponents: [String] = []

		if let p12Attrs = try? FileManager.default.attributesOfItem(atPath: p12.path),
		   let provAttrs = try? FileManager.default.attributesOfItem(atPath: provision.path) {
			hashComponents.append("p12size:\(p12Attrs[.size] as? Int ?? 0)")
			hashComponents.append("provsize:\(provAttrs[.size] as? Int ?? 0)")
			hashComponents.append("p12mod:\((p12Attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)")
			hashComponents.append("provmod:\((provAttrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)")
		}

		hashComponents.append("pwd:\(password)")

		let combinedString = hashComponents.joined(separator: "|")
		return combinedString.sha256() ?? combinedString
	}

	/// Reset all stored certificate hashes (useful for debugging or forcing re-import)
	func resetCertificateHashes() {
		let defaults = UserDefaults.standard
		let allKeys = defaults.dictionaryRepresentation().keys

		for key in allKeys where key.hasPrefix("Feather.certHash.") {
			defaults.removeObject(forKey: key)
		}

		Logger.misc.info("Reset all certificate hashes")
	}

	/// Update an existing certificate without breaking relationships
	private func updateCertificate(
		cert: CertificatePair,
		p12URL: URL,
		provisionURL: URL,
		password: String,
		completion: @escaping (Error?) -> Void
	) {
		Task.detached {
			do {
				let certReader = CertificateReader(provisionURL)
				guard let certPair = certReader.decoded else {
					throw CertificateUpdateError.invalidCertificate
				}

				// Reuse the existing UUID directory.
				let certDir = await MainActor.run {
					Storage.shared.getUuidDirectory(for: cert)
				}

				guard let certDir = certDir else {
					throw CertificateUpdateError.directoryNotFound
				}

				let p12Dest = certDir.appendingPathComponent("cert.p12")
				let provisionDest = certDir.appendingPathComponent("cert.mobileprovision")

				try? FileManager.default.removeItem(at: p12Dest)
				try? FileManager.default.removeItem(at: provisionDest)

				try FileManager.default.copyItem(at: p12URL, to: p12Dest)
				try FileManager.default.copyItem(at: provisionURL, to: provisionDest)

				await MainActor.run {
					cert.password = password
					cert.ppQCheck = certPair.PPQCheck ?? false
					cert.expiration = certPair.ExpirationDate ?? Date()
					cert.revoked = false
					cert.date = Date()

					Storage.shared.saveContext()
					Storage.shared.revokagedCertificate(for: cert)
				}

				await MainActor.run {
					completion(nil)
				}
			} catch {
				await MainActor.run {
					completion(error)
				}
			}
		}
	}
}

private enum CertificateUpdateError: Error {
	case invalidCertificate
	case directoryNotFound
}

// SHA256 extension for stable hashing
extension String {
	func sha256() -> String? {
		guard let data = self.data(using: .utf8) else { return nil }
		var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
		data.withUnsafeBytes {
			_ = CC_SHA256($0.baseAddress, CC_LONG(data.count), &hash)
		}
		return hash.map { String(format: "%02x", $0) }.joined()
	}
}
