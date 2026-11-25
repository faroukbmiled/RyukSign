//
//  AppInstaller.swift
//  RyukSign
//
//  Created by Ryuk
//

import Combine
import Foundation
import SwiftUI
import IDeviceSwift

@MainActor
final class AppInstaller: ObservableObject {
	enum Outcome {
		case installed
		case cancelled
		case exported(URL?)
	}

	let app: AppInfoPresentable
	let viewModel: InstallerStatusViewModel

	@Published var fallbackPage: URL?

	private let _isSharing: Bool
	private let _installationMethod = UserDefaults.standard.integer(forKey: "Feather.installationMethod")
	private let _serverMethod = UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	private let _useShareSheet = UserDefaults.standard.bool(forKey: "Feather.useShareSheetForArchiving")

	private var _server: ServerInstaller?
	private var _archive: ArchiveHandler?
	private var _packageTask: Task<(package: URL, exported: URL?), Error>?
	private var _progressTask: Task<Void, Never>?
	private var _statusObserver: AnyCancellable?
	private var _completion: ((Result<Outcome, Error>) -> Void)?
	private var _hasFinished = false
	private var _declineObserver: NSObjectProtocol?
	private var _declineCheck: DispatchWorkItem?
	private var _installedBefore: InstalledAppState?
	private var _packageSize = 0
	private var _payloadSentAt: Date?

	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self._isSharing = isSharing
		self.viewModel = InstallerStatusViewModel(isIdevice: _installationMethod == 1)

