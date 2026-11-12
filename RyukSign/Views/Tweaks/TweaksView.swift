//
//  TweaksView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

// MARK: - Tab wrapper
struct TweaksView: View {
	var body: some View {
		NBNavigationView(.localized("Tweaks")) {
			TweakLibraryList()
		}
	}
}

// MARK: - Reusable content (tab + Settings)
struct TweakLibraryList: View {
	@ObservedObject var manager = TweakManager.shared

	@State private var _isEditing = false
	@State private var _selection: Set<UUID> = []
	@State private var _query = ""
	@AppStorage("Feather.tweakSort") private var _sortRaw = ItemSortOption.dateNewest.rawValue

	// One sheet and one alert modifier: several on the same view shadow each other.
	@State private var _sheet: Sheet?
	@State private var _alert: ActiveAlert?
	@State private var _folderNameField = ""

	// Setting state while a menu or alert dismisses drops the presentation.
	private func _show(_ sheet: Sheet) { Presentation.afterDismiss { _sheet = sheet } }
	private func _show(_ alert: ActiveAlert) { Presentation.afterDismiss { _alert = alert } }

	enum Sheet: Identifiable {
		case ipaExtract(URL)
		case extractLibrary
		case move(Set<UUID>)

		var id: String {
			switch self {
			case .ipaExtract: 		return "ipaExtract"
			case .extractLibrary: 	return "extractLibrary"
			case .move: 			return "move"
			}
		}
	}

	enum ActiveAlert: Identifiable {
		case newFolder
		case renameFolder(UUID)
		case confirmImport([URL])
		case confirmDelete(Set<UUID>)

		var id: String {
			switch self {
			case .newFolder: 			return "newFolder"
			case .renameFolder(let id): return "rename-\(id)"
			case .confirmImport: 		return "confirmImport"
			case .confirmDelete: 		return "confirmDelete"
			}
		}
	}

	private var _sort: ItemSortOption { ItemSortOption(rawValue: _sortRaw) ?? .dateNewest }

