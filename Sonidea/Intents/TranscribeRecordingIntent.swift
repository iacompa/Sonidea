//
//  TranscribeRecordingIntent.swift
//  Sonidea
//
//  Created by Michael Ramos on 2/4/26.
//

import AppIntents
import Foundation

// MARK: - Transcribe Recording Intent

/// AppIntent for transcribing a recording via Shortcuts or Siri.
/// Finds the recording by name (case-insensitive contains match) or uses the most recent.
/// Returns the transcript text as a string result.
struct TranscribeRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Transcribe Recording"
    static var description = IntentDescription("Transcribes your most recent recording or a recording by name")

    /// Opens the app when run (transcription needs the full app context)
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Recording Name")
    var recordingName: String?

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        // Load recordings directly from persistence
        let allRecordings = DataSafetyFileOps.load(RecordingItem.self, collection: .recordings)
        let activeRecordings = allRecordings.filter { !$0.isTrashed }

        guard !activeRecordings.isEmpty else {
            throw SonideaIntentError.noRecordingsFound
        }

        // Find the target recording
        let recording: RecordingItem
        if let name = recordingName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Case-insensitive contains match; if multiple matches, use most recent
            let matches = activeRecordings
                .filter { $0.title.lowercased().contains(searchName) }
                .sorted { $0.createdAt > $1.createdAt }

            guard let match = matches.first else {
                throw SonideaIntentError.recordingNotFound(name: name)
            }
            recording = match
        } else {
            // No name provided -- use most recent
            guard let mostRecent = activeRecordings.sorted(by: { $0.createdAt > $1.createdAt }).first else {
                throw SonideaIntentError.noRecordingsFound
            }
            recording = mostRecent
        }

        // If the recording already has a transcript, return it immediately
        if !recording.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            // Navigate to the recording in the app
            UserDefaults.standard.set(recording.id.uuidString, forKey: PendingActionKeys.pendingRecordingNavigation)
            return .result(value: recording.transcript)
        }

        // Transcribe the recording
        let transcriptionManager = TranscriptionManager.shared

        // Check authorization first
        let authStatus = transcriptionManager.authorizationStatus
        if authStatus == .denied || authStatus == .restricted {
            throw SonideaIntentError.transcriptionNotAuthorized
        }

        // Verify the audio file exists
        guard FileManager.default.fileExists(atPath: recording.fileURL.path) else {
            throw SonideaIntentError.audioFileNotFound
        }

        do {
            let result = try await transcriptionManager.transcribe(audioURL: recording.fileURL)

            // Set pending transcription result so the app can save it when it opens
            let transcriptData: [String: String] = [
                "recordingID": recording.id.uuidString,
                "transcript": result.text
            ]
            if let encoded = try? JSONEncoder().encode(transcriptData) {
                UserDefaults.standard.set(encoded, forKey: PendingActionKeys.pendingTranscriptionResult)
            }

            // Navigate to the recording in the app
            UserDefaults.standard.set(recording.id.uuidString, forKey: PendingActionKeys.pendingRecordingNavigation)

            return .result(value: result.text)
        } catch {
            throw SonideaIntentError.transcriptionFailed(message: error.localizedDescription)
        }
    }
}
