//
//  TranscriptionManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import Speech

enum TranscriptionError: Error, LocalizedError {
    case notAuthorized
    case notAvailable
    case recognitionFailed(String)
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .notAuthorized:
            return "Speech recognition not authorized. Please enable it in Settings."
        case .notAvailable:
            return "Speech recognition is not available on this device."
        case .recognitionFailed(let message):
            return "Transcription failed: \(message)"
        case .fileNotFound:
            return "Audio file not found."
        }
    }
}

enum TranscriptionAuthStatus {
    case notDetermined
    case authorized
    case denied
    case restricted
}

@MainActor
final class TranscriptionManager {
    static let shared = TranscriptionManager()

    private init() {}

    var authorizationStatus: TranscriptionAuthStatus {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    func requestAuthorization() async -> TranscriptionAuthStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let result: TranscriptionAuthStatus
                switch status {
                case .notDetermined:
                    result = .notDetermined
                case .authorized:
                    result = .authorized
                case .denied:
                    result = .denied
                case .restricted:
                    result = .restricted
                @unknown default:
                    result = .denied
                }
                continuation.resume(returning: result)
            }
        }
    }

    func transcribe(audioURL: URL, language: TranscriptionLanguage = .system) async throws -> String {
        // Check authorization
        let status = authorizationStatus
        if status == .notDetermined {
            let newStatus = await requestAuthorization()
            if newStatus != .authorized {
                throw TranscriptionError.notAuthorized
            }
        } else if status != .authorized {
            throw TranscriptionError.notAuthorized
        }

        // Check file exists
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            throw TranscriptionError.fileNotFound
        }

        // Get recognizer with specified language
        let recognizer: SFSpeechRecognizer?
        if let locale = language.locale {
            recognizer = SFSpeechRecognizer(locale: locale)
        } else {
            recognizer = SFSpeechRecognizer(locale: Locale.current)
        }

        guard let recognizer = recognizer, recognizer.isAvailable else {
            throw TranscriptionError.notAvailable
        }

        // Create recognition request
        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = false

        // Perform recognition
        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed(error.localizedDescription))
                    return
                }

                guard let result = result else {
                    continuation.resume(throwing: TranscriptionError.recognitionFailed("No result returned"))
                    return
                }

                if result.isFinal {
                    let transcript = result.bestTranscription.formattedString
                    continuation.resume(returning: transcript)
                }
            }
        }
    }

    // Convenience method using current locale (backward compatibility)
    func transcribe(audioURL: URL) async throws -> String {
        try await transcribe(audioURL: audioURL, language: .system)
    }
}
