//
//  DownloadProgressAttributes.swift
//  RyukSign
//
//  Live Activity attributes for download progress
//

import Foundation
import ActivityKit

struct DownloadActivityAttributes: ActivityAttributes {
	public struct ContentState: Codable, Hashable {
		var currentDownload: Int
		var totalDownloads: Int
		var overallProgress: Double
		var currentFileName: String
		var appNames: [String]
		var totalBytesDownloaded: Int64
		var totalBytesExpected: Int64
		var bytesPerSecond: Int64
		var lastUpdateTime: Date
		var estimatedCompletionDate: Date?
		var isCompleted: Bool
		var isPaused: Bool
	}

	var startTime: Date
}
