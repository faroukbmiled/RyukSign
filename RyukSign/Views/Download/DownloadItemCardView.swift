//
//  DownloadItemCardView.swift
//  RyukSign
//
//  Extracted from DownloadOverlayView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Download Card View
struct DownloadItemCardView: View {
    let download: Download
    @Binding var isOverlayPresented: Bool
    let cardBackgroundColor: Color
    @State private var progress: Double = 0
    @State private var bytesDownloaded: Int64 = 0
    @State private var totalBytes: Int64 = 0
    @State private var unpackageProgress: Double = 0
    @State private var isActive: Bool = false
    @State private var isPaused: Bool = false
    @State private var cancellables = Set<AnyCancellable>()

    private let updateThrottle: TimeInterval = 0.3

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if !download.isManual {
                        Button(action: {
                            DownloadNavigationHelper.handleAppNameTap(for: download)
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                isOverlayPresented = false
                            }
                        }) {
                            Text(download.fileName)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(download.fileName)
                            .font(.headline.weight(.semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }

                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    if shouldShowPauseButton {
                        Button {
                            if isPaused {
                                download.resume()
                            } else {
                                download.pause()
                            }
                        } label: {
                            Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isPaused ? .green : .orange)
                                .frame(width: 28, height: 28)
                                .background((isPaused ? Color.green : Color.orange).opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if shouldShowCancelButton {
                        Button {
                            DownloadManager.shared.cancelDownload(download)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.red)
                                .frame(width: 28, height: 28)
                                .background(Color.red.opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .frame(height: 6)
                        .foregroundColor(Color(uiColor: .quaternarySystemFill))

                    RoundedRectangle(cornerRadius: 4)
                        .frame(width: geometry.size.width * overallProgress, height: 6)
                        .foregroundStyle(
                            LinearGradient(
                                colors: isPaused ? [.orange.opacity(0.8), .orange] : [.accentColor.opacity(0.8), .accentColor],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .animation(.easeOut(duration: 0.3), value: overallProgress)
                }
            }
            .frame(height: 6)

            HStack {
                Text("\(Int(overallProgress * 100))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()

                Spacer()

                if totalBytes > 0 {
                    HStack(spacing: 4) {
                        Text(bytesDownloaded.formattedByteCount)
                            .animation(.easeOut(duration: 0.2), value: bytesDownloaded)
                        Text("of")
                        Text(totalBytes.formattedByteCount)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                } else if unpackageProgress > 0 {
                    Text(.localized("Processing..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if isActive && progress == 0 {
                    Text(.localized("Starting..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(cardBackgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            if shouldShowCancelButton {
                Button(role: .destructive) {
                    DownloadManager.shared.cancelDownload(download)
                } label: {
                    Label(.localized("Cancel"), systemImage: "xmark")
                }
            }
        }
        .onAppear {
            setupThrottledObservers()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
    }

    private func setupThrottledObservers() {
        progress = download.progress.rounded(toPlaces: 2)
        bytesDownloaded = download.bytesDownloaded
        totalBytes = download.totalBytes
        unpackageProgress = download.unpackageProgress.rounded(toPlaces: 2)
        isActive = download.isActive
        isPaused = download.isPaused

        download.$progress
            .throttle(for: .seconds(updateThrottle), scheduler: RunLoop.main, latest: true)
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { self.progress = $0.rounded(toPlaces: 2) }
            .store(in: &cancellables)

        download.$bytesDownloaded
            .throttle(for: .seconds(updateThrottle), scheduler: RunLoop.main, latest: true)
            .sink { self.bytesDownloaded = $0 }
            .store(in: &cancellables)

        download.$totalBytes
            .removeDuplicates()
            .sink { self.totalBytes = $0 }
            .store(in: &cancellables)

        download.$unpackageProgress
            .throttle(for: .seconds(updateThrottle), scheduler: RunLoop.main, latest: true)
            .removeDuplicates { abs($0 - $1) < 0.01 }
            .sink { self.unpackageProgress = $0.rounded(toPlaces: 2) }
            .store(in: &cancellables)

        download.$isActive
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { self.isActive = $0 }
            .store(in: &cancellables)

        download.$isPaused
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { self.isPaused = $0 }
            .store(in: &cancellables)
    }

    private var overallProgress: Double {
        download.onlyArchiving
        ? unpackageProgress
        : (0.3 * unpackageProgress) + (0.7 * progress)
    }

    private var statusText: String {
        if overallProgress >= 1.0 {
            return "Completed"
        } else if unpackageProgress > 0 && progress >= 1.0 {
            return "Installing..."
        } else if isPaused {
            return "Paused"
        } else if progress > 0 {
            return "Downloading..."
        } else if isActive {
            return "Starting..."
        } else {
            return "Preparing..."
        }
    }

    private var shouldShowCancelButton: Bool {
        let isImportingOrArchiving = (unpackageProgress > 0 && progress >= 1.0) ||
                                    (download.onlyArchiving && unpackageProgress > 0)
        return (isActive || overallProgress < 1.0) && !isImportingOrArchiving
    }

    private var shouldShowPauseButton: Bool {
        return progress > 0 && progress < 1.0 && !download.onlyArchiving
    }
}
