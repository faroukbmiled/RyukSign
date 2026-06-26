//
//  MergedDownloadsView.swift
//  RyukSign
//
//  Extracted from DownloadHeaderView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine
import NimbleExtensions

struct MergedDownloadsView: View {
    let downloads: [Download]
    let combinedProgress: Double
    @State private var showDetails: Bool = false
    @State private var dragOffset: CGFloat = 0
    @State private var showCustomMenu: Bool = false
    @State private var anyPaused: Bool = false
    @State private var cancellables = Set<AnyCancellable>()

    private var headerText: String {
        if anyPaused {
            let pausedCount = downloads.filter { $0.isPaused && $0.progress > 0 && $0.progress < 1.0 }.count
            let activeCount = downloads.filter { $0.progress > 0 && $0.progress < 1.0 && !$0.isPaused }.count

            if pausedCount > 0 && activeCount == 0 {
                return "\(pausedCount) Paused"
            } else if pausedCount > 0 && activeCount > 0 {
                return "\(activeCount) Downloading, \(pausedCount) Paused"
            }
        }
        return "Downloading \(downloads.count) apps"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(headerText)
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(anyPaused ? .orange : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)

                    Text(appNamesPreview)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(showDetails ? nil : 2)
                }
                
                Spacer()

                ZStack(alignment: .topTrailing) {
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            showCustomMenu.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .padding(12)
                    }
                    .buttonStyle(.plain)
                    
                    if showCustomMenu {
                        VStack(alignment: .leading, spacing: 0) {
                            Button {
                                stopAllDownloads()
                            } label: {
                                HStack {
                                    Image(systemName: "stop.circle.fill")
                                        .foregroundColor(.red)
                                    Text(.localized("Stop All Downloads"))
                                        .foregroundColor(.red)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            
                            Divider()

                            Button {
                                toggleDetails()
                            } label: {
                                HStack {
                                    Image(systemName: showDetails ? "eye.slash" : "eye")
                                    Text(showDetails ? "Hide Details" : "Show Details")
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(uiColor: .systemBackground))
                                .shadow(color: .black.opacity(0.15), radius: 20, x: 0, y: 5)
                        )
                        .fixedSize(horizontal: true, vertical: false)
                        .transition(.scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
                        .offset(y: 45)
                        .zIndex(1)
                        // Swallow taps so the menu doesn't close itself
                        .onTapGesture {}
                    }
                }
            }

            if !showDetails {
                HStack {
                    Spacer()
                    Image(systemName: "chevron.compact.down")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(.localized("Swipe for details"))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                }
                .padding(.vertical, 2)
                .opacity(dragOffset > 5 ? Double(1 - (dragOffset / 50)) : 1)
            }
            
            if showDetails {
                VStack(spacing: 6) {
                    ForEach(downloads, id: \.id) { download in
                        DetailedMiniDownloadItemView(download: download)
                    }
                }
                .padding(.vertical, 4)
                .transition(.asymmetric(
                    insertion: .push(from: .top).combined(with: .opacity),
                    removal: .move(edge: .top).combined(with: .opacity)
                ))
                
                HStack {
                    Spacer()
                    Image(systemName: "chevron.compact.up")
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Text(.localized("Swipe to hide"))
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.5))
                    Spacer()
                }
                .padding(.top, 4)
            }
            
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .frame(height: 6)
                    .foregroundColor(Color(uiColor: .quaternarySystemFill))
                
                RoundedRectangle(cornerRadius: 4)
                    .frame(width: UIScreen.main.bounds.width * 0.85 * combinedProgress, height: 6)
                    .foregroundStyle(
                        LinearGradient(
                            colors: anyPaused ? [.orange.opacity(0.8), .orange] : [.accentColor.opacity(0.8), .accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .animation(.easeInOut(duration: 0.3), value: combinedProgress)
            }
            
            HStack {
                Text(anyPaused ? "Paused" : "\(Int(combinedProgress * 100))% overall")
                    .font(.caption.weight(.medium))
                    .foregroundColor(anyPaused ? .orange : .primary)

                Spacer()
                
                let totalBytesDownloaded = downloads.reduce(Int64(0)) { $0 + $1.bytesDownloaded }
                let totalBytesExpected = downloads.reduce(Int64(0)) { $0 + $1.totalBytes }
                
                if totalBytesExpected > 0 {
                    HStack(spacing: 4) {
                        Text(totalBytesDownloaded.formattedByteCount)
                        Text("of")
                        Text(totalBytesExpected.formattedByteCount)
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
        .offset(y: showDetails ? 0 : dragOffset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !showDetails && value.translation.height > 0 {
                        dragOffset = min(value.translation.height, 60)
                    } else if showDetails && value.translation.height < 0 {
                        dragOffset = max(value.translation.height, -60)
                    }
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if !showDetails && value.translation.height > 30 {
                            showDetails = true
                        } else if showDetails && value.translation.height < -30 {
                            showDetails = false
                        }
                        dragOffset = 0
                    }
                }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.8), value: showDetails)
        .onTapGesture {
            if showCustomMenu {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    showCustomMenu = false
                }
            }
        }
        .background(
            Group {
                if showCustomMenu {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showCustomMenu = false
                            }
                        }
                }
            }
        )
        .onAppear {
            setupPauseStateObserver()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            setupPauseStateObserver()
        }
    }

    private func setupPauseStateObserver() {
        cancellables.removeAll()

        for download in downloads {
            download.$isPaused
                .receive(on: DispatchQueue.main)
                .sink { _ in
                    updatePauseState()
                }
                .store(in: &cancellables)
        }

        updatePauseState()
    }

    private func updatePauseState() {
        let downloadableItems = downloads.filter {
            $0.progress > 0 && $0.progress < 1.0
        }

        if downloadableItems.isEmpty {
            anyPaused = false
        } else {
            anyPaused = downloadableItems.allSatisfy { $0.isPaused }
        }
    }

    private var appNamesPreview: String {
        let names = downloads.prefix(3).map { download in
            let name = download.fileName
            return name.count > 20 ? String(name.prefix(17)) + "..." : name
        }
        
        var preview = names.joined(separator: ", ")
        if downloads.count > 3 {
            preview += " +\(downloads.count - 3) more"
        }
        return preview
    }
    
    private func stopAllDownloads() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showCustomMenu = false
        }

        // Delay so the menu-close animation finishes first
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            downloads.forEach { download in
                DownloadManager.shared.cancelDownload(download)
            }
        }
    }
    
    private func toggleDetails() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            showCustomMenu = false
            showDetails.toggle()
        }
    }
}
