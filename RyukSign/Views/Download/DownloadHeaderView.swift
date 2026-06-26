//
//  DownloadHeaderView.swift
//  RyukSign
//
//  Created by samara on 16.05.2025.
//
import SwiftUI
import Foundation
import Combine
import NimbleExtensions

struct DownloadHeaderView: View {
    @ObservedObject var downloadManager: DownloadManager
    @State private var viewState: HeaderState = .expanded
    @AppStorage("Feather.downloadHeaderState") private var savedState: HeaderState = .expanded
    
    enum HeaderState: String, CaseIterable {
        case expanded
        case collapsed
        case minimized
    }
    
    private var activeDownloads: [Download] {
        downloadManager.downloads.filter { download in
            download.isActive || download.progress > 0 || download.unpackageProgress > 0
        }
    }
    
    init(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
        _viewState = State(initialValue: savedState)
    }
    
    var body: some View {
        if !activeDownloads.isEmpty {
            VStack(spacing: 0) {
                switch viewState {
                case .minimized:
                    MinimizedDownloadHeader(
                        downloads: activeDownloads,
                        viewState: $viewState,
                        savedState: $savedState
                    )
                    
                case .collapsed:
                    CollapsedDownloadHeader(
                        downloads: activeDownloads,
                        viewState: $viewState,
                        savedState: $savedState
                    )
                    
                case .expanded:
                    ExpandedDownloadHeader(
                        downloads: activeDownloads,
                        viewState: $viewState,
                        savedState: $savedState
                    )
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: viewState)
        }
    }
}

struct MinimizedDownloadHeader: View {
    let downloads: [Download]
    @Binding var viewState: DownloadHeaderView.HeaderState
    @Binding var savedState: DownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @State private var combinedProgress: Double = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var anyPaused: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .quaternarySystemFill), lineWidth: 2)
                    .frame(width: 20, height: 20)

                Circle()
                    .trim(from: 0, to: combinedProgress)
                    .stroke(anyPaused ? Color.orange : Color.accentColor, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 20, height: 20)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 0.2), value: combinedProgress)
            }

            Text("\(downloads.count)")
                .font(.caption2.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.accentColor)
                .clipShape(Capsule())

            Text("\(Int(combinedProgress * 100))%")
                .font(.caption.weight(.medium))

            Spacer()

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    viewState = .collapsed
                    savedState = .collapsed
                }
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if value.translation.height > 15 {
                            viewState = .collapsed
                            savedState = .collapsed
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
                updateCombinedProgress()
            }
            .store(in: &cancellables)
        }

        updateCombinedProgress()
    }

    private func updateCombinedProgress() {
        guard !downloads.isEmpty else {
            combinedProgress = 0
            return
        }

        let totalProgress = downloads.reduce(0.0) { total, download in
            return total + download.overallProgress
        }

        combinedProgress = totalProgress / Double(downloads.count)
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

struct CollapsedDownloadHeader: View {
    let downloads: [Download]
    @Binding var viewState: DownloadHeaderView.HeaderState
    @Binding var savedState: DownloadHeaderView.HeaderState
    @State private var dragOffset: CGFloat = 0
    @State private var combinedProgress: Double = 0
    @State private var cancellables = Set<AnyCancellable>()
    @State private var anyPaused: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(Color(uiColor: .quaternarySystemFill), lineWidth: 3)
                    .frame(width: 28, height: 28)

                Circle()
                    .trim(from: 0, to: combinedProgress)
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
                    .animation(.linear(duration: 0.2), value: combinedProgress)

                if anyPaused {
                    Image(systemName: "pause.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                } else {
                    Text("\(Int(combinedProgress * 100))")
                        .font(.system(size: 10, weight: .semibold))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(downloads.count == 1 ? downloads[0].fileName : "Downloading \(downloads.count) items")
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Text(statusText)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            
            Spacer()

            HStack(spacing: 8) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewState = .minimized
                        savedState = .minimized
                    }
                } label: {
                    Image(systemName: "chevron.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        viewState = .expanded
                        savedState = .expanded
                    }
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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        if value.translation.height < -15 {
                            viewState = .minimized
                            savedState = .minimized
                        } else if value.translation.height > 15 {
                            viewState = .expanded
                            savedState = .expanded
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
                updateCombinedProgress()
            }
            .store(in: &cancellables)
        }

        updateCombinedProgress()
    }

    private func updateCombinedProgress() {
        guard !downloads.isEmpty else {
            combinedProgress = 0
            return
        }

        let totalProgress = downloads.reduce(0.0) { total, download in
            return total + download.overallProgress
        }

        combinedProgress = totalProgress / Double(downloads.count)
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
        } else if processingCount > 0 && activeCount == 0 {
            return "\(processingCount) processing"
        } else if activeCount > 0 && processingCount > 0 {
            return "\(activeCount) downloading, \(processingCount) processing"
        } else if activeCount > 0 {
            return "\(activeCount) downloading"
        } else {
            return "Preparing..."
        }
    }
}

