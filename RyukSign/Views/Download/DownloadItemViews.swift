//
//  DownloadItemViews.swift
//  RyukSign
//
//  Extracted from DownloadHeaderView.swift for maintainability.
//

import SwiftUI
import Foundation
import NimbleExtensions

struct DetailedMiniDownloadItemView: View {
    let download: Download
    @StateObject private var model = DownloadProgressModel()
    
    var body: some View {
        HStack(spacing: 8) {
            DownloadPhaseRing(phase: model.phase, progress: model.phaseProgress, size: 20, lineWidth: 2)

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

            Text(verbatim: "\(model.phase.title) \(Int(model.phaseProgress * 100))%")
                .font(.caption2.monospacedDigit())
                .foregroundColor(.secondary)
                .lineLimit(1)

            if download.canCancel {
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
            model.bind(to: download)
        }
    }
}

struct DownloadItemView: View {
    let download: Download
    @StateObject private var model = DownloadProgressModel()

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
                    
                    HStack(spacing: 4) {
                        Image(systemName: model.phase.icon)
                            .font(.caption2)
                        Text(model.phase.title)
                            .font(.caption)
                    }
                    .foregroundColor(model.phase.tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                }

                Spacer()

                if download.canCancel {
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
            
            DownloadPhaseBar(phase: model.phase, progress: model.phaseProgress)

            HStack {
                Text("\(Int(model.phaseProgress * 100))%")
                    .font(.caption.weight(.medium))
                    .monospacedDigit()

                Spacer()

                if let detail = model.phase.processingDetail {
                    Text(detail)
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
        .padding(.vertical, 4)
        .onAppear {
            model.bind(to: download)
        }
    }
}
