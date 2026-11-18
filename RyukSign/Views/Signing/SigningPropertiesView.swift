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
	@State private var _identities: [AppIdentity] = []
	
	var saveButtonDisabled: Bool {
		text == initialValue
	}
	
	var title: String
	var initialValue: String
	@Binding var bindingValue: String?
	var suggestion: String? = nil
	var identitiesOf: AppInfoPresentable? = nil

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
			if _identities.contains(where: { $0.identifier != identitiesOf?.identifier }) {
				Section {
					ForEach(_identities) { identity in
						_identityRow(identity)
					}
				} header: {
					Text(.localized("In Your Library"))
				} footer: {
					Text(.localized("Pick an identifier to update that copy instead of installing a new one."))
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
			_identities = identitiesOf.map(Storage.shared.identities(for:)) ?? []
		}
	}

	private func _identityRow(_ identity: AppIdentity) -> some View {
		let details = [
			identity.isInstalled ? String.localized("Installed") : nil,
			identity.app.isSigned ? .localized("Signed") : .localized("Imported"),
			identity.app.version,
			identity.app.name == identitiesOf?.name ? nil : identity.app.name
		]

		return Button {
			text = identity.identifier
		} label: {
			HStack(spacing: 12) {
				FRAppIconView(app: identity.app, size: 36)
				VStack(alignment: .leading, spacing: 2) {
					Text(identity.identifier)
						.font(.subheadline)
						.foregroundStyle(.primary)
						.lineLimit(1)
						.truncationMode(.middle)
					Text(details.compactMap { $0 }.joined(separator: " • "))
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}
				Spacer(minLength: 8)
				if text == identity.identifier {
					Image(systemName: "checkmark")
						.font(.body.weight(.semibold))
						.foregroundStyle(.tint)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
