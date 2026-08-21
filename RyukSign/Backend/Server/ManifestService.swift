//
//  ManifestService.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import OSLog

// itms-services:// only accepts a manifest from a publicly trusted host
enum ManifestService {
	private static let endpoints = [
		"https://ryuksign-install.ryuksign.workers.dev/genPlist",
		"https://api.palera.in/genPlist",
	]
	
	static func resolve(for app: AppInfoPresentable, payload: URL) async -> URL? {
		let candidates = endpoints.compactMap { _url(endpoint: $0, app: app, payload: payload) }
		
		for candidate in candidates {
			if await _serves(candidate) {
				return candidate
			}
			Logger.misc.error("Manifest endpoint unusable: \(candidate.host ?? "?", privacy: .public)")
		}
		
		return candidates.first
	}
	
	private static func _url(endpoint: String, app: AppInfoPresentable, payload: URL) -> URL? {
		guard
			var comps = URLComponents(string: endpoint),
			let identifier = app.identifier,
			let name = app.name,
			let version = app.version
		else {
			return nil
		}
		
		comps.queryItems = [
			URLQueryItem(name: "bundleid", value: identifier),
			URLQueryItem(name: "name", value: name),
			URLQueryItem(name: "version", value: version),
			URLQueryItem(name: "fetchurl", value: payload.absoluteString),
		]
		
		return comps.url
	}
	
	private static func _serves(_ url: URL) async -> Bool {
		guard
			let (data, response) = try? await URLSession.shared.data(for: URLRequest(url: url, timeoutInterval: 10)),
			(response as? HTTPURLResponse)?.statusCode == 200
		else {
			return false
		}
		
		return data.starts(with: Array("<?xml".utf8))
	}
}
