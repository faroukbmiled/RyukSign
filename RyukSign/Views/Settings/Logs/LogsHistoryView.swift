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
	@State private var _text: String = ""

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Activity Logs"), displayMode: .inline) {
			ScrollView {
				if _text.isEmpty {
					Text(.localized("No logs yet"))
						.font(.footnote)
						.foregroundStyle(.secondary)
						.frame(maxWidth: .infinity)
						.padding(.top, 80)
				} else {
					Text(_text)
						.font(.system(.footnote, design: .monospaced))
						.textSelection(.enabled)
						.frame(maxWidth: .infinity, alignment: .leading)
						.padding()
				}
			}
			.refreshable { _load() }
			.toolbar {
				NBToolbarMenu(systemImage: "ellipsis.circle", style: .icon, placement: .topBarTrailing) {
					Button(.localized("Share"), systemImage: "square.and.arrow.up") {
						UIActivityViewController.show(activityItems: [FileLogger.logFileURL])
					}
					.disabled(_text.isEmpty)
					Button(.localized("Refresh"), systemImage: "arrow.clockwise") { _load() }
					Divider()
					Button(.localized("Clear"), systemImage: "trash", role: .destructive) {
						FileLogger.clear()
						_text = ""
					}
				}
			}
			.onAppear(perform: _load)
		}
	}

	private func _load() {
		_text = FileLogger.readAll()
	}
}
