//
//  StorageView.swift
//  RyukSign
//
//  Created by Ryuk
//

import SwiftUI
import NimbleViews

// MARK: - Presentation
extension StorageCategory {
	var title: String {
		switch self {
		case .signed: .localized("Signed Apps")
		case .imported: .localized("Imported Apps")
		case .archives: .localized("Exported IPAs")
		case .tweaks: .localized("Tweaks")
		case .certificates: .localized("Certificates")
		case .caches: .localized("Caches")
		case .logs: .localized("Logs")
		case .temporary: .localized("Temp Files")
		case .leftovers: .localized("Leftovers")
		case .other: .localized("Other")
		}
	}

	var symbol: String {
		switch self {
		case .signed: "checkmark.seal"
		case .imported: "square.and.arrow.down"
		case .archives: "archivebox"
		case .tweaks: "wrench.and.screwdriver"
		case .certificates: "lock.doc"
		case .caches: "photo.stack"
		case .logs: "text.alignleft"
		case .temporary: "clock.arrow.circlepath"
		case .leftovers: "questionmark.folder"
		case .other: "ellipsis.circle"
		}
	}

	var tint: Color {
		switch self {
		case .signed: .blue
		case .imported: .indigo
		case .archives: .teal
		case .tweaks: .orange
		case .certificates: .green
		case .caches: .pink
		case .logs: .brown
		case .temporary: .yellow
		case .leftovers: .red
		case .other: .gray
		}
	}

	var explanation: String? {
		switch self {
		case .leftovers: .localized("Left behind by imports and signings that got interrupted. Nothing uses them.")
		case .temporary: .localized("Work files from importing and signing. Recreated when needed.")
		case .archives: .localized("Saved every time you export or share an IPA. Safe to delete.")
		case .caches: .localized("Icons and web data RyukSign downloaded. Rebuilt as you browse.")
		case .other: .localized("Anything outside RyukSign's own folders, including files you added yourself. The app database is locked so it can't be deleted here.")
		default: nil
		}
	}
}

// MARK: - View
struct StorageView: View {
	@ObservedObject private var _manager = StorageManager.shared
	@State private var _isClearing = false

	// MARK: Body
	var body: some View {
		NBList(.localized("Storage")) {
			Section {
				StorageUsageBar(report: _manager.report)
					.listRowInsets(EdgeInsets(top: 16, leading: 20, bottom: 16, trailing: 20))
			}

			if let report = _manager.report {
				Section {
					ForEach(report.usages) { usage in
						_row(usage)
					}
				}

				_cleanup(report)
			} else {
				_scanning
			}
		}
		.disabled(_isClearing)
		.refreshable { _manager.refresh() }
		.task { _manager.refresh() }
	}
}

// MARK: - View extension
@MainActor
private extension StorageView {
	var _scanning: some View {
		Section {
			HStack(spacing: 10) {
				ProgressView()
				Text(.localized("Calculating…"))
					.foregroundStyle(.secondary)
			}
			.frame(maxWidth: .infinity, alignment: .center)
			.padding(.vertical, 12)
			.listRowBackground(Color.clear)
		}
	}

	@ViewBuilder
	func _row(_ usage: StorageUsage) -> some View {
		if usage.category.isBrowsable, usage.count > 0 {
			NavigationLink(destination: StorageDetailView(category: usage.category)) {
				StorageRowLabel(usage: usage)
			}
		} else {
			StorageRowLabel(usage: usage)
		}
	}

	@ViewBuilder
	func _cleanup(_ report: StorageReport) -> some View {
		Section {
			Button(role: .destructive) {
				DestructiveConfirm.present(
					title: .localized("Free Up Space"),
					message: .localized("Clears caches, logs, temp files and leftovers. Your apps, tweaks and certificates stay.")
				) {
					_clear()
				}
			} label: {
				HStack {
					Label(.localized("Free Up Space"), systemImage: "sparkles")
					Spacer()
					if _isClearing {
						ProgressView()
					} else {
						Text(report.reclaimable.formattedFileSize)
							.foregroundStyle(.secondary)
					}
				}
			}
			.disabled(report.reclaimable == 0)
		} footer: {
			Text(.localized("Signing keeps the imported copy too, so an app you signed is stored twice. Delete the import if you won't sign it again."))
		}
	}

	func _clear() {
		_isClearing = true
		Task {
			await _manager.clear(StorageCategory.safeToClear)
			_isClearing = false
			Toast.success(.localized("Space freed"))
		}
	}
}

// MARK: - View: row
struct StorageRowLabel: View {
	let usage: StorageUsage

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: usage.category.symbol)
				.font(.system(size: 14, weight: .semibold))
				.foregroundStyle(.white)
				.frame(width: 28, height: 28)
				.background(usage.category.tint, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

			VStack(alignment: .leading, spacing: 1) {
				Text(usage.category.title)
				if usage.count > 0 {
					Text(verbatim: .localized("%lld items", arguments: usage.count))
						.font(.caption)
						.foregroundStyle(.secondary)
				}
			}

			Spacer(minLength: 8)

			Text(usage.size.formattedFileSize)
				.font(.subheadline)
				.foregroundStyle(.secondary)
		}
	}
}

// MARK: - View: usage bar
struct StorageUsageBar: View {
	let report: StorageReport?

	var body: some View {
		VStack(alignment: .leading, spacing: 10) {
			HStack(alignment: .firstTextBaseline) {
				Text(report?.total.formattedFileSize ?? "—")
					.font(.system(size: 30, weight: .semibold, design: .rounded))
					.contentTransition(.numericText())
				Text(.localized("used by RyukSign"))
					.font(.subheadline)
					.foregroundStyle(.secondary)
			}

			_bar

			if let report {
				Text(verbatim: .localized("%@ free on device", arguments: report.deviceFree.formattedFileSize))
					.font(.caption)
					.foregroundStyle(.secondary)
			}
		}
		.animation(.snappy, value: report?.total)
	}

	private var _bar: some View {
		GeometryReader { geometry in
			HStack(spacing: 1) {
				ForEach(_segments, id: \.category) { usage in
					Rectangle()
						.fill(usage.category.tint)
						.frame(width: geometry.size.width * _fraction(of: usage))
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
		}
		.frame(height: 10)
		.background(Color(.tertiarySystemFill))
		.clipShape(Capsule())
	}

	private var _segments: [StorageUsage] {
		(report?.usages ?? []).sorted { $0.size > $1.size }
	}

	private func _fraction(of usage: StorageUsage) -> Double {
		guard let total = report?.total, total > 0 else { return 0 }
		return Double(usage.size) / Double(total)
	}
}
