//
//  SigningDescriptionView.swift
//  RyukSign
//
//  Created on 08.02.2026.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningDescriptionView: View {
	@Environment(\.dismiss) var dismiss

	@State private var text: String = ""

	var saveButtonDisabled: Bool {
		text == initialValue
	}

	var title: String
	var initialValue: String
	var onSave: (String?) -> Void

	// MARK: Body
	var body: some View {
		NBList(title) {
			TextField(.localized("Description"), text: $text, axis: .vertical)
				.lineLimit(1...50)
				.textInputAutocapitalization(.none)
		}
		.dismissableKeyboard()
		.toolbar {
			if !text.isEmpty {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Clear")) {
						text = ""
					}
					.foregroundStyle(.secondary)
				}
			}
			NBToolbarButton(
				.localized("Save"),
				style: .text,
				placement: .topBarTrailing,
				isDisabled: saveButtonDisabled
			) {
				if !saveButtonDisabled {
					onSave(text.isEmpty ? nil : text)
					dismiss()
				}
			}
		}
		.onAppear {
			text = initialValue
		}
	}
}
