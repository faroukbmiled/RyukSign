//
//  IgnoredUpdatesView.swift
//  RyukSign
//
//  Manage apps whose update checks are ignored.
//

import SwiftUI
import NimbleViews

// MARK: - View
struct IgnoredUpdatesView: View {
	@ObservedObject private var _manager = SkippedUpdatesManager.shared
	@State private var _search = ""

	private var _filtered: [String] {
		let all = _manager.sortedBundleIDs
		guard !_search.isEmpty else { return all }
		return all.filter { $0.localizedCaseInsensitiveContains(_search) }
	}

	// MARK: Body
	var body: some View {
		List {
			if !_manager.bundleIDs.isEmpty {
				Section {
					ForEach(_filtered, id: \.self) { bundleID in
						_row(bundleID)
					}
				} footer: {
					Text(.localized("Ignored apps don't count toward the Sources update badge and don't appear in the Updates list. You can still update them manually."))
				}
			}
		}
		.navigationTitle(.localized("Ignored Updates"))
		.navigationBarTitleDisplayMode(.inline)
		.searchable(text: $_search, placement: .navigationBarDrawer(displayMode: .always))
		.toolbar {
			if !_manager.bundleIDs.isEmpty {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Resume All"), role: .destructive) {
						_resumeAll()
					}
				}
			}
		}
		.overlay { _overlay }
	}

	@ViewBuilder
	private func _row(_ bundleID: String) -> some View {
		HStack(spacing: 12) {
			Image(systemName: "bell.slash")
				.foregroundStyle(.secondary)
				.frame(width: 22)
			Text(bundleID)
				.font(.subheadline)
				.textSelection(.enabled)
				.lineLimit(1)
				.truncationMode(.middle)
			Spacer(minLength: 0)
		}
		.swipeActions(edge: .trailing, allowsFullSwipe: true) {
			Button {
				_manager.resume(bundleID)
			} label: {
				Label(.localized("Resume Updates"), systemImage: "bell")
			}
			.tint(.accentColor)
		}
	}

	@ViewBuilder
	private var _overlay: some View {
		if _manager.bundleIDs.isEmpty {
			NBContentUnavailable(
				.localized("No Ignored Apps"),
				systemImage: "bell.slash",
				description: .localized("Long-press an app in Sources and choose Ignore Updates. Ignored apps appear here.")
			)
		} else if _filtered.isEmpty {
			NBContentUnavailable(
				.localized("No Results"),
				systemImage: "magnifyingglass",
				description: .localized("No ignored apps match your search.")
			)
		}
	}

	private func _resumeAll() {
		for id in _manager.bundleIDs { _manager.resume(id) }
	}
}
