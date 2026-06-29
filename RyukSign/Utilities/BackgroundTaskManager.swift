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

final class BackgroundTaskManager {

	// AVAudioSession is process-wide; refcount it so one manager stopping can't cut audio for the rest.
	private static let _sessionLock = NSLock()
	private static var _sessionUsers = 0

	private static func retainSession() {
		_sessionLock.lock(); defer { _sessionLock.unlock() }
		_sessionUsers += 1
	}

	private static func releaseSession() -> Bool {
		_sessionLock.lock(); defer { _sessionLock.unlock() }
		_sessionUsers = max(0, _sessionUsers - 1)
		return _sessionUsers == 0
	}

	private var audioPlayer: AVAudioPlayer?
	private var backgroundTaskID: UIBackgroundTaskIdentifier?
	private var cycleTask: Task<Void, Error>?
	private var isRunning = false

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

	func start() {
		guard !isRunning else { return }
		isRunning = true

		do {
			try AVAudioSession.sharedInstance().setCategory(.playback, options: .mixWithOthers)
			try AVAudioSession.sharedInstance().setActive(true)
			Self.retainSession()
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

		NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)

		cycleTask?.cancel()
		stopBackgroundTask()
		stopAudio()
		audioPlayer = nil

		if Self.releaseSession() {
			try? AVAudioSession.sharedInstance().setActive(false)
		}
	}

	@objc private func handleAudioInterruption(_ notification: Notification) {
		guard
			let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
			AVAudioSession.InterruptionType(rawValue: raw) == .began
		else { return }

		if !playAudio() { stop() }
	}

	// Re-arming the background-task assertion each cycle holds background time indefinitely.
	private func startBackgroundCycle() {
		cycleTask = Task {
			let audioStarted = await MainActor.run { playAudio() }
			guard audioStarted else { return }

			await MainActor.run { stopBackgroundTask() }

			backgroundTaskID = await UIApplication.shared.beginBackgroundTask { [weak self] in
				guard let self = self else { return }
				self.sendExpirationNotification()
				self.startBackgroundCycle()
			}

			await MainActor.run { stopAudio() }

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

	deinit {
		stop()
	}
}
