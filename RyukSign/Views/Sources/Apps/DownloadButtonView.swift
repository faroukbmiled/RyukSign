//
//  DownloadButtonView.swift
//  RyukSign
//
//  Created by samsam on 7/25/25.
//
import SwiftUI
import Combine
import AltSourceKit
import NimbleViews
import NimbleExtensions
import CoreData

// MARK: - Tab Selection Observer
class TabSelectionObserver: ObservableObject {
	static let shared = TabSelectionObserver()
	@Published var selectedTab: TabEnum = TabBarPreferences.shared.resolvedLaunchTab
	@Published var highlightedAppUUID: String?
	@Published var sourcesRetapped: Bool = false
	
	private var highlightTimer: Timer?
	
	func navigateToLibraryWithHighlight(uuid: String) {
		highlightedAppUUID = uuid
		DispatchQueue.main.async {
			self.selectedTab = .library
		}
		
		highlightTimer?.invalidate()
		highlightTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
			DispatchQueue.main.async {
				withAnimation(.easeOut(duration: 0.3)) {
					self.highlightedAppUUID = nil
				}
			}
		}
	}
}

struct DownloadButtonView: View {
	let app: ASRepository.App
	@ObservedObject private var downloadManager = DownloadManager.shared
	@ObservedObject private var _updateChecker = AppUpdateChecker.shared

	@State private var installedApp: InstalledAppInfo? = nil
	@State private var isCheckingInstalled = true
	@State private var hasAppeared = false

	private let tabSelection = TabSelectionObserver.shared
	
	@FetchRequest(
		entity: Signed.entity(),
		sortDescriptors: []
	) private var signedApps: FetchedResults<Signed>
	
	@FetchRequest(
		entity: Imported.entity(),
		sortDescriptors: []
	) private var importedApps: FetchedResults<Imported>
	
	struct InstalledAppInfo {
		let uuid: String
		let name: String
		let version: String?
		let type: AppType
		let sourceApp: ASRepository.App

		enum AppType {
			case signed
			case imported
		}

		var isDowngrade: Bool {
			guard let version, let sourceVersion = sourceApp.currentVersion else { return false }
			return AppUpdateChecker.isNewerVersion(version, than: sourceVersion)
		}
	}

	private var _hasUpdate: Bool {
		_updateChecker.updates.contains { update in
			update.candidates.contains { $0.app.currentUniqueId == app.currentUniqueId }
		}
	}

