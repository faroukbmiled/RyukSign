//
//  DownloadLiveActivity.swift
//  RyukSignWidgetExtension
//
//  Created for Live Activity support
//

import ActivityKit
import WidgetKit
import SwiftUI
import AppIntents

// MARK: - App Intents for Live Activity Control

struct PauseDownloadsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Downloads"

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: NSNotification.Name("PauseDownloads"), object: nil)
        return .result()
    }
}

struct ResumeDownloadsIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume Downloads"

    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: NSNotification.Name("ResumeDownloads"), object: nil)
        return .result()
    }
}

/// Joins app names, truncating with an ellipsis past maxLength.
private func formatAppNames(_ names: [String], maxLength: Int = 40) -> String {
	if names.isEmpty {
		return "Downloads"
	}

	if names.count == 1 {
		return names[0]
	}

	var result = ""
	var count = 0

	for (index, name) in names.enumerated() {
		let separator = index > 0 ? ", " : ""
		let potential = result + separator + name

		if potential.count > maxLength {
			// Add ellipsis if we have more items
			if index < names.count - 1 {
				result += "…"
			}
			break
		}

		result = potential
		count += 1
	}

	// If we didn't add all names, ensure ellipsis is there
	if count < names.count && !result.hasSuffix("…") {
		result += "…"
	}

	return result
}

private extension DownloadPhase {
	var tint: Color {
		switch self {
		case .queued: return .secondary
		case .downloading: return .blue
		case .paused: return .orange
		case .importing, .signing: return .purple
		case .completed: return .green
		}
	}

	var label: String {
		switch self {
		case .queued: return "Queued"
		case .downloading: return "Downloading"
		case .paused: return "Paused"
		case .importing: return "Importing"
		case .signing: return "Signing"
		case .completed: return "Done"
		}
	}
}

private struct PhaseBadge: View {
	let state: DownloadActivityAttributes.ContentState
	var size: CGFloat = 24
	var lineWidth: CGFloat = 2

	@ViewBuilder var body: some View {
		switch state.resolvedPhase {
		case .paused:
			Button(intent: ResumeDownloadsIntent()) { ring }.buttonStyle(.plain)
		case .downloading:
			Button(intent: PauseDownloadsIntent()) { ring }.buttonStyle(.plain)
		default:
			ring
		}
	}

	private var ring: some View {
		let phase = state.resolvedPhase
		return ZStack {
			Circle()
				.stroke(phase.tint.opacity(0.3), lineWidth: lineWidth)

			Circle()
				.trim(from: 0, to: phase == .completed ? 1 : state.overallProgress)
				.stroke(phase.tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
				.rotationEffect(.degrees(-90))

			Image(systemName: phase.icon)
				.font(.system(size: size * 0.45))
				.foregroundColor(phase.tint)
		}
		.frame(width: size, height: size)
	}
}

struct DownloadLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: DownloadActivityAttributes.self) { context in
      // Lock screen/banner UI
      DownloadLiveActivityView(context: context)
        .activityBackgroundTint(Color.black.opacity(0.3))
        .activitySystemActionForegroundColor(Color.white)

    } dynamicIsland: { context in
      DynamicIsland {
        // Expanded UI — single, clean center layout
        DynamicIslandExpandedRegion(.center) {
          VStack(spacing: 6) {
            // App names - formatted with ellipsis if needed
            Text(formatAppNames(context.state.appNames, maxLength: 30))
              .font(.subheadline)
              .fontWeight(.medium)
              .lineLimit(1)
              .truncationMode(.tail)
              .multilineTextAlignment(.center)

            HStack(spacing: 8) {
              PhaseBadge(state: context.state)

              ProgressView(value: context.state.overallProgress)
                .tint(context.state.resolvedPhase.tint)
                .frame(maxWidth: .infinity)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)

              if context.state.resolvedPhase == .downloading {
                Text(formatSpeed(context.state.bytesPerSecond))
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .monospacedDigit()
              } else {
                Text(context.state.resolvedPhase.label)
                  .font(.caption)
                  .fontWeight(.semibold)
                  .foregroundColor(context.state.resolvedPhase.tint)
              }
            }

            if context.state.resolvedPhase == .downloading || context.state.resolvedPhase == .paused {
              HStack(spacing: 4) {
                Text(formatBytes(context.state.totalBytesDownloaded))
                Text("/")
                Text(formatBytes(context.state.totalBytesExpected))
              }
              .font(.caption2)
              .foregroundColor(.secondary)
            }

            Text(context.state.totalDownloads > 1
              ? "\(context.state.resolvedPhase.label) \(Int(context.state.overallProgress * 100))% • \(context.state.currentDownload)/\(context.state.totalDownloads)"
              : "\(context.state.resolvedPhase.label) \(Int(context.state.overallProgress * 100))%")
              .font(.caption)
              .foregroundColor(context.state.resolvedPhase.tint)
          }
          .padding(.horizontal, 8)
        }

        DynamicIslandExpandedRegion(.leading) { EmptyView() }
        DynamicIslandExpandedRegion(.trailing) { EmptyView() }
        DynamicIslandExpandedRegion(.bottom) { EmptyView() }

      } compactLeading: {
        // Compact leading (left side of notch)
        HStack(spacing: 0) {
          ZStack {
            Circle()
              .stroke(context.state.resolvedPhase.tint.opacity(0.3), lineWidth: 2)
              .frame(width: 20, height: 20)

            Circle()
              .trim(from: 0, to: context.state.overallProgress)
              .stroke(context.state.resolvedPhase.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .frame(width: 20, height: 20)
              .rotationEffect(.degrees(-90))

            Image(systemName: context.state.resolvedPhase.icon)
              .font(.system(size: 10))
              .foregroundColor(context.state.resolvedPhase.tint)
          }

          Text(" ")
            .opacity(0)
        }

      } compactTrailing: {
        // Compact trailing (right side of notch)
        if context.state.resolvedPhase == .completed {
          HStack(spacing: 2) {
            Image(systemName: "checkmark.circle.fill")
            Text("Done")
              .fontWeight(.semibold)
          }
          .font(.caption2)
          .foregroundColor(.green)
        } else {
          Text("\(Int(context.state.overallProgress * 100))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(context.state.resolvedPhase.tint)
        }

      } minimal: {
        // Minimal UI (when multiple activities are active)
        ZStack {
          Circle()
            .stroke(context.state.resolvedPhase.tint.opacity(0.3), lineWidth: 2)
            .frame(width: 18, height: 18)

          Circle()
            .trim(from: 0, to: context.state.overallProgress)
            .stroke(context.state.resolvedPhase.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(-90))

          Image(systemName: context.state.resolvedPhase.icon)
            .font(.system(size: 9))
            .foregroundColor(context.state.resolvedPhase.tint)
        }
      }
      .widgetURL(URL(string: "feather://downloads"))
      .keylineTint(context.state.resolvedPhase.tint)
    }
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytes)
  }

  private func formatSpeed(_ bytesPerSecond: Int64) -> String {
    // Guard against negative or invalid values
    guard bytesPerSecond > 0 else {
      return "0 KB/s"
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytesPerSecond) + "/s"
  }
}

