//
//  DownloadItemViews.swift
//  RyukSign
//
//  Extracted from DownloadHeaderView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine
import NimbleExtensions

struct DetailedMiniDownloadItemView: View {
    let download: Download
    @State private var progress: Double = 0
    @State private var unpackageProgress: Double = 0
    @State private var isActive: Bool = false
    @State private var cancellables = Set<AnyCancellable>()
    
    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .quaternarySystemFill), lineWidth: 2)
                    .frame(width: 20, height: 20)
                
                Circle()
                    .trim(from: 0, to: overallProgress)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.3), value: overallProgress)
            }
            
            if !download.isManual {
                Button(action: {
                    DownloadNavigationHelper.handleAppNameTap(for: download)
                }) {
                    Text(download.fileName)
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
            } else {
                Text(download.fileName)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("\(Int(overallProgress * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
            
            if shouldShowCancelButton {
                Button {
                    DownloadManager.shared.cancelDownload(download)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Color(uiColor: .quaternarySystemFill).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onAppear {
            setupThrottledObservers()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
    }
    
    private func setupThrottledObservers() {
        download.$progress
            .throttle(for: .seconds(0.3), scheduler: RunLoop.main, latest: true)
            .removeDuplicates { abs($0 - $1) < 0.02 }
            .sink { self.progress = $0.rounded(toPlaces: 2) }
            .store(in: &cancellables)
        
        download.$unpackageProgress
            .throttle(for: .seconds(0.3), scheduler: RunLoop.main, latest: true)
            .removeDuplicates { abs($0 - $1) < 0.02 }
            .sink { self.unpackageProgress = $0.rounded(toPlaces: 2) }
            .store(in: &cancellables)
        
        download.$isActive
            .removeDuplicates()
            .sink { self.isActive = $0 }
            .store(in: &cancellables)
    }
    
    private var overallProgress: Double {
        download.onlyArchiving
        ? unpackageProgress
        : (0.3 * unpackageProgress) + (0.7 * progress)
    }
    
    private var shouldShowCancelButton: Bool {
        let isImportingOrArchiving = (unpackageProgress > 0 && progress >= 1.0) || 
                                    (download.onlyArchiving && unpackageProgress > 0)
        return (isActive || overallProgress < 1.0) && !isImportingOrArchiving
    }
}

struct DownloadItemView: View {
    let download: Download
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
                VStack(alignment: .leading, spacing: 2) {
                    if !download.isManual {
                        Button(action: {
                            DownloadNavigationHelper.handleAppNameTap(for: download)
                        }) {
                            Text(download.fileName)
                                .font(.callout.weight(.semibold))
                                .lineLimit(1)
                                .foregroundColor(.accentColor)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(download.fileName)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                    
                    Text(statusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                
                Spacer()
                
                if shouldShowCancelButton {
                    Button {
                        DownloadManager.shared.cancelDownload(download)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
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
        .padding(.vertical, 4)
        .onAppear {
            setupThrottledObservers()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
    }
    
    private func setupThrottledObservers() {
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
}
