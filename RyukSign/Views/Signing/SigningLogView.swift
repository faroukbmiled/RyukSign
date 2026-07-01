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

	private let _bottomAnchor = "ryuksign.log.bottom"

	// MARK: Body
	var body: some View {
		NBNavigationView(.localized("Signing Logs"), displayMode: .inline) {
			ScrollViewReader { proxy in
				ScrollView {
					LazyVStack(alignment: .leading, spacing: 8) {
						ForEach(_log.lines) { line in
							_row(line).id(line.id)
						}
						Color.clear.frame(height: 1).id(_bottomAnchor)
					}
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(12)
					.background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
					.padding()
				}
				.onChange(of: _log.lines.count) { _ in
					_scrollToBottom(proxy, animated: true)
				}
				.onAppear {
					// Re-scroll after the sheet's present animation settles
					_scrollToBottom(proxy, animated: false)
					DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
						_scrollToBottom(proxy, animated: false)
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

	private func _scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
		guard !_log.lines.isEmpty else { return }
		if animated {
			withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(_bottomAnchor, anchor: .bottom) }
		} else {
			proxy.scrollTo(_bottomAnchor, anchor: .bottom)
		}
	}

	private func _row(_ line: SigningLogLine) -> some View {
		let c = LogParser.classify(line.message, level: line.level)
		return LogRowView(entry: LogEntry(id: line.id, date: line.date, category: nil, message: c.text, kind: c.kind))
	}
}
