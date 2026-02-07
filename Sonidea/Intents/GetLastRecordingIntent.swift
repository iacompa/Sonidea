//
//  GetLastRecordingIntent.swift
//  Sonidea
//
//  Created by Michael Ramos on 2/4/26.
//

import AppIntents
import Foundation

// MARK: - Get Last Recording Intent

/// AppIntent for showing the most recent recording via Shortcuts or Siri.
/// Opens the app and navigates to the most recent recording.
struct GetLastRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Last Recording"
    static var description = IntentDescription("Shows your most recent voice recording in Sonidea")

    /// Opens the app to show the recording
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Load recordings directly from persistence (intents may run before AppState is available)
        let allRecordings = DataSafetyFileOps.load(RecordingItem.self, collection: .recordings)
        let activeRecordings = allRecordings.filter { !$0.isTrashed }

        guard let mostRecent = activeRecordings.sorted(by: { $0.createdAt > $1.createdAt }).first else {
            throw SonideaIntentError.noRecordingsFound
        }

        // Set pending navigation so the app opens to this recording
        UserDefaults.standard.set(mostRecent.id.uuidString, forKey: PendingActionKeys.pendingRecordingNavigation)

        let durationString = Self.formatDuration(mostRecent.duration)
        return .result(value: "\(mostRecent.title) (\(durationString))")
    }

    /// Format a duration in seconds to a human-readable string
    private static func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }
}
