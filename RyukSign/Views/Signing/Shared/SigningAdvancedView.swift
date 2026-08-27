//
//  SigningAdvancedView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

struct SigningAdvancedView: View {
	let app: AppInfoPresentable
	@Binding var options: Options
	/// Used only to flag entitlement entries the selected certificate's provisioning profile doesn't grant.
	var certificate: CertificatePair? = nil
	/// Off where properties are owned higher up, such as a batch sharing one set across every app.
	var showsProperties: Bool = true

	private var _activeInjectionCount: Int {
		options.injectionFiles.count
		+ (options.tweakInjections?.filter { $0.enabled }.count ?? 0)
	}

	/// Entries in the selected entitlements file that don't cleanly match the selected certificate's profile.
	private var _entitlementsFlagCount: Int {
		guard let fileURL = options.appEntitlementsFile else { return 0 }
		let dict = (NSDictionary(contentsOf: fileURL) as? [String: Any]) ?? [:]
		return PlistDiff.flaggedCount(in: dict, against: PlistDiff.grantedEntitlements(for: certificate))
	}

	/// How many things under Modify are customized, visible before the group is even expanded.
	private var _modifyActivityCount: Int {
		options.disInjectionFiles.count
		+ options.removeFiles.count
		+ (options.appEntitlementsFile != nil ? 1 : 0)
		+ options.infoPlistChangeCount
	}

	// MARK: Body
	var body: some View {
		NBSection(.localized("Advanced")) {
			NavigationLink {
				SigningTweaksView(app: app, options: $options)
			} label: {
				Label(.localized("Tweaks"), systemImage: "syringe")
			}
			.badge(_activeInjectionCount)

			DisclosureGroup {
				NavigationLink {
					SigningDylibView(app: app, options: $options.optional())
				} label: {
					Label(.localized("Existing Dylibs"), systemImage: "doc.text.magnifyingglass")
				}

				NavigationLink {
					SigningFrameworksView(app: app, options: $options.optional())
				} label: {
					Label(.localized("Frameworks & PlugIns"), systemImage: "shippingbox")
				}
				NavigationLink {
					SigningEntitlementsView(bindingValue: $options.appEntitlementsFile, app: app, certificate: certificate)
				} label: {
					Label(.localized("Entitlements (Experimental)"), systemImage: options.appEntitlementsFile == nil ? "checkmark.seal" : "checkmark.seal.fill")
				}
				.badge(_entitlementsFlagCount)

				NavigationLink {
					SigningInfoPlistView(app: app, options: $options)
				} label: {
					Label(.localized("Info.plist (Experimental)"), systemImage: options.infoPlistChangeCount == 0 ? "doc.text" : "doc.text.fill")
				}
				.badge(options.infoPlistChangeCount)
			} label: {
				HStack {
					Label(.localized("Modify"), systemImage: "wrench.adjustable")
					if _modifyActivityCount > 0 {
						Spacer()
						Text("\(_modifyActivityCount)")
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
			}

			if showsProperties {
				NavigationLink {
					Form { SigningOptionsView(
						options: $options,
						temporaryOptions: OptionsManager.shared.options
					)}
					.navigationTitle(.localized("Properties"))
				} label: {
					Label(.localized("Properties"), systemImage: "slider.horizontal.3")
				}
			}
		}
	}
}
