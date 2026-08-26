//
//  DylibToggleView.swift
//  RyukSign
//
//  Created by samara on 20.04.2025.
//


import SwiftUI
import UIKit

struct SigningToggleCellView<T>: View {
	let title: String
	@Binding var options: T?
	let arrayKeyPath: WritableKeyPath<T, [String]>
	/// When set and the file still exists, the row offers Send to Tweak Manager / Share.
	var fileURL: URL? = nil

	var body: some View {
		Toggle(title, isOn: Binding(
			get: {
				guard let options = options else { return false }
				return !options[keyPath: arrayKeyPath].contains(title)
			},
			set: { isOn in
				if isOn {
					_removeItem()
				} else {
					_addItem()
				}
			}
		))
		.contextMenu {
			if _exportableURL != nil { _exportActions }
		}
		.swipeActions(edge: .trailing) {
			if _exportableURL != nil { _exportActions }
		}
	}

	private var _exportableURL: URL? {
		guard let fileURL, FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
		return fileURL
	}

	@ViewBuilder
	private var _exportActions: some View {
		Button {
			guard let fileURL = _exportableURL else { return }
			TweakManager.shared.addTweak(name: fileURL.lastPathComponent, from: fileURL)
			Toast.info(.localized("Added to Tweak Manager"))
		} label: {
			Label(.localized("Send to Tweak Manager"), systemImage: "wrench.and.screwdriver")
		}
		Button {
			guard let fileURL = _exportableURL, let shareURL = FileExporter.shareableURL(for: fileURL) else { return }
			UIActivityViewController.show(activityItems: [shareURL])
		} label: {
			Label(.localized("Share"), systemImage: "square.and.arrow.up")
		}
	}

	private func _removeItem() {
		guard var opts = options else { return }
		opts[keyPath: arrayKeyPath].removeAll { $0 == title }
		options = opts
	}
	
	private func _addItem() {
		guard var opts = options else { return }
		if !opts[keyPath: arrayKeyPath].contains(title) {
			opts[keyPath: arrayKeyPath].append(title)
		}
		options = opts
	}
}
