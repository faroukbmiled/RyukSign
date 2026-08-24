//
//  ConditionalDownloadHeader.swift
//  RyukSign
//
//  Extracted from DownloadHeaderView.swift for maintainability.
//

import SwiftUI
import Foundation
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
    @StateObject private var model = DownloadsSummaryModel()
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: model.summary.phase.icon)
                .font(.caption)
                .foregroundColor(model.summary.phase.tint)

            Text("\(downloads.count)")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(model.summary.phase.tint)
                .clipShape(Capsule())

            Text(verbatim: model.summary.phase == .paused ? .localized("Paused") : "\(Int(model.summary.progress * 100))%")
                .font(.caption.weight(.medium))
                .foregroundColor(model.summary.phase == .paused ? .orange : .primary)
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
            model.bind(to: downloads)
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            model.bind(to: downloads)
        }
    }

}

struct CollapsedConditionalHeader: View {
    let downloads: [Download]
    @Binding var viewState: ConditionalDownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @StateObject private var model = DownloadsSummaryModel()

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                DownloadPhaseRing(phase: model.summary.phase, progress: model.summary.progress)

                if model.summary.phase == .paused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                } else {
                    Text(verbatim: "\(Int(model.summary.progress * 100))")
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
                
                Text(model.summary.detail)
                    .font(.caption2)
                    .foregroundColor(model.summary.phase.tint)
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
            model.bind(to: downloads)
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            model.bind(to: downloads)
        }
    }


}

struct ExpandedConditionalHeader: View {
    let downloads: [Download]
    @Binding var viewState: ConditionalDownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @StateObject private var model = DownloadsSummaryModel()

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(.localized("Background Downloads"))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    if isPaused {
                        DownloadManager.shared.resumeAllDownloads()
                    } else {
                        DownloadManager.shared.pauseAllDownloads()
                    }
                } label: {
                    Image(systemName: isPaused ? "play.circle.fill" : "pause.circle.fill")
                        .font(.title3)
                        .foregroundStyle(isPaused ? .green : .orange)
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
                MergedDownloadsView(downloads: downloads, summary: model.summary)
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
            model.bind(to: downloads)
        }
        .onChange(of: downloads.map { $0.id }) { _ in
            model.bind(to: downloads)
        }
    }

    private var isPaused: Bool { model.summary.phase == .paused }
}
