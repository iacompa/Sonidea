//
//  AudioWaveformExtractor.swift
//  Sonidea
//
//  High-resolution waveform extraction with multi-resolution LOD pyramid.
//  Designed for pro-level audio editing with efficient zooming.
//

import AVFoundation
import Foundation
import OSLog

// MARK: - Waveform Data

/// Multi-resolution waveform data with LOD pyramid
struct WaveformData: Equatable {
    /// LOD levels - index 0 is highest resolution, higher indices are lower resolution
    /// LOD0: ~1ms per sample (for max zoom)
    /// LOD1: ~2ms per sample
    /// LOD2: ~4ms per sample
    /// LOD3: ~8ms per sample
    /// LOD4: ~16ms per sample
    /// LOD5: ~32ms per sample (for overview)
    let lodLevels: [[Float]]

    /// Duration of the audio in seconds
    let duration: TimeInterval

    /// Sample rate of the original audio
    let sampleRate: Double

    /// Samples per second at LOD0 (highest resolution)
    let samplesPerSecondLOD0: Int

    /// Get the appropriate LOD level for a given zoom scale
    /// - Parameter zoomScale: 1.0 = full width, higher = more zoomed in
    /// - Parameter viewWidth: Width of the view in points
    /// - Returns: The LOD level index and samples array
    func lodLevel(for zoomScale: CGFloat, viewWidth: CGFloat) -> (level: Int, samples: [Float]) {
        // Calculate how many seconds are visible
        let visibleDuration = duration / Double(zoomScale)

        // Calculate ideal samples per point for smooth rendering
        let idealSamplesPerPoint: Double = 0.5 // 2 points per sample = smooth
        let idealTotalSamples = Double(viewWidth) / idealSamplesPerPoint
        let idealSamplesPerSecond = idealTotalSamples / visibleDuration

        // Find the best LOD level
        for (index, samples) in lodLevels.enumerated() {
            let lodSamplesPerSecond = Double(samples.count) / duration
            if lodSamplesPerSecond >= idealSamplesPerSecond || index == lodLevels.count - 1 {
                return (index, samples)
            }
        }

        return (lodLevels.count - 1, lodLevels.last ?? [])
    }

    /// Get samples for a specific time range at appropriate LOD
    func samples(from startTime: TimeInterval, to endTime: TimeInterval, targetCount: Int) -> [Float] {
        guard !lodLevels.isEmpty, duration > 0, targetCount > 0 else { return [] }

        let rangeDuration = max(0.001, endTime - startTime)
        let idealSamplesPerSecond = Double(targetCount) / rangeDuration

        // Find best LOD - prefer higher resolution when zoomed in
        var bestLOD = lodLevels[0] // Default to highest resolution
        for samples in lodLevels {
            let lodSamplesPerSecond = Double(samples.count) / duration
            if lodSamplesPerSecond >= idealSamplesPerSecond {
                bestLOD = samples
                break
            }
        }

        // Clamp time range to valid bounds
        let clampedStart = max(0, min(startTime, duration))
        let clampedEnd = max(clampedStart, min(endTime, duration))

        // Calculate precise floating-point indices for accurate time-to-sample mapping
        let startProgress = clampedStart / duration
        let endProgress = clampedEnd / duration

        // Use floor for start, ceil for end to ensure we capture all samples in range
        let startIndex = Int(floor(startProgress * Double(bestLOD.count)))
        let endIndex = Int(ceil(endProgress * Double(bestLOD.count)))

        let safeStart = max(0, min(startIndex, bestLOD.count - 1))
        let safeEnd = max(safeStart + 1, min(endIndex, bestLOD.count))

        let slice = Array(bestLOD[safeStart..<safeEnd])

        // Resample to target count if needed
        return resample(slice, to: targetCount)
    }

    private func resample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard samples.count != targetCount else { return samples }

        var result: [Float] = []
        result.reserveCapacity(targetCount)

