//
//  DownloadOverlayView.swift
//  RyukSign
//
//  Created by Ryuk on 13.10.2025.
//

import SwiftUI
import Foundation
import Combine

// MARK: - Sheet Content View
struct DownloadOverlaySheetContent: View {
    @ObservedObject var downloadManager: DownloadManager
    @Binding var isPresented: Bool
    @StateObject private var model = DownloadsSummaryModel()
    @State private var currentSpeed: Int64 = 0
    @State private var speedObserver: AnyCancellable?
    @AppStorage("Feather.downloadOverlayTheme") private var overlayTheme: String = "default"
    @Environment(\.colorScheme) private var colorScheme

    private var activeDownloads: [Download] {
        downloadManager.downloads.filter { download in
            download.isActive || download.progress > 0 || download.unpackageProgress > 0
        }
    }

    private var overlayBackgroundColor: Color {
        if overlayTheme == "greyish" {
            if colorScheme == .dark {
                return Color(uiColor: UIColor(red: 0.15, green: 0.15, blue: 0.15, alpha: 1.0))
            } else {
                return Color(uiColor: .systemBackground)
            }
        } else if overlayTheme == "darkGrey" {
            if colorScheme == .dark {
                return Color(uiColor: UIColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1.0))
            } else {
                return Color(uiColor: .systemBackground)
            }
        } else {
            // AMOLED black in dark mode
            if colorScheme == .dark {
                return Color(uiColor: UIColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0))
            } else {
                return Color(uiColor: .systemBackground)
            }
        }
    }

    private var cardBackgroundColor: Color {
        if colorScheme == .dark {
            return Color(uiColor: UIColor(red: 0.12, green: 0.12, blue: 0.12, alpha: 1.0))
        } else {
            return Color(uiColor: .secondarySystemBackground)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.secondary.opacity(0.5))
                .frame(width: 36, height: 5)
                .padding(.top, 8)
                .padding(.bottom, 6)

            VStack(spacing: 6) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(.localized("Downloads"))
                                .font(.title2.weight(.semibold))

                            if !activeDownloads.isEmpty {
                                Text("• \(activeDownloads.count) active")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        if !activeDownloads.isEmpty {
                            Button {
                                if isPaused {
                                    DownloadManager.shared.resumeAllDownloads()
                                } else {
                                    DownloadManager.shared.pauseAllDownloads()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                                        .font(.caption.weight(.semibold))
                                    Text(isPaused ? "Resume" : "Pause")
                                        .font(.caption.weight(.semibold))
                                        .fixedSize()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(isPaused ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                                .foregroundStyle(isPaused ? .green : .orange)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                        }

                        if !activeDownloads.isEmpty {
                            Button {
                                for download in activeDownloads {
                                    DownloadManager.shared.cancelDownload(download)
                                }
                                DispatchQueue.main.async {
                                    isPresented = false
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "xmark")
                                        .font(.caption.weight(.semibold))
                                    Text(.localized("Stop All"))
                                        .font(.caption.weight(.semibold))
                                        .fixedSize()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .fixedSize()
                        }

                        Button {
                            DispatchQueue.main.async {
                                isPresented = false
                            }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 28, height: 28)
                                .background(Color.secondary.opacity(0.1))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !activeDownloads.isEmpty {
                    Text(overlayStatusText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .monospacedDigit()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if !activeDownloads.isEmpty {
                    DownloadPhaseBar(phase: model.summary.phase, progress: model.summary.progress, height: 4)
                }
            }
            .padding(.horizontal)
            .padding(.top, 6)
            .padding(.bottom, 8)

            if activeDownloads.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "arrow.down.circle")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)

                    Text(.localized("No Active Downloads"))
                        .font(.title3.weight(.medium))
                        .foregroundColor(.primary)

                    Text(.localized("Your downloads will appear here"))
                        .font(.body)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(activeDownloads, id: \.id) { download in
                        DownloadItemCardView(
                            download: download,
                            isOverlayPresented: $isPresented,
                            cardBackgroundColor: cardBackgroundColor
                        )
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.8, anchor: .center).combined(with: .opacity),
                            removal: .scale(scale: 0.3, anchor: .trailing).combined(with: .opacity).combined(with: .move(edge: .trailing))
                        ))
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: activeDownloads.map { $0.id })
            }
        }
        .background(overlayBackgroundColor)
        .onAppear {
            model.bind(to: activeDownloads)
            speedObserver = downloadManager.$currentDownloadSpeed
                .receive(on: DispatchQueue.main)
                .sink { currentSpeed = $0 }
        }
        .onChange(of: activeDownloads.map { $0.id }) { _ in
            model.bind(to: activeDownloads)
        }
        .onChange(of: activeDownloads.count) { newCount in
            // Auto-dismiss once the last download is gone; re-check after the delay to avoid a dismiss race
            if newCount == 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    if activeDownloads.isEmpty {
                        isPresented = false
                    }
                }
            }
        }
    }

    private var isPaused: Bool { model.summary.pausedCount > 0 }

    private var overlayStatusText: String {
        let summary = model.summary
        let percent = "\(Int(summary.progress * 100))%"

        guard summary.phase == .downloading || summary.phase == .paused else {
            return "\(summary.title) • \(percent)"
        }
        return model.bytesExpected > 0
            ? "\(percent) • \(formatSpeed(currentSpeed)) • \(model.bytesExpected.formattedByteCount)"
            : "\(percent) • \(formatSpeed(currentSpeed))"
    }

    private func formatSpeed(_ bytesPerSecond: Int64) -> String {
        guard bytesPerSecond > 0 else {
            return "0 KB/s"
        }

        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: bytesPerSecond) + "/s"
    }
}
