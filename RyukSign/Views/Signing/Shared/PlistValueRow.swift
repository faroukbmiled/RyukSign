//
//  PlistValueRow.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI

// MARK: - View
struct PlistValueRow: View {
	let key: String
	let value: Any?
	var note: String? = nil
	var tint: Color = .secondary
	var isStruck: Bool = false

	// MARK: Body
	var body: some View {
		HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text(key)
					.strikethrough(isStruck)
				if let note {
					Text(note)
						.font(.caption)
						.foregroundStyle(tint)
				}
			}
			Spacer()
			Text(Self.preview(value))
				.foregroundStyle(.secondary)
				.lineLimit(1)
		}
	}

	static func preview(_ value: Any?) -> String {
		guard let value else { return "" }
		switch value {
		case let number as NSNumber:
			return PlistValueKind.isBoolean(value) ? (number.boolValue ? "✓" : "✗") : "\(number)"
		case let string as String:
			return string
		case let array as [String]:
			return array.joined(separator: ", ")
		case let dictionary as [String: Any]:
			return "\(dictionary.count)"
		case let array as [Any]:
			return "\(array.count)"
		default:
			return ""
		}
	}
}
