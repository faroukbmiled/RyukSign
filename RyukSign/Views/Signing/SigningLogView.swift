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
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 8) {
						ForEach(_log.lines) { line in
							_row(line).id(line.id)
						}
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
					.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
					.padding()
				}
				.onChange(of: _log.lines.count) { _ in
					guard let last = _log.lines.last else { return }
					withAnimation(.easeOut(duration: 0.2)) {
						proxy.scrollTo(last.id, anchor: .bottom)
					}
				}
				.onAppear {
					guard let last = _log.lines.last else { return }
					DispatchQueue.main.async {
						proxy.scrollTo(last.id, anchor: .bottom)
					}
				}
			}
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

	private func _row(_ line: SigningLogLine) -> some View {
		let c = LogParser.classify(line.message, level: line.level)
		return LogRowView(entry: LogEntry(id: line.id, date: line.date, category: nil, message: c.text, kind: c.kind))
	}
}
