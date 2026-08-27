//
//  SigningEntitlementsEditorView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningEntitlementsEditorView: View {
	let entry: EntitlementsFile
	var certificate: CertificatePair? = nil

	@ObservedObject private var _manager = EntitlementsManager.shared
	@ObservedObject private var _clipboard = PlistClipboard.shared

	@State private var _dict: [String: Any] = [:]
	@State private var _hasLoaded = false
	@State private var _query = ""
	@State private var _isAddingPresenting = false
	@State private var _addKind: PlistValueKind = .string
	@State private var _showsRaw = false
	@State private var _isImportMergePresenting = false
	@State private var _editMode: EditMode = .inactive
	@State private var _selectedKeys: Set<String> = []
	@State private var _flaggedOnly = false
	@State private var _detailKey: String? = nil

	private var _grantedEntitlements: [String: Any]? {
		PlistDiff.grantedEntitlements(for: certificate)
	}

	private var _reference: PlistEntryReference? {
		guard let granted = _grantedEntitlements else { return nil }
		return PlistEntryReference(
			values: granted,
			missingNote: .localized("Not granted by the selected certificate's provisioning profile"),
			mismatchNote: .localized("Value differs from the selected certificate's provisioning profile"),
			resetTitle: .localized("Reset to Certificate Value")
		)
	}

	private var _flaggedCount: Int {
		PlistDiff.flaggedCount(in: _dict, against: _grantedEntitlements)
	}

	/// Keys whose value differs from the certificate's — the only ones "Reset" has something to reset to.
	private var _mismatchedKeys: [String] {
		guard let granted = _grantedEntitlements else { return [] }
		return _dict.keys.filter { PlistDiff.match(key: $0, value: _dict[$0]!, against: granted) == .differs }
	}

	private var _detailMatch: PlistDiff.Match? {
		guard let _detailKey, let value = _dict[_detailKey], let granted = _grantedEntitlements else { return nil }
		return PlistDiff.match(key: _detailKey, value: value, against: granted)
	}

	private var _keys: [String] {
		var all = _dict.keys.sorted()
		// `_flaggedCount > 0` guard: without it, resetting the last mismatch while filtered
		// leaves the toggle on with nothing left to show and no indication why.
		if _flaggedOnly, _flaggedCount > 0, let granted = _grantedEntitlements {
			all = all.filter { PlistDiff.match(key: $0, value: _dict[$0]!, against: granted) != .matches }
		}
		guard !_query.isEmpty else { return all }
		return all.filter { $0.localizedCaseInsensitiveContains(_query) }
	}

	private var _otherFiles: [EntitlementsFile] {
		_manager.files.filter { $0.id != entry.id }
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Entries")) {
			ForEach(_keys, id: \.self) { key in
				_row(for: key)
			}
		}
		.searchable(
			text: $_query,
			placement: .navigationBarDrawer(displayMode: .automatic),
			prompt: Text(.localized("Search Entitlements"))
		)
		.dismissableKeyboard()
		.toolbar {
			_toolbar
		}
		.environment(\.editMode, $_editMode)
		.navigationDestination(isPresented: $_isAddingPresenting) {
			if _showsRaw {
				PlistRawEditorView(dict: _dict) { dict in
					_dict = dict
					_save()
				}
			} else {
				PlistEntryEditView(
					originalKey: nil,
					kind: _addKind,
					value: _addKind.emptyValue,
					reference: _reference
				) { key, value in
					_dict[key] = value
					_save()
				}
			}
		}
		.sheet(isPresented: $_isImportMergePresenting) {
			FileImporterRepresentableView(
				allowedContentTypes: [.xmlPropertyList, .plist, .entitlements, .mobileProvision, .json],
				folder: .entitlements,
				onDocumentsPicked: { urls in
					guard let url = urls.first else { return }
					_importMerge(from: url)
				}
			)
			.ignoresSafeArea()
		}
		.confirmationDialog(
			_detailKey ?? "",
			isPresented: Binding(get: { _detailKey != nil }, set: { if !$0 { _detailKey = nil } }),
			titleVisibility: .visible
		) {
			if _detailMatch == .differs, let key = _detailKey {
				Button(.localized("Reset to Certificate Value")) {
					_resetToCertificateValue(key)
				}
			}
			Button(.localized("Cancel"), role: .cancel) {}
		} message: {
			Text(_detailMatch == .missing
				? .localized("Not granted by the selected certificate's provisioning profile")
				: .localized("Value differs from the selected certificate's provisioning profile"))
		}
		.onAppear(perform: _load)
	}
}

