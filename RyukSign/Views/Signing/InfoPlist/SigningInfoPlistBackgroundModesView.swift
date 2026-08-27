//
//  SigningInfoPlistBackgroundModesView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct SigningInfoPlistBackgroundModesView: View {
	@Binding var options: Options
	let original: [String: Any]

	private var _knownModes: [(id: String, title: String)] {
		[
			("audio", .localized("Audio and AirPlay")),
			("fetch", .localized("Background Fetch")),
			("remote-notification", .localized("Remote Notifications")),
			("processing", .localized("Background Processing")),
			("location", .localized("Location Updates")),
			("voip", .localized("Voice over IP")),
			("external-accessory", .localized("External Accessory")),
			("bluetooth-central", .localized("Bluetooth Central")),
			("bluetooth-peripheral", .localized("Bluetooth Peripheral")),
			("nearby-interaction", .localized("Nearby Interaction"))
		]
	}

	private var _originalModes: [String] {
		original[MergedInfoPlist.backgroundModesKey] as? [String] ?? []
	}

	private var _selected: [String] {
		MergedInfoPlist(original: original, options: options).backgroundModes
	}

	/// Modes the app already declares that aren't in the known list stay visible, so they can't be dropped by accident.
	private var _modes: [(id: String, title: String)] {
		let known = _knownModes
		let extras = Set(_selected + _originalModes).subtracting(known.map(\.id)).sorted()
		return known + extras.map { (id: $0, title: $0) }
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Background Modes")) {
			Section {
				ForEach(_modes, id: \.id) { mode in
					Toggle(isOn: _binding(for: mode.id)) {
						VStack(alignment: .leading, spacing: 2) {
							Text(mode.title)
							Text(mode.id)
								.font(.caption)
								.foregroundStyle(.secondary)
						}
					}
				}
			} footer: {
				Text(.localized("Background modes only work when the app or an injected tweak actually implements them. Some also need a matching entitlement to install."))
			}
		}
	}
}

// MARK: - Extension: Selection
extension SigningInfoPlistBackgroundModesView {
	private func _binding(for mode: String) -> Binding<Bool> {
		Binding(
			get: { _selected.contains(mode) },
			set: { isOn in
				var modes = _selected
				if isOn {
					guard !modes.contains(mode) else { return }
					modes.append(mode)
				} else {
					modes.removeAll { $0 == mode }
				}
				_apply(modes)
			}
		)
	}

	private func _apply(_ modes: [String]) {
		let key = MergedInfoPlist.backgroundModesKey
		var overrides = options.infoPlistOverrideDict
		var removals = (options.infoPlistRemovals ?? []).filter { $0 != key }
		overrides.removeValue(forKey: key)

		if modes.isEmpty {
			if !_originalModes.isEmpty { removals.append(key) }
		} else if modes.sorted() != _originalModes.sorted() {
			overrides[key] = modes
		}

		options.infoPlistOverrideDict = overrides
		options.infoPlistRemovals = removals.isEmpty ? nil : removals
	}
}
