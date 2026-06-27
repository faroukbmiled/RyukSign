//
//  DownloadManager+Delegates.swift
//  RyukSign
//

import Foundation
import Combine
import UIKit
import UserNotifications
import BackgroundTasks
import ActivityKit

// MARK: - URLSessionDownloadDelegate

extension DownloadManager: URLSessionDownloadDelegate {
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
		guard let download = getDownloadTask(by: downloadTask) else { return }
		
		if isAppInBackground {
			let activeDownloads = downloads.filter { $0.progress > 0 && $0.progress < 1.0 && $0.id != download.id }
			if activeDownloads.isEmpty {
				UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ["merged_download_progress"])
			}
		}
		
		let tempDirectory = FileManager.default.temporaryDirectory
		let customTempDir = tempDirectory.appendingPathComponent("FeatherDownloads", isDirectory: true)
		
		do {
			try FileManager.default.createDirectoryIfNeeded(at: customTempDir)

			let suggestedFileName = downloadTask.response?.suggestedFilename ?? download.fileName
			let destinationURL = customTempDir.appendingPathComponent(suggestedFileName)

			try FileManager.default.removeFileIfNeeded(at: destinationURL)
			try FileManager.default.moveItem(at: location, to: destinationURL)

			// ID-keyed so duplicates count correctly (drives the X/Y counter).
			finishedDownloadingIDs.insert(download.id)

			if downloadActivity != nil {
				let activeDownloads = downloads.filter {
					($0.progress > 0 && $0.progress < 1.0 && !$0.isPaused) ||
					($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
				}
				forceNextProgressUpdate()
				updateLiveActivity(activeDownloads: activeDownloads)
			}

			try handlePackageFile(url: destinationURL, dl: download)
		} catch {
			if isAppInBackground {
				sendCompletionNotification(for: download, status: "❌ Download failed")
			}
			
			download.isActive = false
		}
	}
	
	func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
		guard let download = getDownloadTask(by: downloadTask) else { return }

		download.bytesDownloaded = totalBytesWritten

		if totalBytesExpectedToWrite > 0 {
			download.totalBytes = totalBytesExpectedToWrite
			download.progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
		} else if download.totalBytes > 0 {
			// Server returned 0; fall back to the last known total.
			download.progress = Double(totalBytesWritten) / Double(download.totalBytes)
		}

		// Fires per network chunk; gate the bg-task assertions and filter on the update cadence.
		guard Date().timeIntervalSince(self.lastUpdateTime) >= self.updateThrottle else { return }

		let activeDownloads = self.downloads.filter { $0.progress > 0 && $0.progress < 1.0 && !$0.isPaused }
		guard !activeDownloads.isEmpty else { return }

		if self.isAppInBackground {
			let taskID = UIApplication.shared.beginBackgroundTask {}

			if self.downloadActivity != nil {
				self.updateLiveActivity(activeDownloads: activeDownloads)
			} else {
				self.startLiveActivityIfNeeded()
			}

			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				if taskID != .invalid {
					UIApplication.shared.endBackgroundTask(taskID)
				}
			}
		} else {
			if self.downloadActivity != nil {
				self.updateLiveActivity(activeDownloads: activeDownloads)
			} else {
				self.startLiveActivityIfNeeded()
			}
		}
	}
	
	func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
		guard
			let error = error,
			let downloadTask = task as? URLSessionDownloadTask,
			let download = getDownloadTask(by: downloadTask)
		else {
			return
		}

		let nsError = error as NSError

		// Cancelled — stash resume data and bail.
		if nsError.code == NSURLErrorCancelled {
			if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
				download.resumeData = resumeData
				saveResumeData(for: download)
			}
			return
		}

		// Recoverable network errors — pause for retry instead of failing.
		if nsError.code == NSURLErrorNetworkConnectionLost ||
		   nsError.code == NSURLErrorNotConnectedToInternet ||
		   nsError.code == NSURLErrorTimedOut ||
		   nsError.code == NSURLErrorDNSLookupFailed {
			download.isPaused = true
			download.isActive = false

			if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
				download.resumeData = resumeData
				saveResumeData(for: download)
			}

			sendSystemNotification(
				title: "Download paused",
				body: "\(download.fileName) - will resume when you reopen the app",
				identifier: "pause_\(download.id)"
			)

			DispatchQueue.main.async {
				let activeDownloads = self.downloads.filter {
					($0.progress > 0 && $0.progress < 1.0) ||
					($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
				}

				if self.downloadActivity != nil && !activeDownloads.isEmpty {
					self.forceNextProgressUpdate()
					self.updateLiveActivityWithPausedState(activeDownloads: activeDownloads)
				}
			}

			return
		}

		// Non-resumable server/connection failures — cancel the download.
		if nsError.code == NSURLErrorCannotFindHost ||
		   nsError.code == NSURLErrorCannotConnectToHost ||
		   nsError.code == NSURLErrorBadURL ||
		   nsError.code == NSURLErrorUnsupportedURL ||
		   nsError.code == NSURLErrorResourceUnavailable ||
		   nsError.code == NSURLErrorFileDoesNotExist ||
		   nsError.code == NSURLErrorNoPermissionsToReadFile {
			if isAppInBackground {
				sendCompletionNotification(for: download, status: "❌ Download failed - cannot connect to server")
			} else {
				showUIErrorMessage(for: download, error: nsError)
			}

			download.isActive = false

			DispatchQueue.main.async {
				self.allActivityDownloads.removeValue(forKey: download.id)
				self.finishedDownloadingIDs.remove(download.id)

				if let index = self.getDownloadIndex(by: download.id) {
					self.downloads.remove(at: index)
				}

				let remainingActiveDownloads = self.downloads.filter {
					($0.progress > 0 && $0.progress < 1.0 && !$0.isPaused) ||
					($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
				}

				if !remainingActiveDownloads.isEmpty && self.downloadActivity != nil {
					self.forceNextProgressUpdate()
					self.updateLiveActivity(activeDownloads: remainingActiveDownloads)
				} else {
					self.dismissLiveActivityImmediately()
				}
			}

			return
		}

		// Any other non-recoverable error — drop the download.
		if isAppInBackground {
			sendCompletionNotification(for: download, status: "❌ Download failed")
		} else {
			showUIErrorMessage(for: download, error: nsError)
		}

			download.isActive = false

			DispatchQueue.main.async {
				self.allActivityDownloads.removeValue(forKey: download.id)
				self.finishedDownloadingIDs.remove(download.id)

				if let index = self.getDownloadIndex(by: download.id) {
					self.downloads.remove(at: index)
				}

				let remainingActiveDownloads = self.downloads.filter {
					($0.progress > 0 && $0.progress < 1.0 && !$0.isPaused) ||
					($0.unpackageProgress > 0 && $0.unpackageProgress < 1.0)
				}

				if !remainingActiveDownloads.isEmpty && self.downloadActivity != nil {
					self.forceNextProgressUpdate()
					self.updateLiveActivity(activeDownloads: remainingActiveDownloads)
				} else {
					self.dismissLiveActivityImmediately()
				}
			}
	}
	
	func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
		DispatchQueue.main.async {
			self.backgroundCompletionHandler?()
			self.backgroundCompletionHandler = nil
		}
	}
}

// MARK: - UNUserNotificationCenterDelegate

extension DownloadManager: UNUserNotificationCenterDelegate {
	func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
		completionHandler([.banner, .sound, .badge])
	}
	
	func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
		completionHandler()
	}
}
