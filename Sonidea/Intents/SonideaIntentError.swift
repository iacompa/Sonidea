//
//  SonideaIntentError.swift
//  Sonidea
//
//  Created by Michael Ramos on 2/4/26.
//

import Foundation

// MARK: - Shared Intent Error

/// Error type shared across all Sonidea AppIntents.
/// Provides user-friendly error messages for Siri and Shortcuts.
enum SonideaIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noRecordingsFound
    case recordingNotFound(name: String)
    case audioFileNotFound
    case transcriptionNotAuthorized
    case transcriptionFailed(message: String)
    case exportFailed(message: String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noRecordingsFound:
            return "No recordings found. Record something first!"
        case .recordingNotFound(let name):
            return "No recording found matching \"\(name)\""
        case .audioFileNotFound:
            return "The audio file could not be found on disk."
        case .transcriptionNotAuthorized:
            return "Speech recognition is not authorized. Please enable it in Settings > Privacy > Speech Recognition."
        case .transcriptionFailed(let message):
            return "Transcription failed: \(message)"
        case .exportFailed(let message):
            return "Export failed: \(message)"
        }
    }
}
