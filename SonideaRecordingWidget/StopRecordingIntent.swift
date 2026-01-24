//
//  StopRecordingIntent.swift
//  Sonidea
//
//  AppIntent for stopping a recording via Dynamic Island, Lock Screen, or Shortcuts.
//  This intent can run in the background without opening the app.
//

import AppIntents
import Foundation

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

        return .result()
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let stopRecordingRequested = Notification.Name("stopRecordingRequested")
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
        return .result()
    }
}

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
        return .result()
    }
}

extension Notification.Name {
    static let pauseRecordingRequested = Notification.Name("pauseRecordingRequested")
    static let resumeRecordingRequested = Notification.Name("resumeRecordingRequested")
}
