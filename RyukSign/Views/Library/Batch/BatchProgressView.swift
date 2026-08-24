//
//  BatchProgressView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews
import IDeviceSwift

// MARK: - View
struct BatchProgressView: View {
	@Environment(\.dismiss) var dismiss
	@ObservedObject var runner: BatchJobRunner

	// MARK: Body
	var body: some View {
		NBNavigationView(_title, displayMode: .inline) {
			List {
				Section {
					_summary
						.listRowBackground(Color.clear)
						.listRowSeparator(.hidden)
				}

				Section {
					ForEach(runner.items) { item in
						_row(for: item)
					}
				}
			}
			.animation(.smooth, value: runner.currentIndex)
			.toolbar {
				if runner.isFinished || runner.isCancelled {
					NBToolbarButton(.localized("Done"), style: .text, placement: .topBarTrailing) {
						dismiss()
					}
				} else {
					NBToolbarButton(.localized("Cancel"), style: .text, placement: .topBarLeading) {
						runner.cancel()
					}
				}
			}
		}
		.task { await runner.run() }
	}

	private var _title: String {
		switch runner.phase {
		case .signing: .localized("Signing")
		case .installing: .localized("Installing")
		case .finished: .localized("Finished")
		}
	}

	// MARK: Summary

	@ViewBuilder
	private var _summary: some View {
		VStack(spacing: 12) {
			ZStack {
				Circle()
					.stroke(Color(.tertiarySystemFill), lineWidth: 8)

				Circle()
					.trim(from: 0, to: _fraction)
					.stroke(_accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
					.rotationEffect(.degrees(-90))
					.animation(.smooth, value: _fraction)

				Image(systemName: _summaryIcon)
					.font(.system(size: 26, weight: .medium))
					.foregroundStyle(_accent)
			}
			.frame(width: 84, height: 84)
			.padding(.top, 8)

			Text(_headline)
				.font(.headline)

			Text(_detail)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
		}
		.frame(maxWidth: .infinity)
		.padding(.bottom, 8)
	}

	private var _fraction: Double {
		guard !runner.items.isEmpty else { return 0 }
		let settled = runner.items.filter { $0.state != .queued && $0.state != .working }.count
		return runner.isFinished ? 1 : Double(settled) / Double(runner.items.count)
	}

	private var _accent: Color {
		guard runner.isFinished else { return .accentColor }
		return runner.failed > 0 ? .orange : .green
	}

	private var _summaryIcon: String {
		switch runner.phase {
		case .signing: "signature"
		case .installing: "square.and.arrow.down"
		case .finished: runner.failed > 0 ? "exclamationmark.triangle.fill" : "checkmark"
		}
	}

	private var _headline: String {
		runner.isFinished
			? _title
			: .localized("%lld of %lld", arguments: runner.currentIndex + 1, runner.items.count)
	}

	private var _detail: String {
		guard runner.isFinished else {
			return runner.items.indices.contains(runner.currentIndex)
				? (runner.items[runner.currentIndex].installable.name ?? .localized("Unknown"))
				: ""
		}

		return runner.failed > 0
			? .localized("%lld succeeded, %lld failed", arguments: runner.succeeded, runner.failed)
			: .localized("%lld of %lld", arguments: runner.succeeded, runner.items.count)
	}

	// MARK: Rows

	@ViewBuilder
	private func _row(for item: BatchItem) -> some View {
		HStack(spacing: NBSpacing.row) {
			FRAppIconView(app: item.installable, size: 44)

			if let installer = runner.currentInstaller, item.state == .working, runner.phase == .installing {
				BatchInstallRowView(
					name: item.installable.name ?? .localized("Unknown"),
					installer: installer,
					onSkip: runner.skipCurrentInstall
				)
			} else {
				VStack(alignment: .leading, spacing: 2) {
					Text(item.installable.name ?? .localized("Unknown"))
						.font(.headline)

					Text(_subtitle(for: item))
						.font(.subheadline)
						.foregroundStyle(_isFailed(item) ? Color.red : .secondary)
						.lineLimit(2)
				}
				.frame(maxWidth: .infinity, alignment: .leading)

				_stateIcon(for: item)
			}
		}
		.padding(.vertical, 4)
	}

	private func _isFailed(_ item: BatchItem) -> Bool {
		if case .failed = item.state { return true }
		return false
	}

	private func _subtitle(for item: BatchItem) -> String {
		switch item.state {
		case .queued: .localized("Queued")
		case .working: runner.phase == .signing ? .localized("Signing") : .localized("Installing")
		case .signed: .localized("Signed")
		case .installed: .localized("Installed")
		case .failed(let message): message
		case .skipped: .localized("Skipped")
		}
	}

	@ViewBuilder
	private func _stateIcon(for item: BatchItem) -> some View {
		switch item.state {
		case .queued:
			Image(systemName: "circle.dotted")
				.foregroundStyle(.secondary)
		case .working:
			ProgressView()
		case .signed:
			Image(systemName: runner.mode.installs ? "signature" : "checkmark.circle.fill")
				.foregroundStyle(runner.mode.installs ? Color.accentColor : .green)
		case .installed:
			Image(systemName: "checkmark.circle.fill")
				.foregroundStyle(.green)
		case .failed:
			Image(systemName: "exclamationmark.triangle.fill")
				.foregroundStyle(.red)
		case .skipped:
			Image(systemName: "minus.circle")
				.foregroundStyle(.secondary)
		}
	}
}

// MARK: - View: Active install row
private struct BatchInstallRowView: View {
	let name: String
	@ObservedObject var installer: AppInstaller
	@ObservedObject var viewModel: InstallerStatusViewModel
	let onSkip: () -> Void

	init(name: String, installer: AppInstaller, onSkip: @escaping () -> Void) {
		self.name = name
		self.installer = installer
		self.viewModel = installer.viewModel
		self.onSkip = onSkip
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack {
				Text(name)
					.font(.headline)

				Spacer()

				Button(.localized("Skip"), action: onSkip)
					.font(.subheadline.weight(.medium))
					.buttonStyle(.bordered)
					.controlSize(.small)
			}

			ProgressView(value: viewModel.overallProgress)
				.animation(.smooth, value: viewModel.overallProgress)

			Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.labelStyle(.titleAndIcon)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.sheet(isPresented: $installer.isPresentingFallbackPage) {
			if let url = installer.fallbackPageURL {
				SafariRepresentableView(url: url).ignoresSafeArea()
			}
		}
	}
}
