//
//  StartRecordingIntent.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AppIntents
import Foundation

/// AppIntent for starting a recording via Shortcuts, Action Button, or Lock Screen Widget
struct StartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start a new voice recording in Sonidea")

    /// Opens the app when executed
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // Set the pending flag - the app will pick this up when it becomes active
        AppState.setPendingStartRecording()
        return .result()
    }
}

/// Shortcuts provider to make all intents discoverable in the Shortcuts app and via Siri
struct SonideaShortcuts: AppShortcutsProvider {
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

        AppShortcut(
            intent: GetLastRecordingIntent(),
            phrases: [
                "Get my last recording in \(.applicationName)",
                "Show my latest recording in \(.applicationName)",
                "Open my last voice memo in \(.applicationName)"
            ],
            shortTitle: "Last Recording",
            systemImageName: "clock.arrow.circlepath"
        )

        AppShortcut(
            intent: TranscribeRecordingIntent(),
            phrases: [
                "Transcribe my recording in \(.applicationName)",
                "Transcribe this recording in \(.applicationName)",
                "Get transcript in \(.applicationName)"
            ],
            shortTitle: "Transcribe",
            systemImageName: "text.bubble"
        )

        AppShortcut(
            intent: ExportRecordingIntent(),
            phrases: [
                "Export my recording from \(.applicationName)",
                "Export recording as WAV from \(.applicationName)",
                "Export last recording from \(.applicationName)"
            ],
            shortTitle: "Export Recording",
            systemImageName: "square.and.arrow.up"
        )
    }
}
