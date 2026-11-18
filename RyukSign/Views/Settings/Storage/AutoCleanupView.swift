//
//  AutoCleanupView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews
import NimbleExtensions

// MARK: - View
struct AutoCleanupView: View {
	@ObservedObject private var _optionsManager = OptionsManager.shared

	@AppStorage(InstallCleanup.deleteKey) private var _deleteAfterInstall: Bool = false
	@AppStorage(InstallCleanup.clearCacheKey) private var _clearCacheAfterInstall: Bool = false
	@AppStorage(InstallCleanup.otherVersionsKey) private var _otherVersions: InstallCleanup.OtherVersions = .keep
	@AppStorage(InstallCleanup.otherVersionsScopeKey) private var _otherVersionsScope: InstallCleanup.OtherVersionsScope = .all
	@State private var _versionsSummary = InstallCleanup.VersionMatch.summary

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

			NBSection(.localized("Other Versions")) {
				Picker(.localized("When Installing"), selection: $_otherVersions) {
					ForEach(InstallCleanup.OtherVersions.allCases, id: \.self) { Text($0.title).tag($0) }
				}
				if _otherVersions != .keep {
					NavigationLink(destination: VersionMatchView()) {
						LabeledContent(.localized("Versions to Delete"), value: _versionsSummary)
					}
					Picker(.localized("Include"), selection: $_otherVersionsScope) {
						ForEach(InstallCleanup.OtherVersionsScope.allCases, id: \.self) { Text($0.title).tag($0) }
					}
				}
			} footer: {
				Text(.localized("Deletes other copies of the app you install from your Library. Only older versions unless you choose more."))
			}
		}
		.animation(.default, value: _otherVersions)
		.onAppear { _versionsSummary = InstallCleanup.VersionMatch.summary }
		.onChange(of: _optionsManager.options.post_deleteAppAfterSigned) { _ in
			_optionsManager.saveOptions()
		}
	}
}

struct VersionMatchView: View {
	var body: some View {
		NBList(.localized("Versions to Delete")) {
			Section {
				ForEach(InstallCleanup.VersionMatch.allCases) { VersionMatchRow(match: $0) }
			} footer: {
				Text(.localized("Older versions are deleted by default. Same and Newer are optional. Compared with the version you just installed."))
			}
		}
	}
}

private struct VersionMatchRow: View {
	@AppStorage private var _isOn: Bool
	let match: InstallCleanup.VersionMatch

	init(match: InstallCleanup.VersionMatch) {
		self.match = match
		__isOn = AppStorage(wrappedValue: match.isOnByDefault, match.key)
	}

	var body: some View {
		Button {
			NBHaptic.selection()
			_isOn.toggle()
		} label: {
			HStack {
				VStack(alignment: .leading, spacing: 2) {
					Text(match.title)
						.foregroundStyle(.primary)
					Text(match.subtitle)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
				Spacer()
				if _isOn {
					Image(systemName: "checkmark")
						.font(.body.weight(.semibold))
						.foregroundStyle(.tint)
				}
			}
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
	}
}
