//
//  AudioEditor.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/24/26.
//

import AVFoundation
import Foundation
import os.log

/// Result of an audio editing operation
struct AudioEditResult {
    let outputURL: URL
    let newDuration: TimeInterval
    let success: Bool
    let error: Error?
}

/// Normalization mode: peak-based or loudness (LUFS) based.
enum NormalizeMode: String, CaseIterable, Identifiable {
    case peak
    case lufs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .peak: return "Peak"
        case .lufs: return "LUFS"
        }
    }
}

/// Fade curve types for audio fade operations.
enum FadeCurve: String, CaseIterable, Identifiable {
    case linear
    case sCurve
    case exponential
    case logarithmic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .linear: return "Linear"
        case .sCurve: return "S-Curve"
        case .exponential: return "Exp"
        case .logarithmic: return "Log"
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
        case .logarithmic:
            // Logarithmic: rises quickly at first, then levels off — psychoacoustic inverse of exponential
            // log(1 + k*t) / log(1 + k)
            let k: Float = 53.0  // e^4 - 1 ≈ 53.6, mirrors the exponential curve's steepness
            return log(1.0 + k * clamped) / log(1.0 + k)
        }
    }
}

/// Audio editing operations for trim and cut
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
            let frameCount = Int64(endFrame - startFrame)

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

            // Read and write in chunks to avoid OOM on long recordings
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }
            sourceFile.framePosition = startFrame
            var remaining = frameCount
            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
                try sourceFile.read(into: buffer, frameCount: framesToRead)
                try outputFile.write(from: buffer)
                remaining -= Int64(buffer.frameLength)
            }

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

            // Calculate what to keep (use Int64 to avoid overflow on long files)
            let beforeFrameCount = Int64(cutStartFrame)
            let afterFrameStart = cutEndFrame
            let afterFrameCount = Int64(totalFrames - cutEndFrame)

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

            // Reusable chunk buffer for both segments
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            // Write part before cut (chunked)
            if beforeFrameCount > 0 {
                sourceFile.framePosition = 0
                var remaining = beforeFrameCount
                while remaining > 0 {
                    let framesToRead = AVAudioFrameCount(min(remaining, Int64(chunkFrameCount)))
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try outputFile.write(from: buffer)
                    remaining -= Int64(buffer.frameLength)
                }
            }

            // Write part after cut (chunked)
            if afterFrameCount > 0 {
                sourceFile.framePosition = afterFrameStart
                var remaining = afterFrameCount
                while remaining > 0 {
                    let framesToRead = AVAudioFrameCount(min(remaining, Int64(chunkFrameCount)))
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try outputFile.write(from: buffer)
                    remaining -= Int64(buffer.frameLength)
                }
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

            // Write each keep range to output using chunked I/O to avoid OOM on long recordings
            var totalOutputFrames: Int64 = 0
            let chunkFrameCount: AVAudioFrameCount = 65536

            for range in keepRanges {
                let startFrame = AVAudioFramePosition(range.start * sampleRate)
                let endFrame = AVAudioFramePosition(range.end * sampleRate)
                let rangeFrameCount = Int64(endFrame - startFrame)

                if rangeFrameCount > 0 {
                    let bufferCapacity = min(chunkFrameCount, AVAudioFrameCount(min(rangeFrameCount, Int64(chunkFrameCount))))
                    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferCapacity) else {
                        throw AudioEditorError.editFailed("Failed to allocate audio buffer")
                    }
                    sourceFile.framePosition = startFrame
                    var framesRemaining = rangeFrameCount
                    while framesRemaining > 0 {
                        let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(framesRemaining, Int64(chunkFrameCount))))
                        try sourceFile.read(into: buffer, frameCount: framesToRead)
                        try outputFile.write(from: buffer)
                        framesRemaining -= Int64(buffer.frameLength)
                        totalOutputFrames += Int64(buffer.frameLength)
                    }
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
        fadeInCurve: FadeCurve = .sCurve,
        fadeOutCurve: FadeCurve = .sCurve
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performFade(
                    sourceURL: sourceURL,
                    fadeInDuration: fadeInDuration,
                    fadeOutDuration: fadeOutDuration,
                    fadeInCurve: fadeInCurve,
                    fadeOutCurve: fadeOutCurve
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
        fadeInCurve: FadeCurve,
        fadeOutCurve: FadeCurve
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)

            let fadeInFrames = Int64(fadeInDuration * sampleRate)
            let fadeOutFrames = Int64(fadeOutDuration * sampleRate)
            let totalFrameCount = Int64(totalFrames)
            let fadeInLen = min(fadeInFrames, totalFrameCount)
            let fadeOutLen = min(fadeOutFrames, totalFrameCount)
            let fadeOutStart = totalFrameCount - fadeOutLen

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            sourceFile.framePosition = 0
            var position: Int64 = 0

            while position < totalFrameCount {
                let framesToRead = min(AVAudioFrameCount(chunkFrameCount), AVAudioFrameCount(min(Int64(chunkFrameCount), totalFrameCount - position)))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)

                for frame in 0..<chunkLen {
                    let globalFrame = position + Int64(frame)
                    var gain: Float = 1.0

                    // Fade in region
                    if fadeInLen > 0 && globalFrame < fadeInLen {
                        let t = Float(Double(globalFrame) / Double(fadeInLen))
                        gain *= fadeInCurve.apply(t)
                    }

                    // Fade out region
                    if fadeOutLen > 0 && globalFrame >= fadeOutStart {
                        let localFrame = globalFrame - fadeOutStart
                        let t = Float(Double(localFrame) / Double(fadeOutLen))
                        gain *= fadeOutCurve.apply(1.0 - t)
                    }

                    if gain < 1.0 {
                        for ch in 0..<channelCount {
                            floatData[ch][frame] *= gain
                        }
                    }
                }

                try outputFile.write(from: buffer)
                position += Int64(chunkLen)
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
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int64(totalFrames)

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            // Pass 1: scan true-peak in chunks (4x oversampled via 4-point cubic interpolation)
            // ITU-R BS.1770 recommends 4x oversampling for true-peak detection
            var peak: Float = 0
            // Ring buffer of last 4 samples per channel for cubic interpolation
            var history = [[Float]](repeating: [Float](repeating: 0, count: 4), count: channelCount)
            var sampleCount = 0
            sourceFile.framePosition = 0
            var remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)
                for ch in 0..<channelCount {
                    for frame in 0..<chunkLen {
                        let s = floatData[ch][frame]
                        let abs = Swift.abs(s)
                        if abs > peak { peak = abs }

                        // Shift history and push new sample
                        history[ch][0] = history[ch][1]
                        history[ch][1] = history[ch][2]
                        history[ch][2] = history[ch][3]
                        history[ch][3] = s

                        // Need at least 4 samples before interpolating
                        if sampleCount >= 3 {
                            let y0 = history[ch][0], y1 = history[ch][1]
                            let y2 = history[ch][2], y3 = history[ch][3]
                            // Catmull-Rom cubic interpolation at t=0.25, 0.5, 0.75 between y1 and y2
                            for k in 1...3 {
                                let t = Float(k) * 0.25
                                let t2 = t * t
                                let t3 = t2 * t
                                let interp = 0.5 * ((2.0 * y1)
                                    + (-y0 + y2) * t
                                    + (2.0 * y0 - 5.0 * y1 + 4.0 * y2 - y3) * t2
                                    + (-y0 + 3.0 * y1 - 3.0 * y2 + y3) * t3)
                                let absInterp = Swift.abs(interp)
                                if absInterp > peak { peak = absInterp }
                            }
                        }
                    }
                }
                sampleCount += chunkLen
                remaining -= Int64(chunkLen)
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
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
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
                remaining -= Int64(chunkLen)
            }

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - LUFS Normalize (ITU-R BS.1770-4)

    /// Normalize audio to a target loudness in LUFS using the ITU-R BS.1770-4 algorithm.
    /// Uses K-weighted filtering, 400ms gated measurement, and absolute/relative gating.
    func lufsNormalize(
        sourceURL: URL,
        targetLUFS: Float = -16.0
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performLufsNormalize(
                    sourceURL: sourceURL,
                    targetLUFS: targetLUFS
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performLufsNormalize(
        sourceURL: URL,
        targetLUFS: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int64(totalFrames)

            guard totalFrameCount > 0 else {
                return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: true, error: nil)
            }

            // ── K-filter coefficients (ITU-R BS.1770-4) ──
            // Computed dynamically for any sample rate via bilinear transform.
            // Stage 1: High-shelf (+3.9997 dB, models head acoustic effects)
            // Stage 2: High-pass (RLB weighting, removes energy below ~38 Hz)
            let (shelfCoeffs, hpCoeffs) = AudioEditor.kWeightingCoefficients(sampleRate: sampleRate)
            let shelfB0 = shelfCoeffs.b0, shelfB1 = shelfCoeffs.b1, shelfB2 = shelfCoeffs.b2
            let shelfA1 = shelfCoeffs.a1, shelfA2 = shelfCoeffs.a2
            let hpB0 = hpCoeffs.b0, hpB1 = hpCoeffs.b1, hpB2 = hpCoeffs.b2
            let hpA1 = hpCoeffs.a1, hpA2 = hpCoeffs.a2

            // ── Pass 1: Measure LUFS ──
            // Block size: 400ms with 75% overlap (step = 100ms)
            let blockSamples = max(1, Int(0.4 * sampleRate))
            let stepSamples = max(1, Int(0.1 * sampleRate))

            // For very short files (< 400ms), use the entire file as a single block
            let effectiveBlockSamples = min(blockSamples, Int(min(totalFrameCount, Int64(Int.max))))

            // Biquad filter state per channel (Direct Form II Transposed)
            // Each channel needs two cascaded filters: shelf then highpass
            // State: [z1, z2] per filter per channel
            var shelfZ1 = [Double](repeating: 0, count: channelCount)
            var shelfZ2 = [Double](repeating: 0, count: channelCount)
            var hpZ1 = [Double](repeating: 0, count: channelCount)
            var hpZ2 = [Double](repeating: 0, count: channelCount)

            // We need to process the entire file through K-filters and compute per-block mean square
            // Accumulate filtered squared samples per channel per block
            var blockMeanSquares: [[Double]] = [] // [blockIndex][channel]
            var totalSamplesProcessed: Int64 = 0

            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffer")
            }

            sourceFile.framePosition = 0
            var remaining = totalFrameCount

            // We need overlapping blocks. To handle this with chunked I/O,
            // we keep a rolling accumulator. Process all samples, and emit blocks
            // at every stepSamples interval, each block covering the last blockSamples.
            // We use a ring buffer of squared filtered samples per channel.
            var ringBuffer = [[Double]](repeating: [Double](repeating: 0, count: effectiveBlockSamples), count: channelCount)
            var ringIndex = 0
            var ringFilled = 0 // How many samples have been written to ring so far
            var samplesSinceLastBlock = 0

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)

                for frame in 0..<chunkLen {
                    for ch in 0..<channelCount {
                        let x = Double(floatData[ch][frame])

                        // Stage 1: High-shelf filter (Direct Form II Transposed)
                        let shelfOut = shelfB0 * x + shelfZ1[ch]
                        shelfZ1[ch] = shelfB1 * x - shelfA1 * shelfOut + shelfZ2[ch]
                        shelfZ2[ch] = shelfB2 * x - shelfA2 * shelfOut

                        // Stage 2: High-pass filter (Direct Form II Transposed)
                        let hpOut = hpB0 * shelfOut + hpZ1[ch]
                        hpZ1[ch] = hpB1 * shelfOut - hpA1 * hpOut + hpZ2[ch]
                        hpZ2[ch] = hpB2 * shelfOut - hpA2 * hpOut

                        // Store squared filtered sample in ring buffer
                        ringBuffer[ch][ringIndex] = hpOut * hpOut
                    }

                    ringIndex = (ringIndex + 1) % effectiveBlockSamples
                    ringFilled = min(ringFilled + 1, effectiveBlockSamples)
                    totalSamplesProcessed += 1
                    samplesSinceLastBlock += 1

                    // Emit a block at every stepSamples interval (or at end of file for short files)
                    let shouldEmitBlock: Bool
                    if totalFrameCount < Int64(blockSamples) {
                        // Very short file: emit one block at the very end
                        shouldEmitBlock = (totalSamplesProcessed == totalFrameCount)
                    } else {
                        shouldEmitBlock = (samplesSinceLastBlock >= stepSamples && ringFilled >= effectiveBlockSamples)
                    }

                    if shouldEmitBlock {
                        samplesSinceLastBlock = 0
                        // Compute mean square for this block from ring buffer
                        var channelMeans = [Double](repeating: 0, count: channelCount)
                        let samplesInBlock = ringFilled
                        for ch in 0..<channelCount {
                            var sum: Double = 0
                            for i in 0..<samplesInBlock {
                                sum += ringBuffer[ch][i]
                            }
                            channelMeans[ch] = sum / Double(samplesInBlock)
                        }
                        blockMeanSquares.append(channelMeans)
                    }
                }

                remaining -= Int64(chunkLen)
            }

            // If no blocks were emitted (should not happen unless file is empty), return unchanged
            guard !blockMeanSquares.isEmpty else {
                return AudioEditResult(outputURL: sourceURL, newDuration: Double(totalFrames) / sampleRate, success: true, error: nil)
            }

            // Compute block loudness for each block
            // L_j = -0.691 + 10 * log10(sum of weighted channel mean squares)
            // For mono/stereo voice memos, channel weight G_i = 1.0
            var blockLoudness = [Double](repeating: 0, count: blockMeanSquares.count)
            for j in 0..<blockMeanSquares.count {
                var weightedSum: Double = 0
                for ch in 0..<channelCount {
                    weightedSum += blockMeanSquares[j][ch] // weight = 1.0 for all front channels
                }
                if weightedSum > 0 {
                    blockLoudness[j] = -0.691 + 10.0 * log10(weightedSum)
                } else {
                    blockLoudness[j] = -200.0 // effectively -infinity
                }
            }

            // Absolute gate: discard blocks below -70 LKFS
            let absoluteThreshold: Double = -70.0
            var gatedBlocks: [Int] = []
            for j in 0..<blockLoudness.count {
                if blockLoudness[j] >= absoluteThreshold {
                    gatedBlocks.append(j)
                }
            }

            // Silent file: all blocks below -70 LKFS — return success with no modification
            guard !gatedBlocks.isEmpty else {
                return AudioEditResult(outputURL: sourceURL, newDuration: Double(totalFrames) / sampleRate, success: true, error: nil)
            }

            // Compute ungated LUFS from absolute-gated blocks
            var ungatedSum: Double = 0
            for j in gatedBlocks {
                var weightedSum: Double = 0
                for ch in 0..<channelCount {
                    weightedSum += blockMeanSquares[j][ch]
                }
                ungatedSum += weightedSum
            }
            let ungatedLUFS = -0.691 + 10.0 * log10(ungatedSum / Double(gatedBlocks.count))

            // Relative gate: discard blocks below (ungatedLUFS - 10)
            let relativeThreshold = ungatedLUFS - 10.0
            var finalBlocks: [Int] = []
            for j in gatedBlocks {
                if blockLoudness[j] >= relativeThreshold {
                    finalBlocks.append(j)
                }
            }

            // Should not be empty if ungated blocks exist, but guard anyway
            guard !finalBlocks.isEmpty else {
                return AudioEditResult(outputURL: sourceURL, newDuration: Double(totalFrames) / sampleRate, success: true, error: nil)
            }

            // Compute final gated LUFS
            var finalSum: Double = 0
            for j in finalBlocks {
                var weightedSum: Double = 0
                for ch in 0..<channelCount {
                    weightedSum += blockMeanSquares[j][ch]
                }
                finalSum += weightedSum
            }
            let measuredLUFS = Float(-0.691 + 10.0 * log10(finalSum / Double(finalBlocks.count)))

            // ── Pass 2: Apply gain ──
            var gainDB = targetLUFS - measuredLUFS

            // Cap extreme gain (normalizing near-silence would amplify noise floor)
            if gainDB > 40.0 { gainDB = 0.0 }

            // No gain needed
            if abs(gainDB) < 0.01 {
                return AudioEditResult(outputURL: sourceURL, newDuration: Double(totalFrames) / sampleRate, success: true, error: nil)
            }

            let gainLinear = powf(10.0, gainDB / 20.0)

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            sourceFile.framePosition = 0
            remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
                buffer.frameLength = 0
                try sourceFile.read(into: buffer, frameCount: framesToRead)

                guard let floatData = buffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkLen = Int(buffer.frameLength)
                for ch in 0..<channelCount {
                    for frame in 0..<chunkLen {
                        var val = floatData[ch][frame] * gainLinear
                        // Soft clip using tanh knee at 0.9 (same as compressor)
                        let absVal = fabsf(val)
                        if absVal > 0.9 {
                            let t = (absVal - 0.9) * 10.0 // 0 at knee, 1 at full scale
                            let limited = 0.9 + 0.1 * tanhf(t)
                            val = copysignf(limited, val)
                        }
                        floatData[ch][frame] = val
                    }
                }

                try outputFile.write(from: buffer)
                remaining -= Int64(chunkLen)
            }

            let newDuration = Double(totalFrames) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Noise Gate

    /// Apply a noise gate to attenuate audio below the threshold.
    /// - Parameters:
    ///   - thresholdDb: Gate opens when signal exceeds this level (-60 to -10 dB).
    ///   - attackMs: Time for gate to fully open (1–50 ms).
    ///   - releaseMs: Time for gate to fully close (10–500 ms).
    ///   - holdMs: Minimum time gate stays open after signal drops below threshold (10–500 ms).
    ///   - floorDb: Attenuation when gate is closed (-80 = near silence, -6 = subtle). 0 = no gating.
    func noiseGate(
        sourceURL: URL,
        thresholdDb: Float = -40,
        attackMs: Float = 5,
        releaseMs: Float = 50,
        holdMs: Float = 50,
        floorDb: Float = -80
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performNoiseGate(
                    sourceURL: sourceURL,
                    thresholdDb: thresholdDb,
                    attackMs: attackMs,
                    releaseMs: releaseMs,
                    holdMs: holdMs,
                    floorDb: floorDb
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
        holdMs: Float,
        floorDb: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int64(totalFrames)

            let thresholdLinear = powf(10.0, thresholdDb / 20.0)
            let floorLinear = powf(10.0, min(0, floorDb) / 20.0) // floor gain when gate is closed
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
            var envelope: Float = floorLinear

            sourceFile.framePosition = 0
            var remaining = totalFrameCount

            while remaining > 0 {
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
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

                    // Smooth envelope (ramps between floorLinear and 1.0)
                    let target: Float = gateOpen ? 1.0 : floorLinear
                    if target > envelope {
                        // Attack
                        let coeff = attackSamples > 0 ? (1.0 - floorLinear) / Float(attackSamples) : (1.0 - floorLinear)
                        envelope = min(1.0, envelope + coeff)
                    } else if target < envelope {
                        // Release
                        let coeff = releaseSamples > 0 ? (1.0 - floorLinear) / Float(releaseSamples) : (1.0 - floorLinear)
                        envelope = max(floorLinear, envelope - coeff)
                    }

                    for ch in 0..<channelCount {
                        floatData[ch][frame] *= envelope
                    }
                }

                try outputFile.write(from: buffer)
                remaining -= Int64(chunkLen)
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
        peakReduction: Float = 0,
        mix: Float = 1.0
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performCompressor(
                    sourceURL: sourceURL,
                    makeupGainDb: makeupGainDb,
                    peakReduction: peakReduction,
                    mix: mix
                )
                continuation.resume(returning: result)
            }
        }
    }

    private func performCompressor(
        sourceURL: URL,
        makeupGainDb: Float,
        peakReduction: Float,
        mix: Float
    ) -> AudioEditResult {
        do {
            let sourceFile = try AVAudioFile(forReading: sourceURL)
            let format = sourceFile.processingFormat
            let sampleRate = format.sampleRate
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int64(totalFrames)

            // Map peakReduction (0–10) to compressor parameters
            // 0 = no compression, 10 = heavy compression
            let thresholdDb: Float = -3.0 * peakReduction  // 0 → 0 dB, 10 → -30 dB
            let ratio: Float = 1.0 + peakReduction * 0.7   // 0 → 1:1 (bypass), 10 → 8:1

            // Soft-knee width: 6 dB centered on threshold for smoother compression onset
            let kneeWidthDb: Float = 6.0
            let kneeBottom = thresholdDb - kneeWidthDb / 2.0
            let kneeTop = thresholdDb + kneeWidthDb / 2.0

            let attackMs: Float = 10
            let releaseMs: Float = 100
            let attackCoeff = 1.0 / max(1.0, Float(sampleRate) * attackMs / 1000.0)
            let releaseCoeff = 1.0 / max(1.0, Float(sampleRate) * releaseMs / 1000.0)
            let clampedMix = min(1.0, max(0.0, mix))

            // Auto makeup gain: estimate average gain reduction at threshold and compensate
            // For a signal at threshold, soft knee gives ~half the full ratio reduction
            // Makeup = (thresholdDb - thresholdDb/ratio) * 0.5 ≈ half the max GR at threshold
            let autoMakeupDb: Float = {
                guard ratio > 1.0 else { return 0.0 }
                let grAtThreshold = thresholdDb * (1.0 - 1.0 / ratio)
                // Use ~60% of the GR at threshold as makeup (conservative to avoid clipping)
                return -grAtThreshold * 0.6
            }()
            let totalMakeupDb = makeupGainDb + autoMakeupDb
            let makeupGainLinear = powf(10.0, totalMakeupDb / 20.0)

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
                let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(remaining, Int64(chunkFrameCount))))
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

                    // Calculate target gain using soft-knee compression curve
                    var targetGain: Float = 1.0
                    if maxAbs > 0 {
                        let inputDb = 20.0 * log10f(maxAbs)

                        var outputDb = inputDb
                        if inputDb <= kneeBottom {
                            // Below knee: no compression (1:1)
                            outputDb = inputDb
                        } else if inputDb >= kneeTop {
                            // Above knee: full ratio compression
                            outputDb = thresholdDb + (inputDb - thresholdDb) / ratio
                        } else {
                            // Inside knee: quadratic interpolation for smooth transition
                            // The soft-knee formula blends 1:1 and ratio compression
                            let x = inputDb - kneeBottom
                            let kneeRange = kneeWidthDb
                            let compressionFactor = (1.0 / ratio - 1.0) / (2.0 * kneeRange)
                            outputDb = inputDb + compressionFactor * x * x
                        }

                        let reductionDb = inputDb - outputDb
                        if reductionDb > 0 {
                            targetGain = powf(10.0, -reductionDb / 20.0)
                        }
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

                    // Apply compression gain + makeup gain with dry/wet mix
                    let compGain = envelope * makeupGainLinear
                    for ch in 0..<channelCount {
                        let drySample = floatData[ch][frame]
                        let wetSample = drySample * compGain
                        floatData[ch][frame] = drySample * (1.0 - clampedMix) + wetSample * clampedMix
                        // Soft clip to prevent overs from makeup gain
                        // Knee at 0.9 with tanh saturation — C1 continuous, approaches ±1.0 asymptotically
                        let val = floatData[ch][frame]
                        let absVal = fabsf(val)
                        if absVal > 0.9 {
                            let t = (absVal - 0.9) * 10.0 // 0 at knee, 1 at full scale
                            let limited = 0.9 + 0.1 * tanhf(t)
                            floatData[ch][frame] = copysignf(limited, val)
                        }
                    }
                }

                try outputFile.write(from: buffer)
                remaining -= Int64(chunkLen)
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
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int64(totalFrames)
            let isStereo = channelCount >= 2

            // Freeverb comb filter tuning (calibrated for 44.1kHz, Jezar at Dreampoint)
            let baseCombDelays = [1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617]
            let baseAllpassDelays = [556, 441, 341, 225]

            // Scale delay times for sample rate and room size
            let srScale = Float(sampleRate) / 44100.0
            let roomScale = max(0.3, min(3.0, roomSize))
            let combDelaysL = baseCombDelays.map { max(1, Int(Float($0) * srScale * roomScale)) }
            let allpassDelaysL = baseAllpassDelays.map { max(1, Int(Float($0) * srScale * roomScale)) }

            // Stereo spread: right channel delay lines offset by 23 samples (Freeverb standard)
            let stereoSpread = 23
            let combDelaysR = combDelaysL.map { $0 + stereoSpread }
            let allpassDelaysR = allpassDelaysL.map { $0 + stereoSpread }

            // Feedback coefficient from desired RT60 decay time
            // RT60 = time for reverb to decay by 60dB
            guard let maxCombDelay = combDelaysL.max() else {
                throw AudioEditorError.editFailed("Internal error: empty comb delay array")
            }
            let maxCombSec = Float(maxCombDelay) / Float(sampleRate)
            let rt60 = max(0.1, decay)
            let feedback = min(0.99, max(0.3, powf(10.0, -3.0 * maxCombSec / rt60)))

            // Damping: one-pole lowpass in comb feedback path
            let damp1 = min(1.0, max(0.0, damping))
            let damp2: Float = 1.0 - damp1
            let allpassFeedback: Float = 0.5

            // Pre-delay circular buffer
            let preDelaySamples = max(1, Int(preDelayMs / 1000.0 * Float(sampleRate)))
            var preDelayBuf = [Float](repeating: 0, count: preDelaySamples)
            var preDelayIdx = 0

            // 8 comb filter state (L channel)
            var combBufsL = combDelaysL.map { [Float](repeating: 0, count: $0) }
            var combIdxL = [Int](repeating: 0, count: 8)
            var combLPF_L = [Float](repeating: 0, count: 8)

            // 4 allpass filter state (L channel)
            var apBufsL = allpassDelaysL.map { [Float](repeating: 0, count: $0) }
            var apIdxL = [Int](repeating: 0, count: 4)

            // R channel state (stereo decorrelation via offset delay lines)
            var combBufsR = isStereo ? combDelaysR.map { [Float](repeating: 0, count: $0) } : []
            var combIdxR = isStereo ? [Int](repeating: 0, count: 8) : []
            var combLPF_R = isStereo ? [Float](repeating: 0, count: 8) : []
            var apBufsR = isStereo ? allpassDelaysR.map { [Float](repeating: 0, count: $0) } : []
            var apIdxR = isStereo ? [Int](repeating: 0, count: 4) : []

            // Mix
            let wet = min(1.0, max(0.0, wetDry))
            let dry: Float = 1.0 - wet
            let fixedGain: Float = 0.015  // Scales sum of 8 comb outputs

            // Reverb tail extends output beyond source — cap at 5 seconds to prevent OOM on older devices
            let maxTailSeconds: Double = 5.0
            let requestedTailSeconds = min(10.0, Double(rt60) + 1.0)
            if requestedTailSeconds > maxTailSeconds {
                Logger(subsystem: "com.iacompa.sonidea", category: "AudioEditor")
                    .warning("Reverb tail time \(requestedTailSeconds, privacy: .public)s exceeds \(maxTailSeconds, privacy: .public)s cap — clamping to prevent excessive memory use")
            }
            let tailSeconds = min(maxTailSeconds, requestedTailSeconds)
            let tailFrames = Int64(tailSeconds * sampleRate)
            let totalOutputFrames = totalFrameCount + tailFrames

            // Tail fade-out: smooth fade over last 500ms to prevent abrupt cutoff
            let tailFadeSamples = max(Int64(1), Int64(0.5 * sampleRate))
            let tailFadeStart = totalOutputFrames - tailFadeSamples

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount),
                  let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffers")
            }

            sourceFile.framePosition = 0
            var outWritten: Int64 = 0
            var inRead: Int64 = 0

            while outWritten < totalOutputFrames {
                let chunkSize = min(Int64(chunkFrameCount), totalOutputFrames - outWritten)

                // Read available input
                let inAvailable = max(Int64(0), totalFrameCount - inRead)
                let toRead = AVAudioFrameCount(min(chunkSize, inAvailable))
                inBuf.frameLength = 0
                if toRead > 0 {
                    try sourceFile.read(into: inBuf, frameCount: toRead)
                    inRead += Int64(inBuf.frameLength)
                }
                let actualIn = Int(inBuf.frameLength)

                outBuf.frameLength = AVAudioFrameCount(chunkSize)
                guard let inData = inBuf.floatChannelData,
                      let outData = outBuf.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkSizeInt = Int(chunkSize)
                for frame in 0..<chunkSizeInt {
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

                    // L channel: 8 parallel comb filters with damped feedback
                    var reverbSumL: Float = 0
                    for i in 0..<8 {
                        let combOut = combBufsL[i][combIdxL[i]]
                        combLPF_L[i] = combOut * damp2 + combLPF_L[i] * damp1
                        combBufsL[i][combIdxL[i]] = preDelayed + combLPF_L[i] * feedback
                        combIdxL[i] = (combIdxL[i] + 1) % combDelaysL[i]
                        reverbSumL += combOut
                    }

                    // L channel: 4 series allpass filters for diffusion
                    var apL = reverbSumL
                    for i in 0..<4 {
                        let buffered = apBufsL[i][apIdxL[i]]
                        let apOut = -apL + buffered
                        apBufsL[i][apIdxL[i]] = apL + buffered * allpassFeedback
                        apIdxL[i] = (apIdxL[i] + 1) % allpassDelaysL[i]
                        apL = apOut
                    }

                    let reverbOutL = apL * fixedGain

                    // Tail fade-out to prevent abrupt cutoff at tail cap
                    let globalFrame = outWritten + Int64(frame)
                    var tailGain: Float = 1.0
                    if globalFrame >= tailFadeStart {
                        tailGain = max(0, Float(totalOutputFrames - globalFrame) / Float(tailFadeSamples))
                    }

                    if isStereo {
                        // R channel: 8 parallel comb filters with offset delays for decorrelation
                        var reverbSumR: Float = 0
                        for i in 0..<8 {
                            let combOut = combBufsR[i][combIdxR[i]]
                            combLPF_R[i] = combOut * damp2 + combLPF_R[i] * damp1
                            combBufsR[i][combIdxR[i]] = preDelayed + combLPF_R[i] * feedback
                            combIdxR[i] = (combIdxR[i] + 1) % combDelaysR[i]
                            reverbSumR += combOut
                        }

                        // R channel: 4 series allpass filters
                        var apR = reverbSumR
                        for i in 0..<4 {
                            let buffered = apBufsR[i][apIdxR[i]]
                            let apOut = -apR + buffered
                            apBufsR[i][apIdxR[i]] = apR + buffered * allpassFeedback
                            apIdxR[i] = (apIdxR[i] + 1) % allpassDelaysR[i]
                            apR = apOut
                        }

                        let reverbOutR = apR * fixedGain

                        let dryL: Float = frame < actualIn ? inData[0][frame] : 0
                        let dryR: Float = frame < actualIn ? inData[1][frame] : 0
                        outData[0][frame] = dryL * dry + reverbOutL * wet * tailGain
                        outData[1][frame] = dryR * dry + reverbOutR * wet * tailGain

                        // Any extra channels beyond stereo get L reverb
                        for ch in 2..<channelCount {
                            let dryVal: Float = frame < actualIn ? inData[ch][frame] : 0
                            outData[ch][frame] = dryVal * dry + reverbOutL * wet * tailGain
                        }
                    } else {
                        // Mono
                        let dryVal: Float = frame < actualIn ? inData[0][frame] : 0
                        outData[0][frame] = dryVal * dry + reverbOutL * wet * tailGain
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
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)
            let totalFrameCount = Int64(totalFrames)

            let clampedFB = min(0.9, max(0.0, feedback))
            let clampedDamp = min(0.95, max(0.0, damping))  // Cap at 0.95: 1.0 kills signal entirely

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
            let tailFrames = Int64(tailSeconds * sampleRate)
            let totalOutputFrames = totalFrameCount + tailFrames

            // Tail fade-out: smooth fade over last 500ms to prevent abrupt cutoff
            let echoTailFadeSamples = max(Int64(1), Int64(0.5 * sampleRate))
            let echoTailFadeStart = totalOutputFrames - echoTailFadeSamples

            let outputURL = generateOutputURL(from: sourceURL)
            let outputFile = try AVAudioFile(forWriting: outputURL, settings: sourceFile.fileFormat.settings)

            guard let inBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount),
                  let outBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                throw AudioEditorError.editFailed("Failed to allocate audio buffers")
            }

            sourceFile.framePosition = 0
            var outWritten: Int64 = 0
            var inRead: Int64 = 0

            while outWritten < totalOutputFrames {
                let chunkSize = min(Int64(chunkFrameCount), totalOutputFrames - outWritten)

                let inAvailable = max(Int64(0), totalFrameCount - inRead)
                let toRead = AVAudioFrameCount(min(chunkSize, inAvailable))
                inBuf.frameLength = 0
                if toRead > 0 {
                    try sourceFile.read(into: inBuf, frameCount: toRead)
                    inRead += Int64(inBuf.frameLength)
                }
                let actualIn = Int(inBuf.frameLength)

                outBuf.frameLength = AVAudioFrameCount(chunkSize)
                guard let inData = inBuf.floatChannelData,
                      let outData = outBuf.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access float channel data")
                }

                let chunkSizeInt = Int(chunkSize)
                for frame in 0..<chunkSizeInt {
                    // Tail fade-out to prevent abrupt cutoff
                    let globalFrame = outWritten + Int64(frame)
                    var tailGain: Float = 1.0
                    if globalFrame >= echoTailFadeStart {
                        tailGain = max(0, Float(totalOutputFrames - globalFrame) / Float(echoTailFadeSamples))
                    }

                    for ch in 0..<channelCount {
                        let input: Float = frame < actualIn ? inData[ch][frame] : 0

                        // Read delayed signal
                        let delayed = delayBufs[ch][delayIdx[ch]]

                        // One-pole lowpass damping on delayed signal
                        lpfStores[ch] = delayed * (1.0 - clampedDamp) + lpfStores[ch] * clampedDamp

                        // Write to delay line: input + damped feedback
                        delayBufs[ch][delayIdx[ch]] = input + lpfStores[ch] * clampedFB
                        delayIdx[ch] = (delayIdx[ch] + 1) % delaySamples

                        // Mix wet/dry with tail fade
                        outData[ch][frame] = input * dry + delayed * wet * tailGain
                    }
                }

                try outputFile.write(from: outBuf)
                outWritten += chunkSize
            }

            let newDuration = Double(totalOutputFrames) / Double(sampleRate)
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
            let totalFrames = sourceFile.length  // AVAudioFramePosition (Int64)
            let channelCount = Int(format.channelCount)

            let cutStartFrame = max(0, min(AVAudioFramePosition(startTime * sampleRate), totalFrames))
            let cutEndFrame = max(cutStartFrame, min(AVAudioFramePosition(endTime * sampleRate), totalFrames))
            let crossfadeFrames = Int64(crossfadeDuration * sampleRate)

            let beforeCount = Int64(cutStartFrame)
            let afterStart = Int64(cutEndFrame)
            let afterCount = Int64(totalFrames) - afterStart

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
                var written: Int64 = 0
                while written < beforeEnd {
                    let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(beforeEnd - written, Int64(chunkFrameCount))))
                    buffer.frameLength = 0
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try outputFile.write(from: buffer)
                    written += Int64(buffer.frameLength)
                }
            }

            // 2. Build crossfade overlap in memory (small — typically < 1 second)
            if actualCrossfade > 0 {
                let xfadeCount = Int(actualCrossfade)  // Safe: crossfade is always short (< 1s)
                guard let xfadeBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(xfadeCount)) else {
                    throw AudioEditorError.editFailed("Failed to allocate crossfade buffer")
                }
                xfadeBuffer.frameLength = AVAudioFrameCount(xfadeCount)

                guard let outData = xfadeBuffer.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access crossfade channel data")
                }

                // Read the tail of the "before" region
                guard let beforeTailBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(xfadeCount)) else {
                    throw AudioEditorError.editFailed("Failed to allocate before-tail buffer")
                }
                sourceFile.framePosition = AVAudioFramePosition(beforeCount - actualCrossfade)
                try sourceFile.read(into: beforeTailBuf, frameCount: AVAudioFrameCount(xfadeCount))

                // Read the head of the "after" region
                guard let afterHeadBuf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(xfadeCount)) else {
                    throw AudioEditorError.editFailed("Failed to allocate after-head buffer")
                }
                sourceFile.framePosition = AVAudioFramePosition(afterStart)
                try sourceFile.read(into: afterHeadBuf, frameCount: AVAudioFrameCount(xfadeCount))

                guard let beforeData = beforeTailBuf.floatChannelData,
                      let afterData = afterHeadBuf.floatChannelData else {
                    throw AudioEditorError.editFailed("Cannot access crossfade source data")
                }

                // Equal-power (sqrt) crossfade — perceptually smooth, no loudness dip at midpoint
                for i in 0..<xfadeCount {
                    let t = Float(i) / Float(max(1, xfadeCount))
                    let fadeOut = sqrtf(1.0 - t)  // Equal-power fade out
                    let fadeIn = sqrtf(t)          // Equal-power fade in
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
                var written: Int64 = 0
                while written < afterRemaining {
                    let framesToRead = min(chunkFrameCount, AVAudioFrameCount(min(afterRemaining - written, Int64(chunkFrameCount))))
                    buffer.frameLength = 0
                    try sourceFile.read(into: buffer, frameCount: framesToRead)
                    try outputFile.write(from: buffer)
                    written += Int64(buffer.frameLength)
                }
            }

            let newDuration = Double(totalOutput) / sampleRate
            return AudioEditResult(outputURL: outputURL, newDuration: newDuration, success: true, error: nil)
        } catch {
            return AudioEditResult(outputURL: sourceURL, newDuration: 0, success: false, error: error)
        }
    }

    // MARK: - Combined Preset (Compress → Reverb → Echo in single operation)

    /// Parameters for a combined preset application
    struct CombinedPresetParams {
        // Compression (set to nil to skip)
        var compGain: Float?
        var compReduction: Float?
        var compMix: Float?

        // Reverb (set wetDry to nil or 0 to skip)
        var reverbRoomSize: Float?
        var reverbPreDelayMs: Float?
        var reverbDecay: Float?
        var reverbDamping: Float?
        var reverbWetDry: Float?

        // Echo (set wetDry to nil or 0 to skip)
        var echoDelay: Float?
        var echoFeedback: Float?
        var echoDamping: Float?
        var echoWetDry: Float?

        var hasCompression: Bool {
            guard let g = compGain, let r = compReduction, let m = compMix else { return false }
            return g > 0 || r > 0 || m < 1.0
        }

        var hasReverb: Bool { (reverbWetDry ?? 0) > 0 }
        var hasEcho: Bool { (echoWetDry ?? 0) > 0 }
    }

    /// Apply compression, reverb, and echo sequentially in a single atomic operation.
    /// Each stage writes to a temp file that becomes the input for the next stage.
    /// Returns the final output URL and duration.
    func applyCombinedPreset(
        sourceURL: URL,
        params: CombinedPresetParams
    ) async -> AudioEditResult {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let result = self.performCombinedPreset(sourceURL: sourceURL, params: params)
                continuation.resume(returning: result)
            }
        }
    }

    private func performCombinedPreset(
        sourceURL: URL,
        params: CombinedPresetParams
    ) -> AudioEditResult {
        var currentURL = sourceURL
        var tempFiles: [URL] = []

        // Stage 1: Compression
        if params.hasCompression {
            let result = performCompressor(
                sourceURL: currentURL,
                makeupGainDb: params.compGain ?? 0,
                peakReduction: params.compReduction ?? 0,
                mix: params.compMix ?? 1.0
            )
            guard result.success else {
                cleanupTempFiles(tempFiles)
                return result
            }
            if currentURL != sourceURL { tempFiles.append(currentURL) }
            currentURL = result.outputURL
        }

        // Stage 2: Reverb
        if params.hasReverb {
            let result = performReverb(
                sourceURL: currentURL,
                roomSize: params.reverbRoomSize ?? 1.0,
                preDelayMs: params.reverbPreDelayMs ?? 20,
                decay: params.reverbDecay ?? 2.0,
                damping: params.reverbDamping ?? 0.5,
                wetDry: params.reverbWetDry ?? 0.3
            )
            guard result.success else {
                cleanupTempFiles(tempFiles)
                return result
            }
            if currentURL != sourceURL { tempFiles.append(currentURL) }
            currentURL = result.outputURL
        }

        // Stage 3: Echo
        if params.hasEcho {
            let result = performEcho(
                sourceURL: currentURL,
                delayTime: params.echoDelay ?? 0.25,
                feedback: params.echoFeedback ?? 0.3,
                damping: params.echoDamping ?? 0.3,
                wetDry: params.echoWetDry ?? 0.3
            )
            guard result.success else {
                cleanupTempFiles(tempFiles)
                return result
            }
            if currentURL != sourceURL { tempFiles.append(currentURL) }
            currentURL = result.outputURL
        }

        // Clean up intermediate temp files (keep source and final output)
        cleanupTempFiles(tempFiles)

        // Get final duration
        let duration = getDuration(of: currentURL) ?? 0
        return AudioEditResult(outputURL: currentURL, newDuration: duration, success: true, error: nil)
    }

    private func cleanupTempFiles(_ files: [URL]) {
        for file in files {
            try? FileManager.default.removeItem(at: file)
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

    // MARK: - ITU-R BS.1770-4 K-Weighting Filter Coefficients

    /// Biquad filter coefficients (normalized so a0 = 1).
    /// Transfer function: H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
    struct BiquadCoefficients {
        let b0: Double
        let b1: Double
        let b2: Double
        let a1: Double
        let a2: Double
    }

    /// Compute K-weighting filter coefficients for any sample rate using the bilinear transform.
    ///
    /// The K-weighting filter specified by ITU-R BS.1770-4 consists of two cascaded stages:
    ///   1. **Pre-filter (high shelf)**: +3.9997 dB boost above ~1681 Hz, modeling acoustic
    ///      effects of the human head.
    ///   2. **RLB weighting (highpass)**: 2nd-order highpass at ~38.13 Hz, removing DC and
    ///      subsonic content.
    ///
    /// Both filters are designed as analog prototypes and digitized via the bilinear transform
    /// with frequency pre-warping. The resulting coefficients match the reference values
    /// published for 48 kHz and 44.1 kHz to at least 5 significant digits.
    ///
    /// - Parameter sampleRate: The audio sample rate in Hz (e.g. 8000, 16000, 44100, 48000, 96000).
    /// - Returns: A tuple of (shelf coefficients, highpass coefficients).
    static func kWeightingCoefficients(sampleRate: Double) -> (shelf: BiquadCoefficients, highpass: BiquadCoefficients) {
        // ────────────────────────────────────────────────────────────────
        // Stage 1: Pre-filter (high shelf)
        //
        // Analog prototype parameters (from ITU-R BS.1770-4):
        //   - Shelf gain:  Vh = 10^(+3.9997/20) ≈ 1.58489319...  (the linear voltage gain)
        //   - Quality:     Q  = 0.7071752369554193  (≈ 1/sqrt(2), Butterworth alignment)
        //   - Center freq: fc = 1681.974450955533 Hz
        //
        // High-shelf biquad via bilinear transform with pre-warping:
        //   K  = tan(pi * fc / fs)                    [pre-warped frequency]
        //   Vh = 10^(dBgain / 20)                     [linear gain]
        //   Vb = Vh^0.4996667741545416                 [bandwidth gain; exponent from spec]
        //   a0 = 1 + K/Q + K^2
        //   b0 = (Vh + Vb*K/Q + K^2) / a0
        //   b1 = 2*(K^2 - Vh) / a0
        //   b2 = (Vh - Vb*K/Q + K^2) / a0
        //   a1 = 2*(K^2 - 1) / a0
        //   a2 = (1 - K/Q + K^2) / a0
        // ────────────────────────────────────────────────────────────────

        let shelfFc  = 1681.974450955533
        let shelfQ   = 0.7071752369554193
        let shelfDb  = 3.999843853973347

        let Vh = pow(10.0, shelfDb / 20.0)
        let Vb = pow(Vh, 0.4996667741545416)
        let K  = tan(Double.pi * shelfFc / sampleRate)
        let K2 = K * K
        let KoverQ = K / shelfQ

        let shelfA0 = 1.0 + KoverQ + K2
        let shelfB0 = (Vh + Vb * KoverQ + K2) / shelfA0
        let shelfB1 = 2.0 * (K2 - Vh) / shelfA0
        let shelfB2 = (Vh - Vb * KoverQ + K2) / shelfA0
        let shelfA1 = 2.0 * (K2 - 1.0) / shelfA0
        let shelfA2 = (1.0 - KoverQ + K2) / shelfA0

        let shelf = BiquadCoefficients(b0: shelfB0, b1: shelfB1, b2: shelfB2, a1: shelfA1, a2: shelfA2)

        // ────────────────────────────────────────────────────────────────
        // Stage 2: RLB weighting highpass (2nd-order Butterworth highpass)
        //
        // Analog prototype parameters:
        //   - Cutoff freq:  fc = 38.13547087602444 Hz
        //   - Q = 0.5003270373238773  (≈ 1/2, critically damped)
        //
        // 2nd-order highpass via bilinear transform with pre-warping:
        //   K  = tan(pi * fc / fs)
        //   a0 = 1 + K/Q + K^2
        //   b0 = 1 / a0
        //   b1 = -2 / a0
        //   b2 = 1 / a0
        //   a1 = 2*(K^2 - 1) / a0
        //   a2 = (1 - K/Q + K^2) / a0
        // ────────────────────────────────────────────────────────────────

        let hpFc = 38.13547087602444
        let hpQ  = 0.5003270373238773

        let Khp  = tan(Double.pi * hpFc / sampleRate)
        let Khp2 = Khp * Khp
        let KhpOverQ = Khp / hpQ

        let hpA0 = 1.0 + KhpOverQ + Khp2
        let hpB0 = 1.0 / hpA0
        let hpB1 = -2.0 / hpA0
        let hpB2 = 1.0 / hpA0
        let hpA1 = 2.0 * (Khp2 - 1.0) / hpA0
        let hpA2 = (1.0 - KhpOverQ + Khp2) / hpA0

        let highpass = BiquadCoefficients(b0: hpB0, b1: hpB1, b2: hpB2, a1: hpA1, a2: hpA2)

        return (shelf: shelf, highpass: highpass)
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
