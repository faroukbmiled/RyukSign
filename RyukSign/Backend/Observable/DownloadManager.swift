//
//  DownloadManager.swift
//  RyukSign
//
//  Created by samara on 3.05.2025.
//

import Foundation
import Combine
import UIKit
import UserNotifications
import BackgroundTasks
import ActivityKit

class DownloadManager: NSObject, ObservableObject {
	static let shared = DownloadManager()

	protocol ErrorDelegate: AnyObject {
		func showUIErrorMessage(title: String, message: String)
	}
	
	weak var errorDelegate: ErrorDelegate?
	
	@Published var downloads: [Download] = []
	@Published var currentDownloadSpeed: Int64 = 0

	var manualDownloads: [Download] {
		downloads.filter { isManualDownload($0.id) }
	}

	var _backgroundSession: URLSession!
	var _foregroundSession: URLSession!
	var backgroundCompletionHandler: (() -> Void)?

	var isAppInBackground = false
	var backgroundEntryTime: Date?

	var backgroundTaskManager: BackgroundTaskManager?
	var progressUpdateTimer: Timer?

	// `Any?` so the property carries no availability requirement (ActivityKit is 16.1+, app deploys to 16.0).
	var downloadActivity: Any?

	@available(iOS 16.2, *)
	var _downloadActivity: Activity<DownloadActivityAttributes>? {
		get { downloadActivity as? Activity<DownloadActivityAttributes> }
		set { downloadActivity = newValue }
	}
	var lastUpdateTime: Date = Date()
	var updateThrottle: TimeInterval = 2.0

	/// Makes the next Live Activity / progress notification skip the update throttle.
	func forceNextProgressUpdate() { lastUpdateTime = .distantPast }
	var activityStateTask: Task<Void, Never>?
	// Guards the race where a Live Activity is mid-creation (`downloadActivity == nil`) and the
	// progress timer would otherwise post a fallback notification.
	var isCreatingLiveActivity = false

	var lastBytesDownloaded: Int64 = 0
	var lastSpeedUpdateTime: Date = Date()

	var completedDownloadNames: [String] = []
	var isActivityShowingCompletion = false

	// Every download in this Live Activity session, incl. ones downloaded but not yet archived.
	var allActivityDownloads: [String: (fileName: String, downloaded: Int64, total: Int64)] = [:]

	// Downloads that finished downloading (X in the X/Y counter) — distinct from archiving completion.
	var finishedDownloadingIDs: Set<String> = []

