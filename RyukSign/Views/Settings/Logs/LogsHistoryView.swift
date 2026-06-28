//
//  LogsHistoryView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct LogsHistoryView: View {
	@State private var _entries: [LogEntry] = []

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Activity Logs"), displayMode: .inline) {
			ScrollView {
				if _entries.isEmpty {
					Text(.localized("No logs yet"))
						.font(.footnote)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity)
						.padding(.top, 80)
				} else {
					LazyVStack(alignment: .leading, spacing: 8) {
						ForEach(_entries) { LogRowView(entry: $0, showCategory: true) }
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
					.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
					.padding()
				}
			}
			.refreshable { _load() }
			.toolbar {
				NBToolbarMenu(systemImage: "ellipsis.circle", style: .icon, placement: .topBarTrailing) {
					Button(.localized("Share"), systemImage: "square.and.arrow.up") {
						UIActivityViewController.show(activityItems: [FileLogger.logFileURL])
					}
					.disabled(_entries.isEmpty)
					Button(.localized("Refresh"), systemImage: "arrow.clockwise") { _load() }
					Divider()
					Button(.localized("Clear"), systemImage: "trash", role: .destructive) {
						FileLogger.clear()
						_entries = []
					}
				}
			}
			.onAppear(perform: _load)
		}
	}

	private func _load() {
		DispatchQueue.global(qos: .userInitiated).async {
			let entries = LogParser.parseFile(FileLogger.readAll(), limit: 2000)
			DispatchQueue.main.async { _entries = entries }
		}
	}
}
