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
	@Published var isImporting: Bool = false

	var phase: DownloadPhase {
		if isImporting { return .importing }
		if unpackageProgress >= 1.0 { return .completed }
		if onlyArchiving || progress >= 1.0 { return .importing }
		if isPaused { return .paused }
		return (isActive || progress > 0) ? .downloading : .queued
	}

	var phaseProgress: Double {
		switch phase {
		case .queued: return 0
		case .downloading, .paused: return progress
		case .importing: return unpackageProgress
		case .completed: return 1
		}
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

	func beginImport() {
		isImporting = true
		unpackageProgress = 0.05
	}

	func endImport() {
		isImporting = false
		pendingFileURL = nil
	}

	func pause() {
		DownloadManager.shared.pauseDownload(self)
	}

	func resume() {
		DownloadManager.shared.resumeDownload(self)
	}
}

struct DownloadProgressSummary: Equatable {
	let phase: DownloadPhase
	let progress: Double
	let downloadingCount: Int
	let pausedCount: Int
	let importingCount: Int

	init(_ downloads: [Download]) {
		let byPhase = Dictionary(grouping: downloads, by: \.phase)
		let pending = (byPhase[.downloading] ?? []) + (byPhase[.queued] ?? []) + (byPhase[.paused] ?? [])
		let importing = byPhase[.importing] ?? []

		downloadingCount = byPhase[.downloading]?.count ?? 0
		pausedCount = byPhase[.paused]?.count ?? 0
		importingCount = importing.count

		if !pending.isEmpty {
			phase = downloadingCount == 0 && pausedCount > 0 ? .paused : .downloading
			let expected = pending.reduce(Int64(0)) { $0 + $1.totalBytes }
			if expected > 0 {
				let received = pending.reduce(Int64(0)) { $0 + $1.bytesDownloaded }
				progress = min(1, Double(received) / Double(expected))
			} else {
				progress = Self.average(pending.map(\.phaseProgress))
			}
		} else if !importing.isEmpty {
			phase = .importing
			progress = Self.average(importing.map(\.phaseProgress))
		} else {
			phase = downloads.isEmpty ? .queued : .completed
			progress = downloads.isEmpty ? 0 : 1
		}
	}

	private static func average(_ values: [Double]) -> Double {
		guard !values.isEmpty else { return 0 }
		return values.reduce(0, +) / Double(values.count)
	}
}
