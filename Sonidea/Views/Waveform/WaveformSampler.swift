//
//  WaveformSampler.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import CryptoKit
import Foundation

/// Waveform sample pair: min and max values for a time bucket
/// This allows rendering the actual audio waveform shape (not just envelope)
struct WaveformSamplePair: Codable, Equatable {
    let min: Float  // Minimum sample value (can be negative)
    let max: Float  // Maximum sample value (can be positive)
}

@MainActor
final class WaveformSampler {
    static let shared = WaveformSampler()

    /// Cache key combines URL + file modification date so edits auto-invalidate
    private var cache: [String: [Float]] = [:]
    private var minMaxCache: [String: [WaveformSamplePair]] = [:]
    private let maxCacheEntries = 20
    private var accessOrder: [String] = []
    private var saveDebounceTask: Task<Void, Never>?
    private var saveMinMaxDebounceTask: Task<Void, Never>?

    /// Reverse mapping: URL absoluteString -> Set of SHA-256 cache keys derived from that URL.
    /// Needed because SHA-256 keys can't be prefix-matched for eviction.
    private var urlToCacheKeys: [String: Set<String>] = [:]

    // Resampling cache to avoid redundant recalculations during rapid zoom/scroll
    private var lastResampleKey: String?
    private var lastResampleTarget: Int = 0
    private var lastResampleResult: [Float] = []
    private var lastResampleMinMaxKey: String?
    private var lastResampleMinMaxTarget: Int = 0
    private var lastResampleMinMaxResult: [WaveformSamplePair] = []