	private func _matches(_ tweak: ManagedTweak) -> Bool {
		let q = _query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return true }
		return tweak.name.localizedCaseInsensitiveContains(q)
			|| (tweak.notes ?? "").localizedCaseInsensitiveContains(q)
			|| tweak.autoInjectBundleIds.contains { $0.localizedCaseInsensitiveContains(q) }
	}

	private var _allFiltered: [ManagedTweak] {
		manager.tweaks.filter(_matches).sorted(by: _sort.comparator())
	}
	private var _autoTweaks: [ManagedTweak] { _allFiltered.filter { $0.hasAutoRule && $0.folderId == nil } }
	private var _uncategorized: [ManagedTweak] { _allFiltered.filter { !$0.hasAutoRule && $0.folderId == nil } }
	private var _folders: [TweakFolder] {
		manager.folders.sorted(by: _folderComparator)
	}
	private func _folderComparator(_ a: TweakFolder, _ b: TweakFolder) -> Bool {
		switch _sort {
		case .nameAZ: 		return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
		case .nameZA: 		return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedDescending
		case .dateNewest: 	return a.dateAdded > b.dateAdded
		case .dateOldest: 	return a.dateAdded < b.dateAdded
		case .sizeLargest: 	return manager.tweakCount(inFolder: a.id) > manager.tweakCount(inFolder: b.id)
		}
	}
	private var _hasGroups: Bool {
		(!_folders.isEmpty && !_isEditing) || !_autoTweaks.isEmpty
	}
	private var _isSearching: Bool { !_query.trimmingCharacters(in: .whitespaces).isEmpty }
	private var _visibleSelectableIds: Set<UUID> {
		_isSearching
			? Set(_allFiltered.map { $0.id })
			: Set((_autoTweaks + _uncategorized).map { $0.id })
	}

	private var _navTitle: String {
		_isEditing ? String.localized("%lld Selected", arguments: _selection.count) : .localized("Tweaks")
	}

	var body: some View {
		Group {
			if manager.tweaks.isEmpty && manager.folders.isEmpty {
				_emptyState
			} else {
				NBList(_navTitle) {
					_listContent
				}
				.searchable(text: $_query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(.localized("Search tweaks")))
			}
		}
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
		.animation(.smooth, value: manager.folders)
		.animation(.smooth, value: _isEditing)
		.animation(.smooth, value: _selection)
	}

	// MARK: - Alert content

	private var _alertTitle: String {
		switch _alert {
		case .renameFolder: 	return .localized("Rename Folder")
		case .confirmImport: 	return .localized("Import Tweaks?")
		case .confirmDelete: 	return .localized("Delete Tweaks?")
		case .newFolder, .none: return .localized("New Folder")
		}
	}

	@ViewBuilder
	private var _alertButtons: some View {
		switch _alert {
		case .newFolder, .renameFolder:
			TextField(.localized("Folder Name"), text: $_folderNameField)
			Button(.localized("Cancel"), role: .cancel) {}
			Button(.localized("Save")) { _commitFolderAlert() }
		case .confirmImport(let urls):
			Button(.localized("Cancel"), role: .cancel) {}
			Button(String.localized("Import %lld", arguments: urls.count)) { _importFiles(urls) }
		case .confirmDelete(let ids):
			Button(.localized("Cancel"), role: .cancel) {}
			Button(String.localized("Delete %lld", arguments: ids.count), role: .destructive) { _performDelete(ids) }
		case .none:
			EmptyView()
		}
	}

	@ViewBuilder
	private var _alertMessage: some View {
		switch _alert {
		case .confirmImport(let urls):
			Text(verbatim: .localized("Add %lld files to your Tweak Manager?", arguments: urls.count))
		case .confirmDelete(let ids):
			Text(verbatim: .localized("This permanently removes %lld tweaks and their files.", arguments: ids.count))
		default:
			EmptyView()
		}
	}

	// MARK: - Sheets

	@ViewBuilder
	private func _sheetView(_ sheet: Sheet) -> some View {
		switch sheet {
		case .ipaExtract(let url):
			TweakIPAExtractView(ipaURL: url)
		case .extractLibrary:
			TweakAppExtractPickerView()
		case .move(let ids):
			TweakFolderPickerView(currentFolderId: nil) { target in
				manager.moveTweaks(ids, toFolder: target)
				if let folder = manager.folder(target) {
					Toast.success(.localized("Moved %lld to %@", arguments: ids.count, folder.name), systemImage: "folder.fill")
				}
				_isEditing = false
				_selection.removeAll()
			}
		}
	}

	// MARK: - Import

	private func _pickImport() {
		DocumentPicker.open([.dylib, .deb], multiple: true, folder: .tweaks) { urls in
			if urls.count >= 10 {
				_show(.confirmImport(urls))
			} else {
				_importFiles(urls)
			}
		}
	}

	private func _pickIPA() {
		DocumentPicker.open([.ipa, .tipa], folder: .apps) { urls in
			guard let url = urls.first else { return }
			_show(.ipaExtract(url))
		}
	}

	private func _importFiles(_ urls: [URL]) {
		guard !urls.isEmpty else { return }
		var addedIds: Set<UUID> = []
		for url in urls {
			if let tweak = manager.addTweak(name: url.deletingPathExtension().lastPathComponent, from: url) {
				addedIds.insert(tweak.id)
			}
		}
		if !addedIds.isEmpty {
			let message: String = addedIds.count == 1
				? String.localized("Imported %@", arguments: urls[0].lastPathComponent)
				: String.localized("Imported %lld tweaks", arguments: addedIds.count)
			Toast.success(message, systemImage: "wrench.and.screwdriver.fill")
			if !manager.folders.isEmpty {
				_show(.move(addedIds))
			}
		} else {
			Toast.error(.localized("Couldn't import tweak"), duration: .sticky)
		}
	}

	// MARK: - Folder alert

	private func _commitFolderAlert() {
		switch _alert {
		case .newFolder: 			manager.addFolder(name: _folderNameField)
		case .renameFolder(let id): manager.renameFolder(id, to: _folderNameField)
		default: 					break
		}
	}

	// MARK: - Selection actions

	private var _selectionActions: [SelectionBarAction] {
		[
			SelectionBarAction(title: .localized("Move"), systemImage: "folder", enabled: !_selection.isEmpty) {
				_show(.move(_selection))
			},
			SelectionBarAction(title: .localized("Share"), systemImage: "square.and.arrow.up", enabled: !_selection.isEmpty) {
				_shareSelection()
			},
			SelectionBarAction(title: .localized("Save"), systemImage: "arrow.down.doc", enabled: !_selection.isEmpty) {
				_saveSelection()
			},
			SelectionBarAction(title: .localized("Delete"), systemImage: "trash", role: .destructive, enabled: !_selection.isEmpty) {
				_show(.confirmDelete(_selection))
			}
		]
	}

	private func _shareSelection() {
		let urls = manager.exportableURLs(forTweakIds: _selection)
		guard !urls.isEmpty else { Toast.error(.localized("Couldn't prepare the files"), duration: .long); return }
		UIActivityViewController.show(activityItems: urls)
	}

	private func _saveSelection() {
		let urls = manager.exportableURLs(forTweakIds: _selection)
		guard !urls.isEmpty else { Toast.error(.localized("Couldn't prepare the files"), duration: .long); return }
		DocumentPicker.export(urls)
	}
}

