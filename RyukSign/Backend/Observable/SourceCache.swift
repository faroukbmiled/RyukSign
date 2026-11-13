//
//  SourceCache.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation
import CryptoKit
import NimbleExtensions

enum SourceCache {
	enum Refresh: Double, CaseIterable {
		case always = 0
		case halfHour = 1800
		case hourly = 3600
		case sixHours = 21600
		case daily = 86400
		case manual = -1

		var title: String {
			switch self {
			case .always: .localized("Every Launch")
			case .halfHour: .localized("Every 30 Minutes")
			case .hourly: .localized("Every Hour")
			case .sixHours: .localized("Every 6 Hours")
			case .daily: .localized("Every Day")
			case .manual: .localized("Only When Pulled")
			}
		}
	}

	static let enabledKey = "RyukSign.cacheSources"
	static let refreshKey = "RyukSign.sourceRefresh"

	static var isEnabled: Bool {
		UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
	}

	static var refresh: Refresh {
		(UserDefaults.standard.object(forKey: refreshKey) as? Double).flatMap(Refresh.init) ?? .halfHour
	}

	static let directory = URL.cachesDirectory.appendingPathComponent("Sources", isDirectory: true)

	static func data(for url: URL) -> (data: Data, date: Date)? {
		let file = _file(for: url)
		guard
			let data = try? Data(contentsOf: file),
			let date = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
		else {
			return nil
		}
		return (data, date)
	}

	static func isStale(_ date: Date) -> Bool {
		switch refresh {
		case .always: true
		case .manual: false
		default: Date().timeIntervalSince(date) > refresh.rawValue
		}
	}

	static func store(_ data: Data, for url: URL) {
		try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		try? data.write(to: _file(for: url), options: .atomic)
	}

	static func size() -> Int64 {
		FileManager.default.allocatedSize(at: directory)
	}

	static func clear() {
		try? FileManager.default.removeItem(at: directory)
	}

	private static func _file(for url: URL) -> URL {
		let hash = SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
		return directory.appendingPathComponent(hash + ".json")
	}
}
