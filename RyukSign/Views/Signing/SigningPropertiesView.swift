//
//  SigningAppPropertiesView.swift
//  RyukSign
//
//  Created by samara on 17.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningPropertiesView: View {
	@Environment(\.dismiss) var dismiss
	
	@State private var text: String = ""
	
	var saveButtonDisabled: Bool {
		text == initialValue
	}
	
	var title: String
	var initialValue: String
	@Binding var bindingValue: String?
	var suggestion: String? = nil

	// MARK: Body
	var body: some View {
		NBList(title) {
			Section {
				TextField(initialValue, text: $text)
					.textInputAutocapitalization(.none)
			}
			if let suggestion, suggestion != text {
				Section {
					Button {
						text = suggestion
					} label: {
						Label(.localized("Match Certificate Identifier"), systemImage: "checkmark.seal")
					}
				} footer: {
					Text(verbatim: .localized("Use %@ from your selected provisioning profile.", arguments: suggestion))
				}
			}
		}
		.dismissableKeyboard()
		.toolbar {
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .topBarTrailing,
				isDisabled: saveButtonDisabled
			) {
				if !saveButtonDisabled {
					bindingValue = text
					dismiss()
				}
			}
		}
		.onAppear {
			text = initialValue
		}
	}
}
