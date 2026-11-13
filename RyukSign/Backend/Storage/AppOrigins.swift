//
//  AppOrigins.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

struct AppOrigin: Codable, Hashable, Sendable {
	let source: String
	let appID: String?
	let name: String?
	let version: String?
}

final class AppOrigins: @unchecked Sendable {
	static let shared = AppOrigins()
	static let didChange = Notification.Name("RyukSign.appOriginsChanged")

	private let _lock = NSLock()
	private var _origins: [String: AppOrigin]
	private let _url = URL.applicationSupportDirectory.appendingPathComponent("AppOrigins.json")

	private init() {
		_origins = (try? JSONDecoder().decode([String: AppOrigin].self, from: Data(contentsOf: _url))) ?? [:]
	}

	var all: [String: AppOrigin] {
		_lock.withLock { _origins }
	}

	func set(_ origin: AppOrigin?, for uuid: String) {
		_mutate { $0[uuid] = origin }
	}

	func copy(from source: String?, to uuid: String) {
		guard let source else { return }
		_mutate { $0[uuid] = $0[source] }
	}

	func prune(keeping uuids: Set<String>) {
		_mutate { origins in origins = origins.filter { uuids.contains($0.key) } }
	}

	private func _mutate(_ change: (inout [String: AppOrigin]) -> Void) {
		let changed = _lock.withLock {
			let before = _origins
			change(&_origins)
			guard before != _origins, let data = try? JSONEncoder().encode(_origins) else { return false }

			try? FileManager.default.createDirectory(at: _url.deletingLastPathComponent(), withIntermediateDirectories: true)
			try? data.write(to: _url, options: .atomic)
			return true
		}
		if changed {
			NotificationCenter.default.post(name: Self.didChange, object: nil)
		}
	}
}
