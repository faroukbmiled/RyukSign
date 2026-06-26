//
//  TabBarSettingsView.swift
//  RyukSign
//
//  Reorder, hide, and pick the default launch tab. Backed by TabBarPreferences,
//  which both tab bars read from.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct TabBarSettingsView: View {
	@ObservedObject private var _prefs = TabBarPreferences.shared

	var body: some View {
		NBList(.localized("Tab Bar"), type: .list) {
			NBSection(.localized("Default Launch Tab")) {
				Picker(selection: $_prefs.defaultLaunch) {
					ForEach(_prefs.visibleTabs, id: \.self) { tab in
						Label(tab.title, systemImage: tab.icon).tag(tab)
					}
				} label: {
					Label(.localized("Open On Launch"), systemImage: "house")
				}
				.pickerStyle(.menu)
			} footer: {
				Text(.localized("Which tab the app opens to."))
			}

			NBSection(.localized("Tabs")) {
				ForEach(_prefs.orderedTabs, id: \.self) { tab in
					_row(for: tab)
				}
				.onMove { source, destination in
					_prefs.move(from: source, to: destination)
				}
			} footer: {
				Text(.localized("Drag to reorder (tap Edit). Hidden tabs stay reachable from Settings — the Settings tab can't be hidden."))
			}
		}
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) { EditButton() }
		}
	}

	@ViewBuilder
	private func _row(for tab: TabEnum) -> some View {
		if _prefs.isHideable(tab) {
			Toggle(isOn: Binding(
				get: { !_prefs.isHidden(tab) },
				set: { _prefs.setHidden(tab, !$0) }
			)) {
				Label(tab.title, systemImage: tab.icon)
			}
		} else {
			HStack {
				Label(tab.title, systemImage: tab.icon)
				Spacer()
				Image(systemName: "lock")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}
}
