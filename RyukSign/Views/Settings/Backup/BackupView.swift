//
//  BackupView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

struct BackupView: View {
	@State private var _isWorking = false
	@State private var _exportURL: URL?
	@State private var _showExporter = false
	@State private var _showImporter = false
	@State private var _showExportPassword = false
	@State private var _showRestorePassword = false
	@State private var _password = ""
	@State private var _pendingImportURL: URL?

	var body: some View {
		NBList(.localized("Backup & Restore")) {
			Section {
				Button {
					_password = ""
					_showExportPassword = true
				} label: {
					Label(.localized("Create Backup"), systemImage: "square.and.arrow.up")
				}
			} footer: {
				Text(.localized("Saves your certificates, sources, tweaks, and app settings to a password-encrypted file. Signed and imported apps are not included."))
			}

			Section {
				Button {
					_showImporter = true
				} label: {
					Label(.localized("Restore from Backup"), systemImage: "square.and.arrow.down")
				}
			} footer: {
				Text(.localized("Merges the backup into this install without deleting existing data. The app restarts when done."))
			}
		}
		.disabled(_isWorking)
		.animation(.easeInOut(duration: 0.2), value: _isWorking)
		.overlay { _workingOverlay }
		.sheet(isPresented: $_showExporter) {
			if let url = _exportURL {
				DocumentExporterView(urls: [url]).ignoresSafeArea()
			}
		}
		.sheet(isPresented: $_showImporter) {
			FileImporterRepresentableView(
				allowedContentTypes: [.ryukBackup],
				onDocumentsPicked: { urls in
					guard let url = urls.first else { return }
					_pendingImportURL = url
					_password = ""
					_showRestorePassword = true
				}
			)
			.ignoresSafeArea()
		}
		.alert(.localized("Backup Password"), isPresented: $_showExportPassword) {
			SecureField(.localized("Password"), text: $_password)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Create")) { _runExport() }
		} message: {
			Text(.localized("Choose a password to encrypt this backup. You'll need it to restore."))
		}
		.alert(.localized("Backup Password"), isPresented: $_showRestorePassword) {
			SecureField(.localized("Password"), text: $_password)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Restore")) { _runRestore() }
		} message: {
			Text(.localized("Enter the password this backup was encrypted with."))
		}
	}

	@ViewBuilder
	private var _workingOverlay: some View {
		if _isWorking {
			ZStack {
				Color(.systemBackground).opacity(0.6).ignoresSafeArea()
				VStack(spacing: 14) {
					ProgressView()
					Text(.localized("Working…"))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				.padding(24)
				.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
			}
			.transition(.opacity)
		}
	}

	private func _runExport() {
		guard !_password.isEmpty else {
			Toast.error(.localized("Enter a password to protect the backup."))
			return
		}
		let password = _password
		_isWorking = true
		Task {
			do {
				_exportURL = try await BackupManager.shared.makeBackup(password: password)
				_isWorking = false
				Toast.success(.localized("Backup created"))
				_showExporter = true
			} catch {
				_isWorking = false
				Toast.error(error.localizedDescription)
			}
		}
	}

	private func _runRestore() {
		guard let url = _pendingImportURL, !_password.isEmpty else {
			if _password.isEmpty { Toast.error(.localized("Enter the backup password.")) }
			return
		}
		let password = _password
		_isWorking = true
		Task {
			do {
				let summary = try await BackupManager.shared.restore(from: url, password: password)
				_isWorking = false
				_presentRestoreComplete(summary)
			} catch {
				_isWorking = false
				Toast.error(error.localizedDescription)
			}
		}
	}

	private func _presentRestoreComplete(_ summary: BackupRestoreSummary) {
		let message = summary.skipped > 0
			? String.localized(
				"Added %lld certificates and %lld sources. Skipped %lld already present. RyukSign will restart to apply the backup.",
				arguments: summary.certificates, summary.sources, summary.skipped
			)
			: String.localized(
				"Added %lld certificates and %lld sources. RyukSign will restart to apply the backup.",
				arguments: summary.certificates, summary.sources
			)
		UIAlertController.showAlert(
			title: .localized("Restore Complete"),
			message: message,
			actions: [UIAlertAction(title: .localized("Restart"), style: .default) { _ in
				UIApplication.shared.suspendAndReopen()
			}]
		)
	}
}
