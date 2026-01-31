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
        let clamped = min(max(t, 0), 1)
        switch self {
        case .linear:
            return clamped
        case .sCurve:
            // Perlin smootherstep: 6t⁵ - 15t⁴ + 10t³ — much more dramatic S than basic smoothstep
            let t3 = clamped * clamped * clamped
            let t4 = t3 * clamped
            let t5 = t4 * clamped
            return 6.0 * t5 - 15.0 * t4 + 10.0 * t3
        case .exponential:
            // True exponential: (e^(4t) - 1) / (e^4 - 1)
            // Stays near zero for most of the range, then rises sharply at the end
            let k: Float = 4.0
            return (exp(k * clamped) - 1.0) / (exp(k) - 1.0)
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

    private let chunkFrameCount: AVAudioFrameCount = 65536

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

            let fadeInFrames = Int(fadeInDuration * sampleRate)
            let fadeOutFrames = Int(fadeOutDuration * sampleRate)
            let totalFrameCount = Int(totalFrames)
            let fadeInLen = min(fadeInFrames, totalFrameCount)
            let fadeOutLen = min(fadeOutFrames, totalFrameCount)
            let fadeOutStart = totalFrameCount - fadeOutLen

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            sourceFile.framePosition = 0
            var position = 0

            while position < totalFrameCount {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(totalFrameCount - position))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)

                for frame in 0..<chunkLen {
                    let globalFrame = position + frame
                    var gain: Float = 1.0

                    // Fade in region
                    if fadeInLen > 0 && globalFrame < fadeInLen {
                        let t = Float(globalFrame) / Float(fadeInLen)
                        gain *= curve.apply(t)
                    }

                    // Fade out region
                    if fadeOutLen > 0 && globalFrame >= fadeOutStart {
                        let localFrame = globalFrame - fadeOutStart
                        let t = Float(localFrame) / Float(fadeOutLen)
                        gain *= curve.apply(1.0 - t)
                    }

                    if gain < 1.0 {
                        for ch in 0..<channelCount {
                            floatData[ch][frame] *= gain
                        }
                    }
                }

                try outputFile.write(from: buffer)
                position += chunkLen
            }

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
            let totalFrameCount = Int(totalFrames)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            // Pass 1: scan peak in chunks
            var peak: Float = 0
            sourceFile.framePosition = 0
            var remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(remaining))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)
                for ch in 0..<channelCount {
                    for frame in 0..<chunkLen {
                        let abs = Swift.abs(floatData[ch][frame])
                        if abs > peak { peak = abs }
                    }
                }
                remaining -= chunkLen
            }

            guard peak > 0 else {
                // Silence — nothing to normalize
                return AudioEditResult(outputURL: sourceURL, newDuration: Double(totalFrames) / sampleRate, success: true, error: nil)
            }

            // Pass 2: apply uniform gain in chunks
            let targetLinear = powf(10.0, targetPeakDb / 20.0)
            let gain = targetLinear / peak

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            sourceFile.framePosition = 0
            remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(remaining))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)
                for ch in 0..<channelCount {
                    for frame in 0..<chunkLen {
                        floatData[ch][frame] *= gain
                    }
                }

                try outputFile.write(from: buffer)
                remaining -= chunkLen
            }

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
            let totalFrameCount = Int(totalFrames)

            let thresholdLinear = powf(10.0, thresholdDb / 20.0)
            let attackSamples = Int(attackMs * Float(sampleRate) / 1000.0)
            let releaseSamples = Int(releaseMs * Float(sampleRate) / 1000.0)
            let holdSamples = Int(holdMs * Float(sampleRate) / 1000.0)

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            // Gate state carried across chunk boundaries
            var gateOpen = false
            var holdCounter = 0
            var envelope: Float = 0

            sourceFile.framePosition = 0
            var remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(remaining))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)

                for frame in 0..<chunkLen {
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

                try outputFile.write(from: buffer)
                remaining -= chunkLen
            }

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Compressor

    /// Apply compression with makeup gain and peak reduction.
    /// - Parameters:
    ///   - sourceURL: Source audio file
    ///   - makeupGainDb: Output gain boost (0–10 dB)
    ///   - peakReduction: How aggressively peaks are reduced (0–10 scale).
    ///     Maps to threshold: 0 = no compression, 10 = heavy (-30 dB threshold).
    func compressor(
        sourceURL: URL,
        makeupGainDb: Float = 0,
        peakReduction: Float = 0
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performCompressor(
                    sourceURL: sourceURL,
                    makeupGainDb: makeupGainDb,
                    peakReduction: peakReduction
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performCompressor(
        sourceURL: URL,
        makeupGainDb: Float,
        peakReduction: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int(totalFrames)

            // Map peakReduction (0–10) to compressor parameters
            // 0 = no compression, 10 = heavy compression
            let thresholdDb: Float = -3.0 * peakReduction  // 0 → 0 dB, 10 → -30 dB
            let ratio: Float = 1.0 + peakReduction * 0.7   // 0 → 1:1 (bypass), 10 → 8:1

            let thresholdLinear = powf(10.0, thresholdDb / 20.0)
            let attackMs: Float = 10
            let releaseMs: Float = 100
            let attackCoeff = 1.0 / max(1.0, Float(sampleRate) * attackMs / 1000.0)
            let releaseCoeff = 1.0 / max(1.0, Float(sampleRate) * releaseMs / 1000.0)
            let makeupGainLinear = powf(10.0, makeupGainDb / 20.0)

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            // Envelope state (carried across chunks)
            var envelope: Float = 1.0  // Current gain (1.0 = no reduction)

            sourceFile.framePosition = 0
            var remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(remaining))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)

                for frame in 0..<chunkLen {
                    // Linked-stereo level detection
                    var maxAbs: Float = 0
                    for ch in 0..<channelCount {
                        let absVal = Swift.abs(floatData[ch][frame])
                        if absVal > maxAbs { maxAbs = absVal }
                    }

                    // Calculate target gain for this sample
                    var targetGain: Float = 1.0
                    if maxAbs > thresholdLinear && thresholdLinear > 0 {
                        // dB above threshold
                        let inputDb = 20.0 * log10f(maxAbs)
                        let threshDb = 20.0 * log10f(thresholdLinear)
                        let excessDb = inputDb - threshDb
                        // Compressed excess: only allow excess/ratio through
                        let reducedExcessDb = excessDb / ratio
                        let reductionDb = excessDb - reducedExcessDb
                        targetGain = powf(10.0, -reductionDb / 20.0)
                    }

                    // Smooth envelope with attack/release
                    if targetGain < envelope {
                        // Signal above threshold → reduce gain (attack)
                        envelope += (targetGain - envelope) * attackCoeff
                    } else {
                        // Signal below threshold → release gain back to 1.0
                        envelope += (targetGain - envelope) * releaseCoeff
                    }
                    envelope = max(0.0, min(1.0, envelope))

                    // Apply compression gain + makeup gain
                    let finalGain = envelope * makeupGainLinear
                    for ch in 0..<channelCount {
                        floatData[ch][frame] *= finalGain
                        // Soft clip to prevent overs from makeup gain
                        let val = floatData[ch][frame]
                        if val > 1.0 {
                            floatData[ch][frame] = 1.0 - 1.0 / (1.0 + val - 1.0)
                        } else if val < -1.0 {
                            floatData[ch][frame] = -(1.0 - 1.0 / (1.0 + (-val) - 1.0))
                        }
                    }
                }

                try outputFile.write(from: buffer)
                remaining -= chunkLen
            }

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Reverb (Freeverb Algorithm)

    /// Apply reverb effect using a Freeverb-style algorithm.
    /// - Parameters:
    ///   - roomSize: Scales delay line lengths (0.3–3.0). 0.5 = small room, 1.0 = medium, 2.0+ = hall/cathedral.
    ///   - preDelayMs: Milliseconds of silence before reverb tail begins (0–200ms).
    ///   - decay: RT60 decay time in seconds (0.1–10.0). How long the reverb rings.
    ///   - damping: High-frequency absorption in feedback (0.0–1.0). 0 = bright, 1 = dark.
    ///   - wetDry: Mix balance (0.0 = all dry, 1.0 = all wet).
    func reverb(
        sourceURL: URL,
        roomSize: Float = 1.0,
        preDelayMs: Float = 20,
        decay: Float = 2.0,
        damping: Float = 0.5,
        wetDry: Float = 0.3
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performReverb(
                    sourceURL: sourceURL,
                    roomSize: roomSize,
                    preDelayMs: preDelayMs,
                    decay: decay,
                    damping: damping,
                    wetDry: wetDry
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performReverb(
        sourceURL: URL,
        roomSize: Float,
        preDelayMs: Float,
        decay: Float,
        damping: Float,
        wetDry: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int(totalFrames)

            // Freeverb comb filter tuning (calibrated for 44.1kHz, Jezar at Dreampoint)
            let baseCombDelays = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
            let baseAllpassDelays = [556, 441, 341, 225]

            // Scale delay times for sample rate and room size
            let srScale = Float(sampleRate) / 44100.0
            let roomScale = max(0.3, min(3.0, roomSize))
            let combDelays = baseCombDelays.map { max(1, Int(Float($0) * srScale * roomScale)) }
            let allpassDelays = baseAllpassDelays.map { max(1, Int(Float($0) * srScale * roomScale)) }

            // Feedback coefficient from desired RT60 decay time
            // RT60 = time for reverb to decay by 60dB
            let maxCombSec = Float(combDelays.max()!) / Float(sampleRate)
            let rt60 = max(0.1, decay)
            let feedback = min(0.99, max(0.3, powf(10.0, -3.0 * maxCombSec / rt60)))

            // Damping: one-pole lowpass in comb feedback path
            let damp1 = min(1.0, max(0.0, damping)) * 0.4
            let damp2: Float = 1.0 - damp1
            let allpassFeedback: Float = 0.5

            // Pre-delay circular buffer
            let preDelaySamples = max(1, Int(preDelayMs / 1000.0 * Float(sampleRate)))
            var preDelayBuf = [Float](repeating: 0, count: preDelaySamples)
            var preDelayIdx = 0

            // 8 comb filter state
            var combBufs = combDelays.map { [Float](repeating: 0, count: $0) }
            var combIdx = [Int](repeating: 0, count: 8)
            var combLPF = [Float](repeating: 0, count: 8)

            // 4 allpass filter state
            var apBufs = allpassDelays.map { [Float](repeating: 0, count: $0) }
            var apIdx = [Int](repeating: 0, count: 4)

            // Mix
            let wet = min(1.0, max(0.0, wetDry))
            let dry: Float = 1.0 - wet
            let fixedGain: Float = 0.015  // Scales sum of 8 comb outputs

            // Reverb tail extends output beyond source
            let tailSeconds = min(10.0, Double(rt60) + 1.0)
            let tailFrames = Int(tailSeconds * sampleRate)
            let totalOutputFrames = totalFrameCount + tailFrames

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount),
                  let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffers")
            }

            sourceFile.framePosition = 0
            var outWritten = 0
            var inRead = 0

            while outWritten < totalOutputFrames {
                let chunkSize = min(Int(chunkFrameCount), totalOutputFrames - outWritten)

                // Read available input
                let inAvailable = max(0, totalFrameCount - inRead)
                let toRead = AVAudioFrameCount(min(chunkSize, inAvailable))
                inBuf.frameLength = 0
                if toRead > 0 {
                    try sourceFile.read(into: inBuf, frameCount: toRead)
                    inRead += Int(inBuf.frameLength)
                }
                let actualIn = Int(inBuf.frameLength)

                outBuf.frameLength = AVAudioFrameCount(chunkSize)
                guard let inData = inBuf.floatChannelData,
                      let outData = outBuf.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                for frame in 0..<chunkSize {
                    // Sum to mono for reverb input
                    var mono: Float = 0
                    if frame < actualIn {
                        for ch in 0..<channelCount { mono += inData[ch][frame] }
                        mono /= Float(channelCount)
                    }

                    // Pre-delay
                    let preDelayed = preDelayBuf[preDelayIdx]
                    preDelayBuf[preDelayIdx] = mono
                    preDelayIdx = (preDelayIdx + 1) % preDelaySamples

                    // 8 parallel comb filters with damped feedback
                    var reverbSum: Float = 0
                    for i in 0..<8 {
                        let combOut = combBufs[i][combIdx[i]]
                        // One-pole lowpass in feedback
                        combLPF[i] = combOut * damp2 + combLPF[i] * damp1
                        combBufs[i][combIdx[i]] = preDelayed + combLPF[i] * feedback
                        combIdx[i] = (combIdx[i] + 1) % combDelays[i]
                        reverbSum += combOut
                    }

                    // 4 series allpass filters for diffusion
                    var ap = reverbSum
                    for i in 0..<4 {
                        let buffered = apBufs[i][apIdx[i]]
                        let apOut = -ap + buffered
                        apBufs[i][apIdx[i]] = ap + buffered * allpassFeedback
                        apIdx[i] = (apIdx[i] + 1) % allpassDelays[i]
                        ap = apOut
                    }

                    let reverbOut = ap * fixedGain

                    // Mix wet/dry to all output channels
                    for ch in 0..<channelCount {
                        let dryVal: Float = frame < actualIn ? inData[ch][frame] : 0
                        outData[ch][frame] = dryVal * dry + reverbOut * wet
                    }
                }

                try outputFile.write(from: outBuf)
                outWritten += chunkSize
            }

            let newDuration = Double(totalOutputFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Echo / Delay

    /// Apply echo/delay effect to audio file.
    /// - Parameters:
    ///   - delayTime: Seconds between repeats (0.05–2.0).
    ///   - feedback: How much signal feeds back into the delay (0.0–0.9). Higher = more repeats.
    ///   - damping: High-frequency roll-off per repeat (0.0–1.0). 0 = bright, 1 = dark.
    ///   - wetDry: Mix balance (0.0 = all dry, 1.0 = all wet).
    func echo(
        sourceURL: URL,
        delayTime: Float = 0.25,
        feedback: Float = 0.3,
        damping: Float = 0.3,
        wetDry: Float = 0.3
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performEcho(
                    sourceURL: sourceURL,
                    delayTime: delayTime,
                    feedback: feedback,
                    damping: damping,
                    wetDry: wetDry
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performEcho(
        sourceURL: URL,
        delayTime: Float,
        feedback: Float,
        damping: Float,
        wetDry: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int(totalFrames)

            let clampedFB = min(0.9, max(0.0, feedback))
            let clampedDamp = min(1.0, max(0.0, damping))

            // Per-channel delay line
            let delaySamples = max(1, Int(delayTime * Float(sampleRate)))
            var delayBufs = (0..<channelCount).map { _ in [Float](repeating: 0, count: delaySamples) }
            var delayIdx = [Int](repeating: 0, count: channelCount)
            var lpfStores = [Float](repeating: 0, count: channelCount)

            let wet = min(1.0, max(0.0, wetDry))
            let dry: Float = 1.0 - wet

            // Echo tail: time for repeats to decay to -60dB
            let tailSeconds: Double
            if clampedFB > 0.01 {
                tailSeconds = min(10.0, Double(delayTime) * (-log(0.001) / -log(Double(clampedFB))))
            } else {
                tailSeconds = Double(delayTime) + 0.5
            }
            let tailFrames = Int(tailSeconds * sampleRate)
            let totalOutputFrames = totalFrameCount + tailFrames

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount),
                  let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffers")
            }

            sourceFile.framePosition = 0
            var outWritten = 0
            var inRead = 0

            while outWritten < totalOutputFrames {
                let chunkSize = min(Int(chunkFrameCount), totalOutputFrames - outWritten)

                let inAvailable = max(0, totalFrameCount - inRead)
                let toRead = AVAudioFrameCount(min(chunkSize, inAvailable))
                inBuf.frameLength = 0
                if toRead > 0 {
                    try sourceFile.read(into: inBuf, frameCount: toRead)
                    inRead += Int(inBuf.frameLength)
                }
                let actualIn = Int(inBuf.frameLength)

                outBuf.frameLength = AVAudioFrameCount(chunkSize)
                guard let inData = inBuf.floatChannelData,
                      let outData = outBuf.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                for frame in 0..<chunkSize {
                    for ch in 0..<channelCount {
                        let input: Float = frame < actualIn ? inData[ch][frame] : 0

                        // Read delayed signal
                        let delayed = delayBufs[ch][delayIdx[ch]]

                        // One-pole lowpass damping on delayed signal
                        lpfStores[ch] = delayed * (1.0 - clampedDamp) + lpfStores[ch] * clampedDamp

                        // Write to delay line: input + damped feedback
                        delayBufs[ch][delayIdx[ch]] = input + lpfStores[ch] * clampedFB
                        delayIdx[ch] = (delayIdx[ch] + 1) % delaySamples

                        // Mix wet/dry
                        outData[ch][frame] = input * dry + delayed * wet
                    }
                }

                try outputFile.write(from: outBuf)
                outWritten += chunkSize
            }

            let newDuration = Double(totalOutputFrames) / sampleRate
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

            let beforeCount = Int(cutStartFrame)
            let afterStart = Int(cutEndFrame)
            let afterCount = Int(totalFrames) - afterStart

            // Actual crossfade length is limited by available audio on both sides
            let actualCrossfade = min(crossfadeFrames, beforeCount, afterCount)

            let totalOutput = beforeCount + afterCount - actualCrossfade
            guard totalOutput > 0 else {
                return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: AudioEditorError.invalidRange)
            }

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            // 1. Write "before" portion in chunks (up to beforeCount - actualCrossfade)
            let beforeEnd = beforeCount - actualCrossfade
            if beforeEnd > 0 {
                sourceFile.framePosition = 0
                var written = 0
                while written < beforeEnd {
                    let framesToRead = min(chunkFrameCount, AVAudioFrameCount(beforeEnd - written))
                    buffer.frameLength = 0
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try outputFile.write(from: buffer)
                    written += Int(buffer.frameLength)
                }
            }

            // 2. Build crossfade overlap in memory (small — typically < 1 second)
            if actualCrossfade > 0 {
                guard let xfadeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(actualCrossfade)) else {
                    throw AudioEditorError.editFailed("Failed to allocate crossfade buffer")
                }
                xfadeBuffer.frameLength = AVAudioFrameCount(actualCrossfade)

                guard let outData = xfadeBuffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access crossfade channel data")
                }

                // Read the tail of the "before" region
                guard let beforeTailBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(actualCrossfade)) else {
                    throw AudioEditorError.editFailed("Failed to allocate before-tail buffer")
                }
                sourceFile.framePosition = AVAudioFramePosition(beforeCount - actualCrossfade)
                try sourceFile.read(into: beforeTailBuf, frameCount: AVAudioFrameCount(actualCrossfade))

                // Read the head of the "after" region
                guard let afterHeadBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(actualCrossfade)) else {
                    throw AudioEditorError.editFailed("Failed to allocate after-head buffer")
                }
                sourceFile.framePosition = AVAudioFramePosition(afterStart)
                try sourceFile.read(into: afterHeadBuf, frameCount: AVAudioFrameCount(actualCrossfade))

                guard let beforeData = beforeTailBuf.floatChannelData,
                      let afterData = afterHeadBuf.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access crossfade source data")
                }

                // Blend
                for i in 0..<actualCrossfade {
                    let t = Float(i) / Float(max(1, actualCrossfade))
                    let fadeOut = 1.0 - t
                    let fadeIn = t
                    for ch in 0..<channelCount {
                        outData[ch][i] = beforeData[ch][i] * fadeOut + afterData[ch][i] * fadeIn
                    }
                }

                try outputFile.write(from: xfadeBuffer)
            }

            // 3. Write "after" portion in chunks (past the crossfade overlap)
            let afterRemaining = afterCount - actualCrossfade
            if afterRemaining > 0 {
                sourceFile.framePosition = AVAudioFramePosition(afterStart + actualCrossfade)
                var written = 0
                while written < afterRemaining {
                    let framesToRead = min(chunkFrameCount, AVAudioFrameCount(afterRemaining - written))
                    buffer.frameLength = 0
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try outputFile.write(from: buffer)
                    written += Int(buffer.frameLength)
                }
            }

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
