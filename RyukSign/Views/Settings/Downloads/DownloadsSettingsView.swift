//
//  DownloadsSettingsView.swift
//  RyukSign
//
//  Created by Ryuk on 13.10.2025.
//
import SwiftUI
import NimbleViews

// MARK: - View
struct DownloadsSettingsView: View {
	@AppStorage("Feather.downloadDisplayMode")
	private var _downloadDisplayMode: String = "floating"

	@AppStorage("Feather.backgroundDownloadHeaderStartState")
	private var _backgroundDownloadHeaderStartState: String = "collapsed"

	@AppStorage("Feather.showDownloadHeaderInSourcesTab")
	private var _showDownloadHeaderInSourcesTab: Bool = true

	@AppStorage("Feather.downloadOverlayTheme")
	private var _downloadOverlayTheme: String = "default"

	@AppStorage("Feather.dynamicOverlaySize")
	private var _dynamicOverlaySize: Bool = true

	private let _downloadDisplayModes: [(value: String, name: String, desc: String)] = [
		("floating", .localized("Floating Icon"), .localized("Shows a floating draggable download icon that opens up an overlay when clicked")),
		("header", .localized("Download Header"), .localized("Shows a header at the top of the screen with download progress"))
	]

	private let _downloadHeaderStates: [(value: String, name: String, desc: String)] = [
		("minimized", .localized("Minimized"), .localized("Compact view showing minimal download information")),
		("collapsed", .localized("Collapsed"), .localized("Medium view with basic download progress")),
		("expanded", .localized("Expanded"), .localized("Detailed view showing all download information"))
	]

	private let _overlayThemes: [(value: String, name: String, desc: String)] = [
		("default", .localized("Default"), .localized("Uses system background color (white in light mode, dark in dark mode)")),
		("greyish", .localized("Greyish"), .localized("Uses a custom grey color in dark mode, white in light mode")),
		("darkGrey", .localized("Dark Grey"), .localized("Uses a darker grey color in dark mode, white in light mode"))
	]

	// MARK: Body
	var body: some View {
		NBList(.localized("Downloads")) {
			NBSection(.localized("Display Mode")) {
				Picker(.localized("Download Display Style"), selection: $_downloadDisplayMode) {
					ForEach(_downloadDisplayModes, id: \.value) { mode in
						NBTitleWithSubtitleView(
							title: mode.name,
							subtitle: mode.desc
						)
						.tag(mode.value)
					}
				}
				.labelsHidden()
				.pickerStyle(.inline)
			} footer: {
				Text(.localized("Choose how downloads are displayed in the app. Floating icon is the default and provides a convenient draggable interface."))
			}

			if _downloadDisplayMode == "header" {
				NBSection(.localized("Download Header Options")) {
					Picker(.localized("Background Downloads Initial State"), selection: $_backgroundDownloadHeaderStartState) {
						ForEach(_downloadHeaderStates, id: \.value) { state in
							NBTitleWithSubtitleView(
								title: state.name,
								subtitle: state.desc
							)
							.tag(state.value)
						}
					}
					.labelsHidden()
					.pickerStyle(.inline)

					Toggle(.localized("Show in Sources Tab"), isOn: $_showDownloadHeaderInSourcesTab)
				} footer: {
					Text(.localized("These settings control how background downloads from sources appear. Manual downloads will always show with their own header."))
				}
			}

			if _downloadDisplayMode == "floating" {
				NBSection(.localized("Appearance")) {
					Picker(.localized("Overlay Theme"), selection: $_downloadOverlayTheme) {
						ForEach(_overlayThemes, id: \.value) { theme in
							NBTitleWithSubtitleView(
								title: theme.name,
								subtitle: theme.desc
							)
							.tag(theme.value)
						}
					}
					.labelsHidden()
					.pickerStyle(.inline)
				} footer: {
					Text(.localized("Choose the color theme for the download overlay. Greyish theme provides a softer appearance in dark mode."))
				}

				NBSection(.localized("Overlay Behavior")) {
					Toggle(.localized("Dynamic Overlay Size"), isOn: $_dynamicOverlaySize)
				} footer: {
					Text(.localized("When enabled, the overlay automatically adjusts its height based on the number of active downloads. When disabled, the overlay uses a fixed size."))
				}
			}
		}
	}
}
