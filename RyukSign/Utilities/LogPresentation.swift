//
//  LogPresentation.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI

enum LogKind {
	case info, success, error, detail

	var tint: Color {
		switch self {
		case .info: .secondary
		case .success: .green
		case .error: .red
		case .detail: .secondary
		}
	}

	var textColor: Color {
		switch self {
		case .info: .primary
		case .success: .green
		case .error: .red
		case .detail: .secondary
		}
	}
}

struct LogEntry: Identifiable {
	let id: UUID
	let date: Date?
	let category: String?
	let message: String
	let kind: LogKind

	init(id: UUID = UUID(), date: Date?, category: String?, message: String, kind: LogKind) {
		self.id = id
		self.date = date
		self.category = category
		self.message = message
		self.kind = kind
	}
}

enum LogParser {
	private static let _iso: ISO8601DateFormatter = {
		let f = ISO8601DateFormatter()
		f.formatOptions = [.withInternetDateTime]
		return f
	}()

	static func sanitize(_ raw: String) -> String {
		guard raw.contains("\u{1B}") else { return raw }
		return raw.replacingOccurrences(of: "\u{1B}\\[[0-9;]*[A-Za-z]", with: "", options: .regularExpression)
	}

	static func classify(_ raw: String, level: SigningLogLine.Level? = nil) -> (kind: LogKind, text: String) {
		let message = sanitize(raw)
		if level == .error || message.hasPrefix("ERROR:") {
			let text = message.hasPrefix("ERROR:")
				? String(message.dropFirst(6)).trimmingCharacters(in: .whitespaces)
				: message
			return (.error, text)
		}

		var text = message
		var detail = false
		if text.hasPrefix(">>>") {
			text = String(text.dropFirst(3)).trimmingCharacters(in: .whitespaces)
			detail = true
		}

		if level == .success || text.range(of: "success", options: .caseInsensitive) != nil {
			return (.success, text)
		}
		return (detail ? .detail : .info, text)
	}

	static func parseFile(_ raw: String, limit: Int? = nil) -> [LogEntry] {
		var lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
		if let limit, lines.count > limit { lines = Array(lines.suffix(limit)) }
		return lines.map { line in
			let line = String(line)
			guard
				let firstSpace = line.firstIndex(of: " "),
				let date = _iso.date(from: String(line[..<firstSpace]))
			else {
				let c = classify(line)
				return LogEntry(date: nil, category: nil, message: c.text, kind: c.kind)
			}

			var rest = String(line[line.index(after: firstSpace)...])
			var category: String?
			if rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
				category = String(rest[rest.index(after: rest.startIndex)..<close])
				rest = String(rest[rest.index(after: close)...]).trimmingCharacters(in: .whitespaces)
			}

			let c = classify(rest)
			return LogEntry(date: date, category: category, message: c.text, kind: c.kind)
		}
	}
}

enum LogFormat {
	private static let _time: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "HH:mm:ss"
		return f
	}()

	private static let _dateTime: DateFormatter = {
		let f = DateFormatter()
		f.dateFormat = "MMM d, HH:mm:ss"
		return f
	}()

	static func string(_ date: Date) -> String {
		Calendar.current.isDateInToday(date) ? _time.string(from: date) : _dateTime.string(from: date)
	}

	static func color(forCategory category: String) -> Color {
		switch category.lowercased() {
		case "sign": .blue
		case "analyze": .orange
		case "inject": .purple
		default: .secondary
		}
	}
}

struct LogRowView: View {
	let entry: LogEntry
	var showCategory = false

	var body: some View {
		HStack(alignment: .top, spacing: 8) {
			RoundedRectangle(cornerRadius: 1)
				.fill(entry.kind.tint.opacity(entry.kind == .info ? 0.4 : 1))
				.frame(width: 2.5)

			VStack(alignment: .leading, spacing: 3) {
				if entry.kind != .detail, _hasMeta {
					HStack(spacing: 6) {
						if let date = entry.date {
							Text(LogFormat.string(date)).monospacedDigit()
						}
						if showCategory, let category = entry.category {
							Text(category.uppercased())
								.padding(.horizontal, 5)
								.padding(.vertical, 1)
								.background(LogFormat.color(forCategory: category).opacity(0.18), in: Capsule())
								.foregroundStyle(LogFormat.color(forCategory: category))
						}
					}
					.font(.system(size: 10, weight: .medium, design: .monospaced))
					.foregroundStyle(.tertiary)
				}

				Text(entry.message)
					.font(.system(.footnote, design: .monospaced))
					.foregroundStyle(entry.kind.textColor)
					.textSelection(.enabled)
					.fixedSize(horizontal: false, vertical: true)
					.frame(maxWidth: .infinity, alignment: .leading)
					.padding(.leading, entry.kind == .detail ? 8 : 0)
			}
		}
	}

	private var _hasMeta: Bool {
		entry.date != nil || (showCategory && entry.category != nil)
	}
}
