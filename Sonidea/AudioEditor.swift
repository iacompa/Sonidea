//
//  AudioEditor.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/24/26.
//

import AVFoundation
import Foundation

/// Result of an audio editing operation
struct AudioEditResult {
    let outputURL: URL
    let newDuration: TimeInterval
    let success: Bool
    let error: Error?
}

/// Audio editing operations for trim and cut
@MainActor
final class AudioEditor {
    static let shared = AudioEditor()

    private init() {}

    // MARK: - Trim Operation

    /// Trim audio to keep only the selected range (delete everything outside)
    /// - Parameters:
    ///   - sourceURL: Original audio file URL
    ///   - startTime: Start of selection to keep
    ///   - endTime: End of selection to keep
    /// - Returns: Result with new file URL and duration
    func trim(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performTrim(
                    sourceURL: sourceURL,
                    startTime: startTime,
                    endTime: endTime
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performTrim(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate

            let startFrame = AVAudioFramePosition(startTime * sampleRate)
            let endFrame = AVAudioFramePosition(endTime * sampleRate)
            let frameCount = AVAudioFrameCount(endFrame - startFrame)

            guard frameCount > 0 else {
                return AudioEditResult(
                    outputURL: sourceURL,
                    newDuration: 0,
                    success: false,
                    error: AudioEditorError.invalidRange
                )
            }

            // Create output file with same format
            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: sourceFile.fileFormat.settings
            )

            // Read the selected segment
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
            sourceFile.framePosition = startFrame
            try sourceFile.read(into: buffer, frameCount: frameCount)

            // Write to output
            try outputFile.write(from: buffer)

            let newDuration = Double(frameCount) / sampleRate

            return AudioEditResult(
                outputURL: outputURL,
                newDuration: newDuration,
                success: true,
                error: nil
            )
        } catch {
            return AudioEditResult(
                outputURL: sourceURL,
                newDuration: 0,
                success: false,
                error: error
            )
        }
    }

    // MARK: - Cut Operation

    /// Cut out the selected range (delete selection, keep everything else)
    /// - Parameters:
    ///   - sourceURL: Original audio file URL
    ///   - startTime: Start of selection to remove
    ///   - endTime: End of selection to remove
    /// - Returns: Result with new file URL and duration
    func cut(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performCut(
                    sourceURL: sourceURL,
                    startTime: startTime,
                    endTime: endTime
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performCut(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length

            let cutStartFrame = AVAudioFramePosition(startTime * sampleRate)
            let cutEndFrame = AVAudioFramePosition(endTime * sampleRate)

            // Calculate what to keep
            let beforeFrameCount = AVAudioFrameCount(cutStartFrame)
            let afterFrameStart = cutEndFrame
            let afterFrameCount = AVAudioFrameCount(totalFrames - cutEndFrame)

            let totalOutputFrames = beforeFrameCount + afterFrameCount

            guard totalOutputFrames > 0 else {
                return AudioEditResult(
                    outputURL: sourceURL,
                    newDuration: 0,
                    success: false,
                    error: AudioEditorError.invalidRange
                )
            }

            // Create output file
            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(
                forWriting: outputURL,
                settings: sourceFile.fileFormat.settings
            )

            // Write part before cut
            if beforeFrameCount > 0 {
                let beforeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: beforeFrameCount)!
                sourceFile.framePosition = 0
                try sourceFile.read(into: beforeBuffer, frameCount: beforeFrameCount)
                try outputFile.write(from: beforeBuffer)
            }

            // Write part after cut
            if afterFrameCount > 0 {
                let afterBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: afterFrameCount)!
                sourceFile.framePosition = afterFrameStart
                try sourceFile.read(into: afterBuffer, frameCount: afterFrameCount)
                try outputFile.write(from: afterBuffer)
            }

            let newDuration = Double(totalOutputFrames) / sampleRate

            return AudioEditResult(
                outputURL: outputURL,
                newDuration: newDuration,
                success: true,
                error: nil
            )
        } catch {
            return AudioEditResult(
                outputURL: sourceURL,
                newDuration: 0,
                success: false,
                error: error
            )
        }
    }

    // MARK: - Get Audio Duration

    /// Get the duration of an audio file
    func getDuration(of url: URL) -> TimeInterval? {
        do {
            let file = try AVAudioFile(forReading: url)
            return Double(file.length) / file.processingFormat.sampleRate
        } catch {
            return nil
        }
    }

    // MARK: - Helpers

    private func generateOutputURL(from sourceURL: URL) -> URL {
        let directory = sourceURL.deletingLastPathComponent()
        let originalName = sourceURL.deletingPathExtension().lastPathComponent
        let ext = sourceURL.pathExtension

        // Generate unique name with timestamp
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: Date())

        let newName = "\(originalName)_edited_\(timestamp).\(ext)"
        return directory.appendingPathComponent(newName)
    }

    /// Clean up old file after successful edit
    func cleanupOldFile(at url: URL) {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Errors

enum AudioEditorError: LocalizedError {
    case invalidRange
    case readError
    case writeError

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "Invalid time range for editing"
        case .readError:
            return "Failed to read audio file"
        case .writeError:
            return "Failed to write edited audio"
        }
    }
}
