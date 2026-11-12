//
//  BackgroundTaskManager.swift
//  RyukSign
//
//  Created by Ryuk on 13.10.2025.
//

import Foundation
import UIKit
import AVFoundation
import UserNotifications

// Callable from any thread; all state is touched on main only.
final class BackgroundTaskManager {

	// AVAudioSession is process-wide; refcount it so one manager stopping can't cut audio for the rest.
	private static let _sessionLock = NSLock()
	private static var _sessionUsers = 0

	private static func _retainSession() {
		_sessionLock.lock(); defer { _sessionLock.unlock() }
		_sessionUsers += 1
	}

	private static func _releaseSession() -> Bool {
		_sessionLock.lock(); defer { _sessionLock.unlock() }
		_sessionUsers = max(0, _sessionUsers - 1)
		return _sessionUsers == 0
	}

	private var _player: AVAudioPlayer?
	private var _taskID: UIBackgroundTaskIdentifier = .invalid
	private var _loop: Task<Void, Never>?
	private var _isRunning = false

	private let taskName: String
	private let expirationNotificationTitle: String
	private let expirationNotificationBody: String

	init(
		taskName: String,
		expirationTitle: String = "Task continuing",
		expirationBody: String = "The task will continue when you reopen the app"
	) {
		self.taskName = taskName
		self.expirationNotificationTitle = expirationTitle
		self.expirationNotificationBody = expirationBody
	}

	deinit {
		_stop()
	}

	func start() {
		_onMain { $0._start() }
	}

	func stop() {
		_onMain { $0._stop() }
	}

	private func _onMain(_ work: @escaping (BackgroundTaskManager) -> Void) {
		if Thread.isMainThread {
			work(self)
		} else {
			DispatchQueue.main.async { work(self) }
		}
	}

	private func _start() {
		guard !_isRunning else { return }

		do {
			try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
			try AVAudioSession.sharedInstance().setActive(true)
		} catch {
			return
		}

		Self._retainSession()
		_isRunning = true

		_loop = Task { @MainActor [weak self] in
			while !Task.isCancelled, self?._renew() == true {
				try? await Task.sleep(nanoseconds: 10_000_000_000)
			}
		}
	}

	private func _stop() {
		guard _isRunning else { return }
		_isRunning = false

		_loop?.cancel()
		_loop = nil
		_player?.stop()
		_player = nil
		_endTask()

		if Self._releaseSession() {
			try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
		}
	}

	// Playing audio is what lets iOS grant a backgrounded app a new task.
	private func _renew() -> Bool {
		guard _isRunning else { return false }
		guard _playAudio() else { return true }

		let previous = _taskID
		_taskID = UIApplication.shared.beginBackgroundTask(withName: taskName) { [weak self] in
			self?._expire()
		}
		if previous != .invalid {
			UIApplication.shared.endBackgroundTask(previous)
		}

		_player?.stop()
		return true
	}

	private func _expire() {
		_endTask()
		_sendExpirationNotification()
	}

	private func _endTask() {
		guard _taskID != .invalid else { return }
		UIApplication.shared.endBackgroundTask(_taskID)
		_taskID = .invalid
	}

	private func _playAudio() -> Bool {
		if _player == nil {
			_player = try? AVAudioPlayer(data: Self._silence)
			_player?.numberOfLoops = -1
		}
		return _player?.play() ?? false
	}

	private static let _silence: Data = {
		let sampleRate: UInt32 = 44100
		let bytes = Int(sampleRate) * 2

		var wav = Data(capacity: 44 + bytes)
		func put<T: FixedWidthInteger>(_ value: T) {
			withUnsafeBytes(of: value.littleEndian) { wav.append(contentsOf: $0) }
		}

		wav.append(contentsOf: "RIFF".utf8)
		put(UInt32(36 + bytes))
		wav.append(contentsOf: "WAVEfmt ".utf8)
		put(UInt32(16))
		put(UInt16(1))
		put(UInt16(1))
		put(sampleRate)
		put(sampleRate * 2)
		put(UInt16(2))
		put(UInt16(16))
		wav.append(contentsOf: "data".utf8)
		put(UInt32(bytes))
		wav.append(Data(count: bytes))
		return wav
	}()

	private func _sendExpirationNotification() {
		let content = UNMutableNotificationContent()
		content.title = expirationNotificationTitle
		content.body = expirationNotificationBody
		content.sound = .default

		let request = UNNotificationRequest(
			identifier: "\(taskName)_expiring_\(UUID().uuidString)",
			content: content,
			trigger: nil
		)

		UNUserNotificationCenter.current().add(request)
	}
}
