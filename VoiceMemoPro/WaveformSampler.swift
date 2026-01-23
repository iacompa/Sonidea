//
//  WaveformSampler.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation

@MainActor
final class WaveformSampler {
    static let shared = WaveformSampler()

    private var cache: [URL: [Float]] = [:]
    private let cacheKey = "waveformCache"

    private init() {
        loadCache()
    }

    // MARK: - Public API

    func samples(for url: URL, targetSampleCount: Int = 200) async -> [Float] {
        // Check memory cache first
        if let cached = cache[url] {
            return resample(cached, to: targetSampleCount)
        }

        // Extract samples
        guard let samples = await extractSamples(from: url) else {
            return []
        }

        // Cache in memory
        cache[url] = samples
        saveCache()

        return resample(samples, to: targetSampleCount)
    }

    func clearCache(for url: URL) {
        cache.removeValue(forKey: url)
        saveCache()
    }

    func clearAllCache() {
        cache.removeAll()
        saveCache()
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
                let storageSampleCount = min(500, length)
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

    private func loadCache() {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let stringKeyedCache = try? JSONDecoder().decode([String: [Float]].self, from: data) else {
            return
        }

        for (urlString, samples) in stringKeyedCache {
            if let url = URL(string: urlString) {
                cache[url] = samples
            }
        }
    }
}
