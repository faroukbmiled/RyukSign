//
//  TweakFolderView.swift
//  RyukSign
//
//  Contents of a single tweak folder: the same rows/actions as the library tab,
//  scoped to one folder, with multi-select, search + sort and folder management.
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

struct TweakFolderView: View {
	@Environment(\.dismiss) private var dismiss
	@ObservedObject var manager = TweakManager.shared

	let folderId: UUID

	@State private var _query = ""
	@AppStorage("Feather.tweakSort") private var _sortRaw = ItemSortOption.dateNewest.rawValue
	@State private var _isEditing = false
	@State private var _selection: Set<UUID> = []
	@State private var _sheet: Sheet?
	@State private var _alert: FolderAlert?
	@State private var _renameText = ""

	enum Sheet: Identifiable {
		case export([URL])
		case move(Set<UUID>)
		var id: String { if case .export = self { return "export" } else { return "move" } }
	}

	enum FolderAlert: Identifiable {
		case rename
		case confirmDelete(Set<UUID>)
		var id: String { if case .confirmDelete = self { return "delete" } else { return "rename" } }
	}

	private var _sort: ItemSortOption { ItemSortOption(rawValue: _sortRaw) ?? .dateNewest }
	private var _folderName: String { manager.folder(folderId)?.name ?? .localized("Folder") }
	private var _navTitle: String {
		_isEditing ? String.localized("%lld Selected", arguments: _selection.count) : _folderName
	}