		if !isSharing, _installationMethod == 0 {
			_server = try? ServerInstaller(app: app, viewModel: viewModel)
		}
	}

	deinit {
		_archive?.cleanup()
		_progressTask?.cancel()
		_declineCheck?.cancel()
		if let _declineObserver { NotificationCenter.default.removeObserver(_declineObserver) }
	}

	func start(completion: @escaping (Result<Outcome, Error>) -> Void) {
		guard _completion == nil, !_hasFinished else { return }
		_completion = completion

		guard _isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			_finish(.failure(Self.error(.localized("You cannot update '%@' with itself, please use an alternative tool to update it.", arguments: Bundle.main.name))))
			return
		}

		_statusObserver = viewModel.$status
			.receive(on: DispatchQueue.main)
			.sink { [weak self] in self?._handle($0) }

		Task { await _run() }
	}

	func stop() {
		_hasFinished = true
		_completion = nil
		_disarmDeclineWatch()
		_statusObserver = nil
		_progressTask?.cancel()
		_progressTask = nil
		_release()
	}

	private func _release() {
		_packageTask?.cancel()
		_packageTask = nil
		_server = nil
		_archive?.cleanup()
		_archive = nil
	}

	// MARK: Pipeline

	private func _run() async {
		let keepAlive = BackgroundTaskManager(
			taskName: "Install",
			expirationTitle: .localized("Installation continuing"),
			expirationBody: .localized("The installation will continue when you reopen the app")
		)
		keepAlive.start()
		defer { keepAlive.stop() }

		do {
			let (packageUrl, exported) = try await _package()

			guard !_isSharing else {
				_finish(.success(.exported(_useShareSheet ? exported : nil)))
				return
			}

			switch _installationMethod {
			case 1:
				try await InstallationProxy(viewModel: viewModel)
					.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
			default:
				await _serveForOTA(packageUrl)
			}
		} catch {
			_progressTask?.cancel()
			_finish(.failure(error))
		}
	}

	private func _package() async throws -> (package: URL, exported: URL?) {
		let handler = ArchiveHandler(app: app, viewModel: viewModel)
		_archive = handler
		let isSharing = _isSharing
		let useShareSheet = _useShareSheet

		let task = Task.detached(priority: .userInitiated) {
			try await handler.move()
			try Task.checkCancellation()
			let package = try await handler.archive(forExport: isSharing)
			try Task.checkCancellation()

			guard isSharing else { return (package: package, exported: URL?.none) }
			return (package: package, exported: try await handler.moveToArchive(package, shouldOpen: !useShareSheet))
		}
		_packageTask = task
		return try await task.value
	}

	private func _serveForOTA(_ packageUrl: URL) async {
		guard let server = _server else {
			_finish(.failure(Self.error(.localized("Could not build the installation link, check your connection and try again."))))
			return
		}

		server.packageUrl = packageUrl
		_packageSize = (try? packageUrl.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

		if _serverMethod == 1 {
			viewModel.status = .sendingManifest
			server.manifestUrl = await ManifestService.resolve(for: app, payload: server.payloadEndpoint)
		}

		var failure = server.startupError
		if failure == nil {
			failure = await server.selfCheck()
		}

		if let id = app.identifier {
			_installedBefore = InstalledAppState.current(for: id)
		}
		FileLogger.log("sending \(app.identifier ?? "?") \(app.version ?? "?"), installed: \(_installedBefore?.description ?? "none")", category: "install")

		viewModel.status = failure.map { .broken($0) } ?? .ready
	}

	// MARK: Status

	private func _handle(_ status: InstallerStatusViewModel.InstallerStatus) {
		switch status {
		case .ready where _installationMethod == 0:
			_armDeclineWatch()
			_openInstall(_serverMethod == 0 ? _server?.iTunesLink : _server?.iTunesLinkExternal)
		case .sendingManifest where _progressTask == nil:
			_armDeclineWatch()
		case .sendingPayload:
			fallbackPage = nil
			_disarmDeclineWatch()
			if _installationMethod == 0 { _startProgressPolling() }
		case .installing where _installationMethod == 0:
			_payloadSentAt = _payloadSentAt ?? Date()
			_startProgressPolling()
		case .completed(let result):
			_progressTask?.cancel()
			_progressTask = nil
			_finish(result.map { .installed })
		case .broken(let error):
			_progressTask?.cancel()
			_progressTask = nil
			_finish(.failure(error))
		default:
			break
		}
	}

	private func _openInstall(_ link: String?) {
		guard let link, let url = URL(string: link) else {
			_finish(.failure(Self.error(.localized("Could not build the installation link, check your connection and try again."))))
			return
		}

		UIApplication.shared.open(url) { [weak self] opened in
			if !opened {
				FileLogger.error("iOS refused the scheme, falling back to the redirect page", category: "install")
				self?.fallbackPage = self?._server?.pageEndpoint
			}
		}
	}

	// Declining iOS's install prompt never reports back.
	private func _armDeclineWatch() {
		guard _declineObserver == nil else { return }

		_declineObserver = NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			MainActor.assumeIsolated { self?._scheduleDeclineCheck(after: 3) }
		}

		_scheduleDeclineCheck(after: 60)
	}

	private func _scheduleDeclineCheck(after delay: TimeInterval) {
		_declineCheck?.cancel()

		let work = DispatchWorkItem { [weak self] in
			guard let self, self.fallbackPage == nil else { return }
			switch self.viewModel.status {
			case .ready, .sendingManifest: Task { await self._cancelIfIdle() }
			default: break
			}
		}

		_declineCheck = work
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
	}

	// Slow manifest fetch can mimic a decline.
	private func _cancelIfIdle() async {
		if let id = app.identifier, (UIApplication.installProgress(for: id) ?? 0) > 0 { return }
		switch viewModel.status {
		case .ready, .sendingManifest: _finish(.success(.cancelled))
		default: break
		}
	}

	private func _disarmDeclineWatch() {
		_declineCheck?.cancel()
		_declineCheck = nil

		if let _declineObserver {
			NotificationCenter.default.removeObserver(_declineObserver)
		}
		_declineObserver = nil
	}

	private func _finish(_ result: Result<Outcome, Error>) {
		guard !_hasFinished else { return }
		_hasFinished = true
		_disarmDeclineWatch()
		_statusObserver = nil
		fallbackPage = nil

		if case .failure(let error) = result, !viewModel.isFailed {
			viewModel.status = .broken(error)
		}

		let completion = _completion
		_completion = nil
		_release()
		completion?(result)
	}

	static let detectsRejectionKey = "RyukSign.detectFailedInstalls"

	private static var detectsRejection: Bool {
		UserDefaults.standard.object(forKey: detectsRejectionKey) as? Bool ?? true
	}

	private static func error(_ message: String) -> Error {
		NSError(domain: "Install", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}

	// MARK: Progress

	private func _startProgressPolling() {
		guard _progressTask == nil, let bundleID = app.identifier else { return }
		let before = _installedBefore
		// installd can sit on one value for minutes while it unpacks and verifies a big app.
		let stallLimit = 60 + 60 * Double(_packageSize) / 1_000_000_000

		_progressTask = Task.detached(priority: .utility) { [weak self, viewModel] in
			var startedAt: Date?
			var peak = 0.0
			var last = 0.0
			var lastChange = Date()
			var zeroSince: Date?
			var nextStateCheck = Date()

			while !Task.isCancelled {
				let raw = UIApplication.installProgress(for: bundleID) ?? 0.0
				let now = Date()
				let payloadSentAt = await self?._payloadSentAt
				let delivered = await MainActor.run {
					let value = min(1.0, max(viewModel.uploadProgress * 0.6, raw) / 0.9)
					if value > viewModel.installProgress { viewModel.installProgress = value }
					return viewModel.uploadProgress >= 1
				}

				// Until the payload is sent, only a finished install ends the watch.
				if startedAt == nil, raw > 0, payloadSentAt != nil || raw > 0.6 {
					startedAt = now
					lastChange = now
				}
				let hasStarted = startedAt != nil
				peak = max(peak, raw)
				if raw != last {
					last = raw
					lastChange = now
				}
				zeroSince = raw == 0 ? zeroSince ?? now : nil

				var endReason: String?
				if hasStarted, let zeroSince, now.timeIntervalSince(zeroSince) > 2 {
					endReason = "progress ended"
				} else if !hasStarted, delivered, let payloadSentAt, now.timeIntervalSince(payloadSentAt) > 20 {
					endReason = "progress hidden"
				} else if !hasStarted, let payloadSentAt, now.timeIntervalSince(payloadSentAt) > 120 {
					endReason = "never started"
				} else if hasStarted, now.timeIntervalSince(lastChange) > stallLimit {
					endReason = "progress stuck at \(raw) for \(Int(stallLimit))s"
				} else if now >= nextStateCheck {
					// Tiny apps can finish between samples, and iOS doesn't always reset progress afterwards.
					nextStateCheck = now.addingTimeInterval(1)
					if let current = InstalledAppState.current(for: bundleID), current != before {
						endReason = "installed app changed"
					}
				}

				if let endReason {
					await self?._verifyInstall(reason: endReason, started: hasStarted, delivered: delivered, peak: peak, before: before)
					break
				}

				let isLongInstall = startedAt.map { now.timeIntervalSince($0) > 5 } ?? false
				try? await Task.sleep(nanoseconds: isLongInstall ? 250_000_000 : 50_000_000)
			}
		}
	}

	// installd only reaches 0.88 once it accepts the app.
	private func _verifyInstall(reason: String, started: Bool, delivered: Bool, peak: Double, before: InstalledAppState?) {
		let after = app.identifier.flatMap(InstalledAppState.current(for:))
		let replaced = after != nil && after != before
		FileLogger.log("install ended (\(reason)), started=\(started), delivered=\(delivered), peak=\(peak), installed: \(after?.description ?? "none"), replaced=\(replaced)", category: "install")

		if peak < 0.85, !replaced, started || !delivered, Self.detectsRejection {
			FileLogger.error("iOS rejected \(app.identifier ?? "?") \(app.version ?? "?")", category: "install")
			let message: String = started || after != nil
				? .localized("iOS couldn't install the app. If a copy is already installed, delete it and try again.")
				: .localized("iOS never started installing the app. Try again.")
			viewModel.status = .broken(Self.error(message))
			return
		}

		viewModel.installProgress = 1.0
		viewModel.status = .completed(.success(()))
	}
}
