//
//  AboutView.swift
//  RyukSign
//
//  Created by samara on 30.04.2025.
//

import SwiftUI
import NimbleViews

// MARK: - Extension: Model
extension AboutView {
	struct CreditsModel: Codable, Hashable {
		let name: String?
		let desc: String?
		let github: String
	}
}

// MARK: - View
struct AboutView: View {
	// Hardcoded: upstream's creditsv2.json now 404s.
	private let _credits: [CreditsModel] = [
		.init(name: "Ryuk", desc: "RyukSign Developer", github: "faroukbmiled"),
		.init(name: "claration", desc: "Feather — original project", github: "claration"),
		.init(name: "Asami", desc: "Developer", github: "Nyasami"),
		.init(name: "Lakhan Lothiyi", desc: "AltStore Repositories", github: "llsc12"),
	]

	private let _sourceURL = "https://github.com/faroukbmiled/RyukSign"
	private let _upstreamURL = "https://github.com/claration/Feather"
	private let _licenseURL = "https://github.com/faroukbmiled/RyukSign/blob/main/LICENSE"

	// MARK: Body
	var body: some View {
		NBList(.localized("About")) {
			Section {
				VStack {
					FRAppIconView(size: 72)

					Text(Bundle.main.name)
						.font(.largeTitle)
						.bold()
						.foregroundStyle(Color.accentColor)

					HStack(spacing: 4) {
						Text(.localized("Version"))
						Text(Bundle.main.version)
					}
					.font(.footnote)
					.foregroundStyle(.secondary)
				}
			}
			.frame(maxWidth: .infinity)
			.listRowBackground(EmptyView())

			NBSection(.localized("Credits")) {
				ForEach(_credits, id: \.github) { credit in
					_credit(name: credit.name, desc: credit.desc, github: credit.github)
				}
			}

			NBSection(.localized("Source & License")) {
				Button(.localized("Source Code"), systemImage: "chevron.left.forwardslash.chevron.right") {
					UIApplication.open(_sourceURL)
				}
				Button(.localized("License (GPL-3.0)"), systemImage: "doc.text") {
					UIApplication.open(_licenseURL)
				}
				Button(.localized("Based on Feather"), systemImage: "arrow.triangle.branch") {
					UIApplication.open(_upstreamURL)
				}
			} footer: {
				Text(.localized("RyukSign is free software under the GPL-3.0 license, derived from Feather by claration. The complete corresponding source is available at the Source Code link above."))
			}
		}
	}
}

// MARK: - Extension: view
extension AboutView {
	@ViewBuilder
	private func _credit(
		name: String?,
		desc: String?,
		github: String
	) -> some View {
		Button {
			UIApplication.open("https://github.com/\(github)")
		} label: {
			HStack {
				FRIconCellView(
					title: name ?? github,
					subtitle: desc ?? "",
					iconUrl: URL(string: "https://github.com/\(github).png")!,
					size: 45,
					isCircle: true
				)

				Image(systemName: "arrow.up.right")
					.foregroundColor(.secondary.opacity(0.65))
			}
		}
	}
}