	private func _matches(_ tweak: ManagedTweak) -> Bool {
		let q = _query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return true }
		return tweak.name.localizedCaseInsensitiveContains(q)
			|| (tweak.notes ?? "").localizedCaseInsensitiveContains(q)
			|| tweak.autoInjectBundleIds.contains { $0.localizedCaseInsensitiveContains(q) }
	}

	private var _tweaks: [ManagedTweak] {
		manager.tweaks(inFolder: folderId).filter(_matches).sorted(by: _sort.comparator())
	}
	private var _allIds: Set<UUID> { Set(manager.tweaks(inFolder: folderId).map { $0.id }) }

	var body: some View {
		Group {
			if manager.folder(folderId) == nil {
				Color.clear.onAppear { dismiss() }	// folder deleted while open
			} else if manager.tweakCount(inFolder: folderId) == 0 {
				NBContentUnavailable(
					.localized("Empty Folder"),
					systemImage: "folder",
					description: .localized("Move tweaks here from the library, or with “Move to Folder”.")
				)
			} else {
				NBList(_navTitle) {
					NBSection(.localized("Tweaks"), secondary: "\(_tweaks.count)") {
						ForEach(_tweaks) { _row($0) }
						if _tweaks.isEmpty {
							Text(verbatim: .localized("No matches."))
								.font(.footnote)
								.foregroundColor(.disabled())
						}
					}
				}
				.searchable(text: $_query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search tweaks")))
			}
		}
		.navigationTitle(_navTitle)
		.toolbar { _toolbar }
		.selectionActionBar(isActive: _isEditing, actions: _selectionActions)
		.sheet(item: $_sheet) { sheet in _sheetView(sheet) }
		.alert(
			_alertTitle,
			isPresented: Binding(get: { _alert != nil }, set: { if !$0 { _alert = nil } })
		) {
			_alertButtons
		} message: {
			_alertMessage
		}
		.animation(.smooth, value: manager.tweaks)
		.animation(.smooth, value: _isEditing)
		.animation(.smooth, value: _selection)
	}

	private var _alertTitle: String {
		if case .confirmDelete = _alert { return .localized("Delete Tweaks?") }
		return .localized("Rename Folder")
	}

	@ViewBuilder
	private var _alertButtons: some View {
		switch _alert {
		case .rename, .none:
			TextField(.localized("Folder Name"), text: $_renameText)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Save")) { manager.renameFolder(folderId, to: _renameText) }
		case .confirmDelete(let ids):
			Button(.localized("Cancel"), role: .cancel) {}
			Button(String.localized("Delete %lld", arguments: ids.count), role: .destructive) {
				_selection.removeAll()
				_isEditing = false
				manager.deleteTweaks(ids)
			}
		}
	}

	@ViewBuilder
	private var _alertMessage: some View {
		if case .confirmDelete(let ids) = _alert {
			Text(verbatim: .localized("This permanently removes %lld tweaks and their files.", arguments: ids.count))
		}
	}

	// MARK: Toolbar

	@ToolbarContentBuilder
	private var _toolbar: some ToolbarContent {
		if _isEditing {
			ToolbarItem(placement: .topBarLeading) {
				Button(_selection == _allIds ? .localized("Deselect All") : .localized("Select All")) {
					_selection = (_selection == _allIds) ? [] : _allIds
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Done")) { _isEditing = false; _selection.removeAll() }
					.fontWeight(.semibold)
			}
		} else {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					if manager.tweakCount(inFolder: folderId) > 0 {
						Button(.localized("Select")) { _isEditing = true }
					}
					Picker(.localized("Sort By"), selection: $_sortRaw) {
						ForEach(ItemSortOption.allCases) { option in
							Label(option.label, systemImage: option.systemImage).tag(option.rawValue)
						}
					}
					Divider()
					Button { _shareFolder() } label: { Label(.localized("Share Folder"), systemImage: "square.and.arrow.up") }
					Button { _saveFolder() } label: { Label(.localized("Save Folder to Files"), systemImage: "arrow.down.doc") }
					Button {
						_renameText = _folderName
						_alert = .rename
					} label: { Label(.localized("Rename Folder"), systemImage: "pencil") }
					Button(role: .destructive) {
						manager.deleteFolder(folderId)
						dismiss()
					} label: { Label(.localized("Delete Folder"), systemImage: "trash") }
				} label: {
					Image(systemName: "ellipsis.circle")
				}
			}
		}
	}

	// MARK: Rows

	@ViewBuilder
	private func _row(_ tweak: ManagedTweak) -> some View {
		if _isEditing {
			Button {
				if _selection.contains(tweak.id) { _selection.remove(tweak.id) }
				else { _selection.insert(tweak.id) }
			} label: {
				HStack(spacing: 12) {
					Image(systemName: _selection.contains(tweak.id) ? "checkmark.circle.fill" : "circle")
						.foregroundStyle(_selection.contains(tweak.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
					TweakRowLabel(tweak: tweak)
				}
			}
		} else {
			TweakLibraryRow(
				tweak: tweak,
				onShare: { _share(tweak) },
				onExport: { _exportToFiles(tweak) },
				onMove: { _sheet = .move([tweak.id]) },
				onDelete: { manager.deleteTweak(tweak.id) }
			)
		}
	}

	// MARK: Sheets

	@ViewBuilder
	private func _sheetView(_ sheet: Sheet) -> some View {
		switch sheet {
		case .export(let urls):
			DocumentExporterView(urls: urls).ignoresSafeArea()
		case .move(let ids):
			TweakFolderPickerView(currentFolderId: folderId) { target in
				manager.moveTweaks(ids, toFolder: target)
				_isEditing = false
				_selection.removeAll()
			}
		}
	}

	// MARK: Selection actions

	private var _selectionActions: [SelectionBarAction] {
		[
			SelectionBarAction(title: .localized("Move"), systemImage: "folder", enabled: !_selection.isEmpty) {
				_sheet = .move(_selection)
			},
			SelectionBarAction(title: .localized("Share"), systemImage: "square.and.arrow.up", enabled: !_selection.isEmpty) {
				let urls = manager.exportableURLs(forTweakIds: _selection)
				if urls.isEmpty { Toast.error(.localized("Couldn't prepare the files"), duration: .long) }
				else { UIActivityViewController.show(activityItems: urls) }
			},
			SelectionBarAction(title: .localized("Save"), systemImage: "arrow.down.doc", enabled: !_selection.isEmpty) {
				let urls = manager.exportableURLs(forTweakIds: _selection)
				if urls.isEmpty { Toast.error(.localized("Couldn't prepare the files"), duration: .long) }
				else { _sheet = .export(urls) }
			},
			SelectionBarAction(title: .localized("Delete"), systemImage: "trash", role: .destructive, enabled: !_selection.isEmpty) {
				_alert = .confirmDelete(_selection)
			}
		]
	}

	// MARK: Export helpers

	private func _exportable(_ tweak: ManagedTweak) -> URL? {
		guard let version = tweak.activeVersion,
			  let url = manager.exportableURL(for: tweak, version: version) else {
			Toast.error(.localized("Couldn't prepare the file"), duration: .long)
			return nil
		}
		return url
	}

	private func _share(_ tweak: ManagedTweak) {
		guard let url = _exportable(tweak) else { return }
		UIActivityViewController.show(activityItems: [url])
	}

	private func _exportToFiles(_ tweak: ManagedTweak) {
		guard let url = _exportable(tweak) else { return }
		_sheet = .export([url])
	}

	private func _shareFolder() {
		guard let url = manager.exportFolder(folderId) else {
			Toast.error(.localized("This folder is empty"), duration: .long); return
		}
		UIActivityViewController.show(activityItems: [url])
	}

	private func _saveFolder() {
		guard let url = manager.exportFolder(folderId) else {
			Toast.error(.localized("This folder is empty"), duration: .long); return
		}
		_sheet = .export([url])
	}
}
