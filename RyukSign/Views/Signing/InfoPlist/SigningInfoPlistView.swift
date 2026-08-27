//
//  SigningInfoPlistView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningInfoPlistView: View {
	let app: AppInfoPresentable
	@Binding var options: Options

	@ObservedObject private var _clipboard = PlistClipboard.shared

	@State private var _original: [String: Any] = [:]
	@State private var _hasLoaded = false
	@State private var _query = ""
	@State private var _changedOnly = false
	@State private var _editMode: EditMode = .inactive
	@State private var _selectedKeys: Set<String> = []
	@State private var _draftKey = ""
	@State private var _draftValue: Any = ""
	@State private var _draftKind: PlistValueKind = .string
	@State private var _showsRaw = false
	@State private var _isDraftPresenting = false

	private var _reference: PlistEntryReference {
		PlistEntryReference(
			values: _original,
			missingNote: .localized("Not in the app's original Info.plist"),
			mismatchNote: .localized("Differs from the app's original value"),
			resetTitle: .localized("Reset to Original Value")
		)
	}

	// MARK: Body
	var body: some View {
		// Reading the overrides parses a plist blob, so the whole screen renders off one snapshot.
		let merged = MergedInfoPlist(original: _original, options: options)

		NBList(.localized("Info.plist")) {
			Section {
				NavigationLink {
					SigningInfoPlistBackgroundModesView(options: $options, original: _original)
				} label: {
					Text(.localized("Background Modes"))
				}
				.badge(merged.backgroundModes.count)
			} footer: {
				Text(.localized("These changes are written into the app's Info.plist before it is signed. Editing keys the app relies on can stop it from launching."))
			}

			Section {
				ForEach(_keys(in: merged), id: \.self) { key in
					_row(for: key, in: merged)
				}
			}
		}
		.searchable(
			text: $_query,
			placement: .navigationBarDrawer(displayMode: .automatic),
			prompt: Text(.localized("Search Keys"))
		)
		.dismissableKeyboard()
		.toolbar {
			_toolbar(for: merged)
		}
		.environment(\.editMode, $_editMode)
		.navigationDestination(isPresented: $_isDraftPresenting) {
			if _showsRaw {
				PlistRawEditorView(dict: merged.effective) { _applyRaw($0, in: merged) }
			} else {
				PlistEntryEditView(
					originalKey: _draftKey.isEmpty ? nil : _draftKey,
					kind: _draftKind,
					value: _draftValue,
					reference: _reference
				) { key, value in
					_set(value, for: key, replacing: nil)
				}
			}
		}
		.onAppear(perform: _load)
	}

	private func _keys(in merged: MergedInfoPlist) -> [String] {
		var keys = merged.keys
		if _changedOnly { keys = keys.filter { merged.status(for: $0) != .original } }
		guard !_query.isEmpty else { return keys }
		return keys.filter { $0.localizedCaseInsensitiveContains(_query) }
	}
}

// MARK: - Extension: Status
private extension MergedInfoPlist.Status {
	var note: String? {
		switch self {
		case .original: nil
		case .managed: .localized("RyukSign will set this")
		case .overridden: .localized("Custom value")
		case .removed: .localized("Will be removed")
		}
	}

	var tint: Color {
		switch self {
		case .original: .secondary
		case .managed: .orange
		case .overridden: .blue
		case .removed: .red
		}
	}
}

