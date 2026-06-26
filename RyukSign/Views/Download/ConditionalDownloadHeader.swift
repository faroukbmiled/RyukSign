//
//  ConditionalDownloadHeader.swift
//  RyukSign
//
//  Extracted from DownloadHeaderView.swift for maintainability.
//

import SwiftUI
import Foundation
import Combine
import NimbleExtensions

struct ConditionalDownloadHeaderView: View {
    let downloads: [Download]
    @State private var viewState: HeaderState = .collapsed
    
    static var sessionState: HeaderState? = nil
    
    enum HeaderState: String, CaseIterable {
        case expanded
        case collapsed
        case minimized
    }
    
    init(downloads: [Download]) {
        self.downloads = downloads
        
        if let savedSessionState = Self.sessionState {
            _viewState = State(initialValue: savedSessionState)
        } else {
            let savedStartState = UserDefaults.standard.string(forKey: "Feather.backgroundDownloadHeaderStartState") ?? "collapsed"
            switch savedStartState {
            case "minimized":
                _viewState = State(initialValue: .minimized)
            case "expanded":
                _viewState = State(initialValue: .expanded)
            default:
                _viewState = State(initialValue: .collapsed)
            }
        }
    }
    
    var body: some View {
        if !downloads.isEmpty {
            VStack(spacing: 0) {
                switch viewState {
                case .minimized:
                    MinimizedConditionalHeader(
                        downloads: downloads,
                        viewState: $viewState
                    )
                    
                case .collapsed:
                    CollapsedConditionalHeader(
                        downloads: downloads,
                        viewState: $viewState
                    )
                    
                case .expanded:
                    ExpandedConditionalHeader(
                        downloads: downloads,
                        viewState: $viewState
                    )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewState)
            .onChange(of: viewState) { newValue in
                Self.sessionState = newValue
            }
        }
    }
}

struct MinimizedConditionalHeader: View {
    let downloads: [Download]
    @Binding var viewState: ConditionalDownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @State private var calculatedProgress: Double = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var anyPaused: Bool = false
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: anyPaused ? "pause.circle.fill" : "arrow.down.circle.fill")
                .font(.caption)
                .foregroundColor(anyPaused ? .orange : .accentColor)

            Text("\(downloads.count)")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(anyPaused ? Color.orange : Color.accentColor)
                .clipShape(Capsule())

            Text(anyPaused ? "Paused" : "\(Int(calculatedProgress * 100))%")
                .font(.caption.weight(.medium))
                .foregroundColor(anyPaused ? .orange : .primary)
                .contentTransition(.numericText())
            
            Spacer()
            
            Button {
                viewState = .collapsed
                ConditionalDownloadHeaderView.sessionState = .collapsed
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(uiColor: .tertiarySystemBackground))
        .clipShape(Capsule())
        .padding(.horizontal)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if value.translation.height > 0 {
                        dragOffset = min(value.translation.height, 60)
                    }
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if value.translation.height > 15 {
                            viewState = .collapsed
                            ConditionalDownloadHeaderView.sessionState = .collapsed
                        }
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            setupProgressObservers()
            setupPauseStateObserver()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            setupProgressObservers()
            setupPauseStateObserver()
        }
    }

    private func setupProgressObservers() {
        for download in downloads {
            Publishers.CombineLatest(
                download.$progress,
                download.$unpackageProgress
            )
            .sink { _, _ in
                updateCalculatedProgress()
            }
            .store(in: &cancellables)
        }

        updateCalculatedProgress()
    }

    private func updateCalculatedProgress() {
        guard !downloads.isEmpty else {
            calculatedProgress = 0
            return
        }

        let totalProgress = downloads.reduce(0.0) { total, download in
            return total + download.overallProgress
        }

        calculatedProgress = totalProgress / Double(downloads.count)
    }

    private func setupPauseStateObserver() {
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
}

