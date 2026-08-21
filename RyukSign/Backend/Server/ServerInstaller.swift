//
//  Server.swift
//  feather
//
//  Created by samara on 22.08.2024.
//  Copyright © 2024 Lakr Aream. All Rights Reserved.
//  ORIGINALLY LICENSED UNDER GPL-3.0, MODIFIED FOR USE FOR FEATHER
//

import Foundation
import Vapor
import NIOSSL
import NIOTLS
import SwiftUI
import IDeviceSwift

// MARK: - Class
class ServerInstaller: Identifiable, ObservableObject {
	let id = UUID()
	let port = Int.random(in: 4000...8000)
	private var _needsShutdown = false

	var packageUrl: URL?
	var manifestUrl: URL?
	private(set) var startupError: Error?
	var app: AppInfoPresentable
	@ObservedObject var viewModel: InstallerStatusViewModel
	private var _server: Application?

	private var backgroundTaskManager: BackgroundTaskManager?

	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) throws {
		self.app = app
		self.viewModel = viewModel

		let mode = getServerMethod() == 1 ? "semi-local" : "fully-local"
		FileLogger.log("installer starting: mode=\(mode) host=\(sni()) port=\(port) ipFix=\(getIPFix())", category: "install")

		do {
			let server = try setupApp(port: port)
			_server = server
			try _configureRoutes()
			try server.server.start()
			_needsShutdown = true
			FileLogger.log("server listening on \(sni()):\(port), payload=\(payloadEndpoint.absoluteString)", category: "install")
		} catch {
			FileLogger.error("server failed to start: \(error)", category: "install")
			startupError = error
		}
	}
	
	deinit {
		_shutdownServer()
		backgroundTaskManager?.stop()
	}
	
	private func _configureRoutes() throws {
		_server?.get("*") { [weak self] req in
			guard let self else { return Response(status: .badGateway) }

			FileLogger.log("request: \(req.method.rawValue) \(req.url.path)", category: "install")

			switch req.url.path {
			case plistEndpoint.path:
				self._updateStatus(.sendingManifest)
				if self.backgroundTaskManager == nil {
					self.backgroundTaskManager = BackgroundTaskManager(
						taskName: "ServerInstaller",
						expirationTitle: "Installation continuing",
						expirationBody: "Keep the app open to complete the installation"
					)
					self.backgroundTaskManager?.start()
				}
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "text/xml",
				], body: .init(data: installManifestData))
			case displayImageSmallEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageSmallData))
			case displayImageLargeEndpoint.path:
				return Response(status: .ok, version: req.version, headers: [
					"Content-Type": "image/png",
				], body: .init(data: displayImageLargeData))
			case payloadEndpoint.path:
				guard let packageUrl = packageUrl else {
					return Response(status: .notFound)
				}

				self._updateStatus(.sendingPayload)

				return req.fileio.streamFile(
					at: packageUrl.path
				) { result in
					switch result {
					case .success:
						self._updateStatus(.installing)
					case .failure(let error):
						self._updateStatus(.broken(error))
						self.backgroundTaskManager?.stop()
						self.backgroundTaskManager = nil
					}
				}
			case "/healthz":
				return Response(status: .ok)
			case "/install":
				var headers = HTTPHeaders()
				headers.add(name: .contentType, value: "text/html")
				return Response(status: .ok, headers: headers, body: .init(string: self.html))
			default:
				return Response(status: .notFound)
			}
		}
	}
	
	// installd fails silently when unreachable, so prove it first — but not for Semi Local, where probing a LAN address would prompt for local network access.
	func selfCheck() async -> Error? {
		guard getServerMethod() != 1 else { return nil }

		let host = sni()
		let addresses = Self.resolve(host)
		FileLogger.log("\(host) resolves to \(addresses.isEmpty ? "nothing" : addresses.joined(separator: ", "))", category: "install")

		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = host
		comps.port = port
		comps.path = "/healthz"

		guard let url = comps.url else { return nil }

		do {
			let (_, response) = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
			FileLogger.log("self check reached the server: HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)", category: "install")
			return nil
		} catch {
			FileLogger.error("self check could not reach \(url.absoluteString): \(error.localizedDescription)", category: "install")
			return error
		}
	}
	
	private func _shutdownServer() {
		guard _needsShutdown else { return }
		
		_needsShutdown = false
		_server?.server.shutdown()
		_server?.shutdown()
	}
	
	private func _updateStatus(_ newStatus: InstallerStatusViewModel.InstallerStatus) {
		DispatchQueue.main.async {
			self.viewModel.status = newStatus
		}
	}

	func getServerMethod() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}

	func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
}