// MARK: - Extension: Toolbar
extension SigningInfoPlistView {
	@ToolbarContentBuilder
	private func _toolbar(for merged: MergedInfoPlist) -> some ToolbarContent {
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
				_selectionActions(for: merged)
			}
		} else {
			ToolbarItem(placement: .topBarTrailing) {
				let changedCount = merged.changedCount

				Button {
					_changedOnly.toggle()
				} label: {
					Image(systemName: "line.3.horizontal.decrease")
						.foregroundStyle(changedCount == 0 ? Color.secondary : (_changedOnly ? Color.accentColor : Color.primary))
				}
				.disabled(changedCount == 0)
			}
			NBToolbarMenu(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing
			) {
				_addMenu(for: merged)
			}
		}
	}

	@ViewBuilder
	private func _selectionActions(for merged: MergedInfoPlist) -> some View {
		Button(.localized("Copy"), systemImage: "doc.on.doc") {
			_clipboard.set(_selectedKeys.reduce(into: [String: Any]()) { result, key in
				result[key] = merged.value(for: key)
			})
			_toggleSelectMode()
		}
		.disabled(_selectedKeys.isEmpty)

		Button(.localized("Reset"), systemImage: "arrow.uturn.backward") {
			_selectedKeys.forEach { _reset($0) }
			_toggleSelectMode()
		}
		.disabled(!_selectedKeys.contains(where: merged.isEdited))

		Button(.localized("Delete"), systemImage: "trash", role: .destructive) {
			_selectedKeys.forEach { _remove($0) }
			_toggleSelectMode()
		}
		.disabled(_selectedKeys.isEmpty)

		Divider()

		Button(.localized("Select All"), systemImage: "checkmark.circle") {
			_selectedKeys = Set(_keys(in: merged))
		}
		Button(.localized("Deselect All"), systemImage: "circle") {
			_selectedKeys.removeAll()
		}
		.disabled(_selectedKeys.isEmpty)
	}

	@ViewBuilder
	private func _addMenu(for merged: MergedInfoPlist) -> some View {
		Button(.localized("Add Entry"), systemImage: "plus") {
			_presentDraft(kind: .string)
		}
		Button(.localized("Add Dictionary"), systemImage: "curlybraces") {
			_presentDraft(kind: .dictionary)
		}
		Button(.localized("Add Array"), systemImage: "list.bullet") {
			_presentDraft(kind: .array)
		}
		Menu(.localized("Common Keys")) {
			ForEach(InfoPlistCommonKeys.groups, id: \.title) { group in
				Menu(group.title) {
					ForEach(group.keys.filter { merged.value(for: $0.key) == nil }) { entry in
						Button(entry.key) {
							_presentDraft(key: entry.key, value: entry.value)
						}
					}
				}
			}
		}
		if !_clipboard.entries.isEmpty {
			Button(.localized("Paste"), systemImage: "doc.on.clipboard") {
				_clipboard.entries.forEach { _set($0.value, for: $0.key, replacing: nil) }
			}
		}

		Divider()

		Button(.localized("Edit Raw"), systemImage: "chevron.left.forwardslash.chevron.right") {
			_showsRaw = true
			_isDraftPresenting = true
		}

		if options.infoPlistChangeCount > 0 {
			Button(.localized("Reset All Changes"), systemImage: "arrow.triangle.2.circlepath", role: .destructive) {
				options.infoPlistOverrides = nil
				options.infoPlistRemovals = nil
			}
		}
	}

	private func _toggleSelectMode() {
		withAnimation {
			_editMode = _editMode.isEditing ? .inactive : .active
			if !_editMode.isEditing { _selectedKeys.removeAll() }
		}
	}

	private func _presentDraft(key: String = "", value: Any? = nil, kind: PlistValueKind? = nil) {
		let resolved = kind ?? value.flatMap { PlistValueKind.kind(for: $0) } ?? .string
		_showsRaw = false
		_draftKey = key
		_draftKind = resolved
		_draftValue = value ?? resolved.emptyValue
		_isDraftPresenting = true
	}
}

// MARK: - Extension: Rows
extension SigningInfoPlistView {
	@ViewBuilder
	private func _row(for key: String, in merged: MergedInfoPlist) -> some View {
		let status = merged.status(for: key)
		let value = merged.value(for: key)

		Group {
			if _editMode.isEditing {
				_selectableRow(key: key, value: value, status: status)
			} else {
				_editableRow(key: key, value: value, status: status)
			}
		}
		.swipeActions(edge: .trailing) {
			if status != .removed {
				Button(role: .destructive) {
					_remove(key)
				} label: {
					Label(.localized("Remove"), systemImage: "trash")
				}
			}
			if merged.isEdited(key) {
				Button {
					_reset(key)
				} label: {
					Label(.localized("Reset"), systemImage: "arrow.uturn.backward")
				}
				.tint(.blue)
			}
		}
	}

