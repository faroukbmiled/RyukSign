//
//  TelegramLinkParser.swift
//  RyukSign
//

import Foundation
import UIKit

enum TelegramLinkParser {
	/// Opens telegram URL in Telegram app if installed, otherwise Safari.
	/// Converts https://t.me/<path> → tg://resolve?domain=<path> when possible.
	static func open(_ url: URL) {
		guard let tgURL = telegramAppURL(from: url) else {
			UIApplication.shared.open(url)
			return
		}
		UIApplication.shared.open(tgURL, options: [:]) { success in
			if !success {
				UIApplication.shared.open(url)
			}
		}
	}

	/// Build tg:// scheme URL from a t.me https URL.
	private static func telegramAppURL(from url: URL) -> URL? {
		guard let host = url.host?.lowercased(),
			  ["t.me", "telegram.me"].contains(host) else { return nil }

		let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard !path.isEmpty else { return URL(string: "tg://") }

		var segments = path.split(separator: "/").map(String.init)

		// Preview mode: t.me/s/channel/... → strip leading "s"
		if segments.first == "s", segments.count >= 2 {
			segments.removeFirst()
		}

		let first = segments[0]

		// Private channel: t.me/c/<channel_id>/<post_id> OR t.me/c/<ch>/<topic>/<post>
		if first == "c", segments.count >= 2 {
			let channelId = segments[1]
			if segments.count >= 4, let topicId = Int(segments[2]), let postId = Int(segments[3]) {
				return URL(string: "tg://privatepost?channel=\(channelId)&thread=\(topicId)&post=\(postId)")
			}
			if segments.count >= 3, let postId = Int(segments[2]) {
				return URL(string: "tg://privatepost?channel=\(channelId)&post=\(postId)")
			}
			return URL(string: "tg://privatepost?channel=\(channelId)")
		}

		// Joinchat / invite link: t.me/+abc or t.me/joinchat/abc
		if first.hasPrefix("+") {
			let hash = String(first.dropFirst())
			return URL(string: "tg://join?invite=\(hash)")
		}
		if first == "joinchat", segments.count >= 2 {
			return URL(string: "tg://join?invite=\(segments[1])")
		}

		// Forum topic post: t.me/channel/<topic>/<post>
		if segments.count >= 3, let topicId = Int(segments[1]), let postId = Int(segments[2]) {
			return URL(string: "tg://resolve?domain=\(first)&thread=\(topicId)&post=\(postId)")
		}

		// Post link: t.me/channel/123
		if segments.count >= 2, let postId = Int(segments[1]) {
			return URL(string: "tg://resolve?domain=\(first)&post=\(postId)")
		}

		// Plain username: t.me/username
		return URL(string: "tg://resolve?domain=\(first)")
	}
	private static let allowedHosts: Set<String> = ["t.me", "telegram.me", "telegram.org"]

	static func extractURL(from text: String) -> URL? {
		guard let start = text.range(of: "<tg-link>"),
			  let end = text.range(of: "</tg-link>") else { return nil }
		let urlString = String(text[start.upperBound..<end.lowerBound])
			.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let url = URL(string: urlString),
			  let host = url.host?.lowercased(),
			  allowedHosts.contains(host) else { return nil }
		return url
	}

	/// Extracts the raw `<tg-link>...</tg-link>` tag from a description, if present.
	static func extractRawTag(from text: String?) -> String? {
		guard let text = text,
			  let start = text.range(of: "<tg-link>"),
			  let end = text.range(of: "</tg-link>") else { return nil }
		return String(text[start.lowerBound..<end.upperBound])
	}

	/// Only strips the tag if the URL is a valid telegram link.
	/// Non-telegram tags are left visible so the user can see/edit them.
	static func stripTag(from text: String?) -> String? {
		guard var desc = text else { return nil }
		if let start = desc.range(of: "<tg-link>"),
		   let end = desc.range(of: "</tg-link>") {
			if extractURL(from: desc) != nil {
				desc.removeSubrange(start.lowerBound..<end.upperBound)
			}
		}
		desc = desc.trimmingCharacters(in: .whitespacesAndNewlines)
		return desc.isEmpty ? nil : desc
	}
}