// MARK: - Toolbar
extension TweakLibraryList {
	@ToolbarContentBuilder
	private var _toolbar: some ToolbarContent {
		if _isEditing {
			ToolbarItem(placement: .topBarLeading) {
				Button(_selection == _visibleSelectableIds ? .localized("Deselect All") : .localized("Select All")) {
					if _selection == _visibleSelectableIds {
						_selection.removeAll()
					} else {
						_selection = _visibleSelectableIds
					}
				}
			}
			// Bulk actions live in SelectionActionBar; a .bottomBar item hides behind the tab bar.
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Done")) {
					_isEditing = false
					_selection.removeAll()
				}
				.fontWeight(.semibold)
			}
		} else {
			// Kept mounted: inserting a toolbar item mid-animation drops the tap on it.
			ToolbarItem(placement: .topBarLeading) {
				Button(.localized("Select")) { _isEditing = true }
					.disabled(manager.tweaks.isEmpty)
			}
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Button {
						_pickImport()
					} label: {
						Label(.localized("Import File"), systemImage: "doc.badge.plus")
					}
					Button {
						_pickIPA()
					} label: {
						Label(.localized("Extract from IPA"), systemImage: "shippingbox")
					}
					Button {
						_show(.extractLibrary)
					} label: {
						Label(.localized("Extract from Library App"), systemImage: "square.grid.2x2")
					}
					Divider()
					Button {
						_folderNameField = ""
						_show(.newFolder)
					} label: {
						Label(.localized("New Folder"), systemImage: "folder.badge.plus")
					}
				} label: {
					Image(systemName: "plus")
				}
			}
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Picker(.localized("Sort By"), selection: $_sortRaw) {
						ForEach(ItemSortOption.allCases) { option in
							Label(option.label, systemImage: option.systemImage).tag(option.rawValue)
						}
					}
				} label: {
					Image(systemName: "line.3.horizontal.decrease")
				}
				.disabled(manager.tweaks.isEmpty)
			}
		}
	}

	private func _performDelete(_ ids: Set<UUID>) {
		// Leaving edit mode before the batch delete avoids a list diff crash.
		_selection.removeAll()
		_isEditing = false
		manager.deleteTweaks(ids)
	}

	private func _exportable(_ tweak: ManagedTweak) -> URL? {
		guard let version = tweak.activeVersion else {
			Toast.error(.localized("This tweak has no versions"), duration: .long)
			return nil
		}
		guard let url = manager.exportableURL(for: tweak, version: version) else {
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
		DocumentPicker.export([url])
	}

	// MARK: - Folder export

	private func _folderExportURL(_ folderId: UUID) -> URL? {
		guard let url = manager.exportFolder(folderId) else {
			Toast.error(.localized("This folder is empty"), duration: .long)
			return nil
		}
		return url
	}

	private func _shareFolder(_ folderId: UUID) {
		guard let url = _folderExportURL(folderId) else { return }
		UIActivityViewController.show(activityItems: [url])
	}

	private func _saveFolder(_ folderId: UUID) {
		guard let url = _folderExportURL(folderId) else { return }
		DocumentPicker.export([url])
	}
}

