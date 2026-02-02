//
//  RecordButton.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct VoiceMemosRecordButton: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPulsing = false

    private var recordingState: RecordingState {
        appState.recorder.recordingState
    }

    private var isActive: Bool {
        recordingState.isActive
    }

    private var isRecording: Bool {
        recordingState == .recording
    }

    private var isPaused: Bool {
        recordingState == .paused
    }

    // Theme-aware record button color
    private var recordColor: Color {
        palette.recordButton
    }

    var body: some View {
        ZStack {
            // Main recording ring - pulsing when recording, solid when paused
            Circle()
                .stroke(isActive ? recordColor : recordColor.opacity(0.3), lineWidth: 4)
                .frame(width: 80, height: 80)
                .scaleEffect(isRecording && isPulsing ? 1.08 : 1.0)
                .animation(
                    isRecording ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                    value: isPulsing
                )

            // Fill circle - solid when idle/recording, with pause indicator when paused
            Circle()
                .fill(recordColor)
                .frame(width: 68, height: 68)

            // Icon: mic when idle, pause when recording, play when paused
            Group {
                if isPaused {
                    // Play icon to resume
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: 2) // Visually center the play icon
                } else if isRecording {
                    // Pause icon while recording
                    Image(systemName: "pause.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    // Mic icon when idle
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .onChange(of: isRecording) { _, newValue in
            isPulsing = newValue
        }
        .onAppear {
            isPulsing = isRecording
        }
    }

    private var accessibilityLabel: String {
        switch recordingState {
        case .idle:
            return "Start recording"
        case .recording:
            return "Pause recording"
        case .paused:
            return "Resume recording"
        }
    }
}
