//
//  StartRecordingIntent.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AppIntents
import Foundation

/// AppIntent for starting a recording via Shortcuts, Action Button, or Lock Screen Widget
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start a new voice recording in VoiceMemoPro")

    /// Opens the app when executed
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Set the pending flag - the app will pick this up when it becomes active
        AppState.setPendingStartRecording()
        return .result()
    }
}

/// Shortcuts provider to make the intent discoverable
struct VoiceMemoProShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartRecordingIntent(),
            phrases: [
                "Start recording in \(.applicationName)",
                "Record with \(.applicationName)",
                "New recording in \(.applicationName)",
                "Start a voice memo in \(.applicationName)"
            ],
            shortTitle: "Start Recording",
            systemImageName: "mic.fill"
        )
    }
}
