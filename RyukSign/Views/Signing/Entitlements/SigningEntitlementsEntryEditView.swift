//
//  SigningEntitlementsEntryEditView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningEntitlementsEntryEditView: View {
	@Environment(\.dismiss) var dismiss

	let originalKey: String?
	let grantedEntitlements: [String: Any]?
	let onSave: (String, Any) -> Void

	@State private var _key: String
	@State private var _kind: EntitlementValueKind
	@State private var _stringValue: String
	@State private var _boolValue: Bool
	@State private var _listValue: String

	init(
		originalKey: String?,
		kind: EntitlementValueKind,
		value: Any,
		grantedEntitlements: [String: Any]?,
		onSave: @escaping (String, Any) -> Void
	) {
		self.originalKey = originalKey
		self.grantedEntitlements = grantedEntitlements
		self.onSave = onSave
		__key = State(initialValue: originalKey ?? "")
		__kind = State(initialValue: kind)
		__stringValue = State(initialValue: value as? String ?? "")
		__boolValue = State(initialValue: value as? Bool ?? false)
		__listValue = State(initialValue: (value as? [String])?.joined(separator: "\n") ?? "")
	}

	private var _match: EntitlementsDiff.Match? {
		guard let grantedEntitlements, !_key.isEmpty else { return nil }
		return EntitlementsDiff.match(key: _key, value: _currentValue(), against: grantedEntitlements)
	}

	/// False when the certificate's value is a type this screen can't edit (e.g. a nested dict).
	private var _certificateValueIsResettable: Bool {
		guard let value = grantedEntitlements?[_key] else { return false }
		return EntitlementValueKind.kind(for: value) != nil
	}

	// MARK: Body
	var body: some View {
		NBList(originalKey == nil ? .localized("New Entry") : .localized("Edit Entry")) {
			Section {
				TextField(.localized("Key"), text: $_key)
					.textInputAutocapitalization(.never)
					.autocorrectionDisabled()

				Picker(.localized("Type"), selection: $_kind) {
					ForEach(EntitlementValueKind.allCases) { kind in
						Text(kind.title).tag(kind)
					}
				}
			} footer: {
				_matchFooter
			}

			Section {
				_valueField
				if _match == .valueMismatch, _certificateValueIsResettable {
					Button(.localized("Reset to Certificate Value")) {
						_resetToCertificateValue()
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
				isDisabled: _key.isEmpty
			) {
				onSave(_key, _currentValue())
				dismiss()
			}
		}
	}
}

// MARK: - Extension: View
extension SigningEntitlementsEntryEditView {
	@ViewBuilder
	private var _matchFooter: some View {
		switch _match {
		case .notGranted:
			Text(.localized("Not granted by the selected certificate's provisioning profile"))
				.foregroundStyle(.orange)
		case .valueMismatch:
			Text(.localized("Value differs from the selected certificate's provisioning profile"))
				.foregroundStyle(.blue)
		case .granted, nil:
			EmptyView()
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
		case .stringList:
			TextEditor(text: $_listValue)
				.frame(minHeight: 120)
		}
	}

	private func _resetToCertificateValue() {
		guard let value = grantedEntitlements?[_key] else { return }
		if let kind = EntitlementValueKind.kind(for: value) { _kind = kind }
		_stringValue = value as? String ?? _stringValue
		_boolValue = value as? Bool ?? _boolValue
		_listValue = (value as? [String])?.joined(separator: "\n") ?? _listValue
	}

	private func _currentValue() -> Any {
		switch _kind {
		case .string:
			return _stringValue
		case .boolean:
			return _boolValue
		case .stringList:
			return _listValue
				.split(separator: "\n", omittingEmptySubsequences: true)
				.map { $0.trimmingCharacters(in: .whitespaces) }
				.filter { !$0.isEmpty }
		}
	}
}
