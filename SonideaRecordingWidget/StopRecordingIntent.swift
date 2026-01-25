//
//  StopRecordingIntent.swift
//  SonideaRecordingWidget
//
//  AppIntent for controlling recording via Dynamic Island, Lock Screen, or Shortcuts.
//  These intents can run in the background without opening the app.
//  This file is duplicated in the widget extension (widgets can't import main app code).
//

import ActivityKit
import AppIntents
import Foundation

// MARK: - Stop Recording Intent

/// AppIntent for stopping and saving the current recording
/// Used by Dynamic Island Live Activity and Lock Screen widget
struct StopRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Recording"
    static var description = IntentDescription("Stop and save the current recording")

    /// This intent should NOT open the app - it runs in background
    static var openAppWhenRun: Bool = false

    /// Flag to indicate the intent is being processed
    static let pendingStopKey = "pendingStopRecording"

    @MainActor
    func perform() async throws -> some IntentResult {
        // Set a flag that the app will pick up to stop recording
        // This works even when the app is backgrounded
        UserDefaults.standard.set(true, forKey: Self.pendingStopKey)

        // Post notification for immediate handling if app is active
        NotificationCenter.default.post(
            name: .stopRecordingRequested,
            object: nil
        )

        // CRITICAL: End all Live Activities immediately
        // This ensures the Dynamic Island disappears even if the app doesn't respond
        if #available(iOS 16.1, *) {
            for activity in Activity<RecordingActivityAttributes>.activities {
                await activity.end(
                    .init(
                        state: RecordingActivityAttributes.ContentState(
                            isRecording: false,
                            pausedDuration: nil
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }

        return .result()
    }
}

// MARK: - Pause Recording Intent

/// AppIntent for pausing the current recording
struct PauseRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause Recording"
    static var description = IntentDescription("Pause the current recording")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .pauseRecordingRequested,
            object: nil
        )

        // Update the Live Activity to show paused state
        // The main app will also update it, but this provides immediate feedback
        if #available(iOS 16.1, *) {
            for activity in Activity<RecordingActivityAttributes>.activities {
                // Calculate approximate duration based on start date
                let duration = Date().timeIntervalSince(activity.attributes.startDate)
                await activity.update(
                    .init(
                        state: RecordingActivityAttributes.ContentState(
                            isRecording: false,
                            pausedDuration: duration
                        ),
                        staleDate: nil
                    )
                )
            }
        }

        return .result()
    }
}

// MARK: - Resume Recording Intent

/// AppIntent for resuming a paused recording
struct ResumeRecordingIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Resume Recording"
    static var description = IntentDescription("Resume the paused recording")

    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(
            name: .resumeRecordingRequested,
            object: nil
        )

        // Update the Live Activity to show recording state
        if #available(iOS 16.1, *) {
            for activity in Activity<RecordingActivityAttributes>.activities {
                await activity.update(
                    .init(
                        state: RecordingActivityAttributes.ContentState(
                            isRecording: true,
                            pausedDuration: nil
                        ),
                        staleDate: nil
                    )
                )
            }
        }

        return .result()
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let stopRecordingRequested = Notification.Name("stopRecordingRequested")
    static let pauseRecordingRequested = Notification.Name("pauseRecordingRequested")
    static let resumeRecordingRequested = Notification.Name("resumeRecordingRequested")
}
