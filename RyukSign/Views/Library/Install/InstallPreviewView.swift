//
//  InstallPreview.swift
//  RyukSign
//
//  Created by samara on 22.04.2025.
//

import SwiftUI
import NimbleViews
import IDeviceSwift
import OSLog

// MARK: - View
struct InstallPreviewView: View {
	@Environment(\.dismiss) var dismiss

	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage("Feather.installationMethod") private var _installationMethod: Int = 0
	@AppStorage("Feather.serverMethod") private var _serverMethod: Int = 0
	@State private var _isWebviewPresenting = false
	@State private var progressTask: Task<Void, Never>?

	var app: AppInfoPresentable
	@StateObject var viewModel: InstallerStatusViewModel
	@StateObject var installer: ServerInstaller
	
	@State var isSharing: Bool
	
	init(app: AppInfoPresentable, isSharing: Bool = false) {
		self.app = app
		self.isSharing = isSharing
		let viewModel = InstallerStatusViewModel(isIdevice: UserDefaults.standard.integer(forKey: "Feather.installationMethod") == 1)
		self._viewModel = StateObject(wrappedValue: viewModel)
		self._installer = StateObject(wrappedValue: try! ServerInstaller(app: app, viewModel: viewModel))
	}
	
	// MARK: Body
	var body: some View {
		let cornerRadius = NBRadius.large

		ZStack {
			InstallProgressView(app: app, viewModel: viewModel)
			_status()
			_button()
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
		.background(Color(UIColor.secondarySystemBackground))
		.cornerRadius(cornerRadius)
		.padding([.top, .horizontal])
		.padding(.bottom, 36)
		.ignoresSafeArea(.container, edges: .bottom)
		.sheet(isPresented: $_isWebviewPresenting) {
			SafariRepresentableView(url: installer.pageEndpoint).ignoresSafeArea()
		}
		.onReceive(viewModel.$status) { newStatus in
			guard _installationMethod == 0 else { return }

			switch newStatus {
			case .ready:
				_openInstall(_serverMethod == 0 ? installer.iTunesLink : installer.iTunesLinkExternal)
			case .sendingPayload:
				_isWebviewPresenting = false
			case .installing:
				if progressTask == nil {
					progressTask = startInstallProgressPolling(
						bundleID: app.identifier!,
						viewModel: viewModel
					)
				}
			case .completed, .broken:
				progressTask?.cancel()
				progressTask = nil
			default:
				break
			}
		}
		.onAppear(perform: _install)
		.onDisappear {
			progressTask?.cancel()
			progressTask = nil
		}
	}
	
	// Direct open keeps the install to one tap; the redirect page is only for builds that refuse the scheme.
	private func _openInstall(_ link: String?) {
		guard let link, let url = URL(string: link) else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("Could not build the installation link, check your connection and try again.")
			)
			return
		}

		FileLogger.log("opening \(link)", category: "install")

		UIApplication.shared.open(url) { opened in
			FileLogger.log("itms-services accepted by iOS: \(opened)", category: "install")

			if !opened {
				FileLogger.error("iOS refused the scheme, falling back to the redirect page", category: "install")
				_isWebviewPresenting = true
			}
		}
	}
	
	@ViewBuilder
	private func _status() -> some View {
		Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
			.padding()
			.labelStyle(.titleAndIcon)
			.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
			.animation(.smooth, value: viewModel.statusImage)
	}
	
	@ViewBuilder
	private func _button() -> some View {
		ZStack {
			if viewModel.isCompleted {
				Button {
					UIApplication.openApp(with: app.identifier ?? "")
				} label: {
					NBButton("Open", systemImage: "", style: .text)
				}
				.padding()
				.compatTransition()
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
		.animation(.easeInOut(duration: 0.3), value: viewModel.isCompleted)
	}
	
	private func _install() {
		guard isSharing || app.identifier != Bundle.main.bundleIdentifier! || _installationMethod == 1 else {
			UIAlertController.showAlertWithOk(
				title: .localized("Install"),
				message: .localized("You cannot update '%@' with itself, please use an alternative tool to update it.", arguments: Bundle.main.name)
			)
			return
		}

		Task.detached {
			let keepAlive = BackgroundTaskManager(
				taskName: "Install",
				expirationTitle: .localized("Installation continuing"),
				expirationBody: .localized("The installation will continue when you reopen the app")
			)
			await MainActor.run { keepAlive.start() }
			defer { Task { @MainActor in keepAlive.stop() } }

			do {
				let handler = await ArchiveHandler(app: app, viewModel: viewModel)
				try await handler.move()

				let packageUrl = try await handler.archive()

				if await !isSharing {
					if await _installationMethod == 0 {
						let payload = await MainActor.run { () -> URL? in
							installer.packageUrl = packageUrl
							guard _serverMethod == 1 else { return nil }
							viewModel.status = .sendingManifest
							return installer.payloadEndpoint
						}

						if let payload {
							let manifestUrl = await ManifestService.resolve(for: app, payload: payload)
							await MainActor.run { installer.manifestUrl = manifestUrl }
						}

						let server = await MainActor.run { installer }
						var failure = server.startupError
						if failure == nil {
							failure = await server.selfCheck()
						}

						await MainActor.run {
							if let failure {
								viewModel.status = .broken(failure)
							} else {
								viewModel.status = .ready
							}
						}
					} else if await _installationMethod == 1 {
						let handler = await InstallationProxy(viewModel: viewModel)
						try await handler.install(at: packageUrl, suspend: app.identifier == Bundle.main.bundleIdentifier!)
					}
				} else {
					let package = try await handler.moveToArchive(packageUrl, shouldOpen: !_useShareSheet)

					if await !_useShareSheet {
						await MainActor.run {
							dismiss()
						}
					} else {
						if let package {
							await MainActor.run {
								dismiss()
								UIActivityViewController.show(activityItems: [package])
							}
						}
					}
				}
			} catch {
				await progressTask?.cancel()

				await MainActor.run {
					UIAlertController.showAlertWithOk(
						title: .localized("Install"),
						message: String(describing: error),
						action: {
							HeartbeatManager.shared.start(true)
							dismiss()
						}
					)
				}
			}
		}
	}

	// MARK: - Install Progress Polling

	private func startInstallProgressPolling(
		bundleID: String,
		viewModel: InstallerStatusViewModel
	) -> Task<Void, Never> {

		Task.detached(priority: .background) {
			var hasStarted = false

			while !Task.isCancelled {
				let rawProgress = await UIApplication.installProgress(for: bundleID) ?? 0.0

				if rawProgress > 0 {
					hasStarted = true
				}

				let progress = hasStarted
					? _normalizeInstallProgress(rawProgress)
					: 0.0

				Logger.misc.info("Install progress for \(bundleID): \(progress)")

				await MainActor.run {
					viewModel.installProgress = progress
				}

				// When progress drops back to 0 after starting, installation is complete
				if hasStarted && rawProgress == 0 {
					await MainActor.run {
						viewModel.installProgress = 1.0
						viewModel.status = .completed(.success(()))
					}
					break
				}

				try? await Task.sleep(nanoseconds: 250_000_000) // 250 ms polling interval
			}
		}
	}

	/// Normalizes raw install progress (0.6-0.9 range) to 0.0-1.0
	private func _normalizeInstallProgress(_ rawProgress: Double) -> Double {
		min(1.0, max(0.0, (rawProgress - 0.6) / 0.3))
	}
}
