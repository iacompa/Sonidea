//
//  RecordingLiveActivityWidget.swift
//  SonideaRecordingWidget
//
//  Live Activity widget for Dynamic Island and Lock Screen during recording.
//  Voice Memos-style minimal design.
//

import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct RecordingLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RecordingActivityAttributes.self) { context in
            // Lock Screen / Banner UI
            LockScreenLiveActivityView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded Dynamic Island
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        // Simple red dot indicator
                        Circle()
                            .fill(context.state.isRecording ? Color.red : Color.orange)
                            .frame(width: 8, height: 8)

                        Text(context.state.isRecording ? "Recording" : "Paused")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTimeView(
                        startDate: context.attributes.startDate,
                        isRecording: context.state.isRecording,
                        pausedDuration: context.state.pausedDuration
                    )
                    .font(.title3)
                    .fontWeight(.medium)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 24) {
                        if context.state.isRecording {
                            Button(intent: PauseRecordingIntent()) {
                                Image(systemName: "pause.fill")
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                    .frame(width: 40, height: 32)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(intent: ResumeRecordingIntent()) {
                                Image(systemName: "play.fill")
                                    .font(.body)
                                    .foregroundStyle(.green)
                                    .frame(width: 40, height: 32)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }

                        Button(intent: StopRecordingIntent()) {
                            Image(systemName: "stop.fill")
                                .font(.body)
                                .foregroundStyle(.red)
                                .frame(width: 40, height: 32)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)
                    }
                }
            } compactLeading: {
                // Voice Memos style: tiny red dot or mic
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(context.state.isRecording ? .red : .orange)
            } compactTrailing: {
                // Just the time, minimal
                ElapsedTimeView(
                    startDate: context.attributes.startDate,
                    isRecording: context.state.isRecording,
                    pausedDuration: context.state.pausedDuration
                )
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(context.state.isRecording ? .red : .orange)
            } minimal: {
                // Single waveform icon
                Image(systemName: "waveform")
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
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
            HStack(spacing: 8) {
                Circle()
                    .fill(context.state.isRecording ? Color.red : Color.orange)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isRecording ? "Recording" : "Paused")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Text("Sonidea")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Timer
            ElapsedTimeView(
                startDate: context.attributes.startDate,
                isRecording: context.state.isRecording,
                pausedDuration: context.state.pausedDuration
            )
            .font(.title2)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .monospacedDigit()

            Spacer()

            // Stop button
            Button(intent: StopRecordingIntent()) {
                Image(systemName: "stop.fill")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .activityBackgroundTint(.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Elapsed Time View

struct ElapsedTimeView: View {
    let startDate: Date
    let isRecording: Bool
    let pausedDuration: TimeInterval?

    var body: some View {
        if isRecording {
            Text(startDate, style: .timer)
        } else if let duration = pausedDuration {
            Text(formatDuration(duration))
        } else {
            Text(startDate, style: .timer)
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview("Lock Screen - Recording", as: .content, using: RecordingActivityAttributes(
    recordingId: "preview",
    startDate: Date()
)) {
    RecordingLiveActivityWidget()
} contentStates: {
    RecordingActivityAttributes.ContentState(isRecording: true, pausedDuration: nil)
}

#Preview("Lock Screen - Paused", as: .content, using: RecordingActivityAttributes(
    recordingId: "preview",
    startDate: Date().addingTimeInterval(-125)
)) {
    RecordingLiveActivityWidget()
} contentStates: {
    RecordingActivityAttributes.ContentState(isRecording: false, pausedDuration: 125)
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: RecordingActivityAttributes(
    recordingId: "preview",
    startDate: Date()
)) {
    RecordingLiveActivityWidget()
} contentStates: {
    RecordingActivityAttributes.ContentState(isRecording: true, pausedDuration: nil)
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: RecordingActivityAttributes(
    recordingId: "preview",
    startDate: Date()
)) {
    RecordingLiveActivityWidget()
} contentStates: {
    RecordingActivityAttributes.ContentState(isRecording: true, pausedDuration: nil)
    RecordingActivityAttributes.ContentState(isRecording: false, pausedDuration: 125)
}

#Preview("Dynamic Island Minimal", as: .dynamicIsland(.minimal), using: RecordingActivityAttributes(
    recordingId: "preview",
    startDate: Date()
)) {
    RecordingLiveActivityWidget()
} contentStates: {
    RecordingActivityAttributes.ContentState(isRecording: true, pausedDuration: nil)
}
