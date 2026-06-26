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

            // Icon + Progress + Speed
            HStack(spacing: 8) {
              if context.state.isPaused {
                Button(intent: ResumeDownloadsIntent()) {
                  ZStack {
                    Circle()
                      .stroke(Color.orange.opacity(0.3), lineWidth: 2)
                      .frame(width: 24, height: 24)

                    Circle()
                      .trim(from: 0, to: context.state.overallProgress)
                      .stroke(Color.orange, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                      .frame(width: 24, height: 24)
                      .rotationEffect(.degrees(-90))

                    Image(systemName: "pause.fill")
                      .font(.system(size: 12))
                      .foregroundColor(.orange)
                  }
                }
                .buttonStyle(.plain)
              } else if context.state.isCompleted {
                ZStack {
                  Circle()
                    .stroke(Color.green.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)

                  Circle()
                    .trim(from: 0, to: 1.0)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .frame(width: 24, height: 24)
                    .rotationEffect(.degrees(-90))

                  Image(systemName: "checkmark")
                    .font(.system(size: 12))
                    .foregroundColor(.green)
                }
              } else {
                Button(intent: PauseDownloadsIntent()) {
                  ZStack {
                    Circle()
                      .stroke(Color.blue.opacity(0.3), lineWidth: 2)
                      .frame(width: 24, height: 24)

                    Circle()
                      .trim(from: 0, to: context.state.overallProgress)
                      .stroke(Color.blue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                      .frame(width: 24, height: 24)
                      .rotationEffect(.degrees(-90))

                    Image(systemName: "arrow.down")
                      .font(.system(size: 12))
                      .foregroundColor(.blue)
                  }
                }
                .buttonStyle(.plain)
              }

              ProgressView(value: context.state.overallProgress)
                .tint(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .blue))
                .frame(maxWidth: .infinity)
                .scaleEffect(x: 1, y: 1.5, anchor: .center)

              if context.state.isCompleted {
                Text("Done")
                  .font(.caption)
                  .foregroundColor(.green)
                  .fontWeight(.semibold)
              } else if context.state.isPaused {
                Text("Paused")
                  .font(.caption)
                  .foregroundColor(.orange)
                  .fontWeight(.semibold)
              } else {
                Text(formatSpeed(context.state.bytesPerSecond))
                  .font(.caption)
                  .foregroundColor(.secondary)
                  .monospacedDigit()
              }
            }

            // Download sizes
            HStack(spacing: 4) {
              Text(formatBytes(context.state.totalBytesDownloaded))
                .font(.caption2)
                .foregroundColor(.secondary)
              Text("/")
                .font(.caption2)
                .foregroundColor(.secondary)
              Text(formatBytes(context.state.totalBytesExpected))
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            // Bottom: percent + file count with X/Y format
            if context.state.isCompleted {
              Text(context.state.totalDownloads > 1
                ? "100% • \(context.state.totalDownloads)/\(context.state.totalDownloads)"
                : "100%")
                .font(.caption)
                .foregroundColor(.green)
            } else if context.state.isPaused {
              Text(context.state.totalDownloads > 1
                ? "\(Int(context.state.overallProgress * 100))% • \(context.state.currentDownload)/\(context.state.totalDownloads)"
                : "\(Int(context.state.overallProgress * 100))%")
                .font(.caption)
                .foregroundColor(.orange)
            } else {
              Text(context.state.totalDownloads > 1
                ? "\(Int(context.state.overallProgress * 100))% • \(context.state.currentDownload)/\(context.state.totalDownloads)"
                : "\(Int(context.state.overallProgress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
            }
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
              .stroke(context.state.isCompleted ? Color.green.opacity(0.3) : (context.state.isPaused ? Color.orange.opacity(0.3) : Color.blue.opacity(0.3)), lineWidth: 2)
              .frame(width: 20, height: 20)

            Circle()
              .trim(from: 0, to: context.state.overallProgress)
              .stroke(context.state.isCompleted ? Color.green : (context.state.isPaused ? Color.orange : Color.blue), style: StrokeStyle(lineWidth: 2, lineCap: .round))
              .frame(width: 20, height: 20)
              .rotationEffect(.degrees(-90))

            Image(systemName: context.state.isCompleted ? "checkmark" : (context.state.isPaused ? "pause.fill" : "arrow.down"))
              .font(.system(size: 10))
              .foregroundColor(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .blue))
          }

          Text(" ")
            .opacity(0)
        }

      } compactTrailing: {
        // Compact trailing (right side of notch)
        if context.state.isCompleted {
          HStack(spacing: 2) {
            Image(systemName: "checkmark.circle.fill")
              .font(.caption2)
              .foregroundColor(.green)
            Text("Done")
              .font(.caption2)
              .fontWeight(.semibold)
              .foregroundColor(.green)
          }
        } else if context.state.isPaused {
          Text("\(Int(context.state.overallProgress * 100))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.orange)
        } else {
          Text("\(Int(context.state.overallProgress * 100))%")
            .font(.caption2)
            .fontWeight(.semibold)
            .foregroundColor(.blue)
        }

      } minimal: {
        // Minimal UI (when multiple activities are active)
        ZStack {
          Circle()
            .stroke(context.state.isCompleted ? Color.green.opacity(0.3) : (context.state.isPaused ? Color.orange.opacity(0.3) : Color.blue.opacity(0.3)), lineWidth: 2)
            .frame(width: 18, height: 18)

          Circle()
            .trim(from: 0, to: context.state.overallProgress)
            .stroke(context.state.isCompleted ? Color.green : (context.state.isPaused ? Color.orange : Color.blue), style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(-90))

          Image(systemName: context.state.isCompleted ? "checkmark" : (context.state.isPaused ? "pause.fill" : "arrow.down"))
            .font(.system(size: 9))
            .foregroundColor(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .blue))
        }
      }
      .widgetURL(URL(string: "feather://downloads"))
      .keylineTint(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .blue))
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
      // Top section: Icon, title, and percentage
      HStack(spacing: 10) {
        if context.state.isPaused {
          Button(intent: ResumeDownloadsIntent()) {
            ZStack {
              Circle()
                .stroke(Color.orange.opacity(0.3), lineWidth: 3)
                .frame(width: 28, height: 28)

              Circle()
                .trim(from: 0, to: context.state.overallProgress)
                .stroke(Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))

              Image(systemName: "pause.fill")
                .font(.caption)
                .foregroundColor(.orange)
            }
          }
          .buttonStyle(.plain)
        } else if context.state.isCompleted {
          ZStack {
            Circle()
              .stroke(Color.green.opacity(0.3), lineWidth: 3)
              .frame(width: 28, height: 28)

            Circle()
              .trim(from: 0, to: 1.0)
              .stroke(Color.green, style: StrokeStyle(lineWidth: 3, lineCap: .round))
              .frame(width: 28, height: 28)
              .rotationEffect(.degrees(-90))

            Image(systemName: "checkmark")
              .font(.caption)
              .foregroundColor(.green)
          }
        } else {
          Button(intent: PauseDownloadsIntent()) {
            ZStack {
              Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                .frame(width: 28, height: 28)

              Circle()
                .trim(from: 0, to: context.state.overallProgress)
                .stroke(Color.blue, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 28, height: 28)
                .rotationEffect(.degrees(-90))

              Image(systemName: "arrow.down")
                .font(.caption)
                .foregroundColor(.blue)
            }
          }
          .buttonStyle(.plain)
        }

        VStack(alignment: .leading, spacing: 2) {
          Text(formatAppNames(context.state.appNames, maxLength: 35))
            .font(.subheadline)
            .fontWeight(.bold)
            .lineLimit(1)
            .truncationMode(.tail)

          Text(context.state.isCompleted
            ? (context.state.totalDownloads > 1 ? "Complete (\(context.state.totalDownloads)/\(context.state.totalDownloads))" : "Complete")
            : (context.state.isPaused
              ? (context.state.totalDownloads > 1 ? "Paused (\(context.state.currentDownload)/\(context.state.totalDownloads))" : "Paused")
              : (context.state.totalDownloads > 1 ? "Overall Progress (\(context.state.currentDownload)/\(context.state.totalDownloads))" : "Download Progress")))
            .font(.caption)
            .foregroundColor(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .secondary))
        }

        Spacer()

        if context.state.isCompleted {
          HStack(spacing: 4) {
            Image(systemName: "checkmark.circle.fill")
              .font(.title3)
              .foregroundColor(.green)
            Text("Done")
              .font(.title3)
              .fontWeight(.bold)
              .foregroundColor(.green)
          }
        } else if context.state.isPaused {
          Text("\(Int(context.state.overallProgress * 100))%")
            .font(.title3)
            .fontWeight(.bold)
            .foregroundColor(.orange)
        } else {
          Text("\(Int(context.state.overallProgress * 100))%")
            .font(.title3)
            .fontWeight(.bold)
            .foregroundColor(.blue)
        }
      }

      // Progress bar with speed
      VStack(spacing: 4) {
        ProgressView(value: context.state.overallProgress)
          .tint(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .blue))

        HStack {
          if context.state.isCompleted {
            Text("Completed")
              .font(.caption2)
              .foregroundColor(.green)
              .fontWeight(.semibold)
          } else if context.state.isPaused {
            Text("Paused")
              .font(.caption2)
              .foregroundColor(.orange)
              .fontWeight(.semibold)
          } else {
            Text(formatSpeed(context.state.bytesPerSecond))
              .font(.caption2)
              .foregroundColor(.secondary)
          }

          Spacer()

          if !context.state.isCompleted && !context.state.isPaused, let completionDate = context.state.estimatedCompletionDate {
            HStack(spacing: 3) {
              Image(systemName: "clock")
              Text(timerInterval: Date()...completionDate, countsDown: true)
            }
            .font(.caption2)
            .foregroundColor(.secondary)
          }

          Spacer()

          Text("\(formatBytes(context.state.totalBytesDownloaded)) / \(formatBytes(context.state.totalBytesExpected))")
            .font(.caption2)
            .foregroundColor(context.state.isCompleted ? .green : (context.state.isPaused ? .orange : .secondary))
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
