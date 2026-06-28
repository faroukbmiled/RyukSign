//
//  UIKitFileImporter.swift
//  Feather
//
//  Created by samara on 23.04.2025.
//

import SwiftUI
import UniformTypeIdentifiers

public struct FileImporterRepresentableView: UIViewControllerRepresentable {
	public static let defaultFolderBookmarkKey = "RyukSign.defaultImportFolderBookmark"

	public var allowedContentTypes: [UTType]
	public var allowsMultipleSelection: Bool = false
	public var onDocumentsPicked: ([URL]) -> Void

	public init(
		allowedContentTypes: [UTType],
		allowsMultipleSelection: Bool = false,
		onDocumentsPicked: @escaping ([URL]) -> Void
	) {
		self.allowedContentTypes = allowedContentTypes
		self.allowsMultipleSelection = allowsMultipleSelection
		self.onDocumentsPicked = onDocumentsPicked
	}

	public func makeCoordinator() -> Coordinator {
		Coordinator(onDocumentsPicked: onDocumentsPicked)
	}

	public func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
		let picker = UIDocumentPickerViewController(forOpeningContentTypes: allowedContentTypes, asCopy: true)
		picker.delegate = context.coordinator
		picker.allowsMultipleSelection = allowsMultipleSelection
		if let dir = context.coordinator.defaultFolder() {
			picker.directoryURL = dir
		}
		return picker
	}

	public func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

	public class Coordinator: NSObject, UIDocumentPickerDelegate {
		var onDocumentsPicked: ([URL]) -> Void
		private var heldFolder: URL?

		init(onDocumentsPicked: @escaping ([URL]) -> Void) {
			self.onDocumentsPicked = onDocumentsPicked
		}

		deinit { release() }

		// Scope must stay held while presented or directoryURL is ignored.
		func defaultFolder() -> URL? {
			release()
			guard let data = UserDefaults.standard.data(forKey: FileImporterRepresentableView.defaultFolderBookmarkKey) else { return nil }
			var stale = false
			guard let url = try? URL(resolvingBookmarkData: data, bookmarkDataIsStale: &stale) else { return nil }
			if url.startAccessingSecurityScopedResource() { heldFolder = url }
			return url
		}

		private func release() {
			heldFolder?.stopAccessingSecurityScopedResource()
			heldFolder = nil
		}

		public func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
			release()
			onDocumentsPicked(urls)
		}

		public func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
			release()
			onDocumentsPicked([])
		}
	}
}
