//
//  DownloadManager+LiveActivity.swift
//  RyukSign
//

import Foundation
import Combine
import UIKit
import UserNotifications
import BackgroundTasks
import ActivityKit

extension DownloadManager {
	// MARK: - Live Activity Methods

	private func truncateAppName(_ name: String, maxLength: Int = 15) -> String {
		if name.count <= maxLength {
			return name
		}
		let truncated = String(name.prefix(maxLength - 1))
		return truncated + "…"
	}

	private func formatAppNamesList(_ downloads: [Download]) -> [String] {
		return downloads.map { truncateAppName($0.fileName) }
	}

	private func cleanupAllLiveActivities() async {
		guard #available(iOS 16.2, *) else { return }
		// End existing activities to prevent duplicates.
		for activity in Activity<DownloadActivityAttributes>.activities {
			await activity.end(
				ActivityContent(
					state: activity.content.state,
					staleDate: nil
				),
				dismissalPolicy: .immediate
			)
		}
	}

	func startLiveActivityIfNeeded() {
		guard #available(iOS 16.2, *) else { return }
		guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

		if downloadActivity != nil {
			return
		}

		// Timer, didWriteData and startDownload can all call this concurrently — don't double-create.
		if isCreatingLiveActivity {
			return
		}

		// Imports (onlyArchiving) have no bytes, so only spawn for a real network download.
		let hasNetworkDownload = downloads.contains {
			!$0.onlyArchiving && $0.progress >= 0 && $0.progress < 1.0 && !$0.isPaused
		}
		guard hasNetworkDownload else { return }

		isCreatingLiveActivity = true

		Task {
			await cleanupAllLiveActivities()
			await MainActor.run {
				self.createNewLiveActivity()
				self.isCreatingLiveActivity = false
			}
		}
	}

	private func createNewLiveActivity() {
		guard #available(iOS 16.2, *) else { return }
		guard downloadActivity == nil else { return }

		// Imports (onlyArchiving) carry no bytes and would show a permanent 0% entry — exclude them.
		let activeDownloads = downloads.filter { !$0.onlyArchiving && $0.progress >= 0 && $0.progress < 1.0 && !$0.isPaused }
		guard !activeDownloads.isEmpty else { return }

		completedDownloadNames = []
		allActivityDownloads = Dictionary(uniqueKeysWithValues: activeDownloads.map {
			($0.id, (fileName: $0.fileName, downloaded: $0.bytesDownloaded, total: $0.totalBytes))
		})

		let currentFileName = activeDownloads.count > 1
			? "Multiple Downloads"
			: (activeDownloads.first?.fileName ?? "Download")

		let appNames = Array(allActivityDownloads.values.map { truncateAppName($0.fileName) })

		let totalProgress = activeDownloads.reduce(0.0) { $0 + $1.progress }
		let averageProgress = activeDownloads.isEmpty ? 0.0 : totalProgress / Double(activeDownloads.count)
		let totalBytesDownloaded = activeDownloads.reduce(Int64(0)) { $0 + $1.bytesDownloaded }
		let totalBytesExpected = activeDownloads.reduce(Int64(0)) { $0 + $1.totalBytes }

		let contentState = DownloadActivityAttributes.ContentState(
			currentDownload: 0,
			totalDownloads: activeDownloads.count,
			overallProgress: averageProgress,
			currentFileName: currentFileName,
			appNames: appNames,
			totalBytesDownloaded: totalBytesDownloaded,
			totalBytesExpected: max(totalBytesExpected, 1),
			bytesPerSecond: currentDownloadSpeed,
			lastUpdateTime: Date(),
			estimatedCompletionDate: nil,
			isCompleted: false,
			isPaused: false,
			phase: .downloading
		)

		let attributes = DownloadActivityAttributes(startTime: Date())
		let staleDate = Date().addingTimeInterval(10)

		do {
			_downloadActivity = try Activity.request(
				attributes: attributes,
				content: ActivityContent(state: contentState, staleDate: staleDate),
				pushType: nil
			)

			monitorActivityState()
		} catch {}
	}

