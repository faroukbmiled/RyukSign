//
//  ArchiveHandler.swift
//  RyukSign
//
//  Created by samara on 22.04.2025.
//

import Foundation
import UIKit.UIApplication
import Zip
import SwiftUI
import IDeviceSwift

final class ArchiveHandler: NSObject {
	@ObservedObject var viewModel: InstallerStatusViewModel

	private let _fileManager = FileManager.default
	private let _uuid = UUID().uuidString
	private var _payloadUrl: URL?

	private var _app: AppInfoPresentable
	private let _uniqueWorkDir: URL
	private var backgroundTaskManager: BackgroundTaskManager?
	
	init(app: AppInfoPresentable, viewModel: InstallerStatusViewModel) {
		self.viewModel = viewModel
		self._app = app
		self._uniqueWorkDir = _fileManager.temporaryDirectory
			.appendingPathComponent("FeatherInstall_\(_uuid)", isDirectory: true)
		
		super.init()
	}
	
	func move() async throws {
		guard let appUrl = Storage.shared.getAppDirectory(for: _app) else {
			throw SigningFileHandlerError.appNotFound
		}
		
		let payloadUrl = _uniqueWorkDir.appendingPathComponent("Payload")
		let movedAppURL = payloadUrl.appendingPathComponent(appUrl.lastPathComponent)

		try _fileManager.createDirectoryIfNeeded(at: payloadUrl)
		
		try _fileManager.copyItem(at: appUrl, to: movedAppURL)
		_payloadUrl = payloadUrl
	}
	
	func archive() async throws -> URL {
		// Keep archiving alive in the background.
		await MainActor.run {
			if self.backgroundTaskManager == nil {
				self.backgroundTaskManager = BackgroundTaskManager(
					taskName: "ArchiveHandler",
					expirationTitle: "Archiving continuing",
					expirationBody: "The archiving will continue when you reopen the app"
				)
				self.backgroundTaskManager?.start()
			}
		}

		return try await Task.detached(priority: .background) { [self] in
			defer {
				Task { @MainActor in
					self.backgroundTaskManager?.stop()
					self.backgroundTaskManager = nil
				}
			}

			guard let payloadUrl = await self._payloadUrl else {
				throw SigningFileHandlerError.appNotFound
			}

			let ipaUrl = self._uniqueWorkDir.appendingPathComponent("Archive.ipa")

			try AppArchiver.zip(
				payload: payloadUrl,
				to: ipaUrl,
				compression: ZipCompression.allCases[ArchiveHandler.getCompressionLevel()],
				progress: { progress in
					Task { @MainActor in
						self.viewModel.packageProgress = progress
					}
				})

			return ipaUrl
		}.value
	}
	
	func moveToArchive(_ package: URL, shouldOpen: Bool = false) async throws -> URL? {
		let appendingString = "\(_app.name!)_\(_app.version!)_\(Int(Date().timeIntervalSince1970)).ipa"
		let dest = _fileManager.archives.appendingPathComponent(appendingString)
		
		try? _fileManager.moveItem(
			at: package,
			to: dest
		)
		
		if shouldOpen {
			await MainActor.run {
				UIApplication.open(FileManager.default.archives.toSharedDocumentsURL()!)
			}
		}
		
		return dest
	}
	
	static func getCompressionLevel() -> Int {
		UserDefaults.standard.integer(forKey: "Feather.compressionLevel")
	}
}
