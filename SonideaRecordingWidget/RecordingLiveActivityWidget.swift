//
//  RecordingLiveActivityWidget.swift
//  SonideaRecordingWidget
//
//  Live Activity widget for Dynamic Island and Lock Screen during recording.
//  Apple Voice Memos-inspired design with polished controls.
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
                // ── Expanded Dynamic Island ──

                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        RecordingIndicatorDot(isRecording: context.state.isRecording)

                        Text(context.state.isRecording ? "REC" : "PAUSED")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(context.state.isRecording ? .red : .orange)
                    }
                    .padding(.leading, 2)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    ElapsedTimeView(
                        startDate: context.attributes.startDate,
                        isRecording: context.state.isRecording,
                        pausedDuration: context.state.pausedDuration
                    )
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.trailing, 2)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 16) {
                        // Waveform bars (visual indicator)
                        WaveformBars(isRecording: context.state.isRecording)
                            .frame(height: 24)

                        Spacer()

                        // Controls
                        HStack(spacing: 12) {
                            if context.state.isRecording {
                                Button(intent: PauseRecordingIntent()) {
                                    Image(systemName: "pause.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .frame(width: 36, height: 36)
                                        .background(.white.opacity(0.15), in: Circle())
                                }
                                .buttonStyle(.plain)
                            } else {
                                Button(intent: ResumeRecordingIntent()) {
                                    Image(systemName: "play.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.green)
                                        .frame(width: 36, height: 36)
                                        .background(.green.opacity(0.15), in: Circle())
                                }
                                .buttonStyle(.plain)
                            }

                            Button(intent: StopRecordingIntent()) {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 36, height: 36)
                                    .background(.red, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 2)
                }
            } compactLeading: {
                // Compact: Red recording dot + mic icon
                HStack(spacing: 4) {
                    Circle()
                        .fill(context.state.isRecording ? Color.red : Color.orange)
                        .frame(width: 6, height: 6)

                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(context.state.isRecording ? .red : .orange)
                }
            } compactTrailing: {
                // Compact: Timer
                ElapsedTimeView(
                    startDate: context.attributes.startDate,
                    isRecording: context.state.isRecording,
                    pausedDuration: context.state.pausedDuration
                )
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            } minimal: {
                // Minimal: Pulsing red mic
                ZStack {
                    Circle()
                        .fill(context.state.isRecording ? Color.red.opacity(0.3) : Color.orange.opacity(0.3))
                        .frame(width: 22, height: 22)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(context.state.isRecording ? .red : .orange)
                }
            }
        }
    }
}

// MARK: - Recording Indicator Dot

private struct RecordingIndicatorDot: View {
    let isRecording: Bool

    var body: some View {
        ZStack {
            // Glow ring
            if isRecording {
                Circle()
                    .fill(Color.red.opacity(0.3))
                    .frame(width: 14, height: 14)
            }
            // Solid dot
            Circle()
                .fill(isRecording ? Color.red : Color.orange)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Waveform Bars (Visual Recording Indicator)

private struct WaveformBars: View {
    let isRecording: Bool

    // Fixed bar heights for a visually appealing waveform shape
    private let barHeights: [CGFloat] = [0.3, 0.5, 0.8, 1.0, 0.7, 0.9, 0.6, 0.4, 0.7, 1.0, 0.5, 0.3]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barHeights.count, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(isRecording ? Color.red : Color.orange.opacity(0.5))
                    .frame(width: 3, height: isRecording ? barHeights[index] * 24 : 4)
            }
        }
        .opacity(isRecording ? 1.0 : 0.5)
    }
}

// MARK: - Lock Screen View

struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<RecordingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            // Left: Recording status with waveform bars
            HStack(spacing: 10) {
                // Animated recording indicator
                ZStack {
                    if context.state.isRecording {
                        Circle()
                            .fill(Color.red.opacity(0.25))
                            .frame(width: 28, height: 28)
                    }
                    Circle()
                        .fill(context.state.isRecording ? Color.red : Color.orange)
                        .frame(width: 14, height: 14)
                    Image(systemName: context.state.isRecording ? "mic.fill" : "pause")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.isRecording ? "Recording" : "Paused")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    // Mini waveform bars on lock screen
                    HStack(spacing: 1.5) {
                        ForEach(0..<8, id: \.self) { i in
                            let heights: [CGFloat] = [0.4, 0.7, 1.0, 0.6, 0.9, 0.5, 0.8, 0.3]
                            RoundedRectangle(cornerRadius: 1)
                                .fill(context.state.isRecording ? Color.red : Color.orange.opacity(0.5))
                                .frame(width: 2.5, height: context.state.isRecording ? heights[i] * 12 : 3)
                        }
                    }
                }
            }

            Spacer()

            // Center: Timer
            ElapsedTimeView(
                startDate: context.attributes.startDate,
                isRecording: context.state.isRecording,
                pausedDuration: context.state.pausedDuration
            )
            .font(.system(size: 28, weight: .bold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)

            Spacer()

            // Right: Controls
            HStack(spacing: 10) {
                if context.state.isRecording {
                    Button(intent: PauseRecordingIntent()) {
                        Image(systemName: "pause.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                            .background(.white.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(intent: ResumeRecordingIntent()) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.green)
                            .frame(width: 34, height: 34)
                            .background(.green.opacity(0.2), in: Circle())
                    }
                    .buttonStyle(.plain)
                }

                Button(intent: StopRecordingIntent()) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.red, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .activityBackgroundTint(Color(red: 0.08, green: 0.08, blue: 0.1))
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
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Previews

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