// MARK: - Rows / empty
extension TweakLibraryList {
	@ViewBuilder
	private var _emptyState: some View {
		NBContentUnavailable(
			.localized("No Tweaks"),
			systemImage: "wrench.and.screwdriver",
			description: .localized("Import a .dylib or .deb, or send one over from Web Manager in Settings.")
		) {
			Button {
				_pickImport()
			} label: {
				Label(.localized("Import Tweak"), systemImage: "plus")
			}
		}
	}

	@ViewBuilder
	private func _row(for tweak: ManagedTweak) -> some View {
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
				onMove: { _show(.move([tweak.id])) },
				onDelete: { manager.deleteTweak(tweak.id) }
			)
		}
	}

	// MARK: List content

	@ViewBuilder
	var _listContent: some View {
		if _isSearching {
			NBSection(.localized("Results"), secondary: "\(_allFiltered.count)") {
				ForEach(_allFiltered) { _row(for: $0) }
				if _allFiltered.isEmpty {
					Text(verbatim: .localized("No matches."))
						.font(.footnote)
						.foregroundColor(.disabled())
				}
			}
		} else {
			if !_folders.isEmpty && !_isEditing {
				NBSection(.localized("Folders"), secondary: "\(_folders.count)") {
					ForEach(_folders) { _folderRow($0) }
				}
			}

			if !_autoTweaks.isEmpty {
				NBSection(.localized("Auto-Inject"), secondary: "\(_autoTweaks.count)") {
					ForEach(_autoTweaks) { _row(for: $0) }
				} footer: {
					Text(.localized("These inject automatically when you sign matching apps."))
				}
			}

			if _hasGroups {
				if !_uncategorized.isEmpty {
					NBSection(.localized("Other"), secondary: "\(_uncategorized.count)") {
						ForEach(_uncategorized) { _row(for: $0) }
					}
				}
			} else {
				NBSection(.localized("Library"), secondary: "\(_uncategorized.count)") {
					ForEach(_uncategorized) { _row(for: $0) }
				} footer: {
					Text(.localized("Tap a tweak to choose when and where it injects."))
				}
			}
		}
	}

	@ViewBuilder
	private func _folderRow(_ folder: TweakFolder) -> some View {
		NavigationLink {
			TweakFolderView(folderId: folder.id)
		} label: {
			HStack(spacing: 12) {
				Image(systemName: "folder.fill")
					.font(.system(size: 17))
					.foregroundStyle(.tint)
					.frame(width: 30)
				Text(folder.name)
					.foregroundStyle(.primary)
					.lineLimit(1)
				Spacer()
				Text(verbatim: "\(manager.tweakCount(inFolder: folder.id))")
					.font(.caption)
					.foregroundStyle(Color.primary.opacity(0.6))
			}
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: false) {
			Button(role: .destructive) {
				manager.deleteFolder(folder.id)
			} label: {
				Label(.localized("Delete"), systemImage: "trash")
			}
			Button {
				_folderNameField = folder.name
				_show(.renameFolder(folder.id))
			} label: {
				Label(.localized("Rename"), systemImage: "pencil")
			}
			.tint(.gray)
		}
		.contextMenu {
			Button { _shareFolder(folder.id) } label: {
				Label(.localized("Share Folder"), systemImage: "square.and.arrow.up")
			}
			Button { _saveFolder(folder.id) } label: {
				Label(.localized("Save Folder to Files"), systemImage: "arrow.down.doc")
			}
			Button {
				_folderNameField = folder.name
				_show(.renameFolder(folder.id))
			} label: {
				Label(.localized("Rename"), systemImage: "pencil")
			}
			Divider()
			Button(role: .destructive) {
				manager.deleteFolder(folder.id)
			} label: {
				Label(.localized("Delete Folder"), systemImage: "trash")
			}
		}
	}
}
