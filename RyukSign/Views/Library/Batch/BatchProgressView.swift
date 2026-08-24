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
				.lineLimit(1)
				.minimumScaleFactor(0.8)
				.frame(maxWidth: .infinity)
		}
		.frame(maxWidth: .infinity)
		.padding(.bottom, 8)
	}

	/// Signed apps only count as settled while signing; the install pass has to move them again.
	private var _fraction: Double {
		guard !runner.items.isEmpty else { return 0 }
		guard !runner.isFinished else { return 1 }

		let settled = runner.items.filter { item in
			switch item.state {
			case .queued, .working: false
			case .signed, .alreadySigned: runner.phase == .signing
			default: true
			}
		}.count

		return Double(settled) / Double(runner.items.count)
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

	/// The layout stays identical across states only the trailing accessory and the second line
	/// swap, otherwise every phase change re lays out the whole list.
	@ViewBuilder
	private func _row(for item: BatchItem) -> some View {
		let isInstalling = runner.phase == .installing && item.state == .working

		HStack(spacing: NBSpacing.row) {
			FRAppIconView(app: item.installable, size: 44)

			VStack(alignment: .leading, spacing: 4) {
				Text(item.installable.name ?? .localized("Unknown"))
					.font(.headline)
					.lineLimit(1)

				if isInstalling, let installer = runner.currentInstaller {
					BatchInstallStatusView(installer: installer)
				} else {
					Text(_subtitle(for: item))
						.font(.subheadline)
						.foregroundStyle(_isFailed(item) ? Color.red : .secondary)
						.lineLimit(2)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)

			if isInstalling {
				Button(.localized("Skip"), action: runner.skipCurrentInstall)
					.font(.subheadline.weight(.medium))
					.buttonStyle(.bordered)
					.controlSize(.small)
			} else {
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
		case .alreadySigned: .localized("Already Signed")
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
		case .alreadySigned:
			Image(systemName: "checkmark.seal.fill")
				.foregroundStyle(.secondary)
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

// MARK: - View: Active install status
/// Owns the installer observation so package and upload progress redraw this line alone
/// instead of the whole queue.
private struct BatchInstallStatusView: View {
	@ObservedObject var installer: AppInstaller
	@ObservedObject var viewModel: InstallerStatusViewModel

	init(installer: AppInstaller) {
		self.installer = installer
		self.viewModel = installer.viewModel
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			ProgressView(value: viewModel.overallProgress)
				.animation(.smooth, value: viewModel.overallProgress)

			Label(viewModel.statusLabel, systemImage: viewModel.statusImage)
				.font(.subheadline)
				.foregroundStyle(.secondary)
				.labelStyle(.titleAndIcon)
				.lineLimit(1)
		}
		.frame(maxWidth: .infinity, alignment: .leading)
		.sheet(isPresented: $installer.isPresentingFallbackPage) {
			if let url = installer.fallbackPageURL {
				SafariRepresentableView(url: url).ignoresSafeArea()
			}
		}
	}
}
