//
//  SigningLog.swift
//  RyukSign
//
//  Created by Ryuk
//

import Foundation

// zsign stdout batches rather than one view update per appended line
final class SigningLog: ObservableObject {
	static let shared = SigningLog()

	@Published private(set) var lines: [LogEntry] = []

	private static let _maxLines = 4000
	private static let _flushInterval = 0.08

	private let _queue = DispatchQueue(label: "app.ryuksign.signinglog")
	private var _pending: [LogEntry] = []
	private var _flushScheduled = false

	private init() {}

	func reset() {
		_queue.async {
			self._pending.removeAll()
			DispatchQueue.main.async { self.lines.removeAll() }
		}
	}

	func info(_ message: String, category: String = "sign") { _append(.info, message, category: category) }
	func success(_ message: String, category: String = "sign") { _append(.success, message, category: category) }
	func error(_ message: String, category: String = "sign") { _append(.error, message, category: category) }

	func exportText() -> String {
		let formatter = ISO8601DateFormatter()
		return lines.reversed().map { entry in
			guard let date = entry.date else { return entry.message }
			return "\(formatter.string(from: date))  \(entry.message)"
		}.joined(separator: "\n")
	}

	private func _append(_ level: LogKind, _ rawMessage: String, category: String) {
		let classified = LogParser.classify(rawMessage, level: level)
		guard !classified.text.trimmingCharacters(in: .whitespaces).isEmpty else { return }

		if classified.kind == .error {
			FileLogger.error(classified.text, category: category)
		} else {
			// Re-add the ">>>" marker so re-parsing the file classifies detail lines the same way.
			let logged = classified.kind == .detail ? ">>> \(classified.text)" : classified.text
			FileLogger.log(logged, category: category)
		}

		let entry = LogEntry(date: Date(), category: category, message: classified.text, kind: classified.kind)

		_queue.async {
			self._pending.append(entry)
			guard !self._flushScheduled else { return }
			self._flushScheduled = true
			self._queue.asyncAfter(deadline: .now() + Self._flushInterval) { self._flush() }
		}
	}

	private func _flush() {
		_flushScheduled = false
		guard !_pending.isEmpty else { return }

		let batch = Array(_pending.reversed())
		_pending.removeAll(keepingCapacity: true)

		DispatchQueue.main.async {
			self.lines.insert(contentsOf: batch, at: 0)
			if self.lines.count > Self._maxLines {
				self.lines.removeLast(self.lines.count - Self._maxLines)
			}
		}
	}
}
