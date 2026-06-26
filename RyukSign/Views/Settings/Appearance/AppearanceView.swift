//
//  AppearanceView.swift
//  RyukSign
//
//  Created by samara on 7.05.2025.
//
import SwiftUI
import NimbleViews
import UIKit
// MARK: - View
struct AppearanceView: View {
	@AppStorage("Feather.userInterfaceStyle")
	private var _userIntefacerStyle: Int = UIUserInterfaceStyle.unspecified.rawValue
	
	@AppStorage("Feather.storeCellAppearance")
	private var _storeCellAppearance: Int = 0
	private let _storeCellAppearanceMethods: [(name: String, desc: String)] = [
		(.localized("Standard"), .localized("Default style for the app, only includes subtitle.")),
		(.localized("Big Description"), .localized("Adds the localized description of the app."))
	]
	
	@AppStorage("com.apple.SwiftUI.IgnoreSolariumLinkedOnCheck")
	private var _ignoreSolariumLinkedOnCheck: Bool = false

	@AppStorage("Feather.sourcesTabShowAllReposDirectly")
	private var _sourcesTabShowAllReposDirectly: Bool = false

	@AppStorage("Feather.sourcesShowUpdatesAsTab")
	private var _sourcesShowUpdatesAsTab: Bool = false

	@AppStorage("Feather.showSourcesUpdateBadge")
	private var _showSourcesUpdateBadge: Bool = true

	@AppStorage("Feather.shouldTintIcons")
	private var _shouldTintIcons: Bool = false

	@AppStorage("Feather.shouldChangeIconsBasedOffStyle")
	private var _shouldChangeIconsBasedOffStyle: Bool = false

	@AppStorage("Feather.userTintColor")
	private var _selectedColorHex: String = "#848ef9"

	private var _tintColorBinding: Binding<Color> {
		Binding(
			get: { Color(hex: _selectedColorHex) },
			set: { _selectedColorHex = $0.toHex() }
		)
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Appearance")) {
			Section {
				Picker(.localized("Appearance"), selection: $_userIntefacerStyle) {
					ForEach(UIUserInterfaceStyle.allCases.sorted(by: { $0.rawValue < $1.rawValue }), id: \.rawValue) { style in
						Text(style.label).tag(style.rawValue)
					}
				}
				.pickerStyle(.segmented)
			}

			NBSection(.localized("Theme")) {
				AppearanceTintColorView()
					.listRowInsets(EdgeInsets())
					.listRowBackground(EmptyView())
			}

			Section {
				ColorPicker(
					.localized("Custom Theme Color"),
					selection: _tintColorBinding,
					supportsOpacity: false
				)
			}

			if #available(iOS 18.0, *) {
				NBSection(.localized("Library")) {
					Toggle(.localized("Dynamic Icons"), isOn: $_shouldChangeIconsBasedOffStyle)
					if #available(iOS 18.2, *) {
						Toggle(.localized("Tinted Icons"), isOn: $_shouldTintIcons)
					}
				}
			}

			NBSection(.localized("Sources")) {

				Picker(.localized("Store Cell Appearance"), selection: $_storeCellAppearance) {
					ForEach(0..<_storeCellAppearanceMethods.count, id: \.self) { index in
						let method = _storeCellAppearanceMethods[index]
						NBTitleWithSubtitleView(
							title: method.name,
							subtitle: method.desc
						)
						.tag(index)
					}
				}
				.labelsHidden()
				.pickerStyle(.inline)
				Toggle(.localized("Show All Repos by Default"), isOn: $_sourcesTabShowAllReposDirectly)
				Toggle(.localized("Show Updates as Tab"), isOn: $_sourcesShowUpdatesAsTab)
				Toggle(.localized("Update Count Badge"), isOn: $_showSourcesUpdateBadge)
				NavigationLink(destination: IgnoredUpdatesView()) {
					Label(.localized("Ignored Updates"), systemImage: "bell.slash")
				}
			} footer: {
				Text(.localized("When enabled, the Sources tab shows all apps directly. Toggle off to manage sources. The update count badge shows the number of available app updates on the Sources tab."))
			}
			
			if #available(iOS 19.0, *) {
				NBSection(.localized("Experiments")) {
					Toggle(.localized("Enable Liquid Glass"), isOn: $_ignoreSolariumLinkedOnCheck)
				} footer: {
					Text(.localized("This enables liquid glass for this app, this requires a restart of the app to take effect."))
				}
			}
		}
		.onChange(of: _userIntefacerStyle) { value in
			if let style = UIUserInterfaceStyle(rawValue: value) {
				UIApplication.topViewController()?.view.window?.overrideUserInterfaceStyle = style
			}
		}
		.onChange(of: _ignoreSolariumLinkedOnCheck) { _ in
			UIApplication.shared.suspendAndReopen()
		}
	}
}
