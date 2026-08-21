//
//  RyukSignApp.swift / AppDelegate
//  RyukSign
//
//  Created by samara on 10.04.2025.
//

import SwiftUI
import Nuke
import IDeviceSwift
import BackgroundTasks
import OSLog

@main
struct RyukSignApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    let heartbeat = HeartbeatManager.shared

    @StateObject var downloadManager = DownloadManager.shared
    @StateObject private var tabSelection = TabSelectionObserver.shared
    @StateObject private var selfUpdate = SelfUpdateManager.shared
    let storage = Storage.shared

    private var activeManualDownloads: [Download] {
        downloadManager.manualDownloads.filter { 
            $0.isActive || $0.progress > 0 || $0.unpackageProgress > 0 
        }
    }
    
    private var activeNonManualDownloads: [Download] {
        downloadManager.nonManualDownloads.filter { 
            $0.isActive || $0.progress > 0 || $0.unpackageProgress > 0 
        }
    }
    
    private var hasActiveDownloads: Bool {
        !activeManualDownloads.isEmpty || !activeNonManualDownloads.isEmpty
    }
    
    init() {
        UserDefaults.standard.register(defaults: [
            "Feather.serverMethod": 0, // Fully Local signing
            "Feather.backgroundDownloadHeaderStartState": "collapsed",
            "Feather.showDownloadHeaderInSourcesTab": true,
            "Feather.downloadDisplayMode": "floating", // Default to floating icon
			"Feather.sourcesShowUpdatesAsTab": true,
            "Feather.downloadOverlayTheme": "darkGrey",
            "Feather.dynamicOverlaySize": true
        ])

        // Enable liquid glass on iOS 19+
        if #available(iOS 19.0, *) {
            UserDefaults.standard.set(true, forKey: "com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            Group {
                let downloadDisplayMode = UserDefaults.standard.string(forKey: "Feather.downloadDisplayMode") ?? "floating"

                if downloadDisplayMode == "header" {
                    VStack(spacing: 0) {
                        // Single animation point for header presence
                        if !activeManualDownloads.isEmpty || !activeNonManualDownloads.isEmpty {
                            downloadHeaderContent
                                .transition(.move(edge: .top).combined(with: .opacity))
                                .zIndex(1)
                        }

                        VariedTabbarView()
                            .environment(\.managedObjectContext, storage.context)
                            .environmentObject(tabSelection)
                            .onOpenURL(perform: _handleURL)
                            .zIndex(0)
                    }
                    .animation(.spring(response: 0.4, dampingFraction: 0.8), value: hasActiveDownloads)
                } else {
                    ZStack {
                        VariedTabbarView()
                            .environment(\.managedObjectContext, storage.context)
                            .environmentObject(tabSelection)
                            .onOpenURL(perform: _handleURL)
                            .zIndex(0)

                        // Floating download bubble and overlay (always present to handle its own animations)
                        DownloadBubbleOverlayContainer(downloadManager: downloadManager)
                            .zIndex(1)
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .heartbeatInvalidHost)) { _ in
                DispatchQueue.main.async {
                    UIAlertController.showAlertWithOk(
                        title: "InvalidHostID",
                        message: .localized("Your pairing file is invalid and is incompatible with your device, please import a valid pairing file.")
                    )
                }
            }
            .onAppear {
                if let style = UIUserInterfaceStyle(rawValue: UserDefaults.standard.integer(forKey: "Feather.userInterfaceStyle")) {
                    UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
                }

                UIApplication.topViewController()?.view.window?.tintColor = UIColor(Color(hex: UserDefaults.standard.string(forKey: "Feather.userTintColor") ?? "#B496DC"))
            }
            .onChange(of: scenePhase) { newPhase in
                if newPhase == .active {
                    Task { @MainActor in
                        SourcesViewModel.shared.resetLoadingState()
                    }
                }
            }
            .task {
                await selfUpdate.checkOnLaunch()
            }
            .sheet(isPresented: $selfUpdate.presentUpdatePrompt) {
                if let release = selfUpdate.available {
                    SelfUpdateSheet(release: release)
                }
            }
        }
    }

    @ViewBuilder
    private var downloadHeaderContent: some View {
        if !activeManualDownloads.isEmpty {
            DownloadHeaderView(downloadManager: downloadManager)
        } else if !activeNonManualDownloads.isEmpty {
            let showInSourcesTab = UserDefaults.standard.bool(forKey: "Feather.showDownloadHeaderInSourcesTab")
            let shouldHide = tabSelection.selectedTab == .sources && !showInSourcesTab

            if !shouldHide {
                ConditionalDownloadHeaderView(downloads: activeNonManualDownloads)
            }
        }
    }
	
	private func _handleURL(_ url: URL) {
		if url.scheme == "feather" {
			/// feather://import-certificate?p12=<base64>&mobileprovision=<base64>&password=<base64>
			if url.host == "import-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
					let queryItems = components.queryItems
				else {
					return
				}
				
				func queryValue(_ name: String) -> String? {
					queryItems.first(where: { $0.name == name })?.value?.removingPercentEncoding
				}
				
				guard
					let p12Base64 = queryValue("p12"),
					let provisionBase64 = queryValue("mobileprovision"),
					let passwordBase64 = queryValue("password"),
					let passwordData = Data(base64Encoded: passwordBase64),
					let password = String(data: passwordData, encoding: .utf8)
				else {
					return
				}
				
				let generator = UINotificationFeedbackGenerator()
				generator.prepare()
				
				guard
					let p12URL = FileManager.default.decodeAndWrite(base64: p12Base64, pathComponent: ".p12"),
					let provisionURL = FileManager.default.decodeAndWrite(base64: provisionBase64, pathComponent: ".mobileprovision"),
					FR.checkPasswordForCertificate(for: p12URL, with: password, using: provisionURL)
				else {
					generator.notificationOccurred(.error)
					UIAlertController.showAlertWithOk(
						title: .localized("Import Failed"),
						message: .localized("Failed to import certificate. Please check that the certificate and password are valid.")
					)
					return
				}
				
				FR.handleCertificateFiles(
					p12URL: p12URL,
					provisionURL: provisionURL,
					p12Password: password
				) { error in
					if let error = error {
						UIAlertController.showAlertWithOk(title: .localized("Error"), message: error.localizedDescription)
					} else {
						generator.notificationOccurred(.success)
					}
				}
				
				return
			}
			/// feather://export-certificate?callback_template=<template>
			/// ?callback_template=: This is how we callback to the application requesting the certificate, this will be a url scheme
			/// 	example: livecontainer%3A%2F%2Fcertificate%3Fcert%3D%24%28BASE64_CERT%29%26password%3D%24%28PASSWORD%29
			/// 	decoded: livecontainer://certificate?cert=$(BASE64_CERT)&password=$(PASSWORD)
			/// $(BASE64_CERT) and $(PASSWORD) must be presenting in the callback template so we can replace them with the proper content
			if url.host == "export-certificate" {
				guard
					let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
				else {
					return
				}
				
				let queryItems = components.queryItems?.reduce(into: [String: String]()) { $0[$1.name.lowercased()] = $1.value } ?? [:]
				guard let callbackTemplate = queryItems["callback_template"]?.removingPercentEncoding else { return }
				
				FR.exportCertificateAndOpenUrl(using: callbackTemplate)
			}
			/// feather://source/<url>
			if let fullPath = url.validatedScheme(after: "/source/") {
				FR.handleSource(fullPath) { _ in }
			}
			/// feather://install/<url.ipa>
			if
				let fullPath = url.validatedScheme(after: "/install/"),
				let downloadURL = URL(string: fullPath)
			{
				_ = DownloadManager.shared.startDownload(from: downloadURL)
			}
		} else {
			let ext = url.pathExtension.lowercased()
			if ext == "ipa" || ext == "tipa" {
				// Handle file import using NSFileCoordinator for proper access control
				let tempDir = FileManager.default.uniqueTemporaryDirectory("FeatherShared")
				let destinationURL = tempDir.appendingPathComponent(url.lastPathComponent)

				let didStartAccessing = url.startAccessingSecurityScopedResource()

				let coordinator = NSFileCoordinator()
				var coordinatorError: NSError?

				var copyError: Error?
				coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { sourceURL in
					do {
						try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
						try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
					} catch {
						copyError = error
					}
				}

				if didStartAccessing {
					url.stopAccessingSecurityScopedResource()
				}

				// Surface the real reason the staged copy failed, if any.
				if let error = copyError {
					UIAlertController.showErrorWithCopy(
						title: .localized("Import Failed"),
						message: "Could not copy the shared file into the app.\n\nFile: \(url.lastPathComponent)\nReason: \(error.localizedDescription)"
					)
					return
				}

				if let error = coordinatorError {
					UIAlertController.showErrorWithCopy(
						title: .localized("Import Failed"),
						message: "Could not read the shared file. The other app may have denied access.\n\nFile: \(url.lastPathComponent)\nReason: \(error.localizedDescription)"
					)
					return
				}

				guard FileManager.default.fileExists(atPath: destinationURL.path) else {
					UIAlertController.showErrorWithCopy(
						title: .localized("Import Failed"),
						message: "The shared file could not be copied into the app. It may be inaccessible, or storage may be full.\n\nFile: \(url.lastPathComponent)"
					)
					return
				}

				// Manual download to show progress in the header; completion reports the real outcome.
				let id = "FeatherManualDownload_\(UUID().uuidString)"
				_ = DownloadManager.shared.startArchive(from: destinationURL, id: id) { error in
					if let error = error {
						UIAlertController.showErrorWithCopy(
							title: .localized("Import Failed"),
							message: error.localizedDescription
						)
					} else {
						Toast.success(.localized("Imported successfully"), systemImage: "square.and.arrow.down.fill")
					}
				}

				return
			}

			// Tweak files shared into the app (Open in / share sheet / AirDrop) → Tweak Manager.
			let tweakExtensions: Set<String> = ["dylib", "deb", "framework", "bundle", "zip"]
			if tweakExtensions.contains(ext) {
				_importSharedTweak(url)
				return
			}
		}
	}

	/// Imports a tweak file shared into the app. Archives are unpacked and scanned for
	/// injectables; everything else is added directly. Cleans up its temp copy afterwards.
	private func _importSharedTweak(_ url: URL) {
		let ext = url.pathExtension.lowercased()
		let tempDir = FileManager.default.temporaryDirectory
			.appendingPathComponent("FeatherSharedTweak_\(UUID().uuidString)", isDirectory: true)
		let destinationURL = tempDir.appendingPathComponent(url.lastPathComponent)

		let didStartAccessing = url.startAccessingSecurityScopedResource()
		let coordinator = NSFileCoordinator()
		var coordinatorError: NSError?
		coordinator.coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinatorError) { sourceURL in
			do {
				try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
				try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
			} catch {
				DispatchQueue.main.async { Toast.error(.localized("Import Failed"), duration: .long) }
			}
		}
		if didStartAccessing { url.stopAccessingSecurityScopedResource() }

		guard coordinatorError == nil, FileManager.default.fileExists(atPath: destinationURL.path) else {
			Toast.error(.localized("Import Failed"), duration: .long)
			return
		}

		if ext == "zip" {
			Task {
				do {
					let result = try await TweakExtractor.extract(fromZip: destinationURL)
					await MainActor.run {
						// Ignore artifacts inside a packaged app (a zipped .app/Payload).
						let injectables = result.candidates.filter { !$0.url.path.contains(".app/") }
						var added = 0
						for candidate in injectables {
							if TweakManager.shared.addTweak(
								name: candidate.url.deletingPathExtension().lastPathComponent,
								from: candidate.url
							) != nil { added += 1 }
						}
						try? FileManager.default.removeItem(at: result.workDir)
						try? FileManager.default.removeItem(at: tempDir)
						if added > 0 {
							Toast.success(String.localized("Added %lld tweaks", arguments: added), systemImage: "wrench.and.screwdriver.fill")
						} else {
							Toast.error(.localized("No tweaks found in the archive"), duration: .long)
						}
					}
				} catch {
					await MainActor.run {
						try? FileManager.default.removeItem(at: tempDir)
						Toast.error(error.localizedDescription, duration: .long)
					}
				}
			}
		} else {
			if TweakManager.shared.addTweak(
				name: destinationURL.deletingPathExtension().lastPathComponent,
				from: destinationURL
			) != nil {
				Toast.success(.localized("Added to Tweak Manager"), systemImage: "wrench.and.screwdriver.fill")
			} else {
				Toast.error(.localized("Couldn't import tweak"), duration: .sticky)
			}
			try? FileManager.default.removeItem(at: tempDir)
		}
	}
}


