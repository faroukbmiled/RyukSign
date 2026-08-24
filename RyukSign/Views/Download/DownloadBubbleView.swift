//
//  DownloadBubbleView.swift
//  RyukSign
//
//  Created by Ryuk on 13.10.2025.
//

import SwiftUI
import Foundation

struct DownloadBubbleOverlayContainer: View {
    @ObservedObject var downloadManager: DownloadManager
    @State private var showOverlay = false
    private var hasActiveDownloads: Bool {
        !downloadManager.downloads.filter { download in
            download.isActive || download.progress > 0 || download.unpackageProgress > 0
        }.isEmpty
    }

    var body: some View {
        ZStack {
            DownloadBubbleView(
                downloadManager: downloadManager,
                showOverlay: $showOverlay
            )
            .zIndex(1)
            .transition(.scale(scale: 0.1).combined(with: .opacity))

            if showOverlay {
                DownloadOverlaySheetWrapper(
                    downloadManager: downloadManager,
                    isPresented: $showOverlay
                )
            }
        }
        // Animate only on active-count change, not every child update
        .animation(.spring(response: 0.5, dampingFraction: 0.7), value: hasActiveDownloads)
    }
}

struct DownloadBubbleView: View {
    @ObservedObject var downloadManager: DownloadManager
    @Binding var showOverlay: Bool
    @StateObject private var model = DownloadsSummaryModel()
    @State private var dragAmount: CGPoint?

    private var activeDownloads: [Download] {
        downloadManager.downloads.filter { download in
            download.isActive || download.progress > 0 || download.unpackageProgress > 0
        }
    }

    var body: some View {
        if !activeDownloads.isEmpty {
            GeometryReader { geometry in
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        ZStack {
                                Circle()
                                    .fill(Color(uiColor: .systemBackground))
                                    .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)

                                DownloadPhaseRing(phase: model.summary.phase, progress: model.summary.progress, size: 44)

                                ZStack {
                                    if model.summary.phase == .paused {
                                        Image(systemName: "pause.fill")
                                            .font(.system(size: 14))
                                            .foregroundColor(.orange)
                                    } else {
                                        VStack(spacing: 0) {
                                            Text(verbatim: "\(Int(model.summary.progress * 100))")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundColor(.primary)
                                                .id(Int(model.summary.progress * 100))

                                            Image(systemName: model.summary.phase.icon)
                                                .font(.system(size: 8))
                                                .foregroundColor(model.summary.phase.tint)
                                        }
                                    }
                                }
                                .animation(nil, value: model.summary.progress)

                                if activeDownloads.count > 1 {
                                    Text("\(activeDownloads.count)")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 2)
                                        .background(Color.accentColor)
                                        .clipShape(Capsule())
                                        .offset(x: 16, y: -16)
                                }
                            }
                            .frame(width: 56, height: 56)
                        .contentShape(Circle())
                        .onTapGesture {
                            showOverlay = true
                        }
                        .frame(width: 56, height: 56)
                        .padding(0)
                        .position(dragAmount ?? CGPoint(x: geometry.size.width - 40, y: geometry.size.height - 100))
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    self.dragAmount = value.location
                                }
                                .onEnded { value in
                                    var currentPosition = value.location
                                    let safeArea = geometry.safeAreaInsets

                                    let leftEdgePadding: CGFloat = 28
                                    let rightEdgePadding: CGFloat = 46
                                    let topPadding: CGFloat = 30 + safeArea.top
                                    let bottomPadding: CGFloat = 50 + safeArea.bottom

                                    if currentPosition.x > (geometry.size.width / 2) {
                                        currentPosition.x = geometry.size.width - rightEdgePadding
                                    } else {
                                        currentPosition.x = leftEdgePadding
                                    }

                                    currentPosition.y = min(max(currentPosition.y, topPadding), geometry.size.height - bottomPadding)

                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                                        dragAmount = currentPosition
                                    }

                                    saveBubblePosition(currentPosition)
                                }
                        )
                    }
                }
                .padding(0)
                .onAppear {
                    loadBubblePosition(in: geometry)
                }
            }
            .onAppear {
                model.bind(to: activeDownloads)
            }
            .onChange(of: activeDownloads.map { $0.id }) { _ in
                model.bind(to: activeDownloads)
            }
        }
    }
    
    private func saveBubblePosition(_ position: CGPoint) {
        UserDefaults.standard.set(position.x, forKey: "Feather.downloadBubblePositionX")
        UserDefaults.standard.set(position.y, forKey: "Feather.downloadBubblePositionY")
    }

    private func loadBubblePosition(in geometry: GeometryProxy) {
        let savedX = UserDefaults.standard.double(forKey: "Feather.downloadBubblePositionX")
        let savedY = UserDefaults.standard.double(forKey: "Feather.downloadBubblePositionY")

        if savedX > 0 && savedY > 0 {
            dragAmount = CGPoint(x: CGFloat(savedX), y: CGFloat(savedY))
        } else {
            dragAmount = CGPoint(x: geometry.size.width - 40, y: geometry.size.height - 100)
        }
    }
}
