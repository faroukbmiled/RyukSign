//
//  NBSkeletonView.swift
//  NimbleKit
//
//  Redacted placeholder rows for loading states (reads as "content is coming"
//  instead of a bare centered spinner). iOS 14+ (.redacted).
//

import SwiftUI

/// A single app-cell-shaped placeholder: rounded icon + two text lines + trailing pill.
public struct NBSkeletonRow: View {
	public init() {}

	public var body: some View {
		HStack(spacing: NBSpacing.row) {
			RoundedRectangle(cornerRadius: 13, style: .continuous)
				.fill(Color(.tertiarySystemFill))
				.frame(width: 57, height: 57)

			VStack(alignment: .leading, spacing: 6) {
				RoundedRectangle(cornerRadius: 4)
					.fill(Color(.tertiarySystemFill))
					.frame(width: 140, height: 14)
				RoundedRectangle(cornerRadius: 4)
					.fill(Color(.tertiarySystemFill))
					.frame(width: 200, height: 11)
			}

			Spacer()

			Capsule()
				.fill(Color(.tertiarySystemFill))
				.frame(width: 64, height: 30)
		}
		.padding(.vertical, 6)
	}
}

/// A list of skeleton rows with a gentle pulse to signal activity.
public struct NBSkeletonList: View {
	private let rows: Int
	@State private var _pulse = false

	public init(rows: Int = 8) {
		self.rows = rows
	}

	public var body: some View {
		VStack(spacing: 12) {
			ForEach(0..<rows, id: \.self) { _ in
				NBSkeletonRow()
			}
			Spacer()
		}
		.padding(.horizontal)
		.padding(.top, 8)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.redacted(reason: .placeholder)
		.opacity(_pulse ? 0.55 : 1.0)
		.animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: _pulse)
		.onAppear { _pulse = true }
		.accessibilityHidden(true)
	}
}