    private static var cacheDirectory: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return caches.appendingPathComponent("WaveformCache", isDirectory: true)
    }

    private init() {
        // Ensure cache directory exists
        try? FileManager.default.createDirectory(at: Self.cacheDirectory, withIntermediateDirectories: true)
        loadCache()
        // Clean up legacy UserDefaults cache
        UserDefaults.standard.removeObject(forKey: "waveformCache")
        UserDefaults.standard.removeObject(forKey: "waveformMinMaxCache")
    }

    // MARK: - Cache Key

    /// Build a cache key using SHA-256 of (URL + modification date).
    /// SHA-256 is collision-resistant even for similar file paths (e.g. UUIDs differing by one char).
    /// When the file is edited (trim, fade, normalize, etc.), the modification date changes,
    /// so the old cache entry is automatically missed and fresh samples are extracted.
    private func cacheKey(for url: URL) -> String {
        var raw = url.absoluteString
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let modDate = attrs[.modificationDate] as? Date {
            raw += "|\(modDate.timeIntervalSince1970)"
        }
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Register a SHA-256 cache key in the reverse lookup for later eviction by URL.
    private func registerCacheKey(_ key: String, for url: URL) {
        let urlString = url.absoluteString
        var keys = urlToCacheKeys[urlString] ?? []
        keys.insert(key)
        urlToCacheKeys[urlString] = keys
    }

    // MARK: - LRU Helpers

    private func touchCache(_ key: String) {
        accessOrder.removeAll { $0 == key }
        accessOrder.append(key)
    }

    private func evictIfNeeded() {
        while cache.count > maxCacheEntries, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
            minMaxCache.removeValue(forKey: oldest)
            // Clean up reverse map: remove evicted key from all URL entries
            for (urlString, var keys) in urlToCacheKeys {
                keys.remove(oldest)
                if keys.isEmpty {
                    urlToCacheKeys.removeValue(forKey: urlString)
                } else {
                    urlToCacheKeys[urlString] = keys
                }
            }
        }
    }

    // MARK: - Public API

    func samples(for url: URL, targetSampleCount: Int = 200) async -> [Float] {
        let key = cacheKey(for: url)
        registerCacheKey(key, for: url)

        // Check memory cache first
        if let cached = cache[key] {
            touchCache(key)
            // Return cached resample result if key and target match (avoids redundant work during zoom/scroll)
            if key == lastResampleKey && targetSampleCount == lastResampleTarget {
                return lastResampleResult
            }
            let result = resample(cached, to: targetSampleCount)
            lastResampleKey = key
            lastResampleTarget = targetSampleCount
            lastResampleResult = result
            return result
        }

        // Extract samples
        guard let samples = await extractSamples(from: url) else {
            return []
        }

        // Cache in memory
        cache[key] = samples
        touchCache(key)
        evictIfNeeded()
        saveCache()

        let result = resample(samples, to: targetSampleCount)
        lastResampleKey = key
        lastResampleTarget = targetSampleCount
        lastResampleResult = result
        return result
    }

    /// Get min/max sample pairs for true waveform rendering
    func minMaxSamples(for url: URL, targetSampleCount: Int = 200) async -> [WaveformSamplePair] {
        let key = cacheKey(for: url)
        registerCacheKey(key, for: url)

        // Check memory cache first
        if let cached = minMaxCache[key] {
            touchCache(key)
            // Return cached resample result if key and target match (avoids redundant work during zoom/scroll)
            if key == lastResampleMinMaxKey && targetSampleCount == lastResampleMinMaxTarget {
                return lastResampleMinMaxResult
            }
            let result = resampleMinMax(cached, to: targetSampleCount)
            lastResampleMinMaxKey = key
            lastResampleMinMaxTarget = targetSampleCount
            lastResampleMinMaxResult = result
            return result
        }

        // Extract min/max samples
        guard let samples = await extractMinMaxSamples(from: url) else {
            return []
        }

        // Cache in memory
        minMaxCache[key] = samples
        touchCache(key)
        evictIfNeeded()
        saveMinMaxCache()

        let result = resampleMinMax(samples, to: targetSampleCount)
        lastResampleMinMaxKey = key
        lastResampleMinMaxTarget = targetSampleCount
        lastResampleMinMaxResult = result
        return result
    }

    func clearCache(for url: URL) {
        let urlString = url.absoluteString
        let keysToRemove = urlToCacheKeys[urlString] ?? []
        for key in keysToRemove {
            cache.removeValue(forKey: key)
            minMaxCache.removeValue(forKey: key)
            accessOrder.removeAll { $0 == key }
        }
        urlToCacheKeys.removeValue(forKey: urlString)
        saveCache()
        saveMinMaxCache()
    }

    func clearAllCache() {
        cache.removeAll()
        minMaxCache.removeAll()
        urlToCacheKeys.removeAll()
        saveCache()
        saveMinMaxCache()
    }

    // MARK: - Incremental Waveform Update (Trim Optimization)

    /// Incrementally update waveform for a trim operation by slicing the cached array
    /// instead of re-extracting from disk. Falls back to full extraction if no cache exists.
    ///
    /// - Parameters:
    ///   - oldURL: The URL of the audio file before the trim
    ///   - newURL: The URL of the trimmed audio file
    ///   - originalDuration: Duration of the original audio in seconds
    ///   - trimStart: Start time of the kept region in seconds
    ///   - trimEnd: End time of the kept region in seconds
    ///   - targetSampleCount: Number of samples to return (resampled from storage)
    /// - Returns: Resampled waveform array for the trimmed region
    func samplesAfterTrim(
        oldURL: URL,
        newURL: URL,
        originalDuration: TimeInterval,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        targetSampleCount: Int = 200
    ) async -> [Float] {
        // Try to find cached samples for the old URL (any mod-date variant)
        let oldSamples = findCachedSamples(for: oldURL)

        guard let oldSamples, !oldSamples.isEmpty, originalDuration > 0 else {
            // No cache available — fall back to full extraction from the new file
            return await samples(for: newURL, targetSampleCount: targetSampleCount)
        }

        // Compute slice indices proportional to time
        let startFraction = max(0, trimStart / originalDuration)
        let endFraction = min(1, trimEnd / originalDuration)
        let startIndex = Int(startFraction * Double(oldSamples.count))
        let endIndex = min(Int(endFraction * Double(oldSamples.count)), oldSamples.count)

        guard startIndex < endIndex else {
            return await samples(for: newURL, targetSampleCount: targetSampleCount)
        }

        let sliced = Array(oldSamples[startIndex..<endIndex])

        // Re-normalize the sliced region to 0...1
        let maxValue = sliced.max() ?? 1.0
        let normalized: [Float]
        if maxValue > 0 {
            normalized = sliced.map { $0 / maxValue }
        } else {
            normalized = sliced
        }

        // Cache the trimmed result under the new URL's key
        let newKey = cacheKey(for: newURL)
        registerCacheKey(newKey, for: newURL)
        cache[newKey] = normalized
        touchCache(newKey)
        evictIfNeeded()
        saveCache()

        let result = resample(normalized, to: targetSampleCount)
        lastResampleKey = newKey
        lastResampleTarget = targetSampleCount
        lastResampleResult = result
        return result
    }

    /// Incrementally update min/max waveform for a trim operation.
    func minMaxSamplesAfterTrim(
        oldURL: URL,
        newURL: URL,
        originalDuration: TimeInterval,
        trimStart: TimeInterval,
        trimEnd: TimeInterval,
        targetSampleCount: Int = 200
    ) async -> [WaveformSamplePair] {
        let oldSamples = findCachedMinMaxSamples(for: oldURL)

        guard let oldSamples, !oldSamples.isEmpty, originalDuration > 0 else {
            return await minMaxSamples(for: newURL, targetSampleCount: targetSampleCount)
        }

        let startFraction = max(0, trimStart / originalDuration)
        let endFraction = min(1, trimEnd / originalDuration)
        let startIndex = Int(startFraction * Double(oldSamples.count))
        let endIndex = min(Int(endFraction * Double(oldSamples.count)), oldSamples.count)

        guard startIndex < endIndex else {
            return await minMaxSamples(for: newURL, targetSampleCount: targetSampleCount)
        }

        let sliced = Array(oldSamples[startIndex..<endIndex])

        // Re-normalize to -1...1
        var peakAmplitude: Float = 0.001
        for pair in sliced {
            peakAmplitude = Swift.max(peakAmplitude, abs(pair.min), abs(pair.max))
        }
        let normalized = sliced.map { pair in
            WaveformSamplePair(min: pair.min / peakAmplitude, max: pair.max / peakAmplitude)
        }

        let newKey = cacheKey(for: newURL)
        registerCacheKey(newKey, for: newURL)
        minMaxCache[newKey] = normalized
        touchCache(newKey)
        evictIfNeeded()
        saveMinMaxCache()

        let result = resampleMinMax(normalized, to: targetSampleCount)
        lastResampleMinMaxKey = newKey
        lastResampleMinMaxTarget = targetSampleCount
        lastResampleMinMaxResult = result
        return result
    }

    /// Find cached envelope samples for a URL regardless of modification date.
    /// Searches all cache keys associated with this URL via the reverse lookup.
    private func findCachedSamples(for url: URL) -> [Float]? {
        let urlString = url.absoluteString
        guard let keys = urlToCacheKeys[urlString] else { return nil }
        // Return the most recently accessed entry
        for key in accessOrder.reversed() {
            if keys.contains(key), let samples = cache[key] {
                return samples
            }
        }
        return nil
    }

    /// Find cached min/max samples for a URL regardless of modification date.
    private func findCachedMinMaxSamples(for url: URL) -> [WaveformSamplePair]? {
        let urlString = url.absoluteString
        guard let keys = urlToCacheKeys[urlString] else { return nil }
        for key in accessOrder.reversed() {
            if keys.contains(key), let samples = minMaxCache[key] {
                return samples
            }
        }
        return nil
    }

    // MARK: - Sample Extraction

    private func extractSamples(from url: URL) async -> [Float]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let audioFile = try? AVAudioFile(forReading: url) else {
                    continuation.resume(returning: nil)
                    return
                }

                let format = audioFile.processingFormat
                let totalFrames = Int(audioFile.length)

                guard totalFrames > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Downsample to ~1000 buckets using chunked I/O (avoids OOM on long recordings)
                let storageSampleCount = min(1000, totalFrames)
                let samplesPerBucket = max(1, totalFrames / storageSampleCount)

                var samples = [Float](repeating: 0, count: storageSampleCount)

                let chunkFrameCount: AVAudioFrameCount = 65536
                guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                    continuation.resume(returning: nil)
                    return
                }

                audioFile.framePosition = 0
                var globalFrameOffset = 0

                while globalFrameOffset < totalFrames {
                    let framesToRead = AVAudioFrameCount(min(Int(chunkFrameCount), totalFrames - globalFrameOffset))
                    do {
                        try audioFile.read(into: chunkBuffer, frameCount: framesToRead)
                    } catch {
                        continuation.resume(returning: nil)
                        return
                    }
                    guard let floatChannelData = chunkBuffer.floatChannelData else { break }
                    let channelData = floatChannelData[0]
                    let actualFrames = Int(chunkBuffer.frameLength)

                    for i in 0..<actualFrames {
                        let globalIndex = globalFrameOffset + i
                        let bucketIndex = globalIndex / samplesPerBucket
                        guard bucketIndex < storageSampleCount else { break }
                        let amplitude = abs(channelData[i])
                        if amplitude > samples[bucketIndex] {
                            samples[bucketIndex] = amplitude
                        }
                    }

                    globalFrameOffset += actualFrames
                }

                // Normalize to 0...1
                let maxValue = samples.max() ?? 1.0
                if maxValue > 0 {
                    samples = samples.map { $0 / maxValue }
                }

                continuation.resume(returning: samples)
            }
        }
    }

    /// Extract min/max sample pairs to capture actual waveform shape
    private func extractMinMaxSamples(from url: URL) async -> [WaveformSamplePair]? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                guard let audioFile = try? AVAudioFile(forReading: url) else {
                    continuation.resume(returning: nil)
                    return
                }

                let format = audioFile.processingFormat
                let totalFrames = Int(audioFile.length)

                guard totalFrames > 0 else {
                    continuation.resume(returning: nil)
                    return
                }

                // Downsample to ~1000 sample pairs using chunked I/O (avoids OOM on long recordings)
                let storageSampleCount = min(1000, totalFrames)
                let samplesPerBucket = max(1, totalFrames / storageSampleCount)

                var minValues = [Float](repeating: 0, count: storageSampleCount)
                var maxValues = [Float](repeating: 0, count: storageSampleCount)

                let chunkFrameCount: AVAudioFrameCount = 65536
                guard let chunkBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrameCount) else {
                    continuation.resume(returning: nil)
                    return
                }

                audioFile.framePosition = 0
                var globalFrameOffset = 0

                while globalFrameOffset < totalFrames {
                    let framesToRead = AVAudioFrameCount(min(Int(chunkFrameCount), totalFrames - globalFrameOffset))
                    do {
                        try audioFile.read(into: chunkBuffer, frameCount: framesToRead)
                    } catch {
                        continuation.resume(returning: nil)
                        return
                    }
                    guard let floatChannelData = chunkBuffer.floatChannelData else { break }
                    let channelData = floatChannelData[0]
                    let actualFrames = Int(chunkBuffer.frameLength)

                    for i in 0..<actualFrames {
                        let globalIndex = globalFrameOffset + i
                        let bucketIndex = globalIndex / samplesPerBucket
                        guard bucketIndex < storageSampleCount else { break }
                        let sample = channelData[i]
                        if sample < minValues[bucketIndex] {
                            minValues[bucketIndex] = sample
                        }
                        if sample > maxValues[bucketIndex] {
                            maxValues[bucketIndex] = sample
                        }
                    }

                    globalFrameOffset += actualFrames
                }

                // Build pairs and normalize to -1...1 range
                var peakAmplitude: Float = 0.001
                for i in 0..<storageSampleCount {
                    peakAmplitude = Swift.max(peakAmplitude, abs(minValues[i]), abs(maxValues[i]))
                }

                let normalizedSamples = (0..<storageSampleCount).map { i in
                    WaveformSamplePair(
                        min: minValues[i] / peakAmplitude,
                        max: maxValues[i] / peakAmplitude
                    )
                }

                continuation.resume(returning: normalizedSamples)
            }
        }
    }

    // MARK: - Resampling

    private func resample(_ samples: [Float], to targetCount: Int) -> [Float] {
        guard !samples.isEmpty else { return [] }
        guard samples.count != targetCount else { return samples }

        if samples.count < targetCount {
            // Upsample by interpolation
            var result: [Float] = []
            result.reserveCapacity(targetCount)

            for i in 0..<targetCount {
                let position = Float(i) * Float(samples.count - 1) / Float(max(1, targetCount - 1))
                let lowerIndex = Int(position)
                let upperIndex = min(lowerIndex + 1, samples.count - 1)
                let fraction = position - Float(lowerIndex)

                let interpolated = samples[lowerIndex] * (1 - fraction) + samples[upperIndex] * fraction
                result.append(interpolated)
            }

            return result
        } else {
            // Downsample by taking max in each bucket
            var result: [Float] = []
            result.reserveCapacity(targetCount)

            let samplesPerBucket = Float(samples.count) / Float(targetCount)

            for i in 0..<targetCount {
                let start = Int(Float(i) * samplesPerBucket)
                let end = min(Int(Float(i + 1) * samplesPerBucket), samples.count)

                var maxVal: Float = 0
                for j in start..<end {
                    if samples[j] > maxVal {
                        maxVal = samples[j]
                    }
                }
                result.append(maxVal)
            }

            return result
        }
    }

    private func resampleMinMax(_ samples: [WaveformSamplePair], to targetCount: Int) -> [WaveformSamplePair] {
        guard !samples.isEmpty else { return [] }
        guard samples.count != targetCount else { return samples }

        if samples.count < targetCount {
            // Upsample by interpolation
            var result: [WaveformSamplePair] = []
            result.reserveCapacity(targetCount)

            for i in 0..<targetCount {
                let position = Float(i) * Float(samples.count - 1) / Float(max(1, targetCount - 1))
                let lowerIndex = Int(position)
                let upperIndex = min(lowerIndex + 1, samples.count - 1)
                let fraction = position - Float(lowerIndex)

                let minInterp = samples[lowerIndex].min * (1 - fraction) + samples[upperIndex].min * fraction
                let maxInterp = samples[lowerIndex].max * (1 - fraction) + samples[upperIndex].max * fraction
                result.append(WaveformSamplePair(min: minInterp, max: maxInterp))
            }

            return result
        } else {
            // Downsample by taking true min/max in each bucket
            var result: [WaveformSamplePair] = []
            result.reserveCapacity(targetCount)

            let samplesPerBucket = Float(samples.count) / Float(targetCount)

            for i in 0..<targetCount {
                let start = Int(Float(i) * samplesPerBucket)
                let end = min(Int(Float(i + 1) * samplesPerBucket), samples.count)

                var bucketMin: Float = 0
                var bucketMax: Float = 0
                for j in start..<end {
                    if samples[j].min < bucketMin { bucketMin = samples[j].min }
                    if samples[j].max > bucketMax { bucketMax = samples[j].max }
                }
                result.append(WaveformSamplePair(min: bucketMin, max: bucketMax))
            }

            return result
        }
    }

    // MARK: - Persistence (file-based with debounce)

    private func saveCache() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.persistEnvelopeCache()
        }
    }

    private func saveMinMaxCache() {
        saveMinMaxDebounceTask?.cancel()
        saveMinMaxDebounceTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.persistMinMaxCache()
        }
    }

    private func persistEnvelopeCache() {
        let cacheCopy = cache
        let fileURL = Self.cacheDirectory.appendingPathComponent("envelope.json")
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(cacheCopy) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    private func persistMinMaxCache() {
        let cacheCopy = minMaxCache
        let fileURL = Self.cacheDirectory.appendingPathComponent("minmax.json")
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(cacheCopy) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// SHA-256 hash a raw string (used during cache loading to migrate old keys).
    private static func sha256Key(for raw: String) -> String {
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func loadCache() {
        // Load envelope cache from Caches directory.
        // Keys may be legacy "url|modDate" raw strings or SHA-256 hex strings.
        // Legacy keys are re-hashed; SHA-256 keys (64 hex chars) are kept as-is.
        let envelopeFile = Self.cacheDirectory.appendingPathComponent("envelope.json")
        if let data = try? Data(contentsOf: envelopeFile),
           let stringKeyedCache = try? JSONDecoder().decode([String: [Float]].self, from: data) {
            for (key, samples) in stringKeyedCache {
                if key.count == 64, key.allSatisfy({ $0.isHexDigit }) {
                    // Already a SHA-256 key
                    cache[key] = samples
                } else if key.contains("|") {
                    // Legacy "url|modDate" format — re-hash to SHA-256
                    let newKey = Self.sha256Key(for: key)
                    cache[newKey] = samples
                } else if let url = URL(string: key) {
                    // Legacy bare URL — re-key with current mod date then hash
                    let newKey = cacheKey(for: url)
                    cache[newKey] = samples
                    registerCacheKey(newKey, for: url)
                }
            }
        }

        // Load min/max cache from Caches directory
        let minMaxFile = Self.cacheDirectory.appendingPathComponent("minmax.json")
        if let data = try? Data(contentsOf: minMaxFile),
           let stringKeyedCache = try? JSONDecoder().decode([String: [WaveformSamplePair]].self, from: data) {
            for (key, samples) in stringKeyedCache {
                if key.count == 64, key.allSatisfy({ $0.isHexDigit }) {
                    // Already a SHA-256 key
                    minMaxCache[key] = samples
                } else if key.contains("|") {
                    // Legacy "url|modDate" format — re-hash to SHA-256
                    let newKey = Self.sha256Key(for: key)
                    minMaxCache[newKey] = samples
                } else if let url = URL(string: key) {
                    // Legacy bare URL — re-key with current mod date then hash
                    let newKey = cacheKey(for: url)
                    minMaxCache[newKey] = samples
                    registerCacheKey(newKey, for: url)
                }
            }
        }
    }
}
