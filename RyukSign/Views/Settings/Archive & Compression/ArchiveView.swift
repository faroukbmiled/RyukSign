//
//  ArchiveView.swift
//  RyukSign
//
//  Created by samara on 6.05.2025.
//

import SwiftUI
import Zip
import NimbleViews

// MARK: - View
struct ArchiveView: View {
	@AppStorage("Feather.compressionLevel") private var _compressionLevel: Int = ZipCompression.DefaultCompression.rawValue
	@AppStorage("Feather.useShareSheetForArchiving") private var _useShareSheet: Bool = false
	@AppStorage(ArchiveBackend.storageKey) private var _backend: Int = ArchiveBackend.zip.rawValue
	@AppStorage("RyukSign.useLastExportLocation") private var _useLastExportLocation: Bool = false
	@AppStorage(DefaultFolderPickerView.folderNameKey) private var _importFolderName: String = ""
	@State private var _isPickingImportFolder = false

	// MARK: Body
    var body: some View {
		NBList(.localized("Archive & Compression")) {
			Section {
				Picker(.localized("Compression Level"), systemImage: "archivebox", selection: $_compressionLevel) {
					ForEach(ZipCompression.allCases, id: \.rawValue) { level in
						Text(level.label).tag(level)
					}
				}
				Picker(.localized("Compression Engine"), systemImage: "shippingbox", selection: $_backend) {
					ForEach(ArchiveBackend.allCases, id: \.rawValue) { backend in
						Text(backend.label).tag(backend.rawValue)
					}
				}
			} footer: {
				Text(.localized("The engine used to pack signed apps into IPAs. ZIPFoundation can be a more reliable fallback if Zip fails."))
			}

			Section {
				Toggle(.localized("Show Sheet when Exporting"), systemImage: "square.and.arrow.up", isOn: $_useShareSheet)
			} footer: {
				Text(.localized("Toggling show sheet will present a share sheet after exporting to your files."))
			}

			Section {
				Toggle(.localized("Remember Last Export Location"), systemImage: "clock.arrow.circlepath", isOn: $_useLastExportLocation)
			} footer: {
				Text(.localized("Reopen the Save to Files picker at the last folder you used instead of always starting at the RyukSign documents folder."))
			}

			Section {
				Button {
					_isPickingImportFolder = true
				} label: {
					HStack {
						Label(.localized("Default Import Folder"), systemImage: "folder")
						Spacer()
						Text(_importFolderName.isEmpty ? .localized("Not Set") : _importFolderName)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				if !_importFolderName.isEmpty {
					Button(.localized("Clear Default Folder"), systemImage: "xmark.circle", role: .destructive) {
						UserDefaults.standard.removeObject(forKey: FileImporterRepresentableView.defaultFolderBookmarkKey)
						_importFolderName = ""
					}
				}
			} footer: {
				Text(.localized("Choose a folder to always open when importing files."))
			}
		}
		.sheet(isPresented: $_isPickingImportFolder) {
			DefaultFolderPickerView { _ in _isPickingImportFolder = false }
				.ignoresSafeArea()
		}
    }
}
