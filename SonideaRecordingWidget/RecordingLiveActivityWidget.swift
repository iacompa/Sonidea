//
//  RecordingLiveActivityWidget.swift
//  SonideaRecordingWidget
//
//  Live Activity widget for Dynamic Island and Lock Screen during recording.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI
                DynamicIslandExpandedRegion(.leading) {
                    RecordingIndicator(isRecording: context.state.isRecording)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    StopButton()
                }

                DynamicIslandExpandedRegion(.center) {
                    TimerDisplay(
                        startDate: context.attributes.startDate,
                        isRecording: context.state.isRecording,
                        pausedDuration: context.state.pausedDuration
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        if context.state.isRecording {
                            PauseButton()
                        } else {
                            ResumeButton()
                        }

                        StopAndSaveButton()
                    }
                    .padding(.top, 8)
                }
            } compactLeading: {
                // Compact leading - red recording dot
                RecordingDot(isRecording: context.state.isRecording)
            } compactTrailing: {
                // Compact trailing - timer
                CompactTimerDisplay(
                    startDate: context.attributes.startDate,
                    isRecording: context.state.isRecording,
                    pausedDuration: context.state.pausedDuration
                )
            } minimal: {
                // Minimal - just the recording dot
                RecordingDot(isRecording: context.state.isRecording)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Recording indicator
            RecordingIndicator(isRecording: context.state.isRecording)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.state.isRecording ? "Recording" : "Paused")
                    .font(.headline)
                    .foregroundColor(.primary)

                TimerDisplay(
                    startDate: context.attributes.startDate,
                    isRecording: context.state.isRecording,
                    pausedDuration: context.state.pausedDuration
                )
                .font(.subheadline)
                .foregroundColor(.secondary)
            }

            Spacer()

            // Stop button
            Button(intent: StopRecordingIntent()) {
                Image(systemName: "stop.fill")
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.red)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
        .padding()
        .activityBackgroundTint(Color.black.opacity(0.8))
        .activitySystemActionForegroundColor(Color.white)
    }
}

// MARK: - Recording Indicator

struct RecordingIndicator: View {
    let isRecording: Bool

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isRecording ? Color.red : Color.orange)
                .frame(width: 12, height: 12)
                .opacity(isRecording ? 1.0 : 0.7)

            Image(systemName: "mic.fill")
                .font(.title3)
                .foregroundColor(isRecording ? .red : .orange)
        }
    }
}

// MARK: - Recording Dot (for compact views)

struct RecordingDot: View {
    let isRecording: Bool

    var body: some View {
        Circle()
            .fill(isRecording ? Color.red : Color.orange)
            .frame(width: 12, height: 12)
    }
}

// MARK: - Timer Display

struct TimerDisplay: View {
    let startDate: Date
    let isRecording: Bool
    let pausedDuration: TimeInterval?

    var body: some View {
        if isRecording {
            // Live timer when recording
            Text(startDate, style: .timer)
                .monospacedDigit()
                .contentTransition(.numericText())
        } else if let duration = pausedDuration {
            // Static duration when paused
            Text(formatDuration(duration))
                .monospacedDigit()
        } else {
            Text(startDate, style: .timer)
                .monospacedDigit()
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Compact Timer Display

struct CompactTimerDisplay: View {
    let startDate: Date
    let isRecording: Bool
    let pausedDuration: TimeInterval?

    var body: some View {
        if isRecording {
            Text(startDate, style: .timer)
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.red)
        } else if let duration = pausedDuration {
            Text(formatDuration(duration))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.orange)
        } else {
            Text(startDate, style: .timer)
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.orange)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Buttons

struct StopButton: View {
    var body: some View {
        Button(intent: StopRecordingIntent()) {
            Image(systemName: "stop.fill")
                .font(.title3)
                .foregroundColor(.white)
        }
        .buttonStyle(.plain)
    }
}

struct StopAndSaveButton: View {
    var body: some View {
        Button(intent: StopRecordingIntent()) {
            HStack(spacing: 6) {
                Image(systemName: "stop.fill")
                    .font(.caption)
                Text("Save")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.red)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct PauseButton: View {
    var body: some View {
        Button(intent: PauseRecordingIntent()) {
            HStack(spacing: 6) {
                Image(systemName: "pause.fill")
                    .font(.caption)
                Text("Pause")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.3))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct ResumeButton: View {
    var body: some View {
        Button(intent: ResumeRecordingIntent()) {
            HStack(spacing: 6) {
                Image(systemName: "play.fill")
                    .font(.caption)
                Text("Resume")
                    .font(.caption)
                    .fontWeight(.medium)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.green)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview("Lock Screen", as: .content, using: RecordingActivityAttributes(
    recordingId: "preview",
    startDate: Date(),
    title: "Recording"
)) {
    RecordingLiveActivityWidget()
} contentStates: {
    RecordingActivityAttributes.ContentState(isRecording: true, pausedDuration: nil)
    RecordingActivityAttributes.ContentState(isRecording: false, pausedDuration: 125)
}
