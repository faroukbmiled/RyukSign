//
//  SigningLog.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

struct SigningLogLine: Identifiable, Equatable {
	enum Level {
		case info
		case success
		case error
	}

	let id = UUID()
	let date: Date
	let level: Level
	let message: String
}

final class SigningLog: ObservableObject {
	static let shared = SigningLog()

	@Published private(set) var lines: [SigningLogLine] = []

	private init() {}

	func reset() {
		DispatchQueue.main.async { self.lines.removeAll() }
	}

	func info(_ message: String) { _append(.info, message) }
	func success(_ message: String) { _append(.success, message) }
	func error(_ message: String) { _append(.error, message) }

	func exportText() -> String {
		let formatter = ISO8601DateFormatter()
		return lines.map { "\(formatter.string(from: $0.date))  \($0.message)" }.joined(separator: "\n")
	}

	private func _append(_ level: SigningLogLine.Level, _ rawMessage: String) {
		let message = LogParser.sanitize(rawMessage)
		if level == .error {
			FileLogger.error(message, category: "sign")
		} else {
			FileLogger.log(message, category: "sign")
		}

		DispatchQueue.main.async {
			self.lines.append(SigningLogLine(date: Date(), level: level, message: message))
		}
	}
}
