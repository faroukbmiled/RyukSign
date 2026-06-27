//
//  ConfigurationDictAddView.swift
//  RyukSign
//
//  Created by samara on 20.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct ConfigurationDictAddView: View {
	@Environment(\.dismiss) var dismiss
	
	@State private var _newKey = ""
	@State private var _newValue = ""
	@State private var _showOverrideAlert = false
	@State private var _isLibraryPickerPresenting = false

	var saveButtonDisabled: Bool {
		_newKey.isEmpty || _newValue.isEmpty
	}

	var keyKind: DictKeyKind
	@Binding var dataDict: [String: String]

	// MARK: Body
    var body: some View {
		NBList(.localized("New")) {
			Section {
				TextField(.localized("Value"), text: $_newKey)
				TextField(.localized("Replacement"), text: $_newValue)
			}
			.autocapitalization(.none)

			Section {
				Button(.localized("Choose from Library"), systemImage: "square.grid.2x2") {
					_isLibraryPickerPresenting = true
				}
			}
		}
		.sheet(isPresented: $_isLibraryPickerPresenting) {
			AppLibraryPicker(subtitle: { keyKind.value(for: $0) }) { app in
				_newKey = keyKind.value(for: app) ?? ""
			}
		}
		.dismissableKeyboard()
		.toolbar {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .confirmationAction,
				isDisabled: saveButtonDisabled
			) {
				dataDict[_newKey] = _newValue
				OptionsManager.shared.saveOptions()
				dismiss()
			}
		}
    }
}
