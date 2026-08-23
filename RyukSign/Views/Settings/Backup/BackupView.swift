//
//  BackupView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct BackupView: View {
	@State private var _isWorking = false
	@State private var _exportURL: URL?
	@State private var _showExporter = false
	@State private var _showImporter = false
	@State private var _showRestorePassword = false
	@State private var _password = ""
	@State private var _pendingImportURL: URL?
	@State private var _archive: BackupArchive?
	@State private var _showExportPicker = false
	@State private var _pendingExport: (components: BackupComponents, password: String)?
	@State private var _pendingSummary: BackupRestoreSummary?

	// MARK: Body
	var body: some View {
		NBList(.localized("Backup & Restore")) {
			Section {
				Button {
					_pendingExport = nil
					_showExportPicker = true
				} label: {
					Label(.localized("Create Backup"), systemImage: "square.and.arrow.up")
				}
			} footer: {
				Text(.localized("Saves what you pick to one file. Signed and imported apps aren't included."))
			}

			Section {
				Button {
					_showImporter = true
				} label: {
					Label(.localized("Restore from Backup"), systemImage: "square.and.arrow.down")
				}
			} footer: {
				Text(.localized("Open a backup file, then pick what comes back."))
			}
		}
		.disabled(_isWorking)
		.animation(.easeInOut(duration: 0.2), value: _isWorking)
		.overlay { _workingOverlay }
		.sheet(isPresented: $_showExportPicker, onDismiss: _runExport) {
			let available = BackupManager.shared.availableComponents()
			BackupComponentsView(
				title: .localized("Create Backup"),
				confirmTitle: .localized("Create"),
				available: available.components,
				counts: available.counts,
				footer: .localized("Choose what to include in this backup."),
				passwordFooter: .localized("Leave it empty for an unencrypted backup."),
				onConfirm: { _pendingExport = ($0, $1) }
			)
		}
		.sheet(item: $_archive, onDismiss: _presentRestoreComplete) { archive in
			BackupComponentsView(
				title: .localized("Restore from Backup"),
				confirmTitle: .localized("Restore"),
				available: archive.contents,
				counts: _archiveCounts(archive),
				detail: .localized(
					"Created %@ · RyukSign %@",
					arguments: archive.manifest.createdAt.formatted(date: .abbreviated, time: .shortened),
					archive.manifest.appVersion
				),
				footer: .localized("Nothing is deleted. Anything already here is skipped."),
				onConfirm: { components, _ in
					_pendingSummary = BackupManager.shared.restore(archive, components: components)
				}
			)
		}
		.sheet(isPresented: $_showExporter) {
			if let url = _exportURL {
				DocumentExporterView(urls: [url]).ignoresSafeArea()
			}
		}
		.sheet(isPresented: $_showImporter) {
			FileImporterRepresentableView(
				allowedContentTypes: [.ryukBackup],
				folder: .backups,
				onDocumentsPicked: { urls in
					guard let url = urls.first else { return }
					_pendingImportURL = url
					_password = ""
					if BackupCrypto.isEncrypted(url) {
						_showRestorePassword = true
					} else {
						_openBackup()
					}
				}
			)
			.ignoresSafeArea()
		}
		.alert(.localized("Backup Password"), isPresented: $_showRestorePassword) {
			SecureField(.localized("Password"), text: $_password)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Continue")) { _openBackup() }
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

	private func _archiveCounts(_ archive: BackupArchive) -> [BackupComponents: Int] {
		BackupComponents.ordered.reduce(into: [:]) { result, component in
			result[component] = archive.manifest.count(of: component)
		}
	}

	private func _runExport() {
		guard let pending = _pendingExport else { return }
		_pendingExport = nil
		_isWorking = true
		Task {
			do {
				_exportURL = try await BackupManager.shared.makeBackup(
					password: pending.password,
					components: pending.components
				)
				_isWorking = false
				Toast.success(.localized("Backup created"))
				_showExporter = true
			} catch {
				_isWorking = false
				Toast.error(error.localizedDescription)
			}
		}
	}

	private func _openBackup() {
		guard let url = _pendingImportURL else { return }
		let password = _password
		_isWorking = true
		Task {
			do {
				let archive = try await BackupManager.shared.open(url, password: password)
				_isWorking = false
				guard !archive.contents.isEmpty else {
					Toast.error(.localized("This backup is empty."))
					return
				}
				_archive = archive
			} catch {
				_isWorking = false
				Toast.error(error.localizedDescription)
			}
		}
	}

	private func _presentRestoreComplete() {
		guard let summary = _pendingSummary else { return }
		_pendingSummary = nil

		let needsRestart = !summary.restored.intersection([.settings, .certificates]).isEmpty
		let message = needsRestart
			? summary.lines.joined(separator: "\n") + "\n\n" + .localized("RyukSign will restart to apply the backup.")
			: summary.lines.joined(separator: "\n")

		UIAlertController.showAlert(
			title: .localized("Restore Complete"),
			message: message,
			actions: [
				needsRestart
				? UIAlertAction(title: .localized("Restart"), style: .default) { _ in
					UIApplication.shared.suspendAndReopen()
				}
				: UIAlertAction(title: .localized("Done"), style: .default, handler: nil)
			]
		)
	}
}
