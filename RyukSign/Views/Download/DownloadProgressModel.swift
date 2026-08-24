//
//  DownloadProgressModel.swift
//  RyukSign
//
//  Created by Ryuk on 24.08.2026.
//

import Foundation
import Combine

extension Download {
	var progressEvents: AnyPublisher<Void, Never> {
		Publishers.MergeMany([
			$progress.map { _ in }.eraseToAnyPublisher(),
			$unpackageProgress.map { _ in }.eraseToAnyPublisher(),
			$bytesDownloaded.map { _ in }.eraseToAnyPublisher(),
			$totalBytes.map { _ in }.eraseToAnyPublisher(),
			$isActive.map { _ in }.eraseToAnyPublisher(),
			$isPaused.map { _ in }.eraseToAnyPublisher(),
			$isImporting.map { _ in }.eraseToAnyPublisher(),
			$isSigning.map { _ in }.eraseToAnyPublisher(),
		]).eraseToAnyPublisher()
	}
}

/// `Download` is written from background threads; views observe this instead.
@MainActor
final class DownloadProgressModel: ObservableObject {
	@Published private(set) var phase: DownloadPhase = .queued
	@Published private(set) var phaseProgress: Double = 0
	@Published private(set) var bytesDownloaded: Int64 = 0
	@Published private(set) var totalBytes: Int64 = 0

	private weak var download: Download?
	private var cancellable: AnyCancellable?

	func bind(to download: Download) {
		guard self.download !== download else { return }
		self.download = download
		cancellable = download.progressEvents.mainThreadTicks { [weak self] in self?.refresh() }
		refresh()
	}

	var isPaused: Bool { phase == .paused }

	var showsByteCount: Bool {
		(phase == .downloading || phase == .paused) && totalBytes > 0
	}

	// @Published fires on willSet, so read once the tick lands.
	private func refresh() {
		guard let download else { return }
		phase = download.phase
		phaseProgress = download.phaseProgress
		bytesDownloaded = download.bytesDownloaded
		totalBytes = download.totalBytes
	}
}

@MainActor
final class DownloadsSummaryModel: ObservableObject {
	@Published private(set) var summary = DownloadProgressSummary([])
	@Published private(set) var bytesDownloaded: Int64 = 0
	@Published private(set) var bytesExpected: Int64 = 0

	private var downloads: [Download] = []
	private var cancellable: AnyCancellable?

	func bind(to downloads: [Download]) {
		let identities = downloads.map(ObjectIdentifier.init)
		guard identities != self.downloads.map(ObjectIdentifier.init) else { return }
		self.downloads = downloads

		cancellable = Publishers.MergeMany(downloads.map(\.progressEvents))
			.mainThreadTicks { [weak self] in self?.refresh() }

		refresh()
	}

	private func refresh() {
		let latest = DownloadProgressSummary(downloads)
		if summary != latest { summary = latest }

		let downloaded = downloads.reduce(Int64(0)) { $0 + $1.bytesDownloaded }
		if bytesDownloaded != downloaded { bytesDownloaded = downloaded }

		let expected = downloads.reduce(Int64(0)) { $0 + $1.totalBytes }
		if bytesExpected != expected { bytesExpected = expected }
	}
}

private extension Publisher where Output == Void, Failure == Never {
	// RunLoop.main stalls during scroll tracking.
	func mainThreadTicks(_ handler: @escaping () -> Void) -> AnyCancellable {
		throttle(for: .seconds(0.2), scheduler: DispatchQueue.main, latest: true)
			.sink { _ in handler() }
	}
}