struct ExpandedDownloadHeader: View {
	let downloads: [Download]
	@Binding var viewState: DownloadHeaderView.HeaderState
	@Binding var savedState: DownloadHeaderView.HeaderState
	@State private var showAllDownloads: Bool = false
	@State private var dragOffset: CGFloat = 0
	@State private var cancellables = Set<AnyCancellable>()
	@State private var anyPaused: Bool = false

	var body: some View {
		VStack(spacing: 0) {
			VStack(spacing: 12) {
				HStack {
					Text(downloads.count == 1 ? "Download" : "Downloads (\(downloads.count))")
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
						savedState = .collapsed
					} label: {
						Image(systemName: "chevron.up.circle.fill")
							.font(.title3)
							.foregroundStyle(.secondary)
					}
					.buttonStyle(.borderless)
				}
				.padding(.bottom, 4)
				.onAppear {
					setupPauseStateObserver()
				}
				.onDisappear {
					cancellables.forEach { $0.cancel() }
				}
				
				if downloads.count == 1 {
					DownloadItemView(download: downloads[0])
				} else if downloads.count > 1 {
					DownloadItemView(download: downloads[0])

					if !showAllDownloads {
						Button {
							withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
								showAllDownloads = true
							}
						} label: {
							HStack {
								Image(systemName: "chevron.down")
									.font(.caption2)
								Text(verbatim: .localized("Show %lld more", arguments: downloads.count - 1))
									.font(.caption)
								Spacer()
								
								let otherProgress = downloads.dropFirst().reduce(0.0) { $0 + $1.overallProgress } / Double(downloads.count - 1)
								Text("\(Int(otherProgress * 100))% avg")
									.font(.caption2)
									.foregroundColor(.secondary)
							}
							.foregroundColor(.accentColor)
							.padding(.vertical, 6)
							.padding(.horizontal, 8)
							.background(Color.accentColor.opacity(0.1))
							.clipShape(RoundedRectangle(cornerRadius: 6))
						}
						.buttonStyle(.plain)
					} else {
						VStack(spacing: 8) {
							ForEach(downloads.dropFirst(), id: \.id) { download in
								DownloadItemView(download: download)
									.transition(.asymmetric(
										insertion: .push(from: .top).combined(with: .opacity),
										removal: .push(from: .bottom).combined(with: .opacity)
									))
							}
							
							Button {
								withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
									showAllDownloads = false
								}
							} label: {
								HStack {
									Image(systemName: "chevron.up")
										.font(.caption2)
									Text(.localized("Show less"))
										.font(.caption)
									Spacer()
								}
								.foregroundColor(.secondary)
								.padding(.vertical, 4)
							}
							.buttonStyle(.plain)
						}
					}
				}
			}
			.padding(.horizontal)
			.padding(.vertical, 12)
			.background(Color(uiColor: .secondarySystemBackground))
			.clipShape(RoundedRectangle(cornerRadius: 12))
			.padding(.horizontal)
			
			if downloads.count > 1 && !showAllDownloads {
				let totalProgress = downloads.reduce(0.0) { $0 + $1.overallProgress }
				let averageProgress = totalProgress / Double(downloads.count)
				
				ProgressView(value: averageProgress)
					.progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
					.frame(height: 2)
					.padding(.top, 8)
					.padding(.horizontal)
			}
		}
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
                            savedState = .collapsed
                        }
                        dragOffset = 0
                    }
                }
        )
		.animation(.spring(response: 0.3, dampingFraction: 0.8), value: showAllDownloads)
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
