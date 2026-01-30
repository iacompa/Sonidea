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

/// Fade curve types for audio fade operations.
enum FadeCurve: String, CaseIterable, Identifiable {
    case linear
    case sCurve
    case exponential

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .sCurve: return "S-Curve"
        case .exponential: return "Exponential"
        }
    }

    /// Apply curve to a normalized t value (0...1).
    func apply(_ t: Float) -> Float {
        switch self {
        case .linear:
            return t
        case .sCurve:
            // Smoothstep: 3t² - 2t³
            return t * t * (3.0 - 2.0 * t)
        case .exponential:
            // Exponential rise/fall
            return t * t
        }
    }
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
        guard startTime >= 0, endTime > startTime else {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: AudioEditorError.invalidRange)
        }

        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length

            let startFrame = max(0, min(AVAudioFramePosition(startTime * sampleRate), totalFrames))
            let endFrame = max(startFrame, min(AVAudioFramePosition(endTime * sampleRate), totalFrames))
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
        guard startTime >= 0, endTime > startTime else {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: AudioEditorError.invalidRange)
        }

        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length

            let cutStartFrame = max(0, min(AVAudioFramePosition(startTime * sampleRate), totalFrames))
            let cutEndFrame = max(cutStartFrame, min(AVAudioFramePosition(endTime * sampleRate), totalFrames))

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

    // MARK: - Fade In/Out

    /// Apply fade in and/or fade out to audio.
    func applyFade(
        sourceURL: URL,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval,
        curve: FadeCurve = .sCurve
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performFade(
                    sourceURL: sourceURL,
                    fadeInDuration: fadeInDuration,
                    fadeOutDuration: fadeOutDuration,
                    curve: curve
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performFade(
        sourceURL: URL,
        fadeInDuration: TimeInterval,
        fadeOutDuration: TimeInterval,
        curve: FadeCurve
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)

            let fadeInFrames = AVAudioFrameCount(fadeInDuration * sampleRate)
            let fadeOutFrames = AVAudioFrameCount(fadeOutDuration * sampleRate)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }
            sourceFile.framePosition = 0
            try sourceFile.read(into: buffer, frameCount: AVAudioFrameCount(totalFrames))

            guard let floatData = buffer.floatChannelData else {
                throw AudioEditorError.editFailed("Cannot access float channel data")
            }

            let frameCount = Int(buffer.frameLength)

            // Apply fade in
            if fadeInFrames > 0 {
                let fadeLen = min(Int(fadeInFrames), frameCount)
                for frame in 0..<fadeLen {
                    let t = Float(frame) / Float(fadeLen)
                    let gain = curve.apply(t)
                    for ch in 0..<channelCount {
                        floatData[ch][frame] *= gain
                    }
                }
            }

            // Apply fade out
            if fadeOutFrames > 0 {
                let fadeLen = min(Int(fadeOutFrames), frameCount)
                let fadeStart = frameCount - fadeLen
                for frame in 0..<fadeLen {
                    let t = Float(frame) / Float(fadeLen)
                    let gain = curve.apply(1.0 - t) // Reverse: 1 -> 0
                    for ch in 0..<channelCount {
                        floatData[ch][fadeStart + frame] *= gain
                    }
                }
            }

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)
            try outputFile.write(from: buffer)

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Normalize

    /// Normalize audio to a target peak level.
    func normalize(
        sourceURL: URL,
        targetPeakDb: Float = -0.3
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performNormalize(
                    sourceURL: sourceURL,
                    targetPeakDb: targetPeakDb
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performNormalize(
        sourceURL: URL,
        targetPeakDb: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }
            sourceFile.framePosition = 0
            try sourceFile.read(into: buffer, frameCount: AVAudioFrameCount(totalFrames))

            guard let floatData = buffer.floatChannelData else {
                throw AudioEditorError.editFailed("Cannot access float channel data")
            }

            let frameCount = Int(buffer.frameLength)

            // Pass 1: find peak absolute value across all channels
            var peak: Float = 0
            for ch in 0..<channelCount {
                for frame in 0..<frameCount {
                    let abs = Swift.abs(floatData[ch][frame])
                    if abs > peak { peak = abs }
                }
            }

            guard peak > 0 else {
                // Silence — nothing to normalize
                return AudioEditResult(outputURL: sourceURL, newDuration: Double(totalFrames) / sampleRate, success: true, error: nil)
            }

            // Pass 2: apply uniform gain
            let targetLinear = powf(10.0, targetPeakDb / 20.0)
            let gain = targetLinear / peak

            for ch in 0..<channelCount {
                for frame in 0..<frameCount {
                    floatData[ch][frame] *= gain
                }
            }

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)
            try outputFile.write(from: buffer)

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Noise Gate

    /// Apply a noise gate to silence audio below the threshold.
    func noiseGate(
        sourceURL: URL,
        thresholdDb: Float = -40,
        attackMs: Float = 5,
        releaseMs: Float = 50,
        holdMs: Float = 50
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performNoiseGate(
                    sourceURL: sourceURL,
                    thresholdDb: thresholdDb,
                    attackMs: attackMs,
                    releaseMs: releaseMs,
                    holdMs: holdMs
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performNoiseGate(
        sourceURL: URL,
        thresholdDb: Float,
        attackMs: Float,
        releaseMs: Float,
        holdMs: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }
            sourceFile.framePosition = 0
            try sourceFile.read(into: buffer, frameCount: AVAudioFrameCount(totalFrames))

            guard let floatData = buffer.floatChannelData else {
                throw AudioEditorError.editFailed("Cannot access float channel data")
            }

            let frameCount = Int(buffer.frameLength)
            let thresholdLinear = powf(10.0, thresholdDb / 20.0)
            let attackSamples = Int(attackMs * Float(sampleRate) / 1000.0)
            let releaseSamples = Int(releaseMs * Float(sampleRate) / 1000.0)
            let holdSamples = Int(holdMs * Float(sampleRate) / 1000.0)

            var gateOpen = false
            var holdCounter = 0
            var envelope: Float = 0

            for frame in 0..<frameCount {
                // Linked-stereo: use loudest channel
                var maxAbs: Float = 0
                for ch in 0..<channelCount {
                    let abs = Swift.abs(floatData[ch][frame])
                    if abs > maxAbs { maxAbs = abs }
                }

                let aboveThreshold = maxAbs >= thresholdLinear

                if aboveThreshold {
                    gateOpen = true
                    holdCounter = holdSamples
                } else if holdCounter > 0 {
                    holdCounter -= 1
                } else {
                    gateOpen = false
                }

                // Smooth envelope
                let target: Float = gateOpen ? 1.0 : 0.0
                if target > envelope {
                    // Attack
                    let coeff = attackSamples > 0 ? 1.0 / Float(attackSamples) : 1.0
                    envelope = min(1.0, envelope + coeff)
                } else {
                    // Release
                    let coeff = releaseSamples > 0 ? 1.0 / Float(releaseSamples) : 1.0
                    envelope = max(0.0, envelope - coeff)
                }

                for ch in 0..<channelCount {
                    floatData[ch][frame] *= envelope
                }
            }

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)
            try outputFile.write(from: buffer)

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Cut with Crossfade

    /// Cut out a selection with a crossfade at the splice point instead of a hard cut.
    func cutWithCrossfade(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval,
        crossfadeDuration: TimeInterval = 0.05
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performCutWithCrossfade(
                    sourceURL: sourceURL,
                    startTime: startTime,
                    endTime: endTime,
                    crossfadeDuration: crossfadeDuration
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performCutWithCrossfade(
        sourceURL: URL,
        startTime: TimeInterval,
        endTime: TimeInterval,
        crossfadeDuration: TimeInterval
    ) -> AudioEditResult {
        guard startTime >= 0, endTime > startTime else {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: AudioEditorError.invalidRange)
        }

        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)

            let cutStartFrame = max(0, min(AVAudioFramePosition(startTime * sampleRate), totalFrames))
            let cutEndFrame = max(cutStartFrame, min(AVAudioFramePosition(endTime * sampleRate), totalFrames))
            let crossfadeFrames = Int(crossfadeDuration * sampleRate)

            // Read entire file for crossfade processing
            guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalFrames)) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }
            sourceFile.framePosition = 0
            try sourceFile.read(into: sourceBuffer, frameCount: AVAudioFrameCount(totalFrames))

            guard let srcData = sourceBuffer.floatChannelData else {
                throw AudioEditorError.editFailed("Cannot access float channel data")
            }

            let beforeCount = Int(cutStartFrame)
            let afterStart = Int(cutEndFrame)
            let afterCount = Int(totalFrames) - afterStart

            // Actual crossfade length is limited by available audio on both sides
            let actualCrossfade = min(crossfadeFrames, beforeCount, afterCount)

            let totalOutput = beforeCount + afterCount - actualCrossfade
            guard totalOutput > 0 else {
                return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: AudioEditorError.invalidRange)
            }

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(totalOutput)) else {
                throw AudioEditorError.editFailed("Failed to allocate output buffer")
            }
            outputBuffer.frameLength = AVAudioFrameCount(totalOutput)

            guard let outData = outputBuffer.floatChannelData else {
                throw AudioEditorError.editFailed("Cannot access output channel data")
            }

            // Copy part before cut (minus crossfade overlap)
            let beforeEnd = beforeCount - actualCrossfade
            for ch in 0..<channelCount {
                for frame in 0..<beforeEnd {
                    outData[ch][frame] = srcData[ch][frame]
                }
            }

            // Crossfade zone: blend end of "before" with start of "after"
            for i in 0..<actualCrossfade {
                let t = Float(i) / Float(max(1, actualCrossfade))
                let fadeOut = 1.0 - t // Before fades out
                let fadeIn = t        // After fades in
                let beforeFrame = beforeCount - actualCrossfade + i
                let afterFrame = afterStart + i
                for ch in 0..<channelCount {
                    outData[ch][beforeEnd + i] = srcData[ch][beforeFrame] * fadeOut + srcData[ch][afterFrame] * fadeIn
                }
            }

            // Copy remaining after (past crossfade)
            let afterRemaining = afterCount - actualCrossfade
            let outputOffset = beforeEnd + actualCrossfade
            for ch in 0..<channelCount {
                for frame in 0..<afterRemaining {
                    outData[ch][outputOffset + frame] = srcData[ch][afterStart + actualCrossfade + frame]
                }
            }

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)
            try outputFile.write(from: outputBuffer)

            let newDuration = Double(totalOutput) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
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
        let timestamp = CachedDateFormatter.compactTimestamp.string(from: Date())

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
