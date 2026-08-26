//
//  BatchAppOptionsView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews
import NimbleExtensions

/// Certificate and properties are deliberately absent; a batch sets those once for every app.
struct BatchAppOptionsView: View {
	let app: AppInfoPresentable
	let identifierSuggestion: String?
	@Binding var options: Options
	@Binding var appIcon: UIImage?
	let certificate: CertificatePair?
	let onReset: () -> Void

	// MARK: Body
	var body: some View {
		NBList(app.name ?? .localized("Unknown")) {
			SigningCustomizationView(
				app: app,
				options: $options,
				appIcon: $appIcon,
				identifierSuggestion: identifierSuggestion
			)

			SigningAdvancedView(app: app, options: $options, certificate: certificate, showsProperties: false)

			Section {
			} footer: {
				Text(.localized("The certificate and properties are set once for the whole batch."))
			}
		}
		.toolbar {
			NBToolbarButton(
				.localized("Reset"),
				style: .text,
				placement: .topBarTrailing,
				action: onReset
			)
		}
	}
}
