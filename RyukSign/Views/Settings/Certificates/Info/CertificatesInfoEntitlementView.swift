//
//  CertificatesInfoEntitlementView.swift
//  RyukSign
//
//  Created by samara on 27.04.2025.
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

// MARK: - View
struct CertificatesInfoEntitlementView: View {
	let entitlements: [String: AnyCodable]

	// MARK: Body
	var body: some View {
		NBList(.localized("Entitlements")) {
			ForEach(entitlements.keys.sorted(), id: \.self) { key in
				if let value = entitlements[key]?.value {
					CertificatesInfoEntitlementCellView(key: key, value: value)
				}
			}
		}
		.listStyle(.grouped)
		.toolbar {
			ToolbarItem(placement: .topBarTrailing) {
				Menu {
					Section(.localized("Copy")) {
						Button {
							_copy(_readableString)
						} label: {
							Label(.localized("Copy as Text"), systemImage: "doc.on.doc")
						}
						Button {
							_copy(_plistString)
						} label: {
							Label(.localized("Copy as Property List"), systemImage: "chevron.left.forwardslash.chevron.right")
						}
					}

					Section(.localized("Export File")) {
						Button {
							_export(_readableString, fileName: "entitlements.txt")
						} label: {
							Label(.localized("Readable Text (.txt)"), systemImage: "doc.text")
						}
						Button {
							_export(_jsonString, fileName: "entitlements.json")
						} label: {
							Label(.localized("JSON (.json)"), systemImage: "curlybraces")
						}
						Button {
							_export(_plistString, fileName: "entitlements.plist")
						} label: {
							Label(.localized("Property List (.plist)"), systemImage: "doc.badge.gearshape")
						}
					}
				} label: {
					Image(systemName: "square.and.arrow.up")
				}
				.disabled(entitlements.isEmpty)
			}
		}
	}

	// MARK: - Formats

	/// Human-readable rendering: sorted keys, Yes/No booleans, bulleted arrays.
	private var _readableString: String {
		let header: String = .localized("Entitlements")
		var lines = ["\(header) (\(entitlements.count))", ""]
		for key in entitlements.keys.sorted() {
			if let value = entitlements[key]?.value {
				lines.append(_readableLine(key: key, value: value, indent: 0))
			}
		}
		return lines.joined(separator: "\n")
	}

	private func _readableLine(key: String, value: Any, indent: Int) -> String {
		let pad = String(repeating: "    ", count: indent)

		switch value {
		case let dict as [String: Any]:
			var out = "\(pad)\(key):"
			if dict.isEmpty { return "\(pad)\(key): (empty)" }
			for k in dict.keys.sorted() {
				out += "\n" + _readableLine(key: k, value: dict[k] as Any, indent: indent + 1)
			}
			return out
		case let array as [Any]:
			if array.isEmpty { return "\(pad)\(key): (empty)" }
			var out = "\(pad)\(key):"
			let childPad = String(repeating: "    ", count: indent + 1)
			for item in array {
				if item is [String: Any] || item is [Any] {
					out += "\n" + _readableLine(key: "•", value: item, indent: indent + 1)
				} else {
					out += "\n\(childPad)• \(_scalar(item))"
				}
			}
			return out
		default:
			return "\(pad)\(key): \(_scalar(value))"
		}
	}

	private func _scalar(_ value: Any) -> String {
		switch value {
		case let bool as Bool: 		return bool ? "Yes" : "No"
		case is NSNull: 			return "—"
		case let number as NSNumber: return number.stringValue
		case let string as String: 	return string
		default: 					return String(describing: value)
		}
	}

	/// Standard XML property list (canonical `.entitlements` format).
	private var _plistString: String {
		let dict = entitlements.mapValues { _sanitize($0.value) }
		if
			let data = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0),
			let string = String(data: data, encoding: .utf8)
		{
			return string
		}
		return _readableString
	}

	private var _jsonString: String {
		let dict = entitlements.mapValues { $0.value }
		if
			JSONSerialization.isValidJSONObject(dict),
			let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
			let string = String(data: data, encoding: .utf8)
		{
			return string
		}
		return _readableString
	}

	/// PropertyListSerialization rejects NSNull, so swap it for an empty string.
	private func _sanitize(_ value: Any) -> Any {
		switch value {
		case is NSNull: 				return ""
		case let dict as [String: Any]: return dict.mapValues { _sanitize($0) }
		case let array as [Any]: 		return array.map { _sanitize($0) }
		default: 						return value
		}
	}

	// MARK: - Actions

	private func _copy(_ text: String) {
		UIPasteboard.general.string = text
		Toast.info(.localized("Copied"), systemImage: "doc.on.doc.fill")
	}

	private func _export(_ text: String, fileName: String) {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
		do {
			try Data(text.utf8).write(to: url, options: .atomic)
			UIActivityViewController.show(activityItems: [url])
		} catch {
			UIAlertController.showAlertWithOk(
				title: .localized("Export Failed"),
				message: error.localizedDescription
			)
		}
	}
}
