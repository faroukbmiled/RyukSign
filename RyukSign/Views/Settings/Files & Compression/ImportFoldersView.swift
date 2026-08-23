//
//  ImportFoldersView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct ImportFoldersView: View {
	@State private var _picking: ImportFolder?
	@State private var _names: [ImportFolder: String] = [:]

	// MARK: Body
	var body: some View {
		NBList(.localized("Import Folders")) {
			Section {
				ForEach(ImportFolder.allCases) { folder in
					ImportFolderCellView(folder: folder, name: _names[folder]) {
						_picking = folder
					} onClear: {
						folder.clear()
						_reload()
					}
				}
			} footer: {
				Text(.localized("Give a type its own folder and its picker always opens there. Anything left unset reopens wherever you last browsed, which iOS shares across every picker. Swipe a row to clear it."))
			}

			if !_names.isEmpty {
				Section {
					Button(role: .destructive) {
						ImportFolder.allCases.forEach { $0.clear() }
						_reload()
					} label: {
						Label(.localized("Clear All Folders"), systemImage: "xmark.circle")
					}
				} footer: {
					Text(.localized("Puts every type back to reopening where you last browsed."))
				}
			}
		}
		.animation(.default, value: _names.isEmpty)
		.onAppear(perform: _reload)
		.sheet(item: $_picking) { folder in
			ImportFolderPickerView(folder: folder) { name in
				if let name { _names[folder] = name }
				_picking = nil
			}
			.ignoresSafeArea()
		}
	}

	private func _reload() {
		_names = ImportFolder.allCases.reduce(into: [:]) { names, folder in
			names[folder] = folder.folderName
		}
	}
}

// MARK: - View (cell)
private struct ImportFolderCellView: View {
	let folder: ImportFolder
	let name: String?
	let onSelect: () -> Void
	let onClear: () -> Void

	// MARK: Body
	var body: some View {
		Button(action: onSelect) {
			HStack {
				Label(folder.title, systemImage: folder.icon)
				Spacer()
				Text(name ?? .localized("Last Used"))
					.foregroundStyle(.secondary)
					.lineLimit(1)
					.truncationMode(.middle)
			}
		}
		.swipeActions(edge: .trailing) {
			if name != nil {
				Button(role: .destructive, action: onClear) {
					Label(.localized("Clear"), systemImage: "xmark.circle")
				}
			}
		}
	}
}
