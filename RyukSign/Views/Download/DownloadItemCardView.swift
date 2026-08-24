//
//  DownloadItemCardView.swift
//  RyukSign
//
//  Extracted from DownloadOverlayView.swift for maintainability.
//

import SwiftUI
import Foundation

// MARK: - Download Card View
struct DownloadItemCardView: View {
    let download: Download
    @Binding var isOverlayPresented: Bool
    let cardBackgroundColor: Color
    @StateObject private var model = DownloadProgressModel()

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

                    HStack(spacing: 4) {
                        Image(systemName: model.phase.icon)
                            .font(.caption2)
                        Text(model.phase.title)
                            .font(.caption)
                    }
                    .foregroundColor(model.phase.tint)
                    .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    if shouldShowPauseButton {
                        Button {
                            if model.isPaused {
                                download.resume()
                            } else {
                                download.pause()
                            }
                        } label: {
                            Image(systemName: model.isPaused ? "play.fill" : "pause.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(model.isPaused ? .green : .orange)
                                .frame(width: 28, height: 28)
                                .background((model.isPaused ? Color.green : Color.orange).opacity(0.15))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if download.canCancel {
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

            DownloadPhaseBar(phase: model.phase, progress: model.phaseProgress)

            HStack {
                Text("\(Int(model.phaseProgress * 100))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()

                Spacer()

                if model.phase == .importing {
                    Text(.localized("Unpacking..."))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if model.showsByteCount {
                    HStack(spacing: 4) {
                        Text(model.bytesDownloaded.formattedByteCount)
                            .animation(.easeOut(duration: 0.2), value: model.bytesDownloaded)
                        Text("of")
                        Text(model.totalBytes.formattedByteCount)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                } else if model.phase == .downloading {
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
            if download.canCancel {
                Button(role: .destructive) {
                    DownloadManager.shared.cancelDownload(download)
                } label: {
                    Label(.localized("Cancel"), systemImage: "xmark")
                }
            }
        }
        .onAppear {
            model.bind(to: download)
        }
    }

    private var shouldShowPauseButton: Bool {
        (model.phase == .downloading || model.phase == .paused) && !download.onlyArchiving
    }
}