	private func monitorActivityState() {
		activityStateTask?.cancel()

		guard #available(iOS 16.2, *), let activity = _downloadActivity else { return }

		activityStateTask = Task {
			for await state in activity.activityStateUpdates {
				if state == .dismissed {
					await MainActor.run {
						self.downloadActivity = nil
						self.activityStateTask?.cancel()
						self.activityStateTask = nil
					}
					break
				}
			}
		}
	}

	func updateLiveActivityWithPausedState(activeDownloads: [Download]) {
		guard #available(iOS 16.2, *), let activity = _downloadActivity else { return }

		let hasPausedDownloads = downloads.contains { $0.isPaused }

		let currentState = activity.content.state
		let pausedState = DownloadActivityAttributes.ContentState(
			currentDownload: currentState.currentDownload,
			totalDownloads: currentState.totalDownloads,
			overallProgress: currentState.overallProgress,
			currentFileName: currentState.currentFileName,
			appNames: currentState.appNames,
			totalBytesDownloaded: currentState.totalBytesDownloaded,
			totalBytesExpected: currentState.totalBytesExpected,
			bytesPerSecond: 0,
			lastUpdateTime: Date(),
			estimatedCompletionDate: nil,
			isCompleted: false,
			isPaused: hasPausedDownloads,
			phase: .paused
		)

		Task { @MainActor [weak self] in
			guard let self = self else { return }

			do {
				try await withTimeout(seconds: 2.0) {
					await activity.update(
						ActivityContent(state: pausedState, staleDate: Date().addingTimeInterval(10))
					)
				}
			} catch {
				self.downloadActivity = nil
				self.activityStateTask?.cancel()
				self.activityStateTask = nil
			}
		}
	}

	func updateLiveActivity(activeDownloads: [Download]) {
		guard #available(iOS 16.2, *) else { return }
		let authInfo = ActivityAuthorizationInfo()
		guard authInfo.areActivitiesEnabled else {
			if downloadActivity != nil {
				dismissLiveActivityImmediately()
			}
			return
		}

		let now = Date()
		let shouldThrottle = downloadActivity != nil && now.timeIntervalSince(lastUpdateTime) < updateThrottle
		guard !shouldThrottle else { return }
		lastUpdateTime = now

		// Imports (onlyArchiving) have no network bytes and would skew aggregate progress — skip them.
		for download in activeDownloads where !download.onlyArchiving {
			allActivityDownloads[download.id] = (
				fileName: download.fileName,
				downloaded: download.bytesDownloaded,
				total: download.totalBytes
			)
		}

		// Across the whole session — includes finished-but-not-yet-archived downloads.
		let totalBytesDownloaded = allActivityDownloads.values.reduce(Int64(0)) { $0 + $1.downloaded }
		let totalBytesExpected = allActivityDownloads.values.reduce(Int64(0)) { $0 + $1.total }

		let bytesPerSecond = currentDownloadSpeed

		var estimatedCompletionDate: Date? = nil
		if bytesPerSecond > 0 {
			let remainingBytes = totalBytesExpected - totalBytesDownloaded
			let estimatedSeconds = Double(remainingBytes) / Double(bytesPerSecond)
			estimatedCompletionDate = Date().addingTimeInterval(estimatedSeconds)
		}

		// Keep names until archived (not when downloading finishes).
		let appNames = Array(allActivityDownloads.values.map { truncateAppName($0.fileName) })
		let totalCount = allActivityDownloads.count

		// The "X" in "X/Y" — counts finished downloads, not finished archives.
		let finishedDownloadingCount = finishedDownloadingIDs.count

		let currentFileName = totalCount > 1
			? "Multiple Downloads"
			: (allActivityDownloads.values.first?.fileName ?? activeDownloads.first?.fileName ?? "Download")

		let summary = DownloadProgressSummary(downloads.filter { !$0.onlyArchiving })
		let isDownloading = summary.phase == .downloading
		let isPaused = summary.phase == .paused

		let contentState = DownloadActivityAttributes.ContentState(
			currentDownload: finishedDownloadingCount,
			totalDownloads: totalCount,
			overallProgress: summary.progress,
			currentFileName: currentFileName,
			appNames: appNames,
			totalBytesDownloaded: totalBytesDownloaded,
			totalBytesExpected: totalBytesExpected,
			bytesPerSecond: isDownloading ? bytesPerSecond : 0,
			lastUpdateTime: now,
			estimatedCompletionDate: isDownloading ? estimatedCompletionDate : nil,
			isCompleted: false,
			isPaused: isPaused,
			phase: summary.phase
		)

		let staleDate = Date().addingTimeInterval(10)

		if let activity = _downloadActivity {
			Task { @MainActor [weak self] in
				guard let self = self else { return }

				do {
					try await withTimeout(seconds: 2.0) {
						await activity.update(
							ActivityContent(state: contentState, staleDate: staleDate)
						)
					}
				} catch {
					self.downloadActivity = nil
					self.activityStateTask?.cancel()
					self.activityStateTask = nil
				}
			}
		} else if !isCreatingLiveActivity {
			// Only seed from real network downloads; a pure-import session must not spawn one.
			guard totalCount > 0 else { return }
			let attributes = DownloadActivityAttributes(startTime: Date())
			isCreatingLiveActivity = true

			Task { @MainActor [weak self] in
				guard let self = self else { return }

				do {
					let newActivity = try await withTimeout(seconds: 2.0) {
						try Activity.request(
							attributes: attributes,
							content: ActivityContent(state: contentState, staleDate: staleDate),
							pushType: nil
						)
					}

					self.downloadActivity = newActivity
					self.monitorActivityState()
				} catch {
					self.downloadActivity = nil
				}
				self.isCreatingLiveActivity = false
			}
		}
	}

