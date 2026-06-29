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

/// Extended background execution: loops silent audio to keep the app alive.
final class BackgroundTaskManager {

	// MARK: - Shared audio-session refcount
	// AVAudioSession is process-wide; with several managers running, only the LAST to
	// stop may deactivate it, else stopping one kills background audio for the others.
	private static let _sessionLock = NSLock()
	private static var _sessionUsers = 0

	private static func _retainSession() {
		_sessionLock.lock(); defer { _sessionLock.unlock() }
		_sessionUsers += 1
	}

	/// Returns true when this was the last user (caller should deactivate the session).
	private static func _releaseSession() -> Bool {
		_sessionLock.lock(); defer { _sessionLock.unlock() }
		_sessionUsers = max(0, _sessionUsers - 1)
		return _sessionUsers == 0
	}

	// MARK: - Properties

	private var audioPlayer: AVAudioPlayer?
	private var backgroundTaskID: UIBackgroundTaskIdentifier?
	private var asyncTask: Task<Void, Error>?
	private var isRunning = false

	private let taskName: String
	private let expirationNotificationTitle: String
	private let expirationNotificationBody: String

	// MARK: - Initialization

	init(
		taskName: String,
		expirationTitle: String = "Task continuing",
		expirationBody: String = "The task will continue when you reopen the app"
	) {
		self.taskName = taskName
		self.expirationNotificationTitle = expirationTitle
		self.expirationNotificationBody = expirationBody
	}

	// MARK: - Public Methods

	/// Cycles audio playback to extend background execution indefinitely.
	func start() {
		guard !isRunning else {
			return
		}
		isRunning = true

		do {
			try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
			try AVAudioSession.sharedInstance().setActive(true)
			Self._retainSession()
		} catch {
			isRunning = false
			return
		}

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleAudioInterruption),
			name: AVAudioSession.interruptionNotification,
			object: AVAudioSession.sharedInstance()
		)

		startBackgroundCycle()
	}

	func stop() {
		guard isRunning else { return }
		isRunning = false

		NotificationCenter.default.removeObserver(
			self,
			name: AVAudioSession.interruptionNotification,
			object: nil
		)

		asyncTask?.cancel()
		stopBackgroundTask()
		stopAudio()
		audioPlayer = nil

		// Only deactivate the shared session if no other manager is still using it.
		if Self._releaseSession() {
			try? AVAudioSession.sharedInstance().setActive(false)
		}
	}

	// MARK: - Private Methods

	@objc private func handleAudioInterruption(_ notification: Notification) {
		guard let userInfo = notification.userInfo,
			  let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
			  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
			return
		}

		if type == .began {
			if !playAudio() {
				stop()
			}
		}
	}

	// Play audio, swap the background task, then restart on a 10s cycle.
	private func startBackgroundCycle() {
		asyncTask = Task {
			let audioStarted = await MainActor.run {
				playAudio()
			}
			guard audioStarted else {
				return
			}

			await MainActor.run {
				stopBackgroundTask()
			}

			backgroundTaskID = await UIApplication.shared.beginBackgroundTask { [weak self] in
				guard let self = self else { return }
				self.sendExpirationNotification()
				self.startBackgroundCycle()
			}

			await MainActor.run {
				stopAudio()
			}

			try Task.checkCancellation()

			guard let taskID = backgroundTaskID, taskID != .invalid else {
				startBackgroundCycle()
				return
			}

			try await Task.sleep(for: .seconds(10))
			startBackgroundCycle()
		}
	}

	private func stopBackgroundTask() {
		if let taskID = backgroundTaskID {
			UIApplication.shared.endBackgroundTask(taskID)
			backgroundTaskID = nil
		}
	}

	@discardableResult
	private func playAudio() -> Bool {
		do {
			if audioPlayer == nil {
				guard let soundURL = Bundle.main.url(forResource: "sound", withExtension: "m4a") else {
					return false
				}
				audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
				audioPlayer?.volume = 0.01
				audioPlayer?.numberOfLoops = -1
			}
			audioPlayer?.play()
			return true
		} catch {
			return false
		}
	}

	private func stopAudio() {
		audioPlayer?.stop()
	}

	private func sendExpirationNotification() {
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

	// MARK: - Deinit

	deinit {
		stop()
	}
}