	@ViewBuilder
	private func _selectableRow(key: String, value: Any?, status: MergedInfoPlist.Status) -> some View {
		let isSelected = _selectedKeys.contains(key)

		Button {
			if isSelected { _selectedKeys.remove(key) } else { _selectedKeys.insert(key) }
		} label: {
			HStack {
				Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
					.foregroundStyle(isSelected ? Color.accentColor : .secondary)
				_label(key: key, value: value, status: status)
			}
		}
		.buttonStyle(.plain)
	}

	@ViewBuilder
	private func _editableRow(key: String, value: Any?, status: MergedInfoPlist.Status) -> some View {
		if
			status != .removed,
			let value,
			let kind = PlistValueKind.kind(for: value)
		{
			NavigationLink {
				if kind.isContainer {
					PlistNodeView(title: key, value: value) { newValue in
						_set(newValue, for: key, replacing: nil)
					}
				} else {
					PlistEntryEditView(
						originalKey: key,
						kind: kind,
						value: value,
						reference: _reference
					) { newKey, newValue in
						_set(newValue, for: newKey, replacing: key)
					}
				}
			} label: {
				_label(key: key, value: value, status: status)
			}
		} else {
			_label(key: key, value: value, status: status)
		}
	}

	private func _label(key: String, value: Any?, status: MergedInfoPlist.Status) -> some View {
		PlistValueRow(
			key: key,
			value: value,
			note: status.note,
			tint: status.tint,
			isStruck: status == .removed
		)
	}
}

// MARK: - Extension: Mutations
extension SigningInfoPlistView {
	/// A rename has to strip the old key too, otherwise the app's original value survives beside it.
	private func _set(_ value: Any, for key: String, replacing oldKey: String?) {
		var overrides = options.infoPlistOverrideDict
		var removals = options.infoPlistRemovals ?? []

		if let oldKey, oldKey != key {
			overrides.removeValue(forKey: oldKey)
			if _original[oldKey] != nil, !removals.contains(oldKey) { removals.append(oldKey) }
		}

		overrides[key] = value
		removals.removeAll { $0 == key }

		_commit(overrides: overrides, removals: removals)
	}

	private func _remove(_ key: String) {
		var overrides = options.infoPlistOverrideDict
		var removals = options.infoPlistRemovals ?? []

		overrides.removeValue(forKey: key)
		if _original[key] != nil, !removals.contains(key) { removals.append(key) }

		_commit(overrides: overrides, removals: removals)
	}

	private func _reset(_ key: String) {
		var overrides = options.infoPlistOverrideDict
		overrides.removeValue(forKey: key)

		_commit(overrides: overrides, removals: (options.infoPlistRemovals ?? []).filter { $0 != key })
	}

	/// Raw edits are folded back into the same override and removal model the rest of the screen uses.
	private func _applyRaw(_ dict: [String: Any], in merged: MergedInfoPlist) {
		var overrides: [String: Any] = [:]
		for (key, value) in dict where PlistDiff.match(key: key, value: value, against: merged.baseline) != .matches {
			overrides[key] = value
		}

		let removals = _original.keys
			.filter { dict[$0] == nil && !merged.managedRemovals.contains($0) }
			.sorted()

		_commit(overrides: overrides, removals: removals)
	}

	private func _commit(overrides: [String: Any], removals: [String]) {
		options.infoPlistOverrideDict = overrides
		options.infoPlistRemovals = removals.isEmpty ? nil : removals
	}

	private func _load() {
		guard !_hasLoaded else { return }
		_hasLoaded = true

		guard
			let appURL = Storage.shared.getAppDirectory(for: app),
			let dict = NSDictionary(contentsOf: appURL.appendingPathComponent("Info.plist")) as? [String: Any]
		else {
			return
		}

		_original = dict
	}
}
