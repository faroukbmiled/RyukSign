//
//  LogPresentation.swift
//  RyukSign
//
//  Created by Ryuk
//

import UIKit

enum LogKind {
	case info, success, error, detail

	var tint: UIColor {
		switch self {
		case .info, .detail: .secondaryLabel
		case .success: .systemGreen
		case .error: .systemRed
		}
	}

	var textColor: UIColor {
		switch self {
		case .info: .label
		case .success: .systemGreen
		case .error: .systemRed
		case .detail: .secondaryLabel
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

	static func classify(_ raw: String, level: LogKind? = nil) -> (kind: LogKind, text: String) {
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

	/// Newest first, matching the console.
	static func parseFile(_ raw: String, limit: Int? = nil) -> [LogEntry] {
		var lines = raw.split(separator: "\n", omittingEmptySubsequences: true)
		if let limit, lines.count > limit { lines = Array(lines.suffix(limit)) }
		return lines.reversed().map { line in
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
	private static let _stamp: DateFormatter = {
		let f = DateFormatter()
		f.setLocalizedDateFormatFromTemplate("MMMdjms")
		return f
	}()

	static func string(_ date: Date) -> String {
		_stamp.string(from: date)
	}

	static func color(forCategory category: String) -> UIColor {
		switch category.lowercased() {
		case "sign": .systemBlue
		case "analyze": .systemOrange
		case "inject": .systemPurple
		default: .secondaryLabel
		}
	}
}
