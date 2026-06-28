//
//  DefaultFolderPickerView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers
import NimbleViews

struct DefaultFolderPickerView: UIViewControllerRepresentable {
	static let folderNameKey = "RyukSign.defaultImportFolderName"

	var onPicked: (String?) -> Void

	func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

	func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
		picker.delegate = context.coordinator
		picker.allowsMultipleSelection = false
		return picker
	}

	func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

	final class Coordinator: NSObject, UIDocumentPickerDelegate {
		let onPicked: (String?) -> Void
		init(onPicked: @escaping (String?) -> Void) { self.onPicked = onPicked }

		func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			guard let folder = urls.first else { onPicked(nil); return }
			let scoped = folder.startAccessingSecurityScopedResource()
			defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
			guard let data = try? folder.bookmarkData() else { onPicked(nil); return }
			UserDefaults.standard.set(data, forKey: FileImporterRepresentableView.defaultFolderBookmarkKey)
			UserDefaults.standard.set(folder.lastPathComponent, forKey: DefaultFolderPickerView.folderNameKey)
			onPicked(folder.lastPathComponent)
		}

		func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
			onPicked(nil)
		}
	}
}
