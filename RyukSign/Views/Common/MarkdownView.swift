//
//  MarkdownView.swift
//  RyukSign
//
//  Created by Ryuk on 05.07.2026.
//

import SwiftUI

struct MarkdownView: View {
	let text: String

	var body: some View {
		Text(MarkdownView.render(text))
			.frame(maxWidth: .infinity, alignment: .leading)
	}

	// Cached: the sheet republishes often and AttributedString(markdown:) per line isn't free.
	private static var _cache: [String: AttributedString] = [:]

	static func render(_ markdown: String) -> AttributedString {
		if let cached = _cache[markdown] { return cached }
		let result = _build(markdown)
		_cache[markdown] = result
		return result
	}

	private static func _build(_ markdown: String) -> AttributedString {
		let lines = markdown
			.replacingOccurrences(of: "\r\n", with: "\n")
			.replacingOccurrences(of: "\r", with: "\n")
			.components(separatedBy: "\n")
			.map { $0.trimmingCharacters(in: .whitespaces) }

		var out = AttributedString()
		var wrote = false
		var pendingBreak = false

		for line in lines {
			if line.isEmpty || _isRule(line) {
				if wrote { pendingBreak = true }
				continue
			}
			if wrote { out += AttributedString(pendingBreak ? "\n\n" : "\n") }
			out += _style(line)
			wrote = true
			pendingBreak = false
		}
		return out
	}

	private static func _style(_ line: String) -> AttributedString {
		if let level = _headingLevel(line) {
			var piece = _inline(line.dropFirst(level + 1))
			piece.font = level <= 1 ? .headline : .subheadline.bold()
			return piece
		}
		if line.hasPrefix("- ") || line.hasPrefix("* ") || line.hasPrefix("• ") {
			return _inline("•  " + line.dropFirst(2))
		}
		return _inline(line)
	}

	private static func _isRule(_ line: String) -> Bool {
		line.count >= 3 && (line.allSatisfy { $0 == "-" } || line.allSatisfy { $0 == "*" } || line.allSatisfy { $0 == "_" })
	}

	private static func _headingLevel(_ line: String) -> Int? {
		guard line.hasPrefix("#") else { return nil }
		let hashes = line.prefix { $0 == "#" }.count
		return (hashes <= 6 && line.dropFirst(hashes).hasPrefix(" ")) ? hashes : nil
	}

	private static func _inline<S: StringProtocol>(_ string: S) -> AttributedString {
		let options = AttributedString.MarkdownParsingOptions(
			interpretedSyntax: .inlineOnlyPreservingWhitespace,
			failurePolicy: .returnPartiallyParsedIfPossible
		)
		return (try? AttributedString(markdown: String(string), options: options)) ?? AttributedString(string)
	}
}
