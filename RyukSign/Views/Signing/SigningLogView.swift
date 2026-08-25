//
//  SigningLogView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningLogView: View {
	@ObservedObject private var _log = SigningLog.shared

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Signing Logs"), displayMode: .inline) {
			LogConsoleView(entries: _log.lines, showCategory: true, style: .transparent)
				.background(Color(uiColor: .systemBackground))
				.overlay {
					if _log.lines.isEmpty {
						Text(.localized("No logs yet"))
							.font(.footnote)
							.foregroundStyle(.secondary)
					}
				}
				.toolbar {
					NBToolbarButton(role: .close)
					NBToolbarButton(
						.localized("Copy"),
						style: .text,
						placement: .topBarLeading,
						isDisabled: _log.lines.isEmpty
					) {
						UIPasteboard.general.string = _log.exportText()
						Toast.success(.localized("Copied"))
					}
				}
		}
	}
}
