//
//  ImportFolderPickerView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct ImportFolderPickerView: UIViewControllerRepresentable {
	let folder: ImportFolder
	var onPicked: (String?) -> Void

	func makeCoordinator() -> Coordinator { Coordinator(folder: folder, onPicked: onPicked) }

	func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
		picker.delegate = context.coordinator
		picker.allowsMultipleSelection = false
		return picker
	}

	func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

	final class Coordinator: NSObject, UIDocumentPickerDelegate {
		private let folder: ImportFolder
		private let onPicked: (String?) -> Void

		init(folder: ImportFolder, onPicked: @escaping (String?) -> Void) {
			self.folder = folder
			self.onPicked = onPicked
		}

		func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			guard let picked = urls.first else { onPicked(nil); return }
			let scoped = picked.startAccessingSecurityScopedResource()
			defer { if scoped { picked.stopAccessingSecurityScopedResource() } }
			guard let data = try? picked.bookmarkData() else { onPicked(nil); return }
			UserDefaults.standard.set(data, forKey: folder.bookmarkKey)
			UserDefaults.standard.set(picked.lastPathComponent, forKey: folder.nameKey)
			onPicked(picked.lastPathComponent)
		}

		func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
			onPicked(nil)
		}
	}
}
