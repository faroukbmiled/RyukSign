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
				return self._payload(packageUrl, for: req)
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
	
	private func _payload(_ file: URL, for req: Request) -> Response {
		let response = req.fileio.streamFile(at: file.path)
		guard
			response.status == .ok || response.status == .partialContent,
			let size = (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init),
			size > 0
		else {
			return response
		}

		let bounds = response.headers.first(name: .contentRange)?
			.split(whereSeparator: { " -/".contains($0) })
			.compactMap { Int64($0) } ?? []
		let start = bounds.count == 3 ? bounds[0] : 0
		let end = bounds.count == 3 ? bounds[1] + 1 : size

		response.body = .init(managedAsyncStream: { [weak self] writer in
			var handle: FileIO.FileChunks?
			var sent = start
			var percent = -1
			do {
				let chunks = try await req.fileio.readFile(at: file.path, chunkSize: 1 << 20, offset: start, byteCount: Int(end - start))
				handle = chunks
				for try await chunk in chunks {
					try await writer.writeBuffer(chunk)
					sent += Int64(chunk.readableBytes)
					if Int(sent * 100 / size) != percent {
						percent = Int(sent * 100 / size)
						self?._updateUpload(Double(sent) / Double(size))
					}
				}
			} catch {
				try? await handle?.closeHandle()
				FileLogger.error("payload stream ended early at \(sent)/\(size): \(error)", category: "install")
				self?._updateStatus(.installing)
				throw error
			}
			self?._updateStatus(.installing)
		}, count: Int(end - start), byteBufferAllocator: req.byteBufferAllocator)
		return response
	}

	// installd fails silently when unreachable, so prove it first — but not for Semi Local, where probing a LAN address would prompt for local network access.
	func selfCheck() async -> Error? {
		guard getServerMethod() != 1 else { return nil }

		let host = sni()
		let addresses = Self.resolve(host)

		var comps = URLComponents()
		comps.scheme = "https"
		comps.host = host
		comps.port = port
		comps.path = "/healthz"

		guard let url = comps.url else { return nil }

		do {
			_ = try await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10))
			return nil
		} catch {
			FileLogger.error("self check could not reach \(url.absoluteString) (\(addresses.joined(separator: ", "))): \(error.localizedDescription)", category: "install")
			if LocalCertificate.isEnabled, !LocalCertificate.isTrusted {
				return NSError(domain: "Install", code: -1, userInfo: [
					NSLocalizedDescriptionKey: String.localized("The on-device certificate isn't trusted yet. Install its profile and turn on full trust in Settings › Installation.")
				])
			}
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

	private func _updateUpload(_ fraction: Double) {
		DispatchQueue.main.async {
			if fraction > self.viewModel.uploadProgress { self.viewModel.uploadProgress = fraction }
		}
	}

	func getServerMethod() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	}

	func getIPFix() -> Bool {
		UserDefaults.standard.bool(forKey: "Feather.ipFix")
	}
}
