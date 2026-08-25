//
//  LogConsoleView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import UIKit

// MARK: - Representable
// Plain text console, not a row-based list - no cell reuse or insert animations to race.
struct LogConsoleView: UIViewRepresentable {
	// .console: fixed dark surface regardless of system appearance. .transparent: no background, adaptive text.
	enum Style: Equatable { case console, transparent }

	static let consoleBackgroundColor = UIColor(white: 0.095, alpha: 1)

	let entries: [LogEntry]
	var showCategory = false
	var style: Style = .console
	var onRefresh: (() -> Void)?

	func makeUIView(context: Context) -> UITextView {
		let textView = UITextView()
		textView.isEditable = false
		textView.backgroundColor = style == .console ? Self.consoleBackgroundColor : .clear
		textView.alwaysBounceVertical = true
		textView.textContainerInset = UIEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
		textView.textContainer.lineFragmentPadding = 0
		textView.dataDetectorTypes = []
		textView.indicatorStyle = style == .console ? .white : .default

		if onRefresh != nil {
			let control = UIRefreshControl()
			if style == .console { control.tintColor = .white }
			control.addTarget(context.coordinator, action: #selector(Coordinator.refresh), for: .valueChanged)
			textView.refreshControl = control
		}

		return textView
	}

	func updateUIView(_ textView: UITextView, context: Context) {
		context.coordinator.onRefresh = onRefresh
		context.coordinator.apply(entries, showCategory: showCategory, style: style, to: textView)
	}

	func makeCoordinator() -> Coordinator { Coordinator() }
}

// MARK: - Coordinator
extension LogConsoleView {
	final class Coordinator: NSObject {
		var onRefresh: (() -> Void)?

		private var _shown: [LogEntry] = []
		private var _showCategory = false
		private var _style: Style = .console

		func apply(_ entries: [LogEntry], showCategory: Bool, style: Style, to textView: UITextView) {
			textView.refreshControl?.endRefreshing()

			guard
				entries.count != _shown.count
					|| entries.first?.id != _shown.first?.id
					|| showCategory != _showCategory
					|| style != _style
			else { return }

			let sameContext = showCategory == _showCategory && style == _style
			let prepended = sameContext ? _prependedCount(previous: _shown, newEntries: entries) : nil
			_showCategory = showCategory
			_style = style

			guard let prepended, prepended > 0 else {
				_shown = entries
				textView.textStorage.setAttributedString(Self._text(for: entries, showCategory: showCategory, style: style))
				textView.setContentOffset(CGPoint(x: 0, y: -textView.adjustedContentInset.top), animated: false)
				return
			}

			let pinnedToTop = textView.contentOffset.y <= -textView.adjustedContentInset.top + 1
			let heightBefore = textView.contentSize.height
			_shown = entries

			textView.textStorage.insert(Self._text(for: entries.prefix(prepended), showCategory: showCategory, style: style), at: 0)
			textView.layoutIfNeeded()

			if pinnedToTop {
				textView.setContentOffset(CGPoint(x: 0, y: -textView.adjustedContentInset.top), animated: false)
			} else {
				textView.contentOffset.y += textView.contentSize.height - heightBefore
			}
		}

		@objc func refresh() { onRefresh?() }

		// Only true when `newEntries` is `previous` with rows added at the front.
		private func _prependedCount(previous: [LogEntry], newEntries: [LogEntry]) -> Int? {
			guard !previous.isEmpty else { return nil }
			let insertedCount = newEntries.count - previous.count
			guard insertedCount > 0 else { return nil }
			for i in 0..<previous.count where newEntries[i + insertedCount].id != previous[i].id {
				return nil
			}
			return insertedCount
		}

		private static func _text(for entries: some Sequence<LogEntry>, showCategory: Bool, style: Style) -> NSAttributedString {
			let result = NSMutableAttributedString()
			for entry in entries { result.append(_line(for: entry, showCategory: showCategory, style: style)) }
			return result
		}

		private static let _font = UIFontMetrics(forTextStyle: .footnote)
			.scaledFont(for: .monospacedSystemFont(ofSize: 13, weight: .regular))
		private static let _metaFont = UIFontMetrics(forTextStyle: .caption2)
			.scaledFont(for: .monospacedSystemFont(ofSize: 11, weight: .bold))
		private static let _detailIndent: CGFloat = 18

		private struct _Palette {
			let info, dim, meta, success, error: UIColor
		}

		private static let _consolePalette = _Palette(
			info: UIColor(red: 0.90, green: 0.91, blue: 0.96, alpha: 1),
			dim: UIColor(red: 0.62, green: 0.65, blue: 0.72, alpha: 1),
			meta: UIColor(red: 0.56, green: 0.60, blue: 0.72, alpha: 1),
			success: UIColor(red: 0.34, green: 0.86, blue: 0.60, alpha: 1),
			error: UIColor(red: 1.00, green: 0.45, blue: 0.47, alpha: 1)
		)
		private static let _transparentPalette = _Palette(
			info: .label,
			dim: _consolePalette.dim,
			meta: .secondaryLabel,
			success: .systemGreen,
			error: .systemRed
		)

		private static func _palette(for style: Style) -> _Palette {
			style == .console ? _consolePalette : _transparentPalette
		}

		private static func _textColor(for kind: LogKind, palette: _Palette) -> UIColor {
			switch kind {
			case .info: palette.info
			case .success: palette.success
			case .error: palette.error
			case .detail: palette.dim
			}
		}

		private static let _tagWidth = "[ANALYZE]".count
		private static let _tagIndent = (String(repeating: " ", count: _tagWidth + 1) as NSString)
			.size(withAttributes: [.font: _metaFont]).width

		private static func _tag(_ category: String) -> String {
			let bracketed = "[\(category.uppercased())]"
			guard bracketed.count < _tagWidth else { return bracketed }
			return bracketed.padding(toLength: _tagWidth, withPad: " ", startingAt: 0)
		}

		private static func _line(for entry: LogEntry, showCategory: Bool, style: Style) -> NSAttributedString {
			let palette = _palette(for: style)
			let block = NSMutableAttributedString()
			let hasMeta = entry.kind != .detail

			// Spacing before an entry lives on its date line, not after the prior one - keeps detail runs tight without lookahead.
			if hasMeta, let date = entry.date {
				let dateParagraph = NSMutableParagraphStyle()
				dateParagraph.paragraphSpacingBefore = 10
				dateParagraph.paragraphSpacing = 3
				block.append(NSAttributedString(
					string: LogFormat.string(date) + "\n",
					attributes: [.font: _metaFont, .foregroundColor: palette.meta, .paragraphStyle: dateParagraph]
				))
			}

			let line = NSMutableAttributedString()
			if hasMeta, showCategory, let category = entry.category {
				line.append(NSAttributedString(
					string: "\(_tag(category)) ",
					attributes: [.font: _metaFont, .foregroundColor: LogFormat.color(forCategory: category)]
				))
			}

			line.append(NSAttributedString(
				string: entry.message + "\n",
				attributes: [.font: _font, .foregroundColor: _textColor(for: entry.kind, palette: palette)]
			))

			let indent = entry.kind == .detail ? _detailIndent : (showCategory ? _tagIndent : 0)
			let paragraph = NSMutableParagraphStyle()
			paragraph.headIndent = indent
			paragraph.firstLineHeadIndent = entry.kind == .detail ? _detailIndent : 0
			paragraph.paragraphSpacing = 4
			paragraph.lineSpacing = 1
			if hasMeta, entry.date == nil { paragraph.paragraphSpacingBefore = 10 }
			line.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: line.length))

			block.append(line)
			return block
		}
	}
}
