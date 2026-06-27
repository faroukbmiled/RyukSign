//
//  AppLibraryPicker.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import CoreData
import NimbleViews

// Shared single-select picker over the app library (signed + imported).
struct AppLibraryPicker: View {
	@Environment(\.dismiss) private var dismiss

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \Signed.date, ascending: false)],
		animation: .smooth
	) private var _signed: FetchedResults<Signed>

	@FetchRequest(
		sortDescriptors: [NSSortDescriptor(keyPath: \Imported.date, ascending: false)],
		animation: .smooth
	) private var _imported: FetchedResults<Imported>

	@State private var _query = ""

	var title: String = .localized("Choose App")
	var searchPrompt: String = .localized("Search apps")
	var subtitle: (AppInfoPresentable) -> String? = { $0.identifier }
	var showsChevron: Bool = false
	var dismissOnSelect: Bool = true
	var onSelect: (AppInfoPresentable) -> Void

	private var _signedResults: [AppInfoPresentable] { _signed.filter(_matches) }
	private var _importedResults: [AppInfoPresentable] { _imported.filter(_matches) }
	private var _hasResults: Bool { !_signedResults.isEmpty || !_importedResults.isEmpty }
	private var _libraryEmpty: Bool { _signed.isEmpty && _imported.isEmpty }

	// MARK: Body
	var body: some View {
		NBNavigationView(title) {
			NBList(title) {
				if !_signedResults.isEmpty {
					NBSection(.localized("Signed")) { _rows(_signedResults) }
				}
				if !_importedResults.isEmpty {
					NBSection(.localized("Imported")) { _rows(_importedResults) }
				}
			}
			.searchable(text: $_query, placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text(searchPrompt))
			.overlay { _overlay }
			.toolbar { NBToolbarButton(role: .close) }
		}
	}

	@ViewBuilder
	private func _rows(_ apps: [AppInfoPresentable]) -> some View {
		ForEach(Array(apps.enumerated()), id: \.offset) { _, app in
			Button {
				onSelect(app)
				if dismissOnSelect { dismiss() }
			} label: {
				_row(app)
			}
		}
	}

	@ViewBuilder
	private func _row(_ app: AppInfoPresentable) -> some View {
		HStack(spacing: 12) {
			FRAppIconView(app: app, size: 38)
			VStack(alignment: .leading, spacing: 2) {
				Text(app.name ?? .localized("Unknown"))
					.foregroundStyle(.primary)
					.lineLimit(1)
				if let sub = subtitle(app), !sub.isEmpty {
					Text(sub)
						.font(.caption)
						.foregroundStyle(.secondary)
						.lineLimit(1)
						.truncationMode(.middle)
				}
			}
			if showsChevron {
				Spacer()
				Image(systemName: "chevron.right")
					.font(.caption)
					.foregroundStyle(.tint)
			}
		}
	}

	@ViewBuilder
	private var _overlay: some View {
		if !_hasResults {
			NBContentUnavailable(
				_libraryEmpty ? .localized("No Apps") : .localized("No Results"),
				systemImage: _libraryEmpty ? "square.stack.3d.up.slash" : "magnifyingglass",
				description: _libraryEmpty
					? .localized("Import or sign an app to pick from your library.")
					: .localized("No apps match your search.")
			)
		}
	}

	private func _matches(_ app: AppInfoPresentable) -> Bool {
		let q = _query.trimmingCharacters(in: .whitespaces)
		guard !q.isEmpty else { return true }
		return (app.name ?? "").localizedCaseInsensitiveContains(q)
			|| (app.identifier ?? "").localizedCaseInsensitiveContains(q)
	}
}
