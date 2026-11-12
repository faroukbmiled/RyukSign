//
//  InstallQueue.swift
//  RyukSign
//
//  Created by Ryuk on 24.08.2026.
//

import Foundation
import SwiftUI
import NimbleExtensions
import IDeviceSwift

/// Every install and export runs through here. One sheet at a time keeps the OTA server from
/// starting twice and lets a job survive a dismissed sheet.
@MainActor
final class InstallQueue: ObservableObject {
	static let shared = InstallQueue()

	@Published private(set) var apps: [AnyApp] = []
	@Published private(set) var index = 0
	@Published private(set) var installer: AppInstaller?
	@Published private(set) var isFinished = false
	@Published var isSheetPresented = false

	private var _failures: [(name: String, error: Error)] = []

	// An advance that lands while backgrounded can't start the next install until we're back.
	private init() {
		NotificationCenter.default.addObserver(
			forName: UIApplication.didBecomeActiveNotification,
			object: nil,
			queue: .main
		) { _ in
			MainActor.assumeIsolated { InstallQueue.shared.activate() }
		}
	}

	var current: AnyApp? { apps.indices.contains(index) ? apps[index] : nil }
	var upcoming: [AnyApp] { Array(apps.dropFirst(index + 1)) }
	var showsPill: Bool { current != nil && !isSheetPresented && !isFinished }

	/// A finished run has nothing left to reopen, so closing it retires the queue.
	func sheetDismissed() {
		if isFinished { clear() }
	}

	func enqueue(_ app: AppInfoPresentable, exporting: Bool = false) {
		let entry = AnyApp(base: app, archive: exporting)
		guard !apps.contains(where: { $0.id == entry.id }) else { return }

		if isFinished { _reset() }
		apps.append(entry)

		InstallQueueWindow.shared.ensure()
		isSheetPresented = true
		activate()
	}

	/// Never starts in the background since an OTA install needs its prompt on screen.
	func activate() {
		guard
			installer == nil,
			let current,
			UIApplication.shared.applicationState != .background
		else {
			return
		}

		let installer = AppInstaller(app: current.base, isSharing: current.archive)
		self.installer = installer
		installer.start { [weak self] result in self?._handle(result) }
	}

	func clear() {
		_reset()
		isSheetPresented = false
		InstallQueueWindow.shared.teardown()
	}

	func skip() {
		_abandon()
	}

	private func _handle(_ result: Result<AppInstaller.Outcome, Error>) {
		switch result {
		case .success(.cancelled):
			_abandon()
		case .success(.exported(let package)):
			_abandon()

			guard let package else { return }
			// Let the card leave first or the share sheet presents onto a dying view.
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
				UIActivityViewController.show(activityItems: [package])
			}
		case .success:
			if let app = installer?.app { InstallCleanup.stage(app) }
			_advanceAfterResult()
		case .failure(let error):
			_failures.append((installer?.app.name ?? .localized("App"), error))
			_advanceAfterResult()
		}
	}

	// The user may have skipped ahead during the delay.
	private func _advanceAfterResult() {
		let finished = installer
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
			guard let self, self.installer === finished else { return }
			self._advance()
		}
	}

	private func _reportFailures() {
		let message = _failures.count == 1
			? Self._describe(_failures[0].error)
			: _failures.map { "\($0.name): \(Self._describe($0.error))" }.joined(separator: "\n\n")
		_failures.removeAll()

		UIAlertController.showAlertWithOk(
			title: .localized("Install"),
			message: message,
			action: { [weak self] in
				HeartbeatManager.shared.start(true)
				self?._abandon()
			}
		)
	}

	private static func _describe(_ error: Error) -> String {
		error is LocalizedError || (error as NSError).userInfo[NSLocalizedDescriptionKey] != nil
			? error.localizedDescription
			: String(describing: error)
	}

	/// Keeps the last app on screen so its finished state and Open button survive.
	private func _advance() {
		guard index + 1 < apps.count else {
			guard _failures.isEmpty else {
				_reportFailures()
				return
			}
			isFinished = true
			if !isSheetPresented { clear() }
			return
		}

		installer?.stop()
		installer = nil
		index += 1
		activate()
	}

	/// Dismiss first so the card doesn't blank out mid animation.
	private func _abandon() {
		guard index + 1 < apps.count else {
			guard _failures.isEmpty else {
				_reportFailures()
				return
			}
			guard isSheetPresented else {
				clear()
				return
			}

			installer?.stop()
			isFinished = true
			isSheetPresented = false
			return
		}

		_advance()
	}

	private func _reset() {
		installer?.stop()
		installer = nil
		apps.removeAll()
		index = 0
		isFinished = false
		_failures.removeAll()

		InstallCleanup.flush()
	}
}
