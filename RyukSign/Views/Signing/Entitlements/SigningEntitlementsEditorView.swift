//
//  SigningEntitlementsEditorView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - Value kind

enum EntitlementValueKind: String, CaseIterable, Identifiable {
	case string
	case boolean
	case stringList

	var id: String { rawValue }

	var title: String {
		switch self {
		case .string: .localized("String")
		case .boolean: .localized("Boolean")
		case .stringList: .localized("String List")
		}
	}

	/// Order matters: plist booleans bridge through NSNumber too, so Bool must be checked first.
	static func kind(for value: Any) -> EntitlementValueKind? {
		switch value {
		case is Bool: return .boolean
		case is String: return .string
		case let array as [Any] where array.allSatisfy({ $0 is String }): return .stringList
		default: return nil
		}
	}
}

// MARK: - View
struct SigningEntitlementsEditorView: View {
	let entry: EntitlementsFile
	var certificate: CertificatePair? = nil

	@ObservedObject private var _manager = EntitlementsManager.shared
	@ObservedObject private var _clipboard = EntitlementsClipboard.shared

	@State private var _dict: [String: Any] = [:]
	@State private var _hasLoaded = false
	@State private var _query = ""
	@State private var _isAddingPresenting = false
	@State private var _isImportMergePresenting = false
	@State private var _editMode: EditMode = .inactive
	@State private var _selectedKeys: Set<String> = []
	@State private var _flaggedOnly = false
	@State private var _detailKey: String? = nil

	private var _grantedEntitlements: [String: Any]? {
		EntitlementsDiff.grantedEntitlements(for: certificate)
	}

	private var _flaggedCount: Int {
		EntitlementsDiff.flaggedCount(in: _dict, against: _grantedEntitlements)
	}

	/// Keys whose value differs from the certificate's — the only ones "Reset" has something to reset to.
	private var _mismatchedKeys: [String] {
		guard let granted = _grantedEntitlements else { return [] }
		return _dict.keys.filter { EntitlementsDiff.match(key: $0, value: _dict[$0]!, against: granted) == .valueMismatch }
	}

	private var _detailMatch: EntitlementsDiff.Match? {
		guard let _detailKey, let value = _dict[_detailKey], let granted = _grantedEntitlements else { return nil }
		return EntitlementsDiff.match(key: _detailKey, value: value, against: granted)
	}

	private var _keys: [String] {
		var all = _dict.keys.sorted()
		// `_flaggedCount > 0` guard: without it, resetting the last mismatch while filtered
		// leaves the toggle on with nothing left to show and no indication why.
		if _flaggedOnly, _flaggedCount > 0, let granted = _grantedEntitlements {
			all = all.filter { EntitlementsDiff.match(key: $0, value: _dict[$0]!, against: granted) != .granted }
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
		.toolbar {
			_toolbar
		}
		.environment(\.editMode, $_editMode)
		.navigationDestination(isPresented: $_isAddingPresenting) {
			SigningEntitlementsEntryEditView(
				originalKey: nil,
				kind: .string,
				value: "",
				grantedEntitlements: _grantedEntitlements
			) { key, value in
				_dict[key] = value
				_save()
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
			if _detailMatch == .valueMismatch, let key = _detailKey {
				Button(.localized("Reset to Certificate Value")) {
					_resetToCertificateValue(key)
				}
			}
			Button(.localized("Cancel"), role: .cancel) {}
		} message: {
			Text(_detailMatch == .notGranted
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
			ToolbarItem(placement: .topBarTrailing) {
				Button(.localized("Copy")) {
					_clipboard.set(_dict.filter { _selectedKeys.contains($0.key) })
					_toggleSelectMode()
				}
				.disabled(_selectedKeys.isEmpty)
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
	private var _addMenu: some View {
		Button(.localized("Add Entry"), systemImage: "plus") {
			_isAddingPresenting = true
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
		if !_mismatchedKeys.isEmpty {
			Button(.localized("Reset All Mismatched"), systemImage: "arrow.triangle.2.circlepath") {
				_resetAllMismatched()
			}
		}
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
		guard let value = _grantedEntitlements?[key] else { return }
		_dict[key] = value
		_save()
	}

	private func _resetAllMismatched() {
		guard let granted = _grantedEntitlements else { return }
		for key in _mismatchedKeys {
			_dict[key] = granted[key]
		}
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
				_label(key: key, value: value)
			}
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func _editableRow(key: String, value: Any) -> some View {
		Group {
			if let kind = EntitlementValueKind.kind(for: value) {
				HStack {
					NavigationLink {
						SigningEntitlementsEntryEditView(
							originalKey: key,
							kind: kind,
							value: value,
							grantedEntitlements: _grantedEntitlements
						) { newKey, newValue in
							if newKey != key { _dict.removeValue(forKey: key) }
							_dict[newKey] = newValue
							_save()
						}
					} label: {
						_label(key: key, value: value)
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

	@ViewBuilder
	private func _label(key: String, value: Any) -> some View {
		HStack {
			Text(key)
			Spacer()
			Text(_preview(value))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}

	/// A sibling of the row's NavigationLink, never nested in its label — nested buttons there don't reliably receive taps.
	@ViewBuilder
	private func _matchButton(key: String, value: Any) -> some View {
		if let granted = _grantedEntitlements {
			let match = EntitlementsDiff.match(key: key, value: value, against: granted)
			if match != .granted {
				Button {
					_detailKey = key
				} label: {
					Image(systemName: match == .notGranted ? "exclamationmark.triangle.fill" : "arrow.triangle.2.circlepath.circle.fill")
						.foregroundStyle(match == .notGranted ? .orange : .blue)
				}
				.buttonStyle(.plain)
			}
		}
	}

	private func _preview(_ value: Any) -> String {
		switch value {
		case let bool as Bool: return bool ? "✓" : "✗"
		case let string as String: return string
		case let array as [String]: return array.joined(separator: ", ")
		default: return ""
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