	private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
		try await withThrowingTaskGroup(of: T.self) { group in
			group.addTask {
				try await operation()
			}

			group.addTask {
				try await Task.sleep(for: .seconds(seconds))
				throw TimeoutError()
			}

			let result = try await group.next()!
			group.cancelAll()
			return result
		}
	}

	private struct TimeoutError: Error {}

	private func completeLiveActivity() {
		guard #available(iOS 16.2, *), let activity = _downloadActivity else { return }

		// In foreground, dismiss instead of showing a completion banner.
		if !isAppInBackground {
			dismissLiveActivityImmediately()
			return
		}

		let completedNames = completedDownloadNames.isEmpty
			? activity.content.state.appNames
			: completedDownloadNames.map { truncateAppName($0) }

		// Keep the original total so the banner reads X/X.
		let totalCount = activity.content.state.totalDownloads

		let completionState = DownloadActivityAttributes.ContentState(
			currentDownload: totalCount,
			totalDownloads: totalCount,
			overallProgress: 1.0,
			currentFileName: completedNames.count > 1 ? "Multiple Downloads" : (completedNames.first ?? "Download"),
			appNames: completedNames,
			totalBytesDownloaded: activity.content.state.totalBytesExpected,
			totalBytesExpected: activity.content.state.totalBytesExpected,
			bytesPerSecond: 0,
			lastUpdateTime: Date(),
			estimatedCompletionDate: nil,
			isCompleted: true,
			isPaused: false,
			phase: .completed
		)

		forceNextProgressUpdate()
		isActivityShowingCompletion = true

		Task { @MainActor [weak self] in
			guard let self = self else { return }

			do {
				try await withTimeout(seconds: 2.0) {
					await activity.update(
						ActivityContent(state: completionState, staleDate: nil)
					)
				}
				// Left alive in Notification Center; dismissed when the app becomes active.
			} catch {
				self.downloadActivity = nil
				self.activityStateTask?.cancel()
				self.activityStateTask = nil
			}
		}
	}

	func endLiveActivity() {
		completeLiveActivity()
	}

	func dismissLiveActivityImmediately() {
		guard #available(iOS 16.2, *), let activity = _downloadActivity else { return }

		Task {
			await activity.end(
				ActivityContent(
					state: activity.content.state,
					staleDate: nil
				),
				dismissalPolicy: .immediate
			)

			await MainActor.run {
				self.downloadActivity = nil
				self.activityStateTask?.cancel()
				self.activityStateTask = nil
				self.allActivityDownloads = [:]
				self.finishedDownloadingIDs = []
			}
		}
	}
}
