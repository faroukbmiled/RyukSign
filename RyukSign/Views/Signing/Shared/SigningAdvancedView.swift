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
	/// Off where properties are owned higher up, such as a batch sharing one set across every app.
	var showsProperties: Bool = true

	private var _activeInjectionCount: Int {
		options.injectionFiles.count
		+ (options.tweakInjections?.filter { $0.enabled }.count ?? 0)
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
				#if NIGHTLY || DEBUG
				NavigationLink {
					SigningEntitlementsView(bindingValue: $options.appEntitlementsFile)
				} label: {
					Label(.localized("Entitlements") + " (BETA)", systemImage: "checkmark.seal")
				}
				#endif
			} label: {
				Label(.localized("Modify"), systemImage: "wrench.adjustable")
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