struct DownloadLiveActivityView: View {
  let context: ActivityViewContext<DownloadActivityAttributes>

  var body: some View {
    VStack(spacing: 10) {
      HStack(spacing: 10) {
        PhaseBadge(state: context.state, size: 28, lineWidth: 3)

        VStack(alignment: .leading, spacing: 2) {
          Text(formatAppNames(context.state.appNames, maxLength: 35))
            .font(.subheadline)
            .fontWeight(.bold)
            .lineLimit(1)
            .truncationMode(.tail)

          Text(context.state.totalDownloads > 1
            ? "\(context.state.resolvedPhase.label) (\(context.state.currentDownload)/\(context.state.totalDownloads))"
            : context.state.resolvedPhase.label)
            .font(.caption)
            .foregroundColor(context.state.resolvedPhase.tint)
        }

        Spacer()

        Text("\(Int(context.state.overallProgress * 100))%")
          .font(.title3)
          .fontWeight(.bold)
          .foregroundColor(context.state.resolvedPhase.tint)
      }

      VStack(spacing: 4) {
        ProgressView(value: context.state.overallProgress)
          .tint(context.state.resolvedPhase.tint)

        HStack {
          if context.state.resolvedPhase == .downloading {
            Text(formatSpeed(context.state.bytesPerSecond))
              .font(.caption2)
              .foregroundColor(.secondary)
          } else {
            Text(context.state.resolvedPhase.label)
              .font(.caption2)
              .fontWeight(.semibold)
              .foregroundColor(context.state.resolvedPhase.tint)
          }

          Spacer()

          if context.state.resolvedPhase == .downloading, let completionDate = context.state.estimatedCompletionDate {
            HStack(spacing: 3) {
              Image(systemName: "clock")
              Text(timerInterval: Date()...completionDate, countsDown: true)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
          }

          Spacer()

          if context.state.resolvedPhase == .downloading || context.state.resolvedPhase == .paused {
            Text("\(formatBytes(context.state.totalBytesDownloaded)) / \(formatBytes(context.state.totalBytesExpected))")
              .font(.caption2)
              .foregroundColor(.secondary)
          }
        }
      }
    }
    .padding(16)
  }

  private func formatBytes(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytes)
  }

  private func formatSpeed(_ bytesPerSecond: Int64) -> String {
    // Guard against negative or invalid values
    guard bytesPerSecond > 0 else {
      return "0 KB/s"
    }

    let formatter = ByteCountFormatter()
    formatter.countStyle = .binary
    formatter.allowedUnits = [.useKB, .useMB, .useGB]
    formatter.includesUnit = true
    formatter.isAdaptive = true
    return formatter.string(fromByteCount: bytesPerSecond) + "/s"
  }
}