// MARK: - Extension: Toolbar
extension SigningEntitlementsEditorView {
	@ToolbarContentBuilder
	private var _toolbar: some ToolbarContent {
		ToolbarItem(placement: .topBarLeading) {
			Button(_editMode.isEditing ? .localized("Done") : .localized("Select")) {
				_toggleSelectMode()
			}
		}
		if _editMode.isEditing {
			NBToolbarMenu(
				systemImage: "ellipsis.circle",
				style: .icon,
				placement: .topBarTrailing
			) {
				_selectionActions
			}
		} else {
			ToolbarItem(placement: .topBarTrailing) {
				Button {
					_flaggedOnly.toggle()
				} label: {
					Image(systemName: "line.3.horizontal.decrease")
						.foregroundStyle(_flaggedCount == 0 ? Color.secondary : (_flaggedOnly ? Color.accentColor : Color.primary))
				}
				.disabled(_flaggedCount == 0)
			}
			NBToolbarMenu(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing
			) {
				_addMenu
			}
		}
	}

	@ViewBuilder
	private var _selectionActions: some View {
		Button(.localized("Copy"), systemImage: "doc.on.doc") {
			_clipboard.set(_dict.filter { _selectedKeys.contains($0.key) })
			_toggleSelectMode()
		}
		.disabled(_selectedKeys.isEmpty)

		Button(.localized("Reset to Certificate Value"), systemImage: "arrow.uturn.backward") {
			_resetToCertificateValues(_selectedKeys)
			_toggleSelectMode()
		}
		.disabled(_selectedKeys.isDisjoint(with: _mismatchedKeys))

		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			_delete(_selectedKeys)
			_toggleSelectMode()
		}
		.disabled(_selectedKeys.isEmpty)

		Divider()

		Button(.localized("Select All"), systemImage: "checkmark.circle") {
			_selectedKeys = Set(_keys)
		}
		Button(.localized("Deselect All"), systemImage: "circle") {
			_selectedKeys.removeAll()
		}
		.disabled(_selectedKeys.isEmpty)
	}

	@ViewBuilder
	private var _addMenu: some View {
		Button(.localized("Add Entry"), systemImage: "plus") {
			_present(.string)
		}
		Button(.localized("Add Dictionary"), systemImage: "curlybraces") {
			_present(.dictionary)
		}
		Button(.localized("Add Array"), systemImage: "list.bullet") {
			_present(.array)
		}
		if !_otherFiles.isEmpty {
			Menu(.localized("Merge From Library")) {
				ForEach(_otherFiles) { other in
					Button(other.name) {
						_merge(_manager.load(other))
					}
				}
			}
		}
		Button(.localized("Import File"), systemImage: "square.and.arrow.down") {
			_isImportMergePresenting = true
		}
		if !_clipboard.entries.isEmpty {
			Button(.localized("Paste"), systemImage: "doc.on.clipboard") {
				_merge(_clipboard.entries)
			}
		}
		Divider()

		Button(.localized("Edit Raw"), systemImage: "chevron.left.forwardslash.chevron.right") {
			_showsRaw = true
			_isAddingPresenting = true
		}

		if !_mismatchedKeys.isEmpty {
			Button(.localized("Reset All Mismatched"), systemImage: "arrow.triangle.2.circlepath") {
				_resetAllMismatched()
			}
		}
	}

	private func _present(_ kind: PlistValueKind) {
		_showsRaw = false
		_addKind = kind
		_isAddingPresenting = true
	}

	private func _toggleSelectMode() {
		withAnimation {
			_editMode = _editMode.isEditing ? .inactive : .active
			if !_editMode.isEditing { _selectedKeys.removeAll() }
		}
	}

	private func _merge(_ incoming: [String: Any]) {
		guard !incoming.isEmpty else { return }
		_dict.merge(incoming) { _, incomingValue in incomingValue }
		_save()
	}

	private func _importMerge(from url: URL) {
		guard let dict = EntitlementsManager.parseEntitlements(from: url) else {
			Toast.error(.localized("Couldn't read entitlements from that file"))
			return
		}
		_merge(dict)
	}

	private func _resetToCertificateValue(_ key: String) {
		_resetToCertificateValues([key])
	}

	private func _resetAllMismatched() {
		_resetToCertificateValues(Set(_mismatchedKeys))
	}

	private func _resetToCertificateValues(_ keys: Set<String>) {
		guard let granted = _grantedEntitlements else { return }
		for key in keys where granted[key] != nil {
			_dict[key] = granted[key]
		}
		_save()
	}

	private func _delete(_ keys: Set<String>) {
		keys.forEach { _dict.removeValue(forKey: $0) }
		_save()
	}
}

