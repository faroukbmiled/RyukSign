//
//  PlistRawEditorView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

/// Raw XML editing for anything the structured editors show. Nothing is handed back until it parses.
struct PlistRawEditorView: View {
	@Environment(\.dismiss) var dismiss

	let onSave: ([String: Any]) -> Void

	@State private var _text: String
	private let _initialText: String

	init(dict: [String: Any], onSave: @escaping ([String: Any]) -> Void) {
		self.onSave = onSave
		let text = Self.text(for: dict)
		self._initialText = text
		__text = State(initialValue: text)
	}

	// MARK: Body
	var body: some View {
		TextEditor(text: $_text)
			.font(.system(.footnote, design: .monospaced))
			.autocorrectionDisabled()
			.textInputAutocapitalization(.never)
			.padding(.horizontal, 8)
			.navigationTitle(.localized("Edit Raw"))
			.navigationBarTitleDisplayMode(.inline)
			.dismissableKeyboard()
			.toolbar {
				NBToolbarButton(
					.localized("Save"),
					style: .text,
					placement: .confirmationAction,
					isDisabled: _text == _initialText
				) {
					_save()
				}
			}
	}
}

// MARK: - Extension: Serialization
extension PlistRawEditorView {
	static func text(for dict: [String: Any]) -> String {
		guard
			let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
			let text = String(data: data, encoding: .utf8)
		else {
			return ""
		}
		return text
	}

	private func _save() {
		guard let data = _text.data(using: .utf8) else {
			Toast.error(.localized("Invalid property list"))
			return
		}

		do {
			let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
			guard let dict = object as? [String: Any] else {
				Toast.error(.localized("The root of the property list must be a dictionary"))
				return
			}

			onSave(dict)
			dismiss()
		} catch {
			Toast.error(error.localizedDescription)
		}
	}
}
