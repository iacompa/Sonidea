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
struct WaveformData: Equatable, Codable {
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
        guard duration > 0, zoomScale > 0 else { return (0, lodLevels.first ?? []) }
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

    // Silence detection settings (dBFS-based with hysteresis + debounce)
    private let silenceThresholdDB: Float = -55.0       // dBFS threshold to enter silence
    private let nonSilenceThresholdDB: Float = -50.0    // dBFS threshold to exit silence (hysteresis)
    private let minSilenceDuration: TimeInterval = 0.5  // 500ms minimum silence to cut (applied AFTER roll)
    private let silencePreRollMs: Double = 50.0         // Pre-roll before cut (ms) - protect consonants
    private let silencePostRollMs: Double = 50.0        // Post-roll after cut (ms) - protect transients
    private let rmsWindowMs: Double = 30.0              // RMS window size (ms)
    private let rmsHopMs: Double = 10.0                 // Hop size (ms) - overlap for smoother detection
    private let silenceEnterHoldMs: Double = 80.0       // Debounce: must stay silent for 80ms to enter silence
    private let silenceExitHoldMs: Double = 30.0        // Debounce: must stay non-silent for 30ms to exit silence (reduced for better transient detection)
    private let mergeGapMs: Double = 40.0               // Merge silence regions separated by gaps < 40ms (reduced from 120ms to avoid swallowing short audio)

    // MARK: - Disk Cache

    /// Directory for persisted waveform cache files
    private var diskCacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("Waveforms", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Disk cache URL for an audio file
    private func diskCacheURL(for audioURL: URL) -> URL {
        let name = audioURL.deletingPathExtension().lastPathComponent
        return diskCacheDirectory.appendingPathComponent("\(name).waveform")
    }

    /// Load waveform from disk cache, validating it's newer than the audio file
    private func loadFromDiskCache(for audioURL: URL) -> WaveformData? {
        let cacheURL = diskCacheURL(for: audioURL)
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return nil }

        // Invalidate if audio file is newer than cache
        if let audioDate = (try? FileManager.default.attributesOfItem(atPath: audioURL.path))?[.modificationDate] as? Date,
           let cacheDate = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date,
           audioDate > cacheDate {
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }

        guard let data = try? Data(contentsOf: cacheURL),
              let waveform = try? JSONDecoder().decode(WaveformData.self, from: data) else {
            try? FileManager.default.removeItem(at: cacheURL)
            return nil
        }

        logger.info("Loaded waveform from disk cache: \(audioURL.lastPathComponent)")
        return waveform
    }

    /// Save waveform to disk cache
    private func saveToDiskCache(_ waveform: WaveformData, for audioURL: URL) {
        let cacheURL = diskCacheURL(for: audioURL)
        if let data = try? JSONEncoder().encode(waveform) {
            try? data.write(to: cacheURL, options: .atomic)
            logger.debug("Saved waveform to disk cache: \(audioURL.lastPathComponent)")
        }
    }

    // MARK: - Public API

    /// Extract waveform data with LOD pyramid (chunked reading, disk + memory cache)
    func extractWaveform(from url: URL) async throws -> WaveformData {
        // 1. Check memory cache (instant)
        if let cached = waveformCache[url] {
            return cached
        }

        // 2. Check disk cache (fast — avoids re-reading the audio file)
        if let diskCached = loadFromDiskCache(for: url) {
            waveformCache[url] = diskCached
            return diskCached
        }

        logger.info("Extracting waveform for: \(url.lastPathComponent)")

        let audioFile = try AVAudioFile(forReading: url)
        let format = audioFile.processingFormat
        let sampleRate = format.sampleRate
        let totalFrames = Int(audioFile.length)
        let duration = Double(totalFrames) / sampleRate

        guard totalFrames > 0 else {
            throw WaveformError.emptyAudioFile
        }

        // 3. Chunked extraction — build LOD0 incrementally without loading entire file
        let lod0TargetCount = max(1, Int(duration * Double(baseSamplesPerSecond)))
        let bucketSize = Double(totalFrames) / Double(lod0TargetCount)
        var lod0Samples = [Float](repeating: 0, count: lod0TargetCount)

        let chunkCapacity: AVAudioFrameCount = 65536
        guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkCapacity) else {
            throw WaveformError.bufferCreationFailed
        }

        var framesRead = 0
        while framesRead < totalFrames {
            let remaining = AVAudioFrameCount(totalFrames - framesRead)
            let toRead = min(chunkCapacity, remaining)

            chunkBuffer.frameLength = 0
            try audioFile.read(into: chunkBuffer, frameCount: toRead)

            guard let channelData = chunkBuffer.floatChannelData?[0] else {
                throw WaveformError.noAudioData
            }
            let actualFrames = Int(chunkBuffer.frameLength)

            for i in 0..<actualFrames {
                let globalFrame = framesRead + i
                let bucketIndex = min(Int(Double(globalFrame) / bucketSize), lod0TargetCount - 1)
                let amplitude = abs(channelData[i])
                if amplitude > lod0Samples[bucketIndex] {
                    lod0Samples[bucketIndex] = amplitude
                }
            }

            framesRead += actualFrames
        }

