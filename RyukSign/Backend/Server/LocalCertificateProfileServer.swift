//
//  LocalCertificateProfileServer.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit
import Vapor

// Safari only installs profiles it fetches itself.
@MainActor
enum LocalCertificateProfileServer {
	private static var _server: Application?
	private static var _keepAlive: BackgroundTaskManager?

	static func open() throws {
		let profile = try LocalCertificate.profile()
		stop()

		let port = Int.random(in: 4000...8000)
		let server = Application(ServerInstaller.env)
		server.http.server.configuration.address = .hostname("127.0.0.1", port: port)
		server.get("RyukSign.mobileconfig") { _ in
			Response(
				status: .ok,
				headers: ["Content-Type": "application/x-apple-aspen-config"],
				body: .init(data: profile)
			)
		}
		do {
			try server.server.start()
		} catch {
			server.shutdown()
			throw error
		}
		_server = server

		let keepAlive = BackgroundTaskManager(
			taskName: "LocalCertificateProfile",
			expirationTitle: .localized("Certificate"),
			expirationBody: .localized("Open RyukSign again to finish installing the certificate.")
		)
		keepAlive.start()
		_keepAlive = keepAlive

		UIApplication.shared.open(URL(string: "http://127.0.0.1:\(port)/RyukSign.mobileconfig")!)
		DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
			if _server === server { stop() }
		}
	}

	static func stop() {
		_server?.server.shutdown()
		_server?.shutdown()
		_server = nil
		_keepAlive?.stop()
		_keepAlive = nil
	}
}