struct CollapsedConditionalHeader: View {
    let downloads: [Download]
    @Binding var viewState: ConditionalDownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @State private var calculatedProgress: Double = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var anyPaused: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .quaternarySystemFill), lineWidth: 3)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0, to: calculatedProgress)
                    .stroke(
                        LinearGradient(
                            colors: anyPaused ? [.orange.opacity(0.8), .orange] : [.accentColor.opacity(0.8), .accentColor],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        style: StrokeStyle(lineWidth: 3, lineCap: .round)
                    )
                    .frame(width: 28, height: 28)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.3), value: calculatedProgress)

                if anyPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                } else {
                    Text("\(Int(calculatedProgress * 100))")
                        .font(.system(size: 10, weight: .semibold))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                if downloads.count == 1 {
                    Button(action: {
                        DownloadNavigationHelper.handleAppNameTap(for: downloads[0])
                    }) {
                        Text(downloads[0].fileName)
                            .font(.caption.weight(.medium))
                            .lineLimit(1)
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text(verbatim: .localized("Background: %lld items", arguments: downloads.count))
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                }
                
                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            Spacer()

            HStack(spacing: 8) {
                Button {
                    viewState = .minimized
                    ConditionalDownloadHeaderView.sessionState = .minimized
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                
                Button {
                    viewState = .expanded
                    ConditionalDownloadHeaderView.sessionState = .expanded
                } label: {
                    Image(systemName: "chevron.down.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    dragOffset = max(-100, min(100, value.translation.height))
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if value.translation.height < -15 {
                            viewState = .minimized
                            ConditionalDownloadHeaderView.sessionState = .minimized
                        } else if value.translation.height > 15 {
                            viewState = .expanded
                            ConditionalDownloadHeaderView.sessionState = .expanded
                        }
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            setupProgressObservers()
            setupPauseStateObserver()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            setupProgressObservers()
            setupPauseStateObserver()
        }
    }

    private func setupProgressObservers() {
        for download in downloads {
            Publishers.CombineLatest(
                download.$progress,
                download.$unpackageProgress
            )
            .sink { _, _ in
                updateCalculatedProgress()
            }
            .store(in: &cancellables)
        }

        updateCalculatedProgress()
    }

    private func updateCalculatedProgress() {
        guard !downloads.isEmpty else {
            calculatedProgress = 0
            return
        }

        let totalProgress = downloads.reduce(0.0) { total, download in
            return total + download.overallProgress
        }

        calculatedProgress = totalProgress / Double(downloads.count)
    }

    private func setupPauseStateObserver() {
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

    private var statusText: String {
        let activeCount = downloads.filter { $0.progress > 0 && $0.progress < 1.0 && !$0.isPaused }.count
        let pausedCount = downloads.filter { $0.isPaused && $0.progress > 0 && $0.progress < 1.0 }.count
        let processingCount = downloads.filter { $0.unpackageProgress > 0 && $0.unpackageProgress < 1.0 && $0.progress >= 1.0 }.count

        if pausedCount > 0 && activeCount == 0 && processingCount == 0 {
            return "\(pausedCount) paused"
        } else if pausedCount > 0 && activeCount > 0 {
            return "\(activeCount) downloading, \(pausedCount) paused"
        } else if activeCount > 0 && processingCount > 0 {
            return "\(activeCount) downloading, \(processingCount) processing"
        } else if activeCount > 0 {
            return "\(activeCount) downloading"
        } else if processingCount > 0 {
            return "\(processingCount) processing"
        } else {
            return "Preparing..."
        }
    }
}

struct ExpandedConditionalHeader: View {
    let downloads: [Download]
    @Binding var viewState: ConditionalDownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @State private var calculatedProgress: Double = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var anyPaused: Bool = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(.localized("Background Downloads"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    if anyPaused {
                        DownloadManager.shared.resumeAllDownloads()
                    } else {
                        DownloadManager.shared.pauseAllDownloads()
                    }
                } label: {
                    Image(systemName: anyPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(anyPaused ? .green : .orange)
                }
                .buttonStyle(.borderless)

                Button {
                    viewState = .collapsed
                    ConditionalDownloadHeaderView.sessionState = .collapsed
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
            .padding(.bottom, 4)
            .padding(.horizontal)
            
            if downloads.count == 1, let firstDownload = downloads.first {
                DownloadItemView(download: firstDownload)
                    .padding(.horizontal)
            } else if downloads.count > 1 {
                MergedDownloadsView(downloads: downloads, combinedProgress: calculatedProgress)
                    .padding(.horizontal)
            }
        }
        .padding(.vertical, 12)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .contentShape(Rectangle())
        .offset(y: dragOffset)
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if value.translation.height < 0 {
                        dragOffset = max(value.translation.height, -60)
                    }
                }
                .onEnded { value in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        if value.translation.height < -15 {
                            viewState = .collapsed
                            ConditionalDownloadHeaderView.sessionState = .collapsed
                        }
                        dragOffset = 0
                    }
                }
        )
        .onAppear {
            setupProgressObservers()
            setupPauseStateObserver()
        }
        .onDisappear {
            cancellables.forEach { $0.cancel() }
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            setupProgressObservers()
            setupPauseStateObserver()
        }
    }

    private func setupProgressObservers() {
        // Don't clear cancellables — progress and pause are two observer sets
        for download in downloads {
            Publishers.CombineLatest(
                download.$progress,
                download.$unpackageProgress
            )
            .sink { _, _ in
                updateCalculatedProgress()
            }
            .store(in: &cancellables)
        }

        updateCalculatedProgress()
    }

    private func updateCalculatedProgress() {
        guard !downloads.isEmpty else {
            calculatedProgress = 0
            return
        }

        let totalProgress = downloads.reduce(0.0) { total, download in
            return total + download.overallProgress
        }

        calculatedProgress = totalProgress / Double(downloads.count)
    }

    private func setupPauseStateObserver() {
        for download in downloads {
            download.$isPaused
                .receive(on: DispatchQueue.main)
                .sink {_ in
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
}
