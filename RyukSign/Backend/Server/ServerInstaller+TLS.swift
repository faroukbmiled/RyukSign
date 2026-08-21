//
//  Server+TLS.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import NIOSSL
import NIOTLS
import Vapor
import SystemConfiguration.CaptiveNetwork

// MARK: - Class extension: TLS/Setup
extension ServerInstaller {
	// MARK: Setup
	static let env: Environment = {
		var env = try! Environment.detect()
		try! LoggingSystem.bootstrap(from: &env)
		return env
	}()
	
	func setupApp(port: Int) throws -> Application {
		let app = Application(Self.env)
		app.threadPool = .init(numberOfThreads: 1)
		
		if getServerMethod() != 1 {
			if let tls = try tls() {
				app.http.server.configuration.tlsConfiguration = tls
			} else {
				FileLogger.error("no certificate found, serving plain HTTP on an https:// url — iOS will refuse this", category: "install")
			}
		}
		
		app.http.server.configuration.hostname = sni()
		app.http.server.configuration.tcpNoDelay = true
		app.http.server.configuration.address = .hostname("0.0.0.0", port: port)
		app.http.server.configuration.port = port
		app.routes.defaultMaxBodySize = "128mb"
		app.routes.caseInsensitive = false
		
		return app
	}
	
	// MARK: Files/IP
	func sni() -> String {
		let localhost = "127.0.0.1"
		
		if getServerMethod() == 1 {
			return !self.getIPFix()
			? (Self.getLocalAddress() ?? localhost)
			: localhost
		} else {
			return readCommonName() ?? localhost
		}
	}
	
	func tls() throws -> TLSConfiguration? {
		guard
			let crt = Self.getUrl("server", ext: "crt"),
			let pem = Self.getUrl("server", ext: "pem")
		else {
			FileLogger.error("server.crt or server.pem missing from both Documents and the bundle", category: "install")
			return nil
		}
		
		let source = { (url: URL) in url.path.contains("/Documents/") ? "Documents" : "bundle" }
		FileLogger.log("cert=\(source(crt)) key=\(source(pem))", category: "install")
		
		do {
			let chain = try NIOSSLCertificate.fromPEMFile(crt.path)
			let key = try NIOSSLPrivateKey(file: pem.path, format: .pem)
			FileLogger.log("loaded certificate chain of \(chain.count) (a leaf plus intermediates is expected)", category: "install")
			
			return try TLSConfiguration.makeServerConfiguration(
				certificateChain: chain.map { NIOSSLCertificateSource.certificate($0) },
				privateKey: .privateKey(key)
			)
		} catch {
			FileLogger.error("certificate or key rejected: \(error)", category: "install")
			throw error
		}
	}
	
	func readCommonName() -> String? {
		guard
			let url = Self.getUrl("commonName", ext: "txt"),
			let name = try? String(contentsOf: url, encoding: .utf8)
				.trimmingCharacters(in: .whitespacesAndNewlines),
			!name.isEmpty
		else {
			return nil
		}
		
		// A wildcard CN is not a hostname; any concrete label under it both matches the cert and resolves.
		return name.hasPrefix("*.") ? "local" + name.dropFirst() : name
	}
}

extension ServerInstaller {
	static func getUrl(_ name: String, ext: String) -> URL? {
		let fileManager = FileManager.default

		let documentsURL = URL.documentsDirectory.appendingPathComponent("\(name).\(ext)")
		let bundlesURL = Bundle.main.url(forResource: name, withExtension: ext)

		if fileManager.fileExists(atPath: documentsURL.path) {
			return documentsURL
		}

		if let bundlesURL, fileManager.fileExists(atPath: bundlesURL.path) {
			return bundlesURL
		}

		return nil
	}
	
	static func resolve(_ host: String) -> [String] {
		var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM,
							 ai_protocol: 0, ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
		var result: UnsafeMutablePointer<addrinfo>?
		guard getaddrinfo(host, nil, &hints, &result) == 0, let head = result else { return [] }
		defer { freeaddrinfo(head) }

		var addresses: [String] = []
		var node: UnsafeMutablePointer<addrinfo>? = head
		while let current = node {
			var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
			if getnameinfo(current.pointee.ai_addr, current.pointee.ai_addrlen,
						   &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
				addresses.append(String(cString: buffer))
			}
			node = current.pointee.ai_next
		}
		return addresses
	}
	
	static func getLocalAddress() -> String? {
		var address: String?
		var ifaddr: UnsafeMutablePointer<ifaddrs>?
		
		if getifaddrs(&ifaddr) == 0 {
			var ptr = ifaddr
			while ptr != nil {
				let interface = ptr!.pointee
				let addrFamily = interface.ifa_addr.pointee.sa_family
				
				if addrFamily == UInt8(AF_INET) {
					
					let name = String(cString: interface.ifa_name)
					if name == "en0" || name == "pdp_ip0" {
						
						var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
						if getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
									   &hostname, socklen_t(hostname.count),
									   nil, socklen_t(0), NI_NUMERICHOST) == 0 {
							address = String(cString: hostname)
						}
						
					}
				}
				ptr = ptr!.pointee.ifa_next
			}
			freeifaddrs(ifaddr)
		}
		
		return address
	}
}
