//
//  LocalCertificate.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import Crypto
import SwiftASN1
import X509

enum LocalCertificate {
	static let enabledKey = "RyukSign.useLocalCertificate"
	static let host = "ryuksign.localhost"

	static var isEnabled: Bool {
		UserDefaults.standard.bool(forKey: enabledKey)
	}

	static var chainURL: URL { _directory.appendingPathComponent("server.crt") }
	static var keyURL: URL { _directory.appendingPathComponent("server.pem") }

	private static var _directory: URL {
		URL.applicationSupportDirectory.appendingPathComponent("LocalCertificate", isDirectory: true)
	}
	private static var _authorityURL: URL { _directory.appendingPathComponent("ca.crt") }
	private static var _authorityKeyURL: URL { _directory.appendingPathComponent("ca.pem") }

	// MARK: Issuing

	// The authority is kept for good so the trust the user granted survives server certificate renewals.
	static func prepare() throws {
		try _createDirectory()

		let (authority, authorityKey) = try _loadAuthority() ?? _createAuthority()

		if
			let server = try? _load(chainURL),
			server.subject == (try _serverName()),
			server.notValidAfter > Date().addingTimeInterval(30 * 86_400),
			try server.extensions.authorityKeyIdentifier?.keyIdentifier
				== authority.extensions.subjectKeyIdentifier?.keyIdentifier
		{
			return
		}

		try _issueServerCertificate(authority: authority, authorityKey: authorityKey)
	}

	// An unconstrained authority from an older build is replaced, so the user re-trusts a scoped one.
	private static func _loadAuthority() -> (X509.Certificate, P256.Signing.PrivateKey)? {
		guard
			let certificate = try? _load(_authorityURL),
			(try? certificate.extensions.nameConstraints) != nil,
			let pem = try? String(contentsOf: _authorityKeyURL, encoding: .utf8),
			let key = try? P256.Signing.PrivateKey(pemRepresentation: pem)
		else {
			return nil
		}
		return (certificate, key)
	}

	// The authority key must not travel to another device through a backup.
	private static func _createDirectory() throws {
		var directory = _directory
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		var values = URLResourceValues()
		values.isExcludedFromBackup = true
		try directory.setResourceValues(values)
	}

	private static func _createAuthority() throws -> (X509.Certificate, P256.Signing.PrivateKey) {
		let key = P256.Signing.PrivateKey()
		let name = try DistinguishedName {
			CommonName("RyukSign Local Authority")
			OrganizationName("RyukSign")
		}

		let certificate = try X509.Certificate(
			version: .v3,
			serialNumber: .init(),
			publicKey: .init(key.publicKey),
			notValidBefore: Date().addingTimeInterval(-86_400),
			notValidAfter: Date().addingTimeInterval(10 * 365 * 86_400),
			issuer: name,
			subject: name,
			signatureAlgorithm: .ecdsaWithSHA256,
			extensions: try X509.Certificate.Extensions {
				Critical(BasicConstraints.isCertificateAuthority(maxPathLength: 0))
				Critical(KeyUsage(keyCertSign: true, cRLSign: true))
				// Trusting it must never let it vouch for real websites.
				Critical(NameConstraints(
					permittedDNSDomains: ["localhost"],
					permittedIPRanges: [ASN1OctetString(contentBytes: [127, 0, 0, 1, 255, 255, 255, 255])]
				))
				SubjectKeyIdentifier(hash: .init(key.publicKey))
			},
			issuerPrivateKey: .init(key)
		)

		try certificate.serializeAsPEM().pemString.write(to: _authorityURL, atomically: true, encoding: .utf8)
		try key.pemRepresentation.write(to: _authorityKeyURL, atomically: true, encoding: .utf8)
		return (certificate, key)
	}

	// iOS rejects TLS server certificates valid for more than 825 days.
	private static func _issueServerCertificate(authority: X509.Certificate, authorityKey: P256.Signing.PrivateKey) throws {
		let key = P256.Signing.PrivateKey()

		let certificate = try X509.Certificate(
			version: .v3,
			serialNumber: .init(),
			publicKey: .init(key.publicKey),
			notValidBefore: Date().addingTimeInterval(-86_400),
			notValidAfter: Date().addingTimeInterval(800 * 86_400),
			issuer: authority.subject,
			subject: try _serverName(),
			signatureAlgorithm: .ecdsaWithSHA256,
			extensions: try X509.Certificate.Extensions {
				Critical(BasicConstraints.notCertificateAuthority)
				Critical(KeyUsage(digitalSignature: true))
				try ExtendedKeyUsage([.serverAuth])
				SubjectAlternativeNames([
					.dnsName(host),
					.dnsName("localhost"),
					.ipAddress(ASN1OctetString(contentBytes: [127, 0, 0, 1]))
				])
				SubjectKeyIdentifier(hash: .init(key.publicKey))
				AuthorityKeyIdentifier(keyIdentifier: try authority.extensions.subjectKeyIdentifier?.keyIdentifier)
			},
			issuerPrivateKey: .init(authorityKey)
		)

		let chain = try [certificate, authority].map { try $0.serializeAsPEM().pemString }
		try chain.joined(separator: "\n").write(to: chainURL, atomically: true, encoding: .utf8)
		try key.pemRepresentation.write(to: keyURL, atomically: true, encoding: .utf8)
	}

	private static func _serverName() throws -> DistinguishedName {
		try DistinguishedName { CommonName(host) }
	}

	private static func _load(_ url: URL) throws -> X509.Certificate {
		let documents = try PEMDocument.parseMultiple(pemString: String(contentsOf: url, encoding: .utf8))
		guard let first = documents.first else { throw CocoaError(.fileReadCorruptFile) }
		return try X509.Certificate(pemDocument: first)
	}

	// MARK: Trust

	static var isTrusted: Bool {
		guard
			let server = try? _load(chainURL),
			let authority = try? _load(_authorityURL),
			let serverRef = _secCertificate(server),
			let authorityRef = _secCertificate(authority)
		else {
			return false
		}

		var trust: SecTrust?
		let policy = SecPolicyCreateSSL(true, host as CFString)
		guard SecTrustCreateWithCertificates([serverRef, authorityRef] as CFArray, policy, &trust) == errSecSuccess, let trust else {
			return false
		}
		return SecTrustEvaluateWithError(trust, nil)
	}

	private static func _secCertificate(_ certificate: X509.Certificate) -> SecCertificate? {
		guard let der = try? certificate.serializeAsPEM().derBytes else { return nil }
		return SecCertificateCreateWithData(nil, Data(der) as CFData)
	}

	// MARK: Profile

	static func profile() throws -> Data {
		try prepare()
		let der = try _load(_authorityURL).serializeAsPEM().derBytes

		let payload: [String: Any] = [
			"PayloadType": "com.apple.security.root",
			"PayloadVersion": 1,
			"PayloadIdentifier": "com.ryuksign.localcertificate.authority",
			"PayloadUUID": UUID().uuidString,
			"PayloadDisplayName": "RyukSign Local Authority",
			"PayloadCertificateFileName": "RyukSign.cer",
			"PayloadContent": Data(der)
		]

		let profile: [String: Any] = [
			"PayloadType": "Configuration",
			"PayloadVersion": 1,
			"PayloadIdentifier": "com.ryuksign.localcertificate",
			"PayloadUUID": UUID().uuidString,
			"PayloadDisplayName": "RyukSign Local Install",
			"PayloadDescription": "Lets RyukSign install apps through its own server on this device.",
			"PayloadContent": [payload]
		]

		return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
	}
}
