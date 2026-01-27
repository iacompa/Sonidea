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
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }
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
                guard let beforeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: beforeFrameCount) else {
                    throw AudioEditorError.editFailed("Failed to allocate audio buffer")
                }
                sourceFile.framePosition = 0
                try sourceFile.read(into: beforeBuffer, frameCount: beforeFrameCount)
                try outputFile.write(from: beforeBuffer)
            }

            // Write part after cut
            if afterFrameCount > 0 {
                guard let afterBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: afterFrameCount) else {
                    throw AudioEditorError.editFailed("Failed to allocate audio buffer")
                }
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

    // MARK: - Remove Multiple Silence Ranges (Skip Silence)

    /// Result of skip silence operation
    struct SkipSilenceResult {
        let outputURL: URL
        let newDuration: TimeInterval
        let removedRangesCount: Int
        let removedDuration: TimeInterval
        let success: Bool
        let error: Error?
    }

    /// Remove multiple silence ranges from audio (for Skip Silence feature)
    /// - Parameters:
    ///   - sourceURL: Original audio file URL
    ///   - silenceRanges: Array of silence ranges to remove (must be sorted by start time, non-overlapping)
    ///   - padding: Padding to keep on each side of cuts (default 0.05s)
    /// - Returns: Result with new file URL, duration, and stats
    func removeMultipleSilenceRanges(
        sourceURL: URL,
        silenceRanges: [SilenceRange],
        padding: TimeInterval = 0.05
    ) async -> SkipSilenceResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performRemoveSilenceRanges(
                    sourceURL: sourceURL,
                    silenceRanges: silenceRanges,
                    padding: padding
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performRemoveSilenceRanges(
        sourceURL: URL,
        silenceRanges: [SilenceRange],
        padding: TimeInterval
    ) -> SkipSilenceResult {
        guard !silenceRanges.isEmpty else {
            return SkipSilenceResult(
                outputURL: sourceURL,
                newDuration: getDuration(of: sourceURL) ?? 0,
                removedRangesCount: 0,
                removedDuration: 0,
                success: true,
                error: nil
            )
        }

        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let totalDuration = Double(totalFrames) / sampleRate

            // Build "keep ranges" by inverting silence ranges (with padding adjustment)
            var keepRanges: [(start: TimeInterval, end: TimeInterval)] = []
            var currentStart: TimeInterval = 0

            for silence in silenceRanges {
                // Adjust silence boundaries with padding
                let adjustedSilenceStart = silence.start + padding
                let adjustedSilenceEnd = max(adjustedSilenceStart, silence.end - padding)

                // Skip if padding makes the silence too short
                if adjustedSilenceEnd <= adjustedSilenceStart {
                    continue
                }

                // Add the non-silent part before this silence
                if adjustedSilenceStart > currentStart {
                    keepRanges.append((start: currentStart, end: adjustedSilenceStart))
                }

                currentStart = adjustedSilenceEnd
            }

            // Add the final segment after last silence
            if currentStart < totalDuration {
                keepRanges.append((start: currentStart, end: totalDuration))
            }

            guard !keepRanges.isEmpty else {
                return SkipSilenceResult(
                    outputURL: sourceURL,
                    newDuration: 0,
                    removedRangesCount: silenceRanges.count,
                    removedDuration: totalDuration,
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

            // Write each keep range to output
            var totalOutputFrames: AVAudioFrameCount = 0

            for range in keepRanges {
                let startFrame = AVAudioFramePosition(range.start * sampleRate)
                let endFrame = AVAudioFramePosition(range.end * sampleRate)
                let frameCount = AVAudioFrameCount(endFrame - startFrame)

                if frameCount > 0 {
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                        throw AudioEditorError.editFailed("Failed to allocate audio buffer")
                    }
                    sourceFile.framePosition = startFrame
                    try sourceFile.read(into: buffer, frameCount: frameCount)
                    try outputFile.write(from: buffer)
                    totalOutputFrames += frameCount
                }
            }

            let newDuration = Double(totalOutputFrames) / sampleRate
            let removedDuration = totalDuration - newDuration

            return SkipSilenceResult(
                outputURL: outputURL,
                newDuration: newDuration,
                removedRangesCount: silenceRanges.count,
                removedDuration: removedDuration,
                success: true,
                error: nil
            )
        } catch {
            return SkipSilenceResult(
                outputURL: sourceURL,
                newDuration: 0,
                removedRangesCount: 0,
                removedDuration: 0,
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
    case editFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidRange:
            return "Invalid time range for editing"
        case .readError:
            return "Failed to read audio file"
        case .writeError:
            return "Failed to write edited audio"
        case .editFailed(let message):
            return message
        }
    }
}
