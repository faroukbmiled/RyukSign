//
//  PremiumSettingsView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - View
struct PremiumSettingsView: View {
	@ObservedObject private var _premium = PremiumManager.shared
	@ObservedObject private var _prefs = PremiumFilterPreferences.shared

	@State private var _isCustomLimit: Bool
	@State private var _customLimit: String
	@State private var _showResetConfirmation = false
	@State private var _errorMessage: String?

	init() {
		let limit = PremiumFilterPreferences.shared.clampedLimit
		__isCustomLimit = State(initialValue: !PremiumFilterPreferences.limitPresets.contains(limit))
		__customLimit = State(initialValue: String(limit))
	}

	// MARK: Body
	var body: some View {
		NBList(.localized("Premium RyukSign"), displayMode: .inline) {
			_statusSection
			_filterSection
			_manageSection
		}
		.animation(.default, value: _prefs.mode)
		.dismissableKeyboard()
		.alert(String.localized("Reset Premium?"), isPresented: $_showResetConfirmation) {
			Button(String.localized("Reset"), role: .destructive) {
				PremiumManager.shared.reset()
				Toast.success(.localized("Premium activation has been reset"))
			}
			Button(String.localized("Cancel"), role: .cancel) { }
		} message: {
			Text(String.localized("This will remove all RyukSign premium repositories and clear your activation. You will need a new key to reactivate."))
		}
		.alert(String.localized("Error"), isPresented: Binding(get: { _errorMessage != nil }, set: { if !$0 { _errorMessage = nil } })) {
			Button(String.localized("Contact %@", arguments: RyukSignAPI.telegramUsername)) {
				RyukSignAPI.openTelegram()
			}
			Button(String.localized("OK"), role: .cancel) { }
		} message: {
			Text(_errorMessage ?? "")
		}
	}

	// MARK: Status
	@ViewBuilder
	private var _statusSection: some View {
		Section {
			HStack {
				Label {
					Text(String.localized(_premium.isActive ? "Premium activated" : "Premium is not active"))
				} icon: {
					Image(systemName: "crown.fill")
						.foregroundStyle(.yellow)
				}

				Spacer()

				if _premium.isWorking {
					ProgressView()
				} else if _premium.isActive {
					Text(String.localized("%lld Sources", arguments: _premium.sourceCount))
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}
		}
	}

	// MARK: Catalog filter
	@ViewBuilder
	private var _filterSection: some View {
		NBSection(.localized("Catalog Filter")) {
			Picker(selection: $_prefs.mode) {
				ForEach(PremiumCatalogFilter.allCases) { mode in
					Label(mode.title, systemImage: mode.icon).tag(mode)
				}
			} label: {
				Label(.localized("Include"), systemImage: "line.3.horizontal.decrease")
			}
			.pickerStyle(.menu)

			switch _prefs.mode {
			case .all:
				EmptyView()
			case .latest:
				_limitPicker

				if _isCustomLimit {
					_customLimitField
				}
			case .since:
				DatePicker(
					selection: $_prefs.sinceDate,
					in: ...Date(),
					displayedComponents: .date
				) {
					Label(.localized("Updated Since"), systemImage: "calendar")
				}
			}
		} footer: {
			Text(_prefs.mode.footer)
		}
	}

	@ViewBuilder
	private var _limitPicker: some View {
		Picker(selection: _limitSelection) {
			ForEach(PremiumFilterPreferences.limitPresets, id: \.self) { preset in
				Text(verbatim: "\(preset)").tag(preset)
			}
			Text(String.localized("Custom")).tag(-1)
		} label: {
			Label(.localized("Limit"), systemImage: "number")
		}
		.pickerStyle(.menu)
	}

	@ViewBuilder
	private var _customLimitField: some View {
		LabeledContent {
			TextField(.localized("Custom Limit"), text: $_customLimit)
				.keyboardType(.numberPad)
				.multilineTextAlignment(.trailing)
		} label: {
			Label(.localized("Custom Limit"), systemImage: "pencil")
		}
		.onChange(of: _customLimit) { value in
			let digits = String(value.filter(\.isNumber).prefix(6))
			if digits != value {
				_customLimit = digits
				return
			}

			if let amount = Int(digits), amount > 0 {
				_prefs.limit = amount
			}
		}
	}

	private var _limitSelection: Binding<Int> {
		Binding(
			get: { _isCustomLimit ? -1 : _prefs.clampedLimit },
			set: { selection in
				if selection == -1 {
					_customLimit = String(_prefs.clampedLimit)
					_isCustomLimit = true
				} else {
					_isCustomLimit = false
					_prefs.limit = selection
				}
			}
		)
	}

	// MARK: Manage
	@ViewBuilder
	private var _manageSection: some View {
		NBSection(.localized("Manage")) {
			Button {
				_restore()
			} label: {
				Label(.localized("Restore Repositories"), systemImage: "arrow.clockwise")
			}
			.disabled(_premium.isWorking)

			Button {
				RyukSignAPI.openTelegram()
			} label: {
				Label(.localized("Get a Key"), systemImage: "paperplane.fill")
			}

			Button(role: .destructive) {
				_showResetConfirmation = true
			} label: {
				Label(.localized("Reset Premium"), systemImage: "trash")
			}
			.disabled(!_premium.isActive || _premium.isWorking)
		} footer: {
			Text(String.localized("Restoring re-adds the repositories your key unlocked on this device."))
		}
	}

	// MARK: Actions
	private func _restore() {
		Task {
			do {
				let count = try await PremiumManager.shared.restore()
				Toast.success(.localized("Restored %lld premium repositories", arguments: count))
			} catch {
				_errorMessage = error.localizedDescription
			}
		}
	}
}