	var body: some View {
		ZStack {
			if let currentDownload = downloadManager.getDownload(by: app.currentUniqueId) {
				DownloadProgressButton(download: currentDownload)
					.transition(.scale.combined(with: .opacity))
			} else if let installedApp = installedApp {
				HStack(spacing: 8) {
					if _hasUpdate {
						UpdateCapsuleButton { downloadManager.startDownload(for: app) }
							.transition(.scale.combined(with: .opacity))
					} else if installedApp.isDowngrade {
						Button {
							NBHaptic.tap()
							downloadManager.startDownload(for: app)
						} label: {
							HStack(spacing: 4) {
								Image(systemName: "clock.arrow.circlepath")
									.font(.headline.bold())
								Text("Get")
									.lineLimit(1)
									.font(.headline.bold())
							}
							.foregroundStyle(.secondary)
							.padding(.horizontal, 20)
							.padding(.vertical, 6)
							.background(Color(uiColor: .quaternarySystemFill))
							.clipShape(Capsule())
						}
						.buttonStyle(.borderless)
						.transition(.scale.combined(with: .opacity))
					} else {
						Button {
							tabSelection.navigateToLibraryWithHighlight(uuid: installedApp.uuid)
						} label: {
							Text(.localized(installedApp.type == .imported ? "Imported" : "Signed"))
								.lineLimit(1)
								.font(.headline.bold())
								.foregroundStyle(.secondary)
								.padding(.horizontal, 16)
								.padding(.vertical, 6)
								.background(Color(uiColor: .quaternarySystemFill))
								.clipShape(Capsule())
						}
						.buttonStyle(.borderless)
						.transition(.scale.combined(with: .opacity))
					}
					
					Menu {
						Button {
							tabSelection.navigateToLibraryWithHighlight(uuid: installedApp.uuid)
						} label: {
							Label(.localized("View in Library"), systemImage: "square.grid.2x2")
						}

						Button {
							NBHaptic.tap()
							downloadManager.startDownload(for: app)
						} label: {
							Label(.localized("Download Again"), systemImage: "arrow.down.circle")
						}
					} label: {
						Image(systemName: "ellipsis.circle")
							.font(.body.bold())
							.foregroundStyle(Color.accentColor)
							.frame(width: 31, height: 31)
							.background(Color(uiColor: .quaternarySystemFill))
							.clipShape(Circle())
					}
					.buttonStyle(.borderless)
				}
			} else if !isCheckingInstalled {
				Button {
					NBHaptic.tap()
					downloadManager.startDownload(for: app)
				} label: {
					HStack(spacing: 4) {
						Image(systemName: "arrow.down.circle")
							.font(.headline.bold())
						Text(.localized("Get"))
							.lineLimit(1)
							.font(.headline.bold())
					}
					.foregroundStyle(Color.accentColor)
					.padding(.horizontal, 20)
					.padding(.vertical, 6)
					.background(Color(uiColor: .quaternarySystemFill))
					.clipShape(Capsule())
				}
				.buttonStyle(.borderless)
				.transition(.scale.combined(with: .opacity))
			}
		}
		.onAppear {
			checkIfInstalled()
			// Delay setting hasAppeared to prevent initial animation
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
				hasAppeared = true
			}
		}
		.onChange(of: signedApps.count) { _ in
			checkIfInstalled()
		}
		.onChange(of: importedApps.count) { _ in
			checkIfInstalled()
		}
		.animation(hasAppeared ? .easeInOut(duration: 0.25) : nil, value: downloadManager.getDownload(by: app.currentUniqueId) != nil)
		.animation(hasAppeared ? .easeInOut(duration: 0.25) : nil, value: installedApp != nil)
	}
	
	private func checkIfInstalled() {
        isCheckingInstalled = true

        let appBundleId = app.id ?? ""
        let appNameLower = app.currentName.lowercased()

        func compareVersions(_ lhs: String?, _ rhs: String?) -> Bool {
            guard let l = lhs, let r = rhs else { return false }
            let lParts = l.split(separator: ".").compactMap { Int($0) }
            let rParts = r.split(separator: ".").compactMap { Int($0) }
            for i in 0..<max(lParts.count, rParts.count) {
                let lv = i < lParts.count ? lParts[i] : 0
                let rv = i < rParts.count ? rParts[i] : 0
                if lv != rv { return lv > rv }
            }
            return false
        }

        func identifiersMatch(_ sourceId: String, _ storedId: String?, _ originalId: String?) -> Bool {
            if let originalId = originalId, sourceId == originalId { return true }
            if let storedId = storedId, sourceId == storedId { return true }
            return false
        }

        var candidates: [(uuid: String, name: String, version: String?, type: InstalledAppInfo.AppType)] = []

        for s in signedApps {
            let identifierMatch = !appBundleId.isEmpty &&
                identifiersMatch(appBundleId, s.identifier, s.originalIdentifier)
            let nameMatch = (s.name ?? "").lowercased() == appNameLower

            if identifierMatch || nameMatch {
                candidates.append((s.uuid ?? "", s.name ?? "", s.version, .signed))
            }
        }

        for i in importedApps {
            let identifierMatch = !appBundleId.isEmpty &&
                identifiersMatch(appBundleId, i.identifier, i.originalIdentifier)
            let nameMatch = (i.name ?? "").lowercased() == appNameLower

            if identifierMatch || nameMatch {
                candidates.append((i.uuid ?? "", i.name ?? "", i.version, .imported))
            }
        }

        if let best = candidates.max(by: { !compareVersions($0.version, $1.version) }) {
            installedApp = InstalledAppInfo(
                uuid: best.uuid,
                name: best.name,
                version: best.version,
                type: best.type,
                sourceApp: app
            )
        } else {
            installedApp = nil
        }

        isCheckingInstalled = false
    }
}

struct DownloadProgressButton: View {
	let download: Download
	@State private var _phase: DownloadPhase = .queued
	@State private var _progress: Double = 0

	private var _changes: AnyPublisher<Void, Never> {
		Publishers.MergeMany(
			download.$progress.map { _ in }.eraseToAnyPublisher(),
			download.$unpackageProgress.map { _ in }.eraseToAnyPublisher(),
			download.$isPaused.map { _ in }.eraseToAnyPublisher(),
			download.$isImporting.map { _ in }.eraseToAnyPublisher(),
			download.$isSigning.map { _ in }.eraseToAnyPublisher()
		)
		.receive(on: DispatchQueue.main)
		.eraseToAnyPublisher()
	}

	private var _symbol: String {
		switch _phase {
		case .importing: "archivebox"
		case .signing: "signature"
		default: "square.fill"
		}
	}

	var body: some View {
		ZStack {
			DownloadPhaseRing(phase: _phase, progress: _progress, size: 31, lineWidth: 2.3)
			Image(systemName: _symbol)
				.foregroundStyle(_phase.tint)
				.font(.footnote.bold())
		}
		.contentShape(Circle())
		.onTapGesture {
			if download.canCancel {
				DownloadManager.shared.cancelDownload(download)
			}
		}
		.onReceive(_changes) {
			_phase = download.phase
			_progress = download.phaseProgress
		}
	}
}
