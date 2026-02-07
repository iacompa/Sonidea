//
//  TranscriptionManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import Speech

// MARK: - Transcription Segment

/// A single word/phrase segment from speech recognition with timing information.
/// Used for timestamped transcript display with tappable word highlighting.
struct TranscriptionSegment: Identifiable, Codable, Equatable {
    let id: UUID
    let text: String
    let startTime: TimeInterval
    let duration: TimeInterval
    let confidence: Float

    init(id: UUID = UUID(), text: String, startTime: TimeInterval, duration: TimeInterval, confidence: Float) {
        self.id = id
        self.text = text
        self.startTime = startTime
        self.duration = duration
        self.confidence = confidence
    }
}

// MARK: - Transcription Result

/// Result of a transcription operation containing both the full text and individual segments.
struct TranscriptionResult {
    let text: String
    let segments: [TranscriptionSegment]
}

enum TranscriptionError: Error, LocalizedError {
    case notAuthorized
    case notAvailable
    case recognitionFailed(String)
    case fileNotFound
    case timeout

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
        case .timeout:
            return "Transcription timed out after 120 seconds."
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

    func transcribe(audioURL: URL, language: TranscriptionLanguage = .system) async throws -> TranscriptionResult {
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

        // Perform recognition with a 120-second timeout to prevent hanging
        return try await withThrowingTaskGroup(of: TranscriptionResult.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { continuation in
                    // Thread-safe flag to prevent double-resume of the continuation.
                    // The recognition callback fires on an arbitrary queue, while
                    // the cancellation handler runs on the cancelling thread.
                    let resumeLock = NSLock()
                    var hasResumed = false

                    func safeResume(with result: Result<TranscriptionResult, Error>) {
                        resumeLock.lock()
                        defer { resumeLock.unlock() }
                        guard !hasResumed else { return }
                        hasResumed = true
                        continuation.resume(with: result)
                    }

                    let task = recognizer.recognitionTask(with: request) { result, error in
                        if let error = error {
                            safeResume(with: .failure(TranscriptionError.recognitionFailed(error.localizedDescription)))
                            return
                        }

                        guard let result = result else {
                            safeResume(with: .failure(TranscriptionError.recognitionFailed("No result returned")))
                            return
                        }

                        if result.isFinal {
                            let transcription = result.bestTranscription
                            let text = transcription.formattedString

                            // Extract timestamped segments, filtering out empty ones
                            let segments: [TranscriptionSegment] = transcription.segments.compactMap { seg in
                                let trimmed = seg.substring.trimmingCharacters(in: .whitespacesAndNewlines)
                                guard !trimmed.isEmpty, seg.duration > 0 else { return nil }
                                return TranscriptionSegment(
                                    text: seg.substring,
                                    startTime: seg.timestamp,
                                    duration: seg.duration,
                                    confidence: seg.confidence
                                )
                            }

                            safeResume(with: .success(TranscriptionResult(text: text, segments: segments)))
                        }
                    }

                    // If the task is cancelled externally (e.g. by timeout), cancel recognition and resume
                    Task {
                        await withTaskCancellationHandler {
                            // Wait indefinitely — the recognition callback above handles completion
                            while !Task.isCancelled {
                                try? await Task.sleep(nanoseconds: 1_000_000_000)
                            }
                        } onCancel: {
                            task.cancel()
                            safeResume(with: .failure(TranscriptionError.timeout))
                        }
                    }
                }
            }

            // Timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: 120_000_000_000) // 120 seconds
                throw TranscriptionError.timeout
            }

            // Return the first result and cancel the other task
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    // Convenience method using current locale (backward compatibility)
    func transcribe(audioURL: URL) async throws -> TranscriptionResult {
        try await transcribe(audioURL: audioURL, language: .system)
    }
}