class AppDelegate: NSObject, UIApplicationDelegate, DownloadManager.ErrorDelegate {
	func application(
		_ application: UIApplication,
		didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
	) -> Bool {
		_createPipeline()
		_createDocumentsDirectories()
		StorageManager.purgeStaleTemporary()
		_addDefaultCertificates()
		_registerBackgroundTasks()

		// Idempotent, no-op after first run.
		RyukSignAPI.migrateIfNeeded()

		DownloadManager.shared.errorDelegate = self

		return true
	}
	
	// MARK: - DownloadManager.ErrorDelegate
	
	func showUIErrorMessage(title: String, message: String) {
		DispatchQueue.main.async {
			UIAlertController.showErrorWithCopy(
				title: .localized(title),
				message: message
			)
		}
	}

	func application(
        _ application: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void
    ) {
        DownloadManager.shared.backgroundCompletionHandler = completionHandler
    }
	
	private func _registerBackgroundTasks() {
        if #available(iOS 19.0, *) {
            // BGContinuedProcessingTask: user-initiated download that starts foreground, continues backgrounded.
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: "ryuk.app.Feather.background.download.continued",
                using: nil
            ) { task in
                guard let continuedTask = task as? BGContinuedProcessingTask else { return }
                self._handleContinuedProcessing(task: continuedTask)
            }
        }

        // BGProcessingTask: scheduled background downloads (iOS 16+).
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "ryuk.app.Feather.background.download",
            using: nil
        ) { task in
            self._handleBackgroundDownload(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: "ryuk.app.Feather.background.refresh",
            using: nil
        ) { task in
            self._handleBackgroundRefresh(task: task as! BGAppRefreshTask)
        }
    }
	
	@available(iOS 19.0, *)
	private func _handleContinuedProcessing(task: BGContinuedProcessingTask) {
        // Runs in background; DownloadManager already handles Live Activity updates.
        var wasExpired = false

        task.expirationHandler = {
            wasExpired = true
            // Don't pause — let DownloadManager handle continuation.
            task.setTaskCompleted(success: false)
        }

        // Progress tracking is required by the system.
        let progress = task.progress
        progress.totalUnitCount = 100

        DispatchQueue.global(qos: .userInitiated).async {
            while !wasExpired && !DownloadManager.shared.downloads.isEmpty {
                let activeDownloads = DownloadManager.shared.downloads.filter {
                    $0.isActive || ($0.progress > 0 && $0.progress < 1.0 && !$0.isPaused)
                }

                if activeDownloads.isEmpty {
                    progress.completedUnitCount = 100
                    break
                }

                let totalProgress = activeDownloads.reduce(0.0) { $0 + $1.progress }
                let averageProgress = activeDownloads.isEmpty ? 1.0 : totalProgress / Double(activeDownloads.count)
                progress.completedUnitCount = Int64(averageProgress * 100)

                Thread.sleep(forTimeInterval: 2.0)
            }

            task.setTaskCompleted(success: !wasExpired && DownloadManager.shared.downloads.isEmpty)
        }
    }

	// iOS 17 and below.
	private func _handleBackgroundDownload(task: BGProcessingTask) {
        task.expirationHandler = {
            DownloadManager.shared.pauseAllDownloads()
            task.setTaskCompleted(success: false)
        }

        DownloadManager.shared.resumeAllDownloads()

        let timeout: TimeInterval = 4 * 60
        let startTime = Date()

        DispatchQueue.global().async {
            while !DownloadManager.shared.downloads.isEmpty {
                if Date().timeIntervalSince(startTime) > timeout {
                    break
                }
                Thread.sleep(forTimeInterval: 5.0)
            }
            task.setTaskCompleted(success: true)
        }
    }
	
	private func _handleBackgroundRefresh(task: BGAppRefreshTask) {
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }

        // Schedule a processing task if downloads are still pending.
        if !DownloadManager.shared.downloads.isEmpty {
            _scheduleBackgroundDownloadTask()
        }

        task.setTaskCompleted(success: true)
    }

    func _scheduleBackgroundDownloadTask() {
        let request = BGProcessingTaskRequest(identifier: "ryuk.app.Feather.background.download")
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
        }
    }

    // iOS 19+: for active foreground downloads that may be backgrounded.
    @available(iOS 19.0, *)
    func submitContinuedProcessingTask() {
        let activeDownloads = DownloadManager.shared.downloads.filter {
            $0.isActive || ($0.progress > 0 && $0.progress < 1.0)
        }

        guard !activeDownloads.isEmpty else { return }

        let count = activeDownloads.count
        let request = BGContinuedProcessingTaskRequest(
            identifier: "ryuk.app.Feather.background.download.continued",
            title: "Downloading Apps",
            subtitle: "Processing \(count) item(s)"
        )

        // .queue lets the task continue if backgrounded.
        request.strategy = .queue

        if BGTaskScheduler.supportedResources.contains(.gpu) {
            request.requiredResources = .gpu
        }

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            Logger.misc.error("Failed to submit BGContinuedProcessingTask: \(error.localizedDescription)")
        }
    }

	private func _addDefaultCertificates() {
		CertificateAutoImporter.shared.importBundledCertificatesIfNeeded()
	}
	
	private func _createPipeline() {
		DataLoader.sharedUrlCache.diskCapacity = 0
		
		let pipeline = ImagePipeline {
			let dataLoader: DataLoader = {
				let config = URLSessionConfiguration.default
				config.urlCache = nil
				return DataLoader(configuration: config)
			}()
			let dataCache = try? DataCache(name: "thewonderofyou.Feather.datacache") // disk cache
			let imageCache = Nuke.ImageCache() // memory cache
			dataCache?.sizeLimit = 500 * 1024 * 1024
			imageCache.costLimit = 100 * 1024 * 1024
			$0.dataCache = dataCache
			$0.imageCache = imageCache
			$0.dataLoader = dataLoader
			$0.dataCachePolicy = .automatic
			$0.isStoringPreviewsInMemoryCache = false
		}
		
		ImagePipeline.shared = pipeline
	}
	
	private func _createDocumentsDirectories() {
		let fileManager = FileManager.default

		let directories: [URL] = [
			fileManager.archives,
			fileManager.certificates,
			fileManager.signed,
			fileManager.unsigned
		]
		
		for url in directories {
			try? fileManager.createDirectoryIfNeeded(at: url)
		}
	}
}
