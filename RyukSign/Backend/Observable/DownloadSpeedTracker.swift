//
//  DownloadSpeedTracker.swift
//  RyukSign
//
//  Created by Ryuk on 22.08.2026.
//

import Foundation

struct DownloadSpeedTracker {
	private static let maxRate: Double = 1_073_741_824
	private static let minimumInterval: TimeInterval = 0.2
	private static let riseSmoothing = 0.4
	private static let fallSmoothing = 0.7

	private var lastBytes: Int64?
	private var lastSampledAt: Date?
	private var rate: Double = 0

	var current: Int64 { Int64(rate.rounded()) }

	mutating func sample(totalBytes: Int64, at now: Date = Date()) -> Int64 {
		// A download leaving the list shrinks the total; rebase instead of reading it as a stall.
		guard let lastBytes, let lastSampledAt, totalBytes >= lastBytes else {
			rebase(to: totalBytes, at: now)
			return current
		}

		let elapsed = now.timeIntervalSince(lastSampledAt)
		guard elapsed >= Self.minimumInterval else { return current }

		let instant = min(Double(totalBytes - lastBytes) / elapsed, Self.maxRate)
		// Falls faster than it rises, so a stall doesn't sit on a stale rate.
		let smoothing = instant < rate ? Self.fallSmoothing : Self.riseSmoothing
		rate = rate > 0 ? rate + smoothing * (instant - rate) : instant
		if rate < 1 { rate = 0 }

		rebase(to: totalBytes, at: now)
		return current
	}

	mutating func reset() {
		lastBytes = nil
		lastSampledAt = nil
		rate = 0
	}

	private mutating func rebase(to bytes: Int64, at date: Date) {
		lastBytes = bytes
		lastSampledAt = date
	}
}
