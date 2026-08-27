//
//  PlistEntryEditView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - Value kind

enum PlistValueKind: String, CaseIterable, Identifiable {
	case string
	case boolean
	case number
	case stringList
	case dictionary
	case array

	var id: String { rawValue }

	var title: String {
		switch self {
		case .string: .localized("String")
		case .boolean: .localized("Boolean")
		case .number: .localized("Number")
		case .stringList: .localized("String List")
		case .dictionary: .localized("Dictionary")
		case .array: .localized("Array")
		}
	}

	/// Containers are edited on their own screen instead of in a value field.
	var isContainer: Bool {
		self == .dictionary || self == .array
	}

	var emptyValue: Any {
		switch self {
		case .string: ""
		case .boolean: false
		case .number: 0
		case .stringList: [String]()
		case .dictionary: [String: Any]()
		case .array: [Any]()
		}
	}

	/// Booleans bridge through NSNumber, so they're told apart by CFBoolean's type id, not by casting.
	static func kind(for value: Any) -> PlistValueKind? {
		switch value {
		case let number as NSNumber:
			return CFGetTypeID(number) == CFBooleanGetTypeID() ? .boolean : .number
		case is String:
			return .string
		case let array as [Any] where array.allSatisfy({ $0 is String }):
			return .stringList
		case is [String: Any]:
			return .dictionary
		case is [Any]:
			return .array
		default:
			return nil
		}
	}

	static func isBoolean(_ value: Any) -> Bool {
		guard let number = value as? NSNumber else { return false }
		return CFGetTypeID(number) == CFBooleanGetTypeID()
	}
}

// MARK: - Reference

/// What the edited entry is compared against, plus the wording for the screen it's shown on.
struct PlistEntryReference {
	let values: [String: Any]
	let missingNote: String
	let mismatchNote: String
	let resetTitle: String
}

// MARK: - View
struct PlistEntryEditView: View {
	@Environment(\.dismiss) var dismiss

	let originalKey: String?
	let reference: PlistEntryReference?
	/// Off for array items, where the position is the key and renaming means nothing.
	var keyEditing: Bool = true
	let onSave: (String, Any) -> Void

	private let _originalValue: Any

	@State private var _key: String
	@State private var _kind: PlistValueKind
	@State private var _stringValue: String
	@State private var _boolValue: Bool
	@State private var _numberValue: String
	@State private var _listValue: String

	init(
		originalKey: String?,
		kind: PlistValueKind,
		value: Any,
		reference: PlistEntryReference?,
		keyEditing: Bool = true,
		onSave: @escaping (String, Any) -> Void
	) {
		self.originalKey = originalKey
		self.reference = reference
		self.keyEditing = keyEditing
		self.onSave = onSave
		self._originalValue = value
		__key = State(initialValue: originalKey ?? "")
		__kind = State(initialValue: kind)
		__stringValue = State(initialValue: value as? String ?? "")
		__boolValue = State(initialValue: PlistValueKind.isBoolean(value) && (value as? Bool ?? false))
		__numberValue = State(initialValue: kind == .number ? "\(value)" : "")
		__listValue = State(initialValue: (value as? [String])?.joined(separator: "\n") ?? "")
	}

	private var _match: PlistDiff.Match? {
		guard let reference, !_key.isEmpty else { return nil }
		return PlistDiff.match(key: _key, value: _currentValue(), against: reference.values)
	}

	/// False when the reference value is a type this screen can't edit, such as a nested dictionary.
	private var _referenceValueIsEditable: Bool {
		guard let value = reference?.values[_key] else { return false }
		return PlistValueKind.kind(for: value) != nil
	}

	// MARK: Body
	var body: some View {
		NBList(originalKey == nil ? .localized("New Entry") : .localized("Edit Entry")) {
			Section {
				if keyEditing {
					TextField(.localized("Key"), text: $_key)
						.textInputAutocapitalization(.never)
						.autocorrectionDisabled()
				}

				Picker(.localized("Type"), selection: $_kind) {
					ForEach(PlistValueKind.allCases) { kind in
						Text(kind.title).tag(kind)
					}
				}
			} footer: {
				_matchFooter
			}

			Section {
				_valueField
				if _match == .differs, _referenceValueIsEditable, let reference {
					Button(reference.resetTitle) {
						_resetToReferenceValue()
					}
				}
			} footer: {
				if _kind == .stringList {
					Text(.localized("One value per line"))
				}
			}
		}
		.dismissableKeyboard()
		.toolbar {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .confirmationAction,
				isDisabled: keyEditing && _key.isEmpty
			) {
				onSave(_key, _currentValue())
				dismiss()
			}
		}
	}
}

// MARK: - Extension: View
extension PlistEntryEditView {
	@ViewBuilder
	private var _matchFooter: some View {
		if let reference {
			switch _match {
			case .missing:
				Text(reference.missingNote)
					.foregroundStyle(.orange)
			case .differs:
				Text(reference.mismatchNote)
					.foregroundStyle(.blue)
			case .matches, nil:
				EmptyView()
			}
		}
	}

	@ViewBuilder
	private var _valueField: some View {
		switch _kind {
		case .string:
			TextField(.localized("Value"), text: $_stringValue)
				.textInputAutocapitalization(.never)
		case .boolean:
			Toggle(.localized("Value"), isOn: $_boolValue)
		case .number:
			TextField(.localized("Value"), text: $_numberValue)
				.keyboardType(.numbersAndPunctuation)
		case .stringList:
			TextEditor(text: $_listValue)
				.frame(minHeight: 120)
		case .dictionary, .array:
			Text(.localized("Open this entry after saving to edit its items"))
				.foregroundStyle(.secondary)
		}
	}

	private func _resetToReferenceValue() {
		guard let value = reference?.values[_key] else { return }
		if let kind = PlistValueKind.kind(for: value) { _kind = kind }
		_stringValue = value as? String ?? _stringValue
		_listValue = (value as? [String])?.joined(separator: "\n") ?? _listValue

		if let number = value as? NSNumber {
			if PlistValueKind.isBoolean(value) {
				_boolValue = number.boolValue
			} else {
				_numberValue = "\(number)"
			}
		}
	}

	private func _currentValue() -> Any {
		switch _kind {
		case .string:
			return _stringValue
		case .boolean:
			return _boolValue
		case .number:
			if let int = Int(_numberValue) { return int }
			return Double(_numberValue) ?? 0
		case .stringList:
			return _listValue
				.split(separator: "\n", omittingEmptySubsequences: true)
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty }
		case .dictionary:
			return (_originalValue as? [String: Any]) ?? [:]
		case .array:
			return (_originalValue as? [Any]) ?? []
		}
	}
}