	override init() {
		super.init()

		let foregroundConfig = URLSessionConfiguration.default
		foregroundConfig.timeoutIntervalForRequest = 300 // 5 min
		foregroundConfig.timeoutIntervalForResource = 7200 // 2 hours
		foregroundConfig.httpShouldUsePipelining = true
		foregroundConfig.allowsExpensiveNetworkAccess = true
		foregroundConfig.allowsConstrainedNetworkAccess = true
		foregroundConfig.httpMaximumConnectionsPerHost = 10
		foregroundConfig.multipathServiceType = .handover
		foregroundConfig.waitsForConnectivity = false

		_foregroundSession = URLSession(configuration: foregroundConfig, delegate: self, delegateQueue: nil)

		let backgroundConfig: URLSessionConfiguration = URLSessionConfiguration.background(withIdentifier: "ryuk2.anoxclan.com.background")
		backgroundConfig.isDiscretionary = false // don't wait for ideal conditions
		backgroundConfig.sessionSendsLaunchEvents = true
		backgroundConfig.shouldUseExtendedBackgroundIdleMode = false
		backgroundConfig.timeoutIntervalForRequest = 300 // 5 min
		backgroundConfig.timeoutIntervalForResource = 7200 // 2 hours
		backgroundConfig.httpShouldUsePipelining = true
		backgroundConfig.allowsExpensiveNetworkAccess = true
		backgroundConfig.allowsConstrainedNetworkAccess = true
		backgroundConfig.httpMaximumConnectionsPerHost = 10
		backgroundConfig.waitsForConnectivity = false
		backgroundConfig.networkServiceType = .responsiveData

		_backgroundSession = URLSession(configuration: backgroundConfig, delegate: self, delegateQueue: nil)

		requestNotificationPermissions()

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appWillEnterBackground),
			name: UIApplication.willResignActiveNotification,
			object: nil
		)
		
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appDidBecomeActive),
			name: UIApplication.didBecomeActiveNotification,
			object: nil
		)
		
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(appWillTerminate),
			name: UIApplication.willTerminateNotification,
			object: nil
		)

		// Live Activity control notifications from the widget extension.
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handlePauseDownloadsNotification),
			name: NSNotification.Name("PauseDownloads"),
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(handleResumeDownloadsNotification),
			name: NSNotification.Name("ResumeDownloads"),
			object: nil
		)
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}
	
	private func requestNotificationPermissions() {
		UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge, .providesAppNotificationSettings]) { granted, error in
			if granted {
			} else if let error = error {
			}
		}
		
		UNUserNotificationCenter.current().delegate = self
	}
	
	@objc private func appWillEnterBackground() {
		isAppInBackground = true
		backgroundEntryTime = Date()

		DispatchQueue.global(qos: .userInitiated).async { [weak self] in
			guard let self = self else { return }

			let hasActiveDownloads = self.downloads.contains { download in
				download.isActive || (download.progress > 0 && download.progress < 1.0)
			}

			if hasActiveDownloads {
				DispatchQueue.main.async {
					// Loop silent audio to keep the app alive in the background.
					if self.backgroundTaskManager == nil {
						self.backgroundTaskManager = BackgroundTaskManager(
							taskName: "DownloadManager",
							expirationTitle: "Downloads continuing",
							expirationBody: "Downloads will continue in the background"
						)
						self.backgroundTaskManager?.start()
					}

					self.startProgressNotificationTimer()

					// Audio cycle keeps us alive, so the foreground session works — no switch to the background session.
				}
			}
		}
	}

	@objc private func appDidBecomeActive() {
		isAppInBackground = false
		backgroundEntryTime = nil

		backgroundTaskManager?.stop()
		backgroundTaskManager = nil

		endProgressNotificationTimer()

		UNUserNotificationCenter.current().removeAllDeliveredNotifications()

		let hasActiveDownloads = downloads.contains { download in
			(download.isActive && !download.isPaused) ||
			(download.progress > 0 && download.progress < 1.0 && !download.isPaused) ||
			(download.unpackageProgress > 0 && download.unpackageProgress < 1.0)
		}

		let hasPausedDownloads = downloads.contains { download in
			download.isPaused && download.progress > 0 && download.progress < 1.0
		}

		if downloadActivity != nil && !hasActiveDownloads && !hasPausedDownloads {
			dismissLiveActivityImmediately()
			completedDownloadNames = []
			isActivityShowingCompletion = false
			allActivityDownloads = [:] 
			finishedDownloadingIDs = []
		}

		processPendingDownloads()

		for download in downloads where download.isPaused {
			resumeDownload(download)
		}

		let pausedDownloads = downloads.filter { $0.isPaused }
		if !pausedDownloads.isEmpty && downloadActivity != nil {
			let activeDownloads = self.downloads.filter {
				($0.progress > 0 && $0.progress < 1.0) ||
				($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
			}
			if !activeDownloads.isEmpty {
				self.forceNextProgressUpdate()
				self.updateLiveActivity(activeDownloads: activeDownloads)
			}
		}
	}
	
	@objc private func handlePauseDownloadsNotification() {
		DispatchQueue.main.async {
			self.pauseAllDownloads()
		}
	}

	@objc private func handleResumeDownloadsNotification() {
		DispatchQueue.main.async {
			self.resumeAllDownloads()
		}
	}

	@objc private func appWillTerminate() {
		// Must finish fast (synchronous, time-limited) to avoid watchdog termination.
		backgroundTaskManager?.stop()
		backgroundTaskManager = nil

		endProgressNotificationTimer()

		if #available(iOS 16.2, *), let activity = _downloadActivity {
			Task {
				await activity.end(nil, dismissalPolicy: .immediate)
			}
			downloadActivity = nil
		}

		let saveGroup = DispatchGroup()
		let deadline = DispatchTime.now() + .milliseconds(500)

		for download in downloads {
			if let task = download.task, task.state == .running {
				saveGroup.enter()
				task.cancel { resumeData in
					download.resumeData = resumeData
					self.saveResumeData(for: download)
					saveGroup.leave()
				}
			}
		}

		_ = saveGroup.wait(timeout: deadline)
	}
	
	
	private func startProgressNotificationTimer() {
		progressUpdateTimer?.invalidate()

		progressUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
			guard let self = self else { return }
			self.updateMergedProgressNotification()
		}

		if let timer = progressUpdateTimer {
			RunLoop.main.add(timer, forMode: .common)
		}
	}

	private func endProgressNotificationTimer() {
		progressUpdateTimer?.invalidate()
		progressUpdateTimer = nil
	}
	
	private func processPendingDownloads() {
		for download in downloads {
			if let pendingURL = download.pendingFileURL {
				do {
					try handlePackageFile(url: pendingURL, dl: download)
				} catch {
				}
				download.pendingFileURL = nil
			}
		}
	}
	
	func saveResumeData(for download: Download) {
		guard let resumeData = download.resumeData else { return }
		
		let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let resumeDataPath = documentsPath.appendingPathComponent("ResumeData_\(download.id).data")
		
		try? resumeData.write(to: resumeDataPath)
	}
	
	private func loadResumeData(for download: Download) -> Data? {
		let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let resumeDataPath = documentsPath.appendingPathComponent("ResumeData_\(download.id).data")
		
		return try? Data(contentsOf: resumeDataPath)
	}
	
	// MARK: - Notification Methods

	func updateMergedProgressNotification() {
		// Actively downloading only — archiving doesn't show progress notifications.
		let activeDownloads = downloads.filter {
			(($0.isActive || $0.progress > 0) && $0.progress < 1.0 && !$0.isPaused)
		}

		let pausedDownloads = downloads.filter {
			$0.progress > 0 && $0.progress < 1.0 && $0.isPaused
		}

		guard !activeDownloads.isEmpty || !pausedDownloads.isEmpty else {
			UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["merged_download_progress"])

			currentDownloadSpeed = 0
			endLiveActivity()

			if isAppInBackground && downloads.allSatisfy({ !$0.isActive || $0.isPaused }) {
				backgroundTaskManager?.stop()
				backgroundTaskManager = nil
				endProgressNotificationTimer()
			}

			return
		}

		// Imports (onlyArchiving) are excluded — no network bytes, they'd show a phantom 0% entry.
		if activeDownloads.isEmpty && !pausedDownloads.isEmpty {
			updateLiveActivityWithPausedState(activeDownloads: pausedDownloads)
		} else {
			let downloadingOnly = downloads.filter { !$0.onlyArchiving && $0.progress > 0 && $0.progress < 1.0 && !$0.isPaused }
			updateLiveActivity(activeDownloads: downloadingOnly)
		}

		// Live Activities are the primary progress UI; only fall back to a local notification when
		// they're genuinely unavailable. (Don't branch on `downloadActivity != nil` — it's
		// momentarily false mid-creation, which would race a stray notification onscreen.)
		if #available(iOS 16.2, *), ActivityAuthorizationInfo().areActivitiesEnabled {
			if downloadActivity == nil && !isCreatingLiveActivity {
				startLiveActivityIfNeeded()
			}
			UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["merged_download_progress"])
			return
		}

		// Network downloads only — imports must not produce a stuck 0% notification.
		let notifiableDownloads = activeDownloads.filter { !$0.onlyArchiving }
		guard !notifiableDownloads.isEmpty else {
			UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["merged_download_progress"])
			return
		}

		let content = UNMutableNotificationContent()

		if notifiableDownloads.count == 1 {
			let download = notifiableDownloads[0]
			let percent = Int(download.progress * 100)
			let bytesFormatted = formatBytes(download.bytesDownloaded)
			let totalFormatted = formatBytes(download.totalBytes)

			content.title = download.fileName
			content.body = "\(bytesFormatted) / \(totalFormatted)"
			content.subtitle = "Progress: \(percent)%"
		} else {
			let totalProgress = notifiableDownloads.reduce(0.0) { $0 + $1.progress }
			let averageProgress = totalProgress / Double(notifiableDownloads.count)
			let percent = Int(averageProgress * 100)

			let totalBytesDownloaded = notifiableDownloads.reduce(Int64(0)) { $0 + $1.bytesDownloaded }
			let totalBytesExpected = notifiableDownloads.reduce(Int64(0)) { $0 + $1.totalBytes }

			let bytesFormatted = formatBytes(totalBytesDownloaded)
			let totalFormatted = formatBytes(totalBytesExpected)

			content.title = "Downloading \(notifiableDownloads.count) files"
			content.subtitle = "Overall Progress: \(percent)%"
			content.body = "\(bytesFormatted) / \(totalFormatted)"
		}

		content.sound = nil
		content.interruptionLevel = .passive

		let request = UNNotificationRequest(
			identifier: "merged_download_progress",
			content: content,
			trigger: nil
		)

		UNUserNotificationCenter.current().add(request)
	}
	
	func sendSystemNotification(title: String, body: String, identifier: String) {
		let content = UNMutableNotificationContent()
		content.title = title
		content.body = body
		content.sound = .default
		
		let request = UNNotificationRequest(
			identifier: identifier,
			content: content,
			trigger: nil
		)
		
		UNUserNotificationCenter.current().add(request)
	}
	
	func sendCompletionNotification(for download: Download, status: String) {
		let content = UNMutableNotificationContent()
		content.title = status
		content.body = download.fileName
		content.sound = .default
		content.interruptionLevel = .timeSensitive
		
		let request = UNNotificationRequest(
			identifier: "completion_\(download.id)",
			content: content,
			trigger: nil
		)
		
		UNUserNotificationCenter.current().add(request)
	}

	func showUIErrorMessage(for download: Download, error: NSError) {
		DispatchQueue.main.async {
			let generator = UINotificationFeedbackGenerator()
			generator.notificationOccurred(.error)

			self.errorDelegate?.showUIErrorMessage(
				title: "Failed to download ipa",
				message: error.localizedDescription
			)
		}
	}
	
	// MARK: - Helper Methods
	
	private func formatBytes(_ bytes: Int64) -> String {
		let formatter = ByteCountFormatter()
		formatter.countStyle = .binary
		return formatter.string(fromByteCount: bytes)
	}
	
	// MARK: - Public Methods
	
	func startDownload(from url: URL, id: String = UUID().uuidString, appName: String? = nil, appDescription: String? = nil) -> Download {
        if let existingDownload = downloads.first(where: { $0.url == url }) {
            resumeDownload(existingDownload)
            return existingDownload
        }

        let download = Download(id: id, url: url, appName: appName, appDescription: appDescription)
        download.isActive = true

		let session = isAppInBackground ? _backgroundSession! : _foregroundSession!

		var request = URLRequest(url: url)
		request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
		request.networkServiceType = .responsiveData
		request.allowsExpensiveNetworkAccess = true
		request.allowsConstrainedNetworkAccess = true
		request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")

		// Auth headers for premium sources.
		RyukSignAPI.applyAuthHeaders(to: &request)

		let task = session.downloadTask(with: request)
		download.task = task
		task.priority = 1.0
		task.resume()

		DispatchQueue.main.async {
			self.objectWillChange.send()
			self.downloads.append(download)

			if self.isAppInBackground && self.downloads.count == 1 {
				if self.backgroundTaskManager == nil {
					self.backgroundTaskManager = BackgroundTaskManager(
						taskName: "DownloadManager",
						expirationTitle: "Downloads continuing",
						expirationBody: "Downloads will continue in the background"
					)
					self.backgroundTaskManager?.start()
				}
				self.startProgressNotificationTimer()
			}

			// BGContinuedProcessingTask keeps work going in the background on iOS 19+.
			if #available(iOS 19.0, *) {
				if let appDelegate = UIApplication.shared.delegate as? AppDelegate {
					appDelegate.submitContinuedProcessingTask()
				}
			}

			Task {
				self.startLiveActivityIfNeeded()
			}
		}

		return download
	}
	
	func startArchive(from url: URL, id: String = UUID().uuidString, appName: String? = nil, completion: ((Error?) -> Void)? = nil) -> Download {
		let download = Download(id: id, url: url, onlyArchiving: true, appName: appName)
		download.isActive = true

		DispatchQueue.main.async {
			self.objectWillChange.send()
			self.downloads.append(download)
			download.unpackageProgress = 0.1
		}

		let archivingTaskManager = BackgroundTaskManager(
			taskName: "DownloadManager_Archive",
			expirationTitle: "Archiving continuing",
			expirationBody: "The archiving will continue when you reopen the app"
		)
		archivingTaskManager.start()

		DispatchQueue.global().async {
			FR.handlePackageFile(url, download: download) { err in
				defer {
					archivingTaskManager.stop()
				}

				if let error = err {
					let generator = UINotificationFeedbackGenerator()
					generator.notificationOccurred(.error)

					if let completion = completion {
						// Caller owns the error UI; don't also fire the generic delegate alert.
						DispatchQueue.main.async { completion(error) }
					} else if !self.isAppInBackground {
						self.errorDelegate?.showUIErrorMessage(
							title: "Import Failed",
							message: error.localizedDescription
						)
					}
				} else {
					DispatchQueue.main.async {
						self.objectWillChange.send()
						download.unpackageProgress = 1.0
						completion?(nil)
					}
				}

				download.isActive = false

				DispatchQueue.main.async {
					// Drop from activity tracking only once archiving completes (not on download finish).
					if err == nil {
						self.completedDownloadNames.append(download.fileName)
						self.allActivityDownloads.removeValue(forKey: download.id)
						self.finishedDownloadingIDs.remove(download.id)
					}

					// Snapshot before removing this one.
					let remainingActiveDownloads = self.downloads.filter { dl in
						dl.id != download.id && (dl.isActive || (dl.progress > 0 && dl.progress < 1.0) || (dl.unpackageProgress > 0 && dl.unpackageProgress < 1.0))
					}
					let isLastDownload = remainingActiveDownloads.isEmpty

					if let index = self.getDownloadIndex(by: download.id) {
						self.downloads.remove(at: index)
					}

					if isLastDownload {
						// Background archiving needs no completion state; foreground keeps it until reopened.
						if self.isAppInBackground {
							self.dismissLiveActivityImmediately()
						} else {
							self.endLiveActivity()
						}
					}
				}
			}
		}

		return download
	}
	
	func resumeDownload(_ download: Download) {
		if download.resumeData == nil {
			download.resumeData = loadResumeData(for: download)
		}
		
		let session = isAppInBackground ? _backgroundSession : _foregroundSession
		
		if let resumeData = download.resumeData {
			let task = session!.downloadTask(withResumeData: resumeData)
			download.task = task
			task.resume()
			download.isActive = true
			download.isPaused = false
		} else {
			let url = download.task?.originalRequest?.url ?? download.url
			var request = URLRequest(url: url)
			RyukSignAPI.applyAuthHeaders(to: &request)
			let task = session!.downloadTask(with: request)
			download.task = task
			task.resume()
			download.isActive = true
			download.isPaused = false
		}
		
		DispatchQueue.main.async {
			let activeDownloads = self.downloads.filter {
				($0.progress > 0 && $0.progress < 1.0) ||
				($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
			}
			if !activeDownloads.isEmpty && self.downloadActivity != nil {
				self.forceNextProgressUpdate()
				self.updateLiveActivity(activeDownloads: activeDownloads)
			}
		}
	}

	func pauseDownload(_ download: Download) {
		download.task?.cancel { resumeData in
			download.resumeData = resumeData
			self.saveResumeData(for: download)
		}
		download.isPaused = true
		download.isActive = false
	}
	
	func cancelDownload(_ download: Download) {
		download.task?.cancel()
		download.isActive = false

		let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
		let resumeDataPath = documentsPath.appendingPathComponent("ResumeData_\(download.id).data")
		try? FileManager.default.removeItem(at: resumeDataPath)

		DispatchQueue.main.async {
			if let index = self.downloads.firstIndex(where: { $0.id == download.id }) {
				self.objectWillChange.send()

				// Drop from tracking so a manually stopped download leaves overall progress.
				self.allActivityDownloads.removeValue(forKey: download.id)
				self.finishedDownloadingIDs.remove(download.id)

				self.downloads.remove(at: index)

				let remainingActiveDownloads = self.downloads.filter {
					$0.progress > 0 && $0.progress < 1.0 && !$0.isPaused
				}

				if !remainingActiveDownloads.isEmpty && self.downloadActivity != nil {
					self.forceNextProgressUpdate()
					self.updateLiveActivity(activeDownloads: remainingActiveDownloads)
				} else {
					self.endLiveActivity()
				}

				if self.isAppInBackground && self.downloads.allSatisfy({ !$0.isActive || $0.isPaused }) {
					self.backgroundTaskManager?.stop()
					self.backgroundTaskManager = nil
					self.endProgressNotificationTimer()
				}
			}
		}
	}
	
	func pauseAllDownloads() {
		for download in downloads {
			pauseDownload(download)
		}
		
		DispatchQueue.main.async {
			let activeDownloads = self.downloads.filter {
				($0.progress > 0 && $0.progress < 1.0) ||
				($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
			}
			if !activeDownloads.isEmpty && self.downloadActivity != nil {
				self.forceNextProgressUpdate()
				self.updateLiveActivity(activeDownloads: activeDownloads)
			}
		}
	}
	
	func resumeAllDownloads() {
		for download in downloads where download.isPaused {
			resumeDownload(download)
		}

		if isAppInBackground && backgroundTaskManager == nil {
			let hasActiveDownloads = downloads.contains { download in
				download.isActive || (download.progress > 0 && download.progress < 1.0)
			}

			if hasActiveDownloads {
				backgroundTaskManager = BackgroundTaskManager(
					taskName: "DownloadManager",
					expirationTitle: "Downloads continuing",
					expirationBody: "Downloads will continue in the background"
				)
				backgroundTaskManager?.start()
				startProgressNotificationTimer()
			}
		}
	}
	
	func isManualDownload(_ string: String) -> Bool {
		return string.contains("FeatherManualDownload")
	}
	
	func getDownload(by id: String) -> Download? {
		return downloads.first(where: { $0.id == id })
	}
	
	func getDownloadIndex(by id: String) -> Int? {
		return downloads.firstIndex(where: { $0.id == id })
	}
	
	func getDownloadTask(by task: URLSessionDownloadTask) -> Download? {
		return downloads.first(where: { $0.task == task })
	}
	
	var nonManualDownloads: [Download] {
		downloads.filter { !isManualDownload($0.id) }
	}

	func handlePackageFile(url: URL, dl: Download) throws {
		// Defer archiving only if it hasn't started yet; if it has, let it continue.
		if isAppInBackground && dl.unpackageProgress == 0.0 {
			dl.pendingFileURL = url
			sendCompletionNotification(for: dl, status: "✅ Download complete - ready to import")
			return
		}

		DispatchQueue.main.async {
			self.objectWillChange.send()
			dl.progress = 1.0
			dl.unpackageProgress = 0.0
		}

		let archivingTaskManager = BackgroundTaskManager(
			taskName: "DownloadManager_Import",
			expirationTitle: "Import continuing",
			expirationBody: "The import will continue when you reopen the app"
		)
		archivingTaskManager.start()

		FR.handlePackageFile(url, download: dl) { err in
			defer {
				archivingTaskManager.stop()
			}
			if let error = err {
				let generator = UINotificationFeedbackGenerator()
				generator.notificationOccurred(.error)

				if self.isAppInBackground {
					self.sendCompletionNotification(for: dl, status: "❌ Import failed: \(error.localizedDescription)")
				} else {
					self.errorDelegate?.showUIErrorMessage(
						title: "Import Failed",
						message: error.localizedDescription
					)
				}
			} else {
				DispatchQueue.main.async {
					self.objectWillChange.send()
					dl.unpackageProgress = 1.0
				}
			}

			dl.isActive = false

			DispatchQueue.main.async {
				// Drop from activity tracking only once archiving completes (not on download finish).
				if err == nil {
					DownloadManager.shared.completedDownloadNames.append(dl.fileName)
					DownloadManager.shared.allActivityDownloads.removeValue(forKey: dl.id)
					DownloadManager.shared.finishedDownloadingIDs.remove(dl.id)
				}

				// Snapshot before removing this one.
				let remainingActiveDownloads = DownloadManager.shared.downloads.filter { download in
					download.id != dl.id && (download.isActive || (download.progress > 0 && download.progress < 1.0) || (download.unpackageProgress > 0 && download.unpackageProgress < 1.0))
				}
				let isLastDownload = remainingActiveDownloads.isEmpty

				if let index = DownloadManager.shared.getDownloadIndex(by: dl.id) {
					DownloadManager.shared.downloads.remove(at: index)
				}

				if isLastDownload {
					// Background archiving needs no completion state; foreground keeps it until reopened.
					if DownloadManager.shared.isAppInBackground {
						DownloadManager.shared.dismissLiveActivityImmediately()
					} else {
						DownloadManager.shared.endLiveActivity()
					}
				}
			}
		}
	}
}
