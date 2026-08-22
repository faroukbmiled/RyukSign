//
//  BackupComponentsView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct BackupComponentsView: View {
	@Environment(\.dismiss) private var dismiss

	let title: String
	let confirmTitle: String
	let available: BackupComponents
	var counts: [BackupComponents: Int] = [:]
	var detail: String?
	let footer: String
	var passwordFooter: String?
	let onConfirm: (BackupComponents, String) -> Void

	@State private var _selection: BackupComponents
	@State private var _password = ""

	init(
		title: String,
		confirmTitle: String,
		available: BackupComponents,
		counts: [BackupComponents: Int] = [:],
		detail: String? = nil,
		footer: String,
		passwordFooter: String? = nil,
		onConfirm: @escaping (BackupComponents, String) -> Void
	) {
		self.title = title
		self.confirmTitle = confirmTitle
		self.available = available
		self.counts = counts
		self.detail = detail
		self.footer = footer
		self.passwordFooter = passwordFooter
		self.onConfirm = onConfirm
		__selection = State(initialValue: available)
	}

	// MARK: Body
	var body: some View {
		NBNavigationView(title, displayMode: .inline) {
			Form {
				NBSection(.localized("Include")) {
					ForEach(BackupComponents.ordered.filter { available.contains($0) }, id: \.rawValue) { component in
						Toggle(isOn: _binding(component)) {
							HStack {
								Label(component.title, systemImage: component.icon)
								Spacer()
								if let count = counts[component] {
									Text(verbatim: "\(count)")
										.foregroundStyle(.secondary)
								}
							}
						}
					}

					Button(.localized("Select All")) {
						_selection = available
					}
					.disabled(_selection == available)
				} footer: {
					VStack(alignment: .leading, spacing: 6) {
						if let detail {
							Text(verbatim: detail)
						}
						Text(footer)
					}
				}

				if let passwordFooter {
					NBSection(.localized("Password")) {
						SecureField(.localized("Password"), text: $_password)
					} footer: {
						Text(passwordFooter)
					}
				}
			}
			.dismissableKeyboard()
			.toolbar {
				NBToolbarButton(role: .cancel)

				NBToolbarButton(
					confirmTitle,
					style: .text,
					placement: .confirmationAction,
					isDisabled: _selection.isEmpty
				) {
					onConfirm(_selection, _password)
					dismiss()
				}
			}
		}
	}

	private func _binding(_ component: BackupComponents) -> Binding<Bool> {
		Binding(
			get: { _selection.contains(component) },
			set: { isOn in
				if isOn { _selection.insert(component) } else { _selection.remove(component) }
			}
		)
	}
}
