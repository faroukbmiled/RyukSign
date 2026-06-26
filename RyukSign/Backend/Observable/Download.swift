//
//  Download.swift
//  RyukSign
//

import Foundation
import Combine
import UIKit
import UserNotifications
import BackgroundTasks
import ActivityKit

class Download: Identifiable, @unchecked Sendable {
	@Published var progress: Double = 0.0
	@Published var bytesDownloaded: Int64 = 0
	@Published var totalBytes: Int64 = 0
	@Published var unpackageProgress: Double = 0.0
	@Published var isActive: Bool = false
	@Published var isPaused: Bool = false
	
	var overallProgress: Double {
		onlyArchiving
		? unpackageProgress
		: (0.3 * unpackageProgress) + (0.7 * progress)
	}
	
	var task: URLSessionDownloadTask?
	var resumeData: Data?
	var pendingFileURL: URL?
	
	let id: String
	let url: URL
	let fileName: String
	let onlyArchiving: Bool
	let appDescription: String?

	var isManual: Bool {
		id.contains("FeatherManualDownload")
	}

	init(
		id: String,
		url: URL,
		onlyArchiving: Bool = false,
		appName: String? = nil,
		appDescription: String? = nil
	) {
		self.id = id
		self.url = url
		self.onlyArchiving = onlyArchiving
		self.fileName = appName ?? url.lastPathComponent
		self.appDescription = appDescription
	}

	func pause() {
		DownloadManager.shared.pauseDownload(self)
	}

	func resume() {
		DownloadManager.shared.resumeDownload(self)
	}
}
