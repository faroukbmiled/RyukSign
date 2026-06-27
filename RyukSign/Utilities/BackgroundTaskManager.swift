//
//  BackgroundTaskManager.swift
//  RyukSign
//
//  Created by Ryuk on 13.10.2025.
//

import Foundation
import AVFoundation
import UserNotifications

final class BackgroundTaskManager {

	// MARK: - Shared silence engine
	// Refcounted: the session is process-wide, so stopping one manager must not cut audio for others.
	private static let _lock = NSLock()
	private static var _users = 0
	private static let _engine = AVAudioEngine()
	private static var _silenceNode: AVAudioSourceNode?
	private static var _interruptionObserver: NSObjectProtocol?

	private static func retain() -> Bool {
		_lock.lock(); defer { _lock.unlock() }
		_users += 1
		guard _users == 1 else { return true }

		do {
			let session = AVAudioSession.sharedInstance()
			try session.setCategory(.playback, options: .mixWithOthers)
			try session.setActive(true)

			let node = AVAudioSourceNode { _, _, _, audioBufferList -> OSStatus in
				let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
				for buffer in buffers {
					memset(buffer.mData, 0, Int(buffer.mDataByteSize))
				}
				return noErr
			}
			_silenceNode = node
			_engine.attach(node)
			_engine.connect(node, to: _engine.mainMixerNode, format: nil)
			try _engine.start()

			_interruptionObserver = NotificationCenter.default.addObserver(
				forName: AVAudioSession.interruptionNotification,
				object: session,
				queue: .main
			) { note in
				guard
					let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
					AVAudioSession.InterruptionType(rawValue: raw) == .ended
				else { return }
				try? session.setActive(true)
				try? _engine.start()
			}
			return true
		} catch {
			_users = 0
			return false
		}
	}

	private static func release() {
		_lock.lock(); defer { _lock.unlock() }
		_users = max(0, _users - 1)
		guard _users == 0 else { return }

		if let observer = _interruptionObserver {
			NotificationCenter.default.removeObserver(observer)
			_interruptionObserver = nil
		}
		_engine.stop()
		if let node = _silenceNode {
			_engine.detach(node)
			_silenceNode = nil
		}
		try? AVAudioSession.sharedInstance().setActive(false)
	}

	// MARK: - Properties

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

	func start() {
		guard !isRunning else { return }
		isRunning = true

		// Can't hold background time (Low Power Mode, audio disabled) — tell the user.
		if !Self.retain() {
			isRunning = false
			sendExpirationNotification()
		}
	}

	func stop() {
		guard isRunning else { return }
		isRunning = false
		Self.release()
	}

	// MARK: - Private Methods

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
