//
//  BackupCrypto.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import CryptoKit
import CommonCrypto
import NimbleExtensions

enum BackupCrypto {
	private static let magic = Data("RYUKBK1\n".utf8)
	private static let plainMagic = Data("RYUKBK0\n".utf8)
	private static let saltCount = 16
	private static let iterations = 200_000

	enum Failure: LocalizedError {
		case badFormat
		case wrongPassword
		case passwordRequired
		case cryptoFailed

		var errorDescription: String? {
			switch self {
			case .badFormat: String.localized("This file isn't a valid RyukSign backup.")
			case .wrongPassword: String.localized("Incorrect password or corrupted backup.")
			case .passwordRequired: String.localized("This backup needs a password.")
			case .cryptoFailed: String.localized("Backup encryption failed, please try again.")
			}
		}
	}

	static func isEncrypted(_ url: URL) -> Bool {
		guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
		defer { try? handle.close() }
		return (try? handle.read(upToCount: magic.count)) == magic
	}

	static func seal(_ plaintext: Data, password: String) throws -> Data {
		guard !password.isEmpty else { return plainMagic + plaintext }

		let salt = try _randomBytes(saltCount)
		let sealed = try AES.GCM.seal(plaintext, using: try _deriveKey(password: password, salt: salt))
		var out = magic
		out.append(salt)
		out.append(sealed.combined!)
		return out
	}

	static func unseal(_ data: Data, password: String) throws -> Data {
		if data.prefix(plainMagic.count) == plainMagic {
			return data.dropFirst(plainMagic.count)
		}
		guard data.count > magic.count + saltCount, data.prefix(magic.count) == magic else {
			throw Failure.badFormat
		}
		guard !password.isEmpty else { throw Failure.passwordRequired }
		let salt = data.subdata(in: magic.count..<(magic.count + saltCount))
		let box = data.subdata(in: (magic.count + saltCount)..<data.count)
		let key = try _deriveKey(password: password, salt: salt)
		do {
			return try AES.GCM.open(try AES.GCM.SealedBox(combined: box), using: key)
		} catch {
			throw Failure.wrongPassword
		}
	}

	private static func _randomBytes(_ count: Int) throws -> Data {
		var bytes = Data(count: count)
		let status = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
		guard status == errSecSuccess else { throw Failure.cryptoFailed }
		return bytes
	}

	private static func _deriveKey(password: String, salt: Data) throws -> SymmetricKey {
		var derived = [UInt8](repeating: 0, count: 32)
		let pw = Array(password.utf8)
		let status = pw.withUnsafeBytes { pwBuf in
			salt.withUnsafeBytes { saltBuf in
				CCKeyDerivationPBKDF(
					CCPBKDFAlgorithm(kCCPBKDF2),
					pwBuf.baseAddress?.assumingMemoryBound(to: Int8.self), pw.count,
					saltBuf.bindMemory(to: UInt8.self).baseAddress, salt.count,
					CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
					UInt32(iterations),
					&derived, derived.count
				)
			}
		}
		guard Int(status) == kCCSuccess else { throw Failure.cryptoFailed }
		return SymmetricKey(data: Data(derived))
	}
}
