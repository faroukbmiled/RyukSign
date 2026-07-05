//
//  SelfUpdateSheet.swift
//  RyukSign
//
//  Created by Ryuk on 05.07.2026.
//

import SwiftUI
import NimbleViews

struct SelfUpdateSheet: View {
	let release: SelfUpdateRelease
	var offersReminders: Bool = true

	@ObservedObject private var _manager = SelfUpdateManager.shared
	@Environment(\.dismiss) private var dismiss

	private var _isWorking: Bool {
		switch _manager.phase {
		case .downloading, .importing, .signing, .installing, .done: return true
		default: return false
		}
	}

	private var _locksDismiss: Bool {
		switch _manager.phase {
		case .downloading, .importing, .signing: return true
		default: return false
		}
	}

	var body: some View {
		NBNavigationView(release.isInstalled ? .localized("Reinstall") : .localized("Update Available")) {
			ZStack {
				if _isWorking {
					_busy
						.transition(.scale(scale: 0.92).combined(with: .opacity))
				} else {
					ScrollView {
						VStack(alignment: .leading, spacing: 20) {
							_header
							if !release.notes.isEmpty {
								_notes
							}
						}
						.padding()
					}
					.safeAreaInset(edge: .bottom) { _footer }
					.transition(.opacity)
				}
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
			.animation(.spring(response: 0.42, dampingFraction: 0.82), value: _isWorking)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button(.localized("Close")) { dismiss() }
						.disabled(_locksDismiss)
				}
			}
			.interactiveDismissDisabled(_locksDismiss)
			.onDisappear { _manager.endFlow() }
		}
	}

	// MARK: Header

	private var _header: some View {
		VStack(alignment: .leading, spacing: 8) {
			HStack(spacing: 14) {
				Image(uiImage: UIImage(named: Bundle.main.iconFileName ?? "") ?? UIImage())
					.resizable()
					.frame(width: 60, height: 60)
					.clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
				VStack(alignment: .leading, spacing: 3) {
					Text(release.title)
						.font(.title3.bold())
					HStack(spacing: 6) {
						Text(Bundle.main.version)
						Image(systemName: "arrow.right")
							.font(.caption2)
						Text(release.version)
							.foregroundStyle(Color.accentColor)
					}
					.font(.subheadline)
					.foregroundStyle(.secondary)
				}
				Spacer(minLength: 0)
			}
			if let date = release.publishedAt {
				Text(date.formatted(date: .abbreviated, time: .omitted))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
	}

	private var _notes: some View {
		VStack(alignment: .leading, spacing: 8) {
			Text(.localized("What's New"))
				.font(.headline)
			MarkdownView(text: release.notes)
				.foregroundStyle(.secondary)
				.textSelection(.enabled)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	// MARK: Working state

	private var _busy: some View {
		VStack(spacing: 22) {
			Spacer()
			Image(uiImage: UIImage(named: Bundle.main.iconFileName ?? "") ?? UIImage())
				.resizable()
				.frame(width: 72, height: 72)
				.clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

			ZStack {
				if let value = _determinateValue {
					Circle()
						.stroke(Color.secondary.opacity(0.2), lineWidth: 6)
					Circle()
						.trim(from: 0, to: value)
						.stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
						.rotationEffect(.degrees(-90))
						.animation(.easeInOut(duration: 0.25), value: value)
					Text("\(Int(value * 100))%")
						.font(.callout.bold().monospacedDigit())
						.contentTransition(.numericText())
				} else {
					ProgressView()
						.controlSize(.large)
						.scaleEffect(1.3)
				}
			}
			.frame(width: 92, height: 92)
			.transition(.opacity)
			.animation(.smooth(duration: 0.3), value: _determinateValue == nil)

			VStack(spacing: 4) {
				Text(_statusText)
					.font(.headline)
					.contentTransition(.opacity)
				if case .installing = _manager.phase {
					Text(.localized("Installing on the Home Screen. You can close this."))
						.font(.caption)
						.foregroundStyle(.secondary)
						.multilineTextAlignment(.center)
				}
			}
			.animation(.smooth(duration: 0.25), value: _statusText)

			Spacer()

			if !_locksDismiss {
				Button(.localized("Close")) {
					_manager.phase = .idle
					dismiss()
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding()
	}

	// MARK: Footer

	@ViewBuilder
	private var _footer: some View {
		VStack(spacing: 10) {
			if case .failed(let message) = _manager.phase {
				_failure(message)
			} else {
				_actions
			}
		}
		.padding()
		.background(.bar)
	}

	private var _actions: some View {
		VStack(spacing: 10) {
			Label(.localized("Sign with the certificate you first installed RyukSign with, or iOS won't update it in place."), systemImage: "info.circle")
				.font(.caption)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)

			Button {
				_manager.beginUpdate(to: release)
			} label: {
				Text(verbatim: release.isInstalled ? .localized("Reinstall %@", arguments: release.version) : .localized("Update Now"))
					.frame(maxWidth: .infinity)
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.large)

			if offersReminders {
				HStack(spacing: 10) {
					Button(.localized("Remind Me Later")) { dismiss() }
						.frame(maxWidth: .infinity)
					Button(.localized("Ignore This Version"), role: .destructive) {
						_manager.ignore(release.version)
						dismiss()
					}
					.frame(maxWidth: .infinity)
				}
				.buttonStyle(.bordered)
				.controlSize(.large)
			}
		}
	}

	private var _determinateValue: Double? {
		switch _manager.phase {
		case .downloading(let value): return value
		case .installing where _manager.installProgress > 0: return _manager.installProgress
		default: return nil
		}
	}

	private func _failure(_ message: String) -> some View {
		VStack(spacing: 10) {
			Label(message, systemImage: "exclamationmark.triangle.fill")
				.font(.footnote)
				.foregroundStyle(.secondary)
				.frame(maxWidth: .infinity, alignment: .leading)
			HStack(spacing: 10) {
				Button(.localized("Close")) {
					_manager.phase = .idle
					dismiss()
				}
				.frame(maxWidth: .infinity)
				Button(.localized("Try Again")) {
					_manager.beginUpdate(to: release)
				}
				.frame(maxWidth: .infinity)
			}
			.buttonStyle(.bordered)
			.controlSize(.large)
		}
	}

	private var _statusText: String {
		switch _manager.phase {
		case .downloading: return .localized("Downloading")
		case .importing: return .localized("Preparing")
		case .signing: return .localized("Signing")
		case .installing: return .localized("Installing")
		case .done: return .localized("Finishing")
		default: return ""
		}
	}
}
