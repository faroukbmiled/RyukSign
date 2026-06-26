//
//  TweakRowLabel.swift
//  RyukSign
//

import SwiftUI
import UIKit
import NimbleViews
import NimbleExtensions

// MARK: - Row label
struct TweakRowLabel: View {
	let tweak: ManagedTweak

	private var _subtitle: String {
		var parts: [String] = []
		if let v = tweak.activeVersion {
			parts.append(v.label)
			if v.components.count > 1 {
				parts.append(.localized("%lld files", arguments: v.components.count))
			}
			parts.append(v.fileSize.formattedFileSize)
		}
		parts.append(.localized("%lld versions", arguments: tweak.versions.count))
		return parts.joined(separator: " · ")
	}

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: tweak.activeVersion?.fileType.systemImage ?? "wrench.and.screwdriver")
				.font(.system(size: 17))
				.foregroundStyle(.tint)
				.frame(width: 30)

			VStack(alignment: .leading, spacing: 2) {
				Text(tweak.name)
					.lineLimit(1)
					.foregroundStyle(tweak.isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(Color.primary.opacity(0.45)))
				Text(_subtitle)
					.font(.caption)
					.foregroundStyle(Color.primary.opacity(0.6))
					.lineLimit(1)
			}

			Spacer()

			if tweak.injectByDefault {
				_badge(.localized("Default"), systemImage: "infinity")
			} else if !tweak.autoInjectBundleIds.isEmpty {
				_badge("\(tweak.autoInjectBundleIds.count)", systemImage: "app.badge")
			}
		}
	}

	@ViewBuilder
	private func _badge(_ text: String, systemImage: String) -> some View {
		HStack(spacing: 3) {
			Image(systemName: systemImage)
				.foregroundStyle(.tint)
			Text(text)
				.foregroundStyle(.primary)
		}
		.font(.caption2.weight(.semibold))
		.padding(.horizontal, 7)
		.padding(.vertical, 3)
		.background(Color.accentColor.opacity(0.15))
		.clipShape(Capsule())
	}
}
