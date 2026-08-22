//
//  LinkTagParser.swift
//  RyukSign
//
//  Extracts hidden `<tg-link>`/`<gh-link>` tags that sources embed in app descriptions,
//  so they render as buttons instead of raw markup.
//

import Foundation
import UIKit
import NimbleExtensions

enum LinkTag: String, CaseIterable {
	case telegram = "tg-link"
	case github = "gh-link"

	var title: String {
		switch self {
		case .telegram: return .localized("Telegram")
		case .github: return .localized("GitHub")
		}
	}

	var symbol: String {
		switch self {
		case .telegram: return "paperplane.fill"
		case .github: return "chevron.left.forwardslash.chevron.right"
		}
	}

	fileprivate var allowedHosts: Set<String> {
		switch self {
		case .telegram: return ["t.me", "telegram.me", "telegram.org"]
		case .github: return ["github.com", "www.github.com", "gist.github.com", "raw.githubusercontent.com"]
		}
	}

	fileprivate var openingTag: String { "<\(rawValue)>" }
	fileprivate var closingTag: String { "</\(rawValue)>" }

	func open(_ url: URL) {
		switch self {
		case .telegram: TelegramLinkParser.open(url)
		case .github: UIApplication.shared.open(url)
		}
	}
}

struct TaggedLink: Identifiable {
	let tag: LinkTag
	let url: URL
	var id: LinkTag { tag }
}

enum LinkTagParser {
	static func url(for tag: LinkTag, in text: String?) -> URL? {
		guard let text, let bounds = bounds(of: tag, in: text) else { return nil }
		let urlString = text[bounds.inner].trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: urlString),
			  let host = url.host?.lowercased(),
			  tag.allowedHosts.contains(host) else { return nil }
		return url
	}

	static func links(in text: String?) -> [TaggedLink] {
		LinkTag.allCases.compactMap { tag in
			url(for: tag, in: text).map { TaggedLink(tag: tag, url: $0) }
		}
	}

	/// Raw tags worth preserving when a description is edited by hand.
	static func rawTags(in text: String?) -> String? {
		guard let text else { return nil }
		let tags = LinkTag.allCases.compactMap { tag -> String? in
			guard url(for: tag, in: text) != nil, let bounds = bounds(of: tag, in: text) else { return nil }
			return String(text[bounds.outer])
		}
		return tags.isEmpty ? nil : tags.joined()
	}

	/// Malformed tags are left visible so the user can see and fix them.
	static func strip(from text: String?) -> String? {
		guard var stripped = text else { return nil }
		for tag in LinkTag.allCases {
			guard url(for: tag, in: stripped) != nil, let bounds = bounds(of: tag, in: stripped) else { continue }
			stripped.removeSubrange(bounds.outer)
		}
		stripped = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
		return stripped.isEmpty ? nil : stripped
	}

	private static func bounds(
		of tag: LinkTag,
		in text: String
	) -> (outer: Range<String.Index>, inner: Range<String.Index>)? {
		guard let start = text.range(of: tag.openingTag),
			  let end = text.range(of: tag.closingTag),
			  start.upperBound <= end.lowerBound else { return nil }
		return (start.lowerBound..<end.upperBound, start.upperBound..<end.lowerBound)
	}
}