// MARK: - Extension: Rows
extension SigningEntitlementsEditorView {
	@ViewBuilder
	private func _row(for key: String) -> some View {
		if let value = _dict[key] {
			if _editMode.isEditing {
				_selectableRow(key: key, value: value)
			} else {
				_editableRow(key: key, value: value)
			}
		}
	}

	@ViewBuilder
	private func _selectableRow(key: String, value: Any) -> some View {
		let isSelected = _selectedKeys.contains(key)

		Button {
			if isSelected { _selectedKeys.remove(key) } else { _selectedKeys.insert(key) }
		} label: {
			HStack {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isSelected ? Color.accentColor : .secondary)
				PlistValueRow(key: key, value: value)
			}
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func _editableRow(key: String, value: Any) -> some View {
		Group {
			if let kind = PlistValueKind.kind(for: value) {
				HStack {
					NavigationLink {
						if kind.isContainer {
							PlistNodeView(title: key, value: value) { newValue in
								_dict[key] = newValue
								_save()
							}
						} else {
							PlistEntryEditView(
								originalKey: key,
								kind: kind,
								value: value,
								reference: _reference
							) { newKey, newValue in
								if newKey != key { _dict.removeValue(forKey: key) }
								_dict[newKey] = newValue
								_save()
							}
						}
					} label: {
						PlistValueRow(key: key, value: value)
					}
					_matchButton(key: key, value: value)
				}
			} else {
				CertificatesInfoEntitlementCellView(key: key, value: value)
			}
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive) {
				_dict.removeValue(forKey: key)
				_save()
			} label: {
				Label(.localized("Delete"), systemImage: "trash")
			}
		}
	}

	/// A sibling of the row's NavigationLink, never nested in its label — nested buttons there don't reliably receive taps.
	@ViewBuilder
	private func _matchButton(key: String, value: Any) -> some View {
		if let granted = _grantedEntitlements {
			let match = PlistDiff.match(key: key, value: value, against: granted)
			if match != .matches {
				Button {
					_detailKey = key
				} label: {
					Image(systemName: match == .missing ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath.circle.fill")
						.foregroundStyle(match == .missing ? .orange : .blue)
				}
				.buttonStyle(.plain)
			}
		}
	}
}

// MARK: - Extension: Persistence
extension SigningEntitlementsEditorView {
	private func _load() {
		guard !_hasLoaded else { return }
		_dict = _manager.load(entry)
		_hasLoaded = true
	}

	private func _save() {
		_manager.save(entry, dict: _dict)
	}
}
