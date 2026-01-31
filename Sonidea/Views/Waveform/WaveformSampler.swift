//
//  WaveformSampler.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
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

    private var cache: [URL: [Float]] = [:]
    private var minMaxCache: [URL: [WaveformSamplePair]] = [:]
    private let cacheKey = "waveformCache"
    private let minMaxCacheKey = "waveformMinMaxCache"
    private let maxCacheEntries = 20
    private var accessOrder: [URL] = []

    private init() {
        loadCache()
    }

    // MARK: - LRU Helpers

    private func touchCache(_ url: URL) {
        accessOrder.removeAll { $0 == url }
        accessOrder.append(url)
    }

    private func evictIfNeeded() {
        while cache.count > maxCacheEntries, let oldest = accessOrder.first {
            accessOrder.removeFirst()
            cache.removeValue(forKey: oldest)
            minMaxCache.removeValue(forKey: oldest)
        }
    }

    // MARK: - Public API

    func samples(for url: URL, targetSampleCount: Int = 200) async -> [Float] {
        // Check memory cache first
        if let cached = cache[url] {
            touchCache(url)
            return resample(cached, to: targetSampleCount)
        }

        // Extract samples
        guard let samples = await extractSamples(from: url) else {
            return []
        }

        // Cache in memory
        cache[url] = samples
        touchCache(url)
        evictIfNeeded()
        saveCache() // TODO: debounce cache persistence

        return resample(samples, to: targetSampleCount)
    }

    /// Get min/max sample pairs for true waveform rendering
    func minMaxSamples(for url: URL, targetSampleCount: Int = 200) async -> [WaveformSamplePair] {
        // Check memory cache first
        if let cached = minMaxCache[url] {
            touchCache(url)
            return resampleMinMax(cached, to: targetSampleCount)
        }

        // Extract min/max samples
        guard let samples = await extractMinMaxSamples(from: url) else {
            return []
        }

        // Cache in memory
        minMaxCache[url] = samples
        touchCache(url)
        evictIfNeeded()
        saveMinMaxCache() // TODO: debounce cache persistence

        return resampleMinMax(samples, to: targetSampleCount)
    }

    func clearCache(for url: URL) {
        cache.removeValue(forKey: url)
        minMaxCache.removeValue(forKey: url)
        saveCache()
        saveMinMaxCache()
    }

    func clearAllCache() {
        cache.removeAll()
        minMaxCache.removeAll()
        saveCache()
        saveMinMaxCache()
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
                let frameCount = AVAudioFrameCount(audioFile.length)

                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    try audioFile.read(into: buffer)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                guard let floatChannelData = buffer.floatChannelData else {
                    continuation.resume(returning: nil)
                    return
                }

                let channelData = floatChannelData[0]
                let length = Int(buffer.frameLength)

                // Downsample to ~500 samples for storage efficiency
                let storageSampleCount = min(1000, length)
                let samplesPerBucket = max(1, length / storageSampleCount)

                var samples: [Float] = []
                samples.reserveCapacity(storageSampleCount)

                for i in 0..<storageSampleCount {
                    let start = i * samplesPerBucket
                    let end = min(start + samplesPerBucket, length)

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
                let frameCount = AVAudioFrameCount(audioFile.length)

                guard frameCount > 0,
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
                    continuation.resume(returning: nil)
                    return
                }

                do {
                    try audioFile.read(into: buffer)
                } catch {
                    continuation.resume(returning: nil)
                    return
                }

                guard let floatChannelData = buffer.floatChannelData else {
                    continuation.resume(returning: nil)
                    return
                }

                let channelData = floatChannelData[0]
                let length = Int(buffer.frameLength)

                // Downsample to ~500 sample pairs for storage efficiency
                let storageSampleCount = min(1000, length)
                let samplesPerBucket = max(1, length / storageSampleCount)

                var samples: [WaveformSamplePair] = []
                samples.reserveCapacity(storageSampleCount)

                for i in 0..<storageSampleCount {
                    let start = i * samplesPerBucket
                    let end = min(start + samplesPerBucket, length)

                    var minValue: Float = 0
                    var maxValue: Float = 0

                    for j in start..<end {
                        let sample = channelData[j]
                        if sample < minValue {
                            minValue = sample
                        }
                        if sample > maxValue {
                            maxValue = sample
                        }
                    }

                    samples.append(WaveformSamplePair(min: minValue, max: maxValue))
                }

                // Normalize to -1...1 range
                var peakAmplitude: Float = 0.001  // Avoid division by zero
                for pair in samples {
                    peakAmplitude = Swift.max(peakAmplitude, abs(pair.min), abs(pair.max))
                }

                let normalizedSamples = samples.map { pair in
                    WaveformSamplePair(
                        min: pair.min / peakAmplitude,
                        max: pair.max / peakAmplitude
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
                let position = Float(i) * Float(samples.count - 1) / Float(targetCount - 1)
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
                let position = Float(i) * Float(samples.count - 1) / Float(targetCount - 1)
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

    // MARK: - Persistence

    private func saveCache() {
        // Convert URL keys to strings for encoding
        var stringKeyedCache: [String: [Float]] = [:]
        for (url, samples) in cache {
            stringKeyedCache[url.absoluteString] = samples
        }

        if let data = try? JSONEncoder().encode(stringKeyedCache) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }

    private func saveMinMaxCache() {
        var stringKeyedCache: [String: [WaveformSamplePair]] = [:]
        for (url, samples) in minMaxCache {
            stringKeyedCache[url.absoluteString] = samples
        }

        if let data = try? JSONEncoder().encode(stringKeyedCache) {
            UserDefaults.standard.set(data, forKey: minMaxCacheKey)
        }
    }

    private func loadCache() {
        // Load envelope cache
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let stringKeyedCache = try? JSONDecoder().decode([String: [Float]].self, from: data) {
            for (urlString, samples) in stringKeyedCache {
                if let url = URL(string: urlString) {
                    cache[url] = samples
                }
            }
        }

        // Load min/max cache
        if let data = UserDefaults.standard.data(forKey: minMaxCacheKey),
           let stringKeyedCache = try? JSONDecoder().decode([String: [WaveformSamplePair]].self, from: data) {
            for (urlString, samples) in stringKeyedCache {
                if let url = URL(string: urlString) {
                    minMaxCache[url] = samples
                }
            }
        }
    }
}
