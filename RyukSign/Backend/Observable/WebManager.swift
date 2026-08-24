//
//  WebManager.swift
//  RyukSign
//

import Foundation
import UIKit
import OSLog

final class WebManager: ObservableObject {
	static let shared = WebManager()

	@Published private(set) var isRunning = false
	@Published private(set) var recentUploads: [String] = []
	@Published var lastError: String?

	@Published var port: Int {
		didSet { UserDefaults.standard.set(port, forKey: "Feather.webManager.port") }
	}
	@Published var requireAuth: Bool {
		didSet { UserDefaults.standard.set(requireAuth, forKey: "Feather.webManager.auth") }
	}
	@Published var username: String {
		didSet { UserDefaults.standard.set(username, forKey: "Feather.webManager.user") }
	}
	@Published var password: String {
		didSet { UserDefaults.standard.set(password, forKey: "Feather.webManager.pass") }
	}
	/// Keep server reachable in background via silent-audio keep-alive.
	@Published var keepAlive: Bool {
		didSet {
			UserDefaults.standard.set(keepAlive, forKey: "Feather.webManager.keepAlive")
			_applyKeepAlive()
		}
	}

	private var _server: WebManagerServer?
	private var _keepAliveTask: BackgroundTaskManager?

	// Coalesce a burst of uploads (e.g. a folder copy) into one toast.
	private var _pendingToastCount = 0
	private var _pendingToastName: String?
	private var _toastWork: DispatchWorkItem?

	private init() {
		let defaults = UserDefaults.standard
		self.port = defaults.object(forKey: "Feather.webManager.port") as? Int ?? 8080
		self.requireAuth = defaults.bool(forKey: "Feather.webManager.auth")
		self.username = defaults.string(forKey: "Feather.webManager.user") ?? "ryuk"
		self.password = defaults.string(forKey: "Feather.webManager.pass") ?? ""
		self.keepAlive = defaults.bool(forKey: "Feather.webManager.keepAlive")

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(_didEnterBackground),
			name: UIApplication.didEnterBackgroundNotification,
			object: nil
		)
	}

	// MARK: Lifecycle

	func start() {
		guard !isRunning else { return }
		lastError = nil

		let auth: WebManagerServer.Auth? = (requireAuth && !username.isEmpty && !password.isEmpty)
			? .init(username: username, password: password)
			: nil

		do {
			_server = try WebManagerServer(port: port, auth: auth) { [weak self] name in
				DispatchQueue.main.async {
					guard let self else { return }
					self.recentUploads.insert(name, at: 0)
					if self.recentUploads.count > 25 {
						self.recentUploads.removeLast(self.recentUploads.count - 25)
					}
					self._queueReceiveToast(name)
				}
			}
			isRunning = true
			if keepAlive { _startKeepAlive() }
		} catch {
			Logger.misc.error("WebManagerServer failed to start: \(error.localizedDescription)")
			lastError = error.localizedDescription
			_server = nil
			isRunning = false
		}
	}

	func stop() {
		_stopKeepAlive()
		_server?.shutdown()
		_server = nil
		isRunning = false
	}

	func toggle() {
		isRunning ? stop() : start()
	}

	func clearRecent() {
		recentUploads.removeAll()
	}

	/// Restart so changed settings (port/auth) take effect.
	func restartIfRunning() {
		guard isRunning else { return }
		stop()
		start()
	}

	/// Password protection is only effective with a username AND a non-empty password.
	var authActive: Bool { requireAuth && !username.isEmpty && !password.isEmpty }

	// MARK: URLs

	var localAddress: String { ServerInstaller.getLocalAddress() ?? "127.0.0.1" }
	var httpURL: String { "http://\(localAddress):\(port)/" }
	var webdavURL: String { "dav://\(localAddress):\(port)/" }

	// MARK: Keep-alive

	private func _applyKeepAlive() {
		if isRunning && keepAlive {
			_startKeepAlive()
		} else {
			_stopKeepAlive()
		}
	}

	private func _startKeepAlive() {
		guard _keepAliveTask == nil else { return }
		let task = BackgroundTaskManager(
			taskName: "WebManager",
			expirationTitle: .localized("Web Manager running"),
			expirationBody: .localized("Reopen RyukSign to keep the server reachable.")
		)
		task.start()
		_keepAliveTask = task
	}

	private func _stopKeepAlive() {
		_keepAliveTask?.stop()
		_keepAliveTask = nil
	}

	// MARK: Toasts

	private func _queueReceiveToast(_ name: String) {
		_pendingToastCount += 1
		_pendingToastName = name
		_toastWork?.cancel()

		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			let count = self._pendingToastCount
			let message: String = count <= 1
				? String.localized("Received %@", arguments: self._pendingToastName ?? "file")
				: String.localized("Received %lld items", arguments: count)
			Toast.success(message, systemImage: "tray.and.arrow.down.fill")
			self._pendingToastCount = 0
			self._pendingToastName = nil
		}
		_toastWork = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: work)
	}

	@objc private func _didEnterBackground() {
		// Keep-alive holds the server up; otherwise background sockets are unreliable, so stop cleanly.
		if keepAlive && isRunning { return }
		stop()
	}
}
