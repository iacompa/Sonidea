//
//  RecordingLiveActivityWidget.swift
//  SonideaRecordingWidget
//
//  Live Activity widget for Dynamic Island and Lock Screen during recording.
//  Designed with Apple-like minimal aesthetics.
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
                        // Animated recording indicator
                        RecordingPulse(isRecording: context.state.isRecording)

                        Text(context.state.isRecording ? "Recording" : "Paused")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.secondary)
                    }
                }

                DynamicIslandExpandedRegion(.trailing) {
                    // Elapsed time - prominent
                    ElapsedTimeView(
                        startDate: context.attributes.startDate,
                        isRecording: context.state.isRecording,
                        pausedDuration: context.state.pausedDuration
                    )
                    .font(.title2)
                    .fontWeight(.semibold)
                    .fontDesign(.rounded)
                    .monospacedDigit()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    // Action buttons - minimal, icon-focused
                    HStack(spacing: 20) {
                        // Pause/Resume button
                        if context.state.isRecording {
                            Button(intent: PauseRecordingIntent()) {
                                Label("Pause", systemImage: "pause.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    .foregroundStyle(.primary)
                                    .frame(width: 44, height: 36)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Button(intent: ResumeRecordingIntent()) {
                                Label("Resume", systemImage: "play.fill")
                                    .labelStyle(.iconOnly)
                                    .font(.title3)
                                    .foregroundStyle(.green)
                                    .frame(width: 44, height: 36)
                                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                            }
                            .buttonStyle(.plain)
                        }

                        // Stop button
                        Button(intent: StopRecordingIntent()) {
                            Label("Stop", systemImage: "stop.fill")
                                .labelStyle(.iconOnly)
                                .font(.title3)
                                .foregroundStyle(.red)
                                .frame(width: 44, height: 36)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                // Compact leading - mic with subtle animation
                Image(systemName: context.state.isRecording ? "mic.fill" : "mic.slash.fill")
                    .font(.body)
                    .foregroundStyle(context.state.isRecording ? .red : .orange)
                    .symbolEffect(.pulse, options: .repeating, isActive: context.state.isRecording)
            } compactTrailing: {
                // Compact trailing - timer
                ElapsedTimeView(
                    startDate: context.attributes.startDate,
                    isRecording: context.state.isRecording,
                    pausedDuration: context.state.pausedDuration
                )
                .font(.caption)
                .fontWeight(.medium)
                .fontDesign(.rounded)
                .monospacedDigit()
                .foregroundStyle(context.state.isRecording ? .red : .orange)
            } minimal: {
                // Minimal - just a recording indicator
                Image(systemName: "mic.fill")
                    .font(.caption)
                    .foregroundStyle(context.state.isRecording ? .red : .orange)
                    .symbolEffect(.pulse, options: .repeating, isActive: context.state.isRecording)
            }
        }
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 16) {
            // Left side: Recording indicator and status
            HStack(spacing: 10) {
                // Animated pulse indicator
                RecordingPulse(isRecording: context.state.isRecording)

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isRecording ? "Recording" : "Paused")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text("Sonidea")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Center: Elapsed time
            ElapsedTimeView(
                startDate: context.attributes.startDate,
                isRecording: context.state.isRecording,
                pausedDuration: context.state.pausedDuration
            )
            .font(.title)
            .fontWeight(.semibold)
            .fontDesign(.rounded)
            .monospacedDigit()
            .foregroundStyle(.primary)

            Spacer()

            // Right side: Stop button
            Button(intent: StopRecordingIntent()) {
                Image(systemName: "stop.fill")
                    .font(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .frame(width: 40, height: 40)
                    .background(.red, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .activityBackgroundTint(.black.opacity(0.85))
        .activitySystemActionForegroundColor(.white)
    }
}

// MARK: - Recording Pulse Indicator

struct RecordingPulse: View {
    let isRecording: Bool

    var body: some View {
        Circle()
            .fill(isRecording ? Color.red : Color.orange)
            .frame(width: 10, height: 10)
            .shadow(color: isRecording ? .red.opacity(0.5) : .clear, radius: 4)
    }
}

// MARK: - Elapsed Time View

struct ElapsedTimeView: View {
    let startDate: Date
    let isRecording: Bool
    let pausedDuration: TimeInterval?

    var body: some View {
        if isRecording {
            // Live timer when recording
            Text(startDate, style: .timer)
                .contentTransition(.numericText())
        } else if let duration = pausedDuration {
            // Static duration when paused
            Text(formatDuration(duration))
        } else {
            // Fallback
            Text(startDate, style: .timer)
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
