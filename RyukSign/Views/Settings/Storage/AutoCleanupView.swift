//
//  AutoCleanupView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct AutoCleanupView: View {
	@ObservedObject private var _optionsManager = OptionsManager.shared

	@AppStorage(InstallCleanup.deleteKey) private var _deleteAfterInstall: Bool = false
	@AppStorage(InstallCleanup.clearCacheKey) private var _clearCacheAfterInstall: Bool = false
	@AppStorage(InstallCleanup.olderVersionsKey) private var _olderVersions: InstallCleanup.OlderVersions = .ask
	@AppStorage(InstallCleanup.olderVersionsScopeKey) private var _olderVersionsScope: InstallCleanup.OlderVersionsScope = .all

	// MARK: Body
	var body: some View {
		NBList(.localized("Automatic Cleanup")) {
			NBSection(.localized("After Signing")) {
				Toggle(.localized("Delete Imported Copy"), isOn: $_optionsManager.options.post_deleteAppAfterSigned)
			} footer: {
				Text(.localized("Keeps only the signed app. Auto Sign always does this."))
			}

			NBSection(.localized("After Installing")) {
				Toggle(.localized("Delete Signed App"), isOn: $_deleteAfterInstall)
				Toggle(.localized("Clear Cache"), isOn: $_clearCacheAfterInstall)
			} footer: {
				Text(.localized("Installed apps stay on your device. Cache is icons and web data, rebuilt as you browse."))
			}

			NBSection(.localized("Older Versions")) {
				Picker(.localized("When Updating"), selection: $_olderVersions) {
					ForEach(InstallCleanup.OlderVersions.allCases, id: \.self) { Text($0.title).tag($0) }
				}
				if _olderVersions != .keep {
					Picker(.localized("Include"), selection: $_olderVersionsScope) {
						ForEach(InstallCleanup.OlderVersionsScope.allCases, id: \.self) { Text($0.title).tag($0) }
					}
				}
			}
		}
		.animation(.default, value: _olderVersions)
		.onChange(of: _optionsManager.options.post_deleteAppAfterSigned) { _ in
			_optionsManager.saveOptions()
		}
	}
}
