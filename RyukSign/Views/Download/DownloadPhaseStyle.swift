//
//  DownloadPhaseStyle.swift
//  RyukSign
//
//  Created by Ryuk on 24.08.2026.
//

import SwiftUI
import NimbleExtensions

extension DownloadPhase {
	var tint: Color {
		switch self {
		case .queued: return .secondary
		case .downloading: return .accentColor
		case .paused: return .orange
		case .importing: return .purple
		case .completed: return .green
		}
	}

	var gradient: LinearGradient {
		LinearGradient(colors: [tint.opacity(0.8), tint], startPoint: .leading, endPoint: .trailing)
	}

	var title: String {
		switch self {
		case .queued: return .localized("Queued")
		case .downloading: return .localized("Downloading")
		case .paused: return .localized("Paused")
		case .importing: return .localized("Importing")
		case .completed: return .localized("Completed")
		}
	}
}

extension Download {
	var canCancel: Bool {
		switch phase {
		case .queued, .downloading, .paused: return true
		case .importing, .completed: return false
		}
	}
}

extension DownloadProgressSummary {
	var title: String { phase.title }

	var detail: String {
		var parts: [String] = []
		if downloadingCount > 0 { parts.append(.localized("%lld downloading", arguments: downloadingCount)) }
		if pausedCount > 0 { parts.append(.localized("%lld paused", arguments: pausedCount)) }
		if importingCount > 0 { parts.append(.localized("%lld importing", arguments: importingCount)) }
		return parts.isEmpty ? .localized("Preparing...") : parts.joined(separator: ", ")
	}
}

struct DownloadPhaseBar: View {
	let phase: DownloadPhase
	let progress: Double
	var height: CGFloat = 6

	var body: some View {
		GeometryReader { geometry in
			ZStack(alignment: .leading) {
				RoundedRectangle(cornerRadius: height / 2)
					.frame(height: height)
					.foregroundColor(Color(uiColor: .quaternarySystemFill))

				RoundedRectangle(cornerRadius: height / 2)
					.frame(width: geometry.size.width * min(max(progress, 0), 1), height: height)
					.foregroundStyle(phase.gradient)
					.animation(.easeOut(duration: 0.3), value: progress)
					.animation(.easeInOut(duration: 0.25), value: phase)
			}
		}
		.frame(height: height)
	}
}

struct DownloadPhaseRing: View {
	let phase: DownloadPhase
	let progress: Double
	var size: CGFloat = 28
	var lineWidth: CGFloat = 3

	var body: some View {
		ZStack {
			Circle()
				.stroke(Color(uiColor: .quaternarySystemFill), lineWidth: lineWidth)

			Circle()
				.trim(from: 0, to: min(max(progress, 0), 1))
				.stroke(phase.gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
				.rotationEffect(.degrees(-90))
				.animation(.linear(duration: 0.2), value: progress)
		}
		.frame(width: size, height: size)
	}
}
