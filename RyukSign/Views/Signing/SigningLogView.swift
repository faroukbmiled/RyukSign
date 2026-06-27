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
					.padding()
				}
				.onChange(of: _log.lines.count) { _ in
					guard let last = _log.lines.last else { return }
					withAnimation(.easeOut(duration: 0.2)) {
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

	@ViewBuilder
	private func _row(_ line: SigningLogLine) -> some View {
		HStack(alignment: .top, spacing: 8) {
			Image(systemName: _symbol(line.level))
				.font(.caption)
				.foregroundStyle(_tint(line.level))
				.frame(width: 16)
			Text(line.message)
				.font(.system(.footnote, design: .monospaced))
				.textSelection(.enabled)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
	}

	private func _symbol(_ level: SigningLogLine.Level) -> String {
		switch level {
		case .info: "circle.fill"
		case .success: "checkmark.circle.fill"
		case .error: "xmark.octagon.fill"
		}
	}

	private func _tint(_ level: SigningLogLine.Level) -> Color {
		switch level {
		case .info: .secondary
		case .success: .green
		case .error: .red
		}
	}
}
