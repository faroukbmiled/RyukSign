//
//  DownloadProgressAttributes.swift
//  RyukSign
//
//  Live Activity attributes for download progress
//

import Foundation
import ActivityKit

enum DownloadPhase: String, Codable, Hashable {
	case queued
	case downloading
	case paused
	case importing
	case signing
	case completed

	var isProcessing: Bool {
		self == .importing || self == .signing
	}

	var icon: String {
		switch self {
		case .queued: return "clock"
		case .downloading: return "arrow.down"
		case .paused: return "pause.fill"
		case .importing: return "shippingbox.fill"
		case .signing: return "signature"
		case .completed: return "checkmark"
		}
	}
}

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
		// Optional so older builds' activities still decode.
		var phase: DownloadPhase?

		var resolvedPhase: DownloadPhase {
			if let phase { return phase }
			if isCompleted { return .completed }
			return isPaused ? .paused : .downloading
		}
	}

	var startTime: Date
}
