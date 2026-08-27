//
//  PlistNodeView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

/// Edits one nested plist container, drilling as deep as the value goes. Changes bubble up through `onChange`.
struct PlistNodeView: View {
	let title: String
	let onChange: (Any) -> Void

	@State private var _value: Any
	@State private var _isAddingPresenting = false
	@State private var _addKind: PlistValueKind = .string

	init(title: String, value: Any, onChange: @escaping (Any) -> Void) {
		self.title = title
		self.onChange = onChange
		__value = State(initialValue: value)
	}

	private var _dictionary: [String: Any]? { _value as? [String: Any] }
	private var _array: [Any]? { _value as? [Any] }
	private var _isEmpty: Bool { (_dictionary?.isEmpty ?? true) && (_array?.isEmpty ?? true) }

	// MARK: Body
	var body: some View {
		NBList(title) {
			Section {
				if let dictionary = _dictionary {
					ForEach(dictionary.keys.sorted(), id: \.self) { key in
						_row(
							label: key,
							value: dictionary[key] ?? "",
							keyEditing: true,
							save: { newKey, newValue in _setChild(key: key, newKey: newKey, value: newValue) },
							delete: { _removeChild(key: key) }
						)
					}
				} else if let array = _array {
					ForEach(Array(array.enumerated()), id: \.offset) { index, item in
						_row(
							label: .localized("Item %@", arguments: "\(index + 1)"),
							value: item,
							keyEditing: false,
							save: { _, newValue in _setItem(at: index, value: newValue) },
							delete: { _removeItem(at: index) }
						)
					}
				}
			} footer: {
				if _isEmpty {
					Text(.localized("No items"))
				}
			}
		}
		.toolbar {
			NBToolbarMenu(
				systemImage: "plus",
				style: .icon,
				placement: .topBarTrailing
			) {
				Button(.localized("Add Entry"), systemImage: "plus") {
					_present(.string)
				}
				Button(.localized("Add Dictionary"), systemImage: "curlybraces") {
					_present(.dictionary)
				}
				Button(.localized("Add Array"), systemImage: "list.bullet") {
					_present(.array)
				}
			}
		}
		.navigationDestination(isPresented: $_isAddingPresenting) {
			PlistEntryEditView(
				originalKey: nil,
				kind: _addKind,
				value: _addKind.emptyValue,
				reference: nil,
				keyEditing: _dictionary != nil
			) { key, value in
				_append(key: key, value: value)
			}
		}
	}
}

// MARK: - Extension: Rows
extension PlistNodeView {
	@ViewBuilder
	private func _row(
		label: String,
		value: Any,
		keyEditing: Bool,
		save: @escaping (String, Any) -> Void,
		delete: @escaping () -> Void
	) -> some View {
		Group {
			if let kind = PlistValueKind.kind(for: value) {
				NavigationLink {
					// Erased, otherwise the view type would recurse into itself forever.
					if kind.isContainer {
						AnyView(PlistNodeView(title: label, value: value) { save(label, $0) })
					} else {
						AnyView(PlistEntryEditView(
							originalKey: label,
							kind: kind,
							value: value,
							reference: nil,
							keyEditing: keyEditing,
							onSave: save
						))
					}
				} label: {
					PlistValueRow(key: label, value: value)
				}
			} else {
				CertificatesInfoEntitlementCellView(key: label, value: value)
			}
		}
		.swipeActions(edge: .trailing) {
			Button(role: .destructive, action: delete) {
				Label(.localized("Delete"), systemImage: "trash")
			}
		}
	}
}

// MARK: - Extension: Mutations
extension PlistNodeView {
	private func _present(_ kind: PlistValueKind) {
		_addKind = kind
		_isAddingPresenting = true
	}

	private func _setChild(key: String, newKey: String, value: Any) {
		var dictionary = _dictionary ?? [:]
		if newKey != key { dictionary.removeValue(forKey: key) }
		dictionary[newKey] = value
		_commit(dictionary)
	}

	private func _removeChild(key: String) {
		var dictionary = _dictionary ?? [:]
		dictionary.removeValue(forKey: key)
		_commit(dictionary)
	}

	private func _setItem(at index: Int, value: Any) {
		guard var array = _array, array.indices.contains(index) else { return }
		array[index] = value
		_commit(array)
	}

	private func _removeItem(at index: Int) {
		guard var array = _array, array.indices.contains(index) else { return }
		array.remove(at: index)
		_commit(array)
	}

	private func _append(key: String, value: Any) {
		if var dictionary = _dictionary {
			dictionary[key] = value
			_commit(dictionary)
		} else if var array = _array {
			array.append(value)
			_commit(array)
		}
	}

	private func _commit(_ value: Any) {
		_value = value
		onChange(value)
	}
}