        // Normalize LOD0 to 0...1
        let maxValue = lod0Samples.max() ?? 1.0
        if maxValue > 0.001 {
            lod0Samples = lod0Samples.map { min(1.0, $0 / maxValue) }
        }

        // 4. Derive LOD1-5 by downsampling LOD0
        var lodLevels: [[Float]] = [lod0Samples]
        for lodIndex in 1..<lodLevelCount {
            let factor = 1 << lodIndex // 2, 4, 8, 16, 32
            let targetCount = max(1, lod0TargetCount / factor)
            lodLevels.append(downsamplePeak(lod0Samples, to: targetCount))
            logger.debug("LOD\(lodIndex): \(targetCount) samples")
        }

        let waveformData = WaveformData(
            lodLevels: lodLevels,
            duration: duration,
            sampleRate: sampleRate,
            samplesPerSecondLOD0: baseSamplesPerSecond
        )

        // 5. Cache in memory + persist to disk
        waveformCache[url] = waveformData
        saveToDiskCache(waveformData, for: url)

        logger.info("Waveform extracted: \(lodLevels[0].count) samples at LOD0, duration: \(String(format: "%.2f", duration))s")

        return waveformData
    }

    /// Detect silence ranges in the audio using dBFS-based RMS with hysteresis and debounce
    ///
    /// Algorithm order:
    /// 1. Detect silence/non-silence using RMS→dBFS + hysteresis state machine with debounce
    /// 2. Build raw silence regions from continuous "silence" state
    /// 3. Merge silence regions separated by tiny gaps (< mergeGapMs)
    /// 4. Apply pre/post roll by SHRINKING each region
    /// 5. Enforce minSilenceDuration on rolled regions ONLY
    ///
    /// - Parameters:
    ///   - url: Audio file URL
    ///   - threshold: Custom silence threshold in dBFS (default: -45 dBFS)
    ///   - minDuration: Minimum silence duration to keep (default: 0.5s, applied after roll)
    /// - Returns: Array of silence ranges ready for removal
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
        let channelCount = Int(format.channelCount)

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

        let length = Int(buffer.frameLength)

        // Use provided thresholds or defaults
        let silenceThreshold = threshold ?? silenceThresholdDB         // -45 dBFS to enter silence
        let nonSilenceThreshold = threshold.map { $0 + 5 } ?? nonSilenceThresholdDB  // -40 dBFS to exit silence
        let minSilence = minDuration ?? minSilenceDuration

        // Convert timing parameters to samples/windows
        let windowSizeSamples = Int(sampleRate * rmsWindowMs / 1000.0)
        let hopSizeSamples = Int(sampleRate * rmsHopMs / 1000.0)
        let hopDuration = rmsHopMs / 1000.0

        // Debounce hold counts (in hops)
        let enterHoldCount = Int(ceil(silenceEnterHoldMs / rmsHopMs))
        let exitHoldCount = Int(ceil(silenceExitHoldMs / rmsHopMs))

        // Calculate number of analysis frames
        let frameCount2 = max(0, (length - windowSizeSamples) / hopSizeSamples + 1)

        logger.debug("Silence detection: threshold=\(silenceThreshold)dB, hysteresis=\(nonSilenceThreshold)dB, window=\(self.rmsWindowMs)ms, hop=\(self.rmsHopMs)ms, enterHold=\(enterHoldCount), exitHold=\(exitHoldCount)")

        #if DEBUG
        // Debug: collect dB statistics to verify detection is working correctly
        var debugDBValues: [Float] = []
        var debugSilentFrameCount = 0
        var debugLoudFrameCount = 0
        #endif

        // ============================================================
        // STEP 1: Detect silence using RMS→dBFS + hysteresis + debounce
        // ============================================================

        enum SilenceState {
            case nonSilent
            case pendingSilent(holdCounter: Int)  // Waiting for debounce to confirm silence
            case silent
            case pendingNonSilent(holdCounter: Int)  // Waiting for debounce to confirm non-silence
        }

        var state: SilenceState = .nonSilent
        var rawSilenceRanges: [SilenceRange] = []
        var silenceStartTime: TimeInterval?

        for frameIndex in 0..<frameCount2 {
            let sampleStart = frameIndex * hopSizeSamples
            let sampleEnd = min(sampleStart + windowSizeSamples, length)
            let sampleCount = sampleEnd - sampleStart

            guard sampleCount > 0 else { continue }

            // Calculate max-channel RMS (handles stereo better than single channel)
            var maxChannelRMS: Float = 0
            for ch in 0..<channelCount {
                let channelData = floatChannelData[ch]
                var sumSquares: Float = 0
                for i in sampleStart..<sampleEnd {
                    let sample = channelData[i]
                    sumSquares += sample * sample
                }
                let channelRMS = sqrt(sumSquares / Float(sampleCount))
                maxChannelRMS = max(maxChannelRMS, channelRMS)
            }

            // Convert RMS to dBFS: dBFS = 20 * log10(rms), floor at -96 dBFS
            let dBFS: Float = maxChannelRMS > 0.000001 ? 20.0 * log10(maxChannelRMS) : -96.0

            #if DEBUG
            // Collect debug stats (sample every 10th frame to avoid too much data)
            if frameIndex % 10 == 0 {
                debugDBValues.append(dBFS)
            }
            if dBFS <= silenceThreshold {
                debugSilentFrameCount += 1
            } else {
                debugLoudFrameCount += 1
            }
            #endif

            let frameTime = Double(frameIndex) * hopDuration
            // SILENCE = audio level BELOW threshold (quiet)
            // NON-SILENCE = audio level ABOVE threshold (loud)
            let isBelowSilenceThreshold = dBFS <= silenceThreshold
            let isAboveNonSilenceThreshold = dBFS > nonSilenceThreshold

            // State machine with debounce
            switch state {
            case .nonSilent:
                if isBelowSilenceThreshold {
                    // Start pending transition to silence
                    state = .pendingSilent(holdCounter: 1)
                }

            case .pendingSilent(let holdCounter):
                if isBelowSilenceThreshold {
                    if holdCounter >= enterHoldCount {
                        // Confirmed: transition to silence
                        // Backdate silence start to when we first went below threshold
                        silenceStartTime = frameTime - (Double(holdCounter) * hopDuration)
                        state = .silent
                    } else {
                        state = .pendingSilent(holdCounter: holdCounter + 1)
                    }
                } else {
                    // Went back above threshold, cancel pending
                    state = .nonSilent
                }

            case .silent:
                if isAboveNonSilenceThreshold {
                    // Start pending transition to non-silence
                    state = .pendingNonSilent(holdCounter: 1)
                }

            case .pendingNonSilent(let holdCounter):
                if isAboveNonSilenceThreshold {
                    if holdCounter >= exitHoldCount {
                        // Confirmed: transition to non-silence
                        // End silence at when we first went above threshold
                        if let startTime = silenceStartTime {
                            let endTime = frameTime - (Double(holdCounter) * hopDuration)
                            rawSilenceRanges.append(SilenceRange(start: startTime, end: endTime))
                        }
                        silenceStartTime = nil
                        state = .nonSilent
                    } else {
                        state = .pendingNonSilent(holdCounter: holdCounter + 1)
                    }
                } else {
                    // Dropped back below threshold, stay in silence
                    state = .silent
                }
            }
        }

        // Handle silence at end of file
        if case .silent = state, let startTime = silenceStartTime {
            rawSilenceRanges.append(SilenceRange(start: startTime, end: duration))
        } else if case .pendingNonSilent = state, let startTime = silenceStartTime {
            // Was about to exit silence but file ended - count as silence to end
            rawSilenceRanges.append(SilenceRange(start: startTime, end: duration))
        }

        logger.debug("Raw silence regions: \(rawSilenceRanges.count)")

        // ============================================================
        // STEP 2: Merge silence regions separated by tiny gaps
        // ============================================================

        let mergeGap = mergeGapMs / 1000.0
        var mergedRanges: [SilenceRange] = []

        for range in rawSilenceRanges {
            if let last = mergedRanges.last {
                let gap = range.start - last.end
                if gap < mergeGap {
                    // Merge: extend previous range to cover this one
                    mergedRanges[mergedRanges.count - 1] = SilenceRange(start: last.start, end: range.end)
                } else {
                    mergedRanges.append(range)
                }
            } else {
                mergedRanges.append(range)
            }
        }

        logger.debug("After merge: \(mergedRanges.count) regions")

        // ============================================================
        // STEP 3: Apply pre/post roll by SHRINKING each region
        // ============================================================

        let preRoll = silencePreRollMs / 1000.0
        let postRoll = silencePostRollMs / 1000.0

        var rolledRanges: [SilenceRange] = []
        for range in mergedRanges {
            let adjustedStart = range.start + preRoll
            let adjustedEnd = range.end - postRoll

            // Only keep if start < end after roll
            if adjustedStart < adjustedEnd {
                let finalStart = max(0, min(adjustedStart, duration))
                let finalEnd = max(finalStart, min(adjustedEnd, duration))
                if finalStart < finalEnd {
                    rolledRanges.append(SilenceRange(start: finalStart, end: finalEnd))
                }
            }
        }

        logger.debug("After roll: \(rolledRanges.count) regions")

        // ============================================================
        // STEP 4: Enforce minSilenceDuration on ROLLED regions
        // ============================================================

        var silenceRanges: [SilenceRange] = []
        for range in rolledRanges {
            if range.duration >= minSilence {
                silenceRanges.append(range)
            }
        }

        // Cache the result
        silenceCache[url] = silenceRanges

        let totalSilence = silenceRanges.reduce(0.0) { $0 + $1.duration }
        logger.info("Detected \(silenceRanges.count) removable silence ranges (from \(rawSilenceRanges.count) raw), total: \(String(format: "%.1f", totalSilence))s")

        #if DEBUG
        // Print comprehensive debug summary
        let totalFrames = debugSilentFrameCount + debugLoudFrameCount
        let silentPercent = totalFrames > 0 ? (Double(debugSilentFrameCount) / Double(totalFrames)) * 100 : 0
        let minDB = debugDBValues.min() ?? -96
        let maxDB = debugDBValues.max() ?? 0
        let avgDB = debugDBValues.isEmpty ? -96 : debugDBValues.reduce(0, +) / Float(debugDBValues.count)

        print("🔇 SILENCE DETECTION DEBUG:")
        print("   File: \(url.lastPathComponent)")
        print("   Duration: \(String(format: "%.1f", duration))s")
        print("   Threshold: \(silenceThreshold) dB (silence = level BELOW this)")
        print("   Hysteresis exit: \(nonSilenceThreshold) dB (exit silence when ABOVE this)")
        print("   dB range: min=\(String(format: "%.1f", minDB)), max=\(String(format: "%.1f", maxDB)), avg=\(String(format: "%.1f", avgDB))")
        print("   Frames: \(debugSilentFrameCount) silent, \(debugLoudFrameCount) loud (\(String(format: "%.1f", silentPercent))% silent)")
        print("   Raw silence regions: \(rawSilenceRanges.count)")
        print("   After merge: \(mergedRanges.count)")
        print("   After roll: \(rolledRanges.count)")
        print("   Final (≥\(minSilence)s): \(silenceRanges.count) regions, \(String(format: "%.1f", totalSilence))s total")
        if !silenceRanges.isEmpty {
            print("   First 3 silence ranges:")
            for (i, range) in silenceRanges.prefix(3).enumerated() {
                print("     [\(i)] \(String(format: "%.2f", range.start))s - \(String(format: "%.2f", range.end))s (\(String(format: "%.2f", range.duration))s)")
            }
        }
        #endif

        return silenceRanges
    }

    /// Clear cache for a specific URL (memory + disk)
    func clearCache(for url: URL) {
        waveformCache.removeValue(forKey: url)
        silenceCache.removeValue(forKey: url)
        let cacheFile = diskCacheURL(for: url)
        try? FileManager.default.removeItem(at: cacheFile)
    }

    /// Clear only silence cache for a specific URL (keeps waveform cache)
    func clearSilenceCache(for url: URL) {
        silenceCache.removeValue(forKey: url)
    }

    /// Clear all caches (memory + disk)
    func clearAllCaches() {
        waveformCache.removeAll()
        silenceCache.removeAll()
        try? FileManager.default.removeItem(at: diskCacheDirectory)
    }

    /// Pre-warm the cache for an audio URL (call after recording finishes)
    func precomputeWaveform(for url: URL) async {
        // Skip if already cached
        guard waveformCache[url] == nil else { return }
        guard loadFromDiskCache(for: url) == nil else {
            // Load disk cache into memory
            if let diskCached = loadFromDiskCache(for: url) {
                waveformCache[url] = diskCached
            }
            return
        }

        logger.info("Pre-computing waveform for: \(url.lastPathComponent)")
        _ = try? await extractWaveform(from: url)
    }

    // MARK: - Private Helpers

    /// Downsample by taking peak amplitude in each bucket
    private func downsamplePeak(_ source: [Float], to targetCount: Int) -> [Float] {
        guard !source.isEmpty, targetCount > 0 else { return [] }
        guard source.count != targetCount else { return source }

        var result = [Float]()
        result.reserveCapacity(targetCount)

        let bucketSize = Double(source.count) / Double(targetCount)
        for i in 0..<targetCount {
            let start = Int(Double(i) * bucketSize)
            let end = min(Int(Double(i + 1) * bucketSize), source.count)
            var maxVal: Float = 0
            for j in start..<end {
                if source[j] > maxVal { maxVal = source[j] }
            }
            result.append(maxVal)
        }

        return result
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