        if samples.count < targetCount {
            // Upsample with linear interpolation
            for i in 0..<targetCount {
                let position = Float(i) * Float(samples.count - 1) / Float(max(1, targetCount - 1))
                let lowerIndex = Int(position)
                let upperIndex = min(lowerIndex + 1, samples.count - 1)
                let fraction = position - Float(lowerIndex)
                result.append(samples[lowerIndex] * (1 - fraction) + samples[upperIndex] * fraction)
            }
        } else {
            // Downsample by taking max in each bucket
            let samplesPerBucket = Float(samples.count) / Float(targetCount)
            for i in 0..<targetCount {
                let start = Int(Float(i) * samplesPerBucket)
                let end = min(Int(Float(i + 1) * samplesPerBucket), samples.count)
                var maxVal: Float = 0
                for j in start..<end {
                    if samples[j] > maxVal { maxVal = samples[j] }
                }
                result.append(maxVal)
            }
        }

        return result
    }
}

// MARK: - Silence Range

/// Represents a range of silence in the audio
struct SilenceRange: Equatable, Codable {
    let start: TimeInterval
    let end: TimeInterval

    var duration: TimeInterval { end - start }

    func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }
}

// MARK: - Audio Waveform Extractor

/// High-performance waveform extractor with LOD pyramid and silence detection
actor AudioWaveformExtractor {
    static let shared = AudioWaveformExtractor()

    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "WaveformExtractor")

    // Cache for extracted waveforms
    private var waveformCache: [URL: WaveformData] = [:]
    private var silenceCache: [URL: [SilenceRange]] = [:]

    // Configuration
    private let lodLevelCount = 6
    private let baseSamplesPerSecond = 1000 // LOD0: 1000 samples/sec = 1ms resolution

    // Silence detection settings
    private let silenceThresholdDB: Float = -40.0 // dBFS threshold for silence
    private let minSilenceDuration: TimeInterval = 0.25 // 250ms minimum silence

    // MARK: - Public API

    /// Extract waveform data with LOD pyramid
    func extractWaveform(from url: URL) async throws -> WaveformData {
        // Check cache first
        if let cached = waveformCache[url] {
            return cached
        }

        logger.info("Extracting waveform for: \(url.lastPathComponent)")

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)
        let duration = Double(frameCount) / sampleRate

        guard frameCount > 0 else {
            throw WaveformError.emptyAudioFile
        }

        // Read audio data
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WaveformError.bufferCreationFailed
        }

        try audioFile.read(into: buffer)

        guard let floatChannelData = buffer.floatChannelData else {
            throw WaveformError.noAudioData
        }

        let channelData = floatChannelData[0]
        let length = Int(buffer.frameLength)

        // Build LOD pyramid
        var lodLevels: [[Float]] = []

        for lodIndex in 0..<lodLevelCount {
            let samplesPerSecond = baseSamplesPerSecond / (1 << lodIndex) // 1000, 500, 250, 125, 62, 31
            let targetSampleCount = max(1, Int(duration * Double(samplesPerSecond)))

            let samples = extractLODSamples(
                from: channelData,
                length: length,
                targetCount: targetSampleCount
            )

            lodLevels.append(samples)
            logger.debug("LOD\(lodIndex): \(samples.count) samples (\(samplesPerSecond) samples/sec)")
        }

        let waveformData = WaveformData(
            lodLevels: lodLevels,
            duration: duration,
            sampleRate: sampleRate,
            samplesPerSecondLOD0: baseSamplesPerSecond
        )

        // Cache the result
        waveformCache[url] = waveformData

        logger.info("Waveform extracted: \(lodLevels[0].count) samples at LOD0, duration: \(String(format: "%.2f", duration))s")

        return waveformData
    }

    /// Detect silence ranges in the audio
    func detectSilence(from url: URL, threshold: Float? = nil, minDuration: TimeInterval? = nil) async throws -> [SilenceRange] {
        // Check cache first
        if let cached = silenceCache[url] {
            return cached
        }

        logger.info("Detecting silence for: \(url.lastPathComponent)")

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(audioFile.length)
        let duration = Double(frameCount) / sampleRate

        guard frameCount > 0 else {
            return []
        }

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            throw WaveformError.bufferCreationFailed
        }

        try audioFile.read(into: buffer)

        guard let floatChannelData = buffer.floatChannelData else {
            throw WaveformError.noAudioData
        }

        let channelData = floatChannelData[0]
        let length = Int(buffer.frameLength)

        let thresholdDB = threshold ?? silenceThresholdDB
        let minSilence = minDuration ?? minSilenceDuration

        // Convert dB threshold to linear amplitude
        let thresholdLinear = pow(10.0, thresholdDB / 20.0)

        // Analyze in 10ms windows
        let windowSize = Int(sampleRate * 0.01) // 10ms windows
        let windowCount = length / windowSize

        var silenceRanges: [SilenceRange] = []
        var silenceStartTime: TimeInterval?

        for windowIndex in 0..<windowCount {
            let start = windowIndex * windowSize
            let end = min(start + windowSize, length)

            // Calculate RMS for this window
            var sumSquares: Float = 0
            for i in start..<end {
                let sample = channelData[i]
                sumSquares += sample * sample
            }
            let rms = sqrt(sumSquares / Float(end - start))

            let windowTime = Double(windowIndex) * 0.01
            let isSilent = rms < thresholdLinear

            if isSilent {
                if silenceStartTime == nil {
                    silenceStartTime = windowTime
                }
            } else {
                if let startTime = silenceStartTime {
                    let silenceDuration = windowTime - startTime
                    if silenceDuration >= minSilence {
                        silenceRanges.append(SilenceRange(start: startTime, end: windowTime))
                    }
                    silenceStartTime = nil
                }
            }
        }

        // Handle silence at the end
        if let startTime = silenceStartTime {
            let silenceDuration = duration - startTime
            if silenceDuration >= minSilence {
                silenceRanges.append(SilenceRange(start: startTime, end: duration))
            }
        }

        // Cache the result
        silenceCache[url] = silenceRanges

        logger.info("Detected \(silenceRanges.count) silence ranges")

        return silenceRanges
    }

    /// Clear cache for a specific URL
    func clearCache(for url: URL) {
        waveformCache.removeValue(forKey: url)
        silenceCache.removeValue(forKey: url)
    }

    /// Clear all caches
    func clearAllCaches() {
        waveformCache.removeAll()
        silenceCache.removeAll()
    }

    // MARK: - Private Helpers

    private func extractLODSamples(from channelData: UnsafePointer<Float>, length: Int, targetCount: Int) -> [Float] {
        guard length > 0, targetCount > 0 else { return [] }

        var samples: [Float] = []
        samples.reserveCapacity(targetCount)

        // Use floating-point bucket boundaries to ensure ALL audio samples are covered
        // This prevents the "trailing samples skipped" bug from integer division
        let bucketSize = Double(length) / Double(targetCount)

        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(Int(Double(i + 1) * bucketSize), length)

            // Use peak amplitude for each bucket
            var maxAmplitude: Float = 0
            for j in start..<end {
                let amplitude = abs(channelData[j])
                if amplitude > maxAmplitude {
                    maxAmplitude = amplitude
                }
            }

            samples.append(maxAmplitude)
        }

        // Normalize to 0...1
        let maxValue = samples.max() ?? 1.0
        if maxValue > 0.001 { // Avoid division by near-zero
            samples = samples.map { min(1.0, $0 / maxValue) }
        }

        return samples
    }
}

// MARK: - Waveform Error

enum WaveformError: LocalizedError {
    case emptyAudioFile
    case bufferCreationFailed
    case noAudioData
    case extractionFailed(String)

    var errorDescription: String? {
        switch self {
        case .emptyAudioFile:
            return "Audio file is empty"
        case .bufferCreationFailed:
            return "Failed to create audio buffer"
        case .noAudioData:
            return "No audio data found"
        case .extractionFailed(let message):
            return "Waveform extraction failed: \(message)"
        }
    }
}
