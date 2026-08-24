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
import OSLog

/// Install pipeline without a UI, so the single-app card and the batch queue can share it.
@MainActor
final class AppInstaller: ObservableObject {
	enum Outcome {
		case installed
		case cancelled
		case exported(URL?)
	}

	let app: AppInfoPresentable
	let viewModel: InstallerStatusViewModel

	/// redirect page fallback.
	@Published var isPresentingFallbackPage = false

	private let _isSharing: Bool
	private let _installationMethod = UserDefaults.standard.integer(forKey: "Feather.installationMethod")
	private let _serverMethod = UserDefaults.standard.integer(forKey: "Feather.serverMethod")
	private let _useShareSheet = UserDefaults.standard.bool(forKey: "Feather.useShareSheetForArchiving")

	private var _server: ServerInstaller?
	private var _progressTask: Task<Void, Never>?
	private var _statusObserver: AnyCancellable?
	private var _completion: ((Result<Outcome, Error>) -> Void)?
	private var _hasFinished = false
	private var _declineObserver: NSObjectProtocol?
	private var _declineCheck: DispatchWorkItem?

	var fallbackPageURL: URL? { _server?.pageEndpoint }

	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self._isSharing = isSharing
		self.viewModel = InstallerStatusViewModel(isIdevice: _installationMethod == 1)

		if !isSharing, _installationMethod == 0 {
			_server = try? ServerInstaller(app: app, viewModel: viewModel)
		}
	}

	deinit {
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

	/// Stops without reporting an outcome; the caller has already moved on.
	func stop() {
		_hasFinished = true
		_completion = nil
		_disarmDeclineWatch()
		_statusObserver = nil
		_progressTask?.cancel()
		_progressTask = nil
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

	/// Copying and zipping the bundle stays off the main actor; both are long and fully blocking.
	private func _package() async throws -> (package: URL, exported: URL?) {
		let app = app
		let viewModel = viewModel
		let isSharing = _isSharing
		let useShareSheet = _useShareSheet

		return try await Task.detached(priority: .userInitiated) {
			let handler = ArchiveHandler(app: app, viewModel: viewModel)
			try await handler.move()
			let package = try await handler.archive()

			guard isSharing else { return (package, nil) }
			return (package, try await handler.moveToArchive(package, shouldOpen: !useShareSheet))
		}.value
	}

	private func _serveForOTA(_ packageUrl: URL) async {
		guard let server = _server else {
			_finish(.failure(Self.error(.localized("Could not build the installation link, check your connection and try again."))))
			return
		}

		server.packageUrl = packageUrl

		if _serverMethod == 1 {
			viewModel.status = .sendingManifest
			server.manifestUrl = await ManifestService.resolve(for: app, payload: server.payloadEndpoint)
		}

		var failure = server.startupError
		if failure == nil {
			failure = await server.selfCheck()
		}

		viewModel.status = failure.map { .broken($0) } ?? .ready
	}

	// MARK: Status

	private func _handle(_ status: InstallerStatusViewModel.InstallerStatus) {
		switch status {
		case .ready where _installationMethod == 0:
			_openInstall(_serverMethod == 0 ? _server?.iTunesLink : _server?.iTunesLinkExternal)
		case .sendingManifest:
			_armDeclineWatch()
		case .sendingPayload:
			isPresentingFallbackPage = false
			_disarmDeclineWatch()
		case .installing where _installationMethod == 0:
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

	// Direct open keeps the install to one tap; the redirect page is only for builds that refuse the scheme.
	private func _openInstall(_ link: String?) {
		guard let link, let url = URL(string: link) else {
			_finish(.failure(Self.error(.localized("Could not build the installation link, check your connection and try again."))))
			return
		}

		FileLogger.log("opening \(link)", category: "install")

		UIApplication.shared.open(url) { [weak self] opened in
			FileLogger.log("itms-services accepted by iOS: \(opened)", category: "install")

			if !opened {
				FileLogger.error("iOS refused the scheme, falling back to the redirect page", category: "install")
				self?.isPresentingFallbackPage = true
			}
		}
	}

	/// Declining iOS's prompt never reports back, so focus returning with no payload request means cancelled.
	private func _armDeclineWatch() {
		guard _declineObserver == nil else { return }

		_declineObserver = NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { [weak self] _ in
			self?._scheduleDeclineCheck(after: 2)
		}

		_scheduleDeclineCheck(after: 60)
	}

	private func _scheduleDeclineCheck(after delay: TimeInterval) {
		_declineCheck?.cancel()

		let work = DispatchWorkItem { [weak self] in
			guard let self, case .sendingManifest = self.viewModel.status else { return }
			self._finish(.success(.cancelled))
		}

		_declineCheck = work
		DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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

		let completion = _completion
		_completion = nil
		completion?(result)
	}

	private static func error(_ message: String) -> Error {
		NSError(domain: "Install", code: -1, userInfo: [NSLocalizedDescriptionKey: message])
	}

	// MARK: Progress

	private func _startProgressPolling() {
		guard _progressTask == nil, let bundleID = app.identifier else { return }

		_progressTask = Task.detached(priority: .background) { [viewModel] in
			var hasStarted = false

			while !Task.isCancelled {
				let raw = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if raw > 0 { hasStarted = true }

				Logger.misc.info("Install progress for \(bundleID): \(raw)")

				let value = hasStarted ? min(1.0, max(0.0, (raw - 0.6) / 0.3)) : 0.0

				await MainActor.run {
					if viewModel.installProgress != value {
						viewModel.installProgress = value
					}
				}

				// Progress dropping back to zero after it started means installd is done.
				if hasStarted, raw == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 250_000_000)
			}
		}
	}
}
