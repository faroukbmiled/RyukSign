//
//  LibraryInfoView.swift
//  RyukSign
//
//  Created by samara on 14.04.2025.
//

import SwiftUI
import NimbleViews
import Zsign

// MARK: - View
struct LibraryInfoView: View {
	var app: AppInfoPresentable
	@State private var _displayedDescription: String?

	// MARK: Body
    var body: some View {
		NBNavigationView(app.name ?? "", displayMode: .inline) {
			List {
				Section {} header: {
					FRAppIconView(app: app)
						.frame(maxWidth: .infinity, alignment: .center)
				}

				_infoSection(for: app)
				_certSection(for: app)
				_bundleSection(for: app)
				_executableSection(for: app)

				Section {
					_linksSection(for: app)
					Button(.localized("Open in Files"), systemImage: "folder") {
						UIApplication.open(Storage.shared.getUuidDirectory(for: app)!.toSharedDocumentsURL()!)
					}
				}
			}
			.toolbar {
				NBToolbarButton(role: .close)
			}
		}
		.onAppear {
			_displayedDescription = app.appDescription
		}
    }
}

// MARK: - Extension: View
extension LibraryInfoView {
	@ViewBuilder
	private func _infoSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Info")) {
			if let name = app.name {
				_infoCell(.localized("Name"), desc: name)
			}

			if let ver = app.version {
				_infoCell(.localized("Version"), desc: ver)
			}

			if let id = app.identifier {
				_infoCell(.localized("Identifier"), desc: id)
			}

			if let originalId = app.originalIdentifier, originalId != app.identifier {
				_infoCell(.localized("Original Identifier"), desc: originalId)
			}

			NavigationLink {
				SigningDescriptionView(
					title: .localized("Description"),
					initialValue: LinkTagParser.strip(from: _displayedDescription) ?? "",
					onSave: { newValue in
						var saved = newValue
						if let tags = LinkTagParser.rawTags(in: _displayedDescription) {
							saved = saved.map { $0 + tags } ?? tags
						}
						Storage.shared.updateDescription(for: app, description: saved)
						_displayedDescription = saved
					}
				)
			} label: {
				LabeledContent(.localized("Description")) {
					Text(LinkTagParser.strip(from: _displayedDescription) ?? .localized("None"))
						.lineLimit(1)
				}
			}
			.copyableText(LinkTagParser.strip(from: _displayedDescription) ?? "")

			if let date = app.date {
				_infoCell(.localized("Date Added"), desc: date.formatted())
			}
		}
	}
	
	@ViewBuilder
	private func _certSection(for app: AppInfoPresentable) -> some View {
		if let cert = Storage.shared.getCertificate(from: app) {
			NBSection(.localized("Certificate")) {
				CertificatesCellView(
					cert: cert
				)
			}
		}
	}
	
	@ViewBuilder
	private func _bundleSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Bundle")) {
			NavigationLink(.localized("Alternative Icons")) {
				SigningAlternativeIconView(app: app, appIcon: .constant(nil), isModifing: false)
			}
			NavigationLink(.localized("Frameworks & PlugIns")) {
				SigningFrameworksView(app: app, options: .constant(nil))
			}
		}
	}
	
	@ViewBuilder
	private func _executableSection(for app: AppInfoPresentable) -> some View {
		NBSection(.localized("Executable")) {
			NavigationLink(.localized("Dylibs")) {
				SigningDylibView(app: app, options: .constant(nil))
			}
		}
	}
	
	@ViewBuilder
	private func _linksSection(for app: AppInfoPresentable) -> some View {
		ForEach(LinkTagParser.links(in: _displayedDescription)) { link in
			Button {
				link.tag.open(link.url)
			} label: {
				Label {
					Text(link.tag.title)
				} icon: {
					Image(systemName: link.tag.symbol)
				}
			}
		}
	}

	@ViewBuilder
	private func _infoCell(_ title: String, desc: String) -> some View {
		LabeledContent(title) {
			Text(desc)
		}
		.copyableText(desc)
	}
}
