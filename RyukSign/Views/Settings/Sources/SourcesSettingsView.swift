//
//  SourcesSettingsView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

struct SourcesSettingsView: View {
	@AppStorage(SourceCache.enabledKey) private var _cacheEnabled = true
	@AppStorage(SourceCache.refreshKey) private var _refresh = SourceCache.Refresh.halfHour.rawValue

	@AppStorage("RyukSign.sourcesShowAppCount") private var _showsAppCount = true
	@AppStorage("RyukSign.sourcesCombinedNews") private var _combinedNews = true
	@AppStorage(AppUpdateChecker.newestKey) private var _updateToNewest = false
	@AppStorage("RyukSign.libraryShowsUpdates") private var _libraryShowsUpdates = true
	@AppStorage(AppUpdateChecker.singleSourceKey) private var _singleSourceDirectly = true
	@AppStorage(AppUpdateChecker.groupKey) private var _groupsByApp = true
	@AppStorage(AppUpdateChecker.launchCheckKey) private var _checksOnLaunch = true

	@State private var _cacheSize: Int64 = 0

	var body: some View {
		NBList(.localized("Sources")) {
			NBSection(.localized("Display")) {
				Toggle(.localized("Show App Counts"), isOn: $_showsAppCount)
				Toggle(.localized("News in All Repositories"), isOn: $_combinedNews)
			}

			NBSection(.localized("Updates")) {
				Picker(.localized("Update From"), selection: $_updateToNewest) {
					Text(.localized("Ask Each Time")).tag(false)
					Text(.localized("Newest Version")).tag(true)
				}
				Toggle(.localized("Skip Choice for One Source"), isOn: $_singleSourceDirectly)
				Toggle(.localized("Group by App"), isOn: $_groupsByApp)
				Toggle(.localized("Show in Library"), isOn: $_libraryShowsUpdates)
				Toggle(.localized("Check on Launch"), isOn: $_checksOnLaunch)
				NavigationLink(destination: IgnoredUpdatesView()) {
					Text(.localized("Ignored Updates"))
				}
			} footer: {
				Text(.localized("Pinned sources and apps found in only one source update right away. Check on Launch loads your sources at startup, following the cache setting."))
			}

			NBSection(.localized("Cache")) {
				Toggle(.localized("Keep Sources Offline"), isOn: $_cacheEnabled)

				if _cacheEnabled {
					Picker(.localized("Refresh"), selection: $_refresh) {
						ForEach(SourceCache.Refresh.allCases, id: \.rawValue) { option in
							Text(option.title).tag(option.rawValue)
						}
					}
				}

				Button(role: .destructive) {
					SourceCache.clear()
					_cacheSize = 0
				} label: {
					HStack {
						Text(.localized("Clear Cache"))
						Spacer()
						Text(_cacheSize.formattedFileSize)
							.foregroundStyle(.secondary)
					}
				}
				.disabled(_cacheSize == 0)
			} footer: {
				Text(.localized("Sources open instantly from the last copy and refresh in the background."))
			}
		}
		.task(id: _cacheEnabled) {
			if !_cacheEnabled { SourceCache.clear() }
			_cacheSize = await Task.detached { SourceCache.size() }.value
		}
	}
}
