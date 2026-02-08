//
//  SkipSilenceManager.swift
//  Sonidea
//
//  Manages skip silence functionality during playback.
//  Detects and automatically skips over silent segments.
//

import Foundation
import AVFoundation
import OSLog

// MARK: - Skip Silence Settings

struct SkipSilenceSettings: Equatable, Codable {
    /// Silence threshold in dBFS (default: -55 dB)
    /// Detection uses hysteresis: enters silence at threshold, exits at threshold + 5dB
    var thresholdDB: Float = -55.0

    /// Whether to automatically determine threshold from the audio's noise floor
    var autoThreshold: Bool = false

    /// Minimum silence duration to skip/cut (default: 500ms)
    var minSilenceDuration: TimeInterval = 0.5

    /// Whether to apply a short fade when skipping (prevents clicks)
    var enableFade: Bool = true

    /// Fade duration in seconds
    var fadeDuration: TimeInterval = 0.02

    static let `default` = SkipSilenceSettings()
}

// MARK: - Skip Silence Manager

@MainActor
@Observable
final class SkipSilenceManager {
    // MARK: - Properties

    /// Whether skip silence is enabled
    var isEnabled: Bool = false {
        didSet {
            if isEnabled && silenceRanges.isEmpty {
                // Need to analyze first
                isAnalyzing = true
            }
        }
    }

    /// Whether silence analysis is in progress
    private(set) var isAnalyzing: Bool = false

    /// Current settings
    var settings: SkipSilenceSettings = .default

    /// Detected silence ranges
    private(set) var silenceRanges: [SilenceRange] = []

    /// Total silence duration detected
    var totalSilenceDuration: TimeInterval {
        silenceRanges.reduce(0) { $0 + $1.duration }
    }

    /// Number of silence segments
    var silenceSegmentCount: Int {
        silenceRanges.count
    }

    /// URL of the currently analyzed audio
    private var analyzedURL: URL?

    /// Logger
    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "SkipSilence")

    /// Last seek time to prevent infinite loops
    private var lastSeekTime: TimeInterval = -1
    private var lastSeekTimestamp: Date = .distantPast

    // MARK: - Public API

    /// Analyze audio file for silence ranges
    func analyze(url: URL) async {
        // Skip if already analyzed for this URL
        if analyzedURL == url && !silenceRanges.isEmpty {
            isAnalyzing = false
            return
        }

        isAnalyzing = true
        logger.info("Analyzing silence for: \(url.lastPathComponent)")

        do {
            var threshold = settings.thresholdDB

            // Auto-threshold: analyze first 10 seconds to find noise floor, then set threshold
            // at noise floor + 15dB. This adapts to different recording environments.
            if settings.autoThreshold {
                let noiseFloor = await Self.estimateNoiseFloor(url: url, logger: logger)
                if let noiseFloor {
                    threshold = noiseFloor + 15.0
                    // Clamp to a reasonable range
                    threshold = max(-70.0, min(-20.0, threshold))
                    logger.info("Auto-threshold: noise floor=\(String(format: "%.1f", noiseFloor))dB, threshold=\(String(format: "%.1f", threshold))dB")
                } else {
                    logger.warning("Auto-threshold: could not estimate noise floor, using manual threshold \(threshold)dB")
                }
            }

            let ranges = try await AudioWaveformExtractor.shared.detectSilence(
                from: url,
                threshold: threshold,
                minDuration: settings.minSilenceDuration
            )

            silenceRanges = ranges
            analyzedURL = url

            logger.info("Found \(ranges.count) silence ranges, total: \(String(format: "%.1f", self.totalSilenceDuration))s")
        } catch {
            logger.error("Silence analysis failed: \(error.localizedDescription)")
            silenceRanges = []
        }

        isAnalyzing = false
    }

    /// Re-analyze with current settings
    func reanalyze() async {
        guard let url = analyzedURL else { return }
        silenceRanges = []

        // Clear cache to force reanalysis
        await AudioWaveformExtractor.shared.clearCache(for: url)
        await analyze(url: url)
    }

    /// Check if a time position is in a silence range and get the end time to skip to.
    /// Uses binary search for O(log n) lookup instead of linear scan.
    /// - Parameter currentTime: Current playback time
    /// - Returns: The time to seek to if in silence, nil if not in silence
    func shouldSkip(at currentTime: TimeInterval) -> TimeInterval? {
        guard isEnabled && !isAnalyzing && !silenceRanges.isEmpty else { return nil }

        // Prevent rapid repeated seeks (debounce)
        let now = Date()
        if abs(currentTime - lastSeekTime) < 0.1 && now.timeIntervalSince(lastSeekTimestamp) < 0.5 {
            return nil
        }

        // Binary search: find the silence range that could contain currentTime.
        // silenceRanges is sorted by start time (from AudioWaveformExtractor).
        // We find the last range whose start <= currentTime, then check containment.
        var lo = 0
        var hi = silenceRanges.count - 1
        var candidateIndex = -1

        while lo <= hi {
            let mid = lo + (hi - lo) / 2
            if silenceRanges[mid].start <= currentTime {
                candidateIndex = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }

        // Check if the candidate range contains currentTime (with small tolerance at end)
        if candidateIndex >= 0 {
            let range = silenceRanges[candidateIndex]
            if currentTime >= range.start && currentTime < range.end - 0.05 {
                let skipTo = range.end
                lastSeekTime = skipTo
                lastSeekTimestamp = now
                logger.debug("Skipping silence: \(String(format: "%.2f", currentTime)) -> \(String(format: "%.2f", skipTo))")
                return skipTo
            }
        }

        return nil
    }

    // MARK: - Auto-Threshold Noise Floor Estimation

    /// Analyze the first 10 seconds of audio to estimate the noise floor in dBFS.
    /// Computes RMS in 20ms windows, sorts them, and takes the 10th percentile as the noise floor.
    /// Returns nil if the file cannot be read or is too short.
    private static func estimateNoiseFloor(url: URL, logger: Logger) async -> Float? {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let format = audioFile.processingFormat
            let sampleRate = format.sampleRate
            let channelCount = Int(format.channelCount)

            guard sampleRate > 0, channelCount > 0 else { return nil }

            // Analyze up to the first 10 seconds
            let maxFrames = Int(min(Double(audioFile.length), sampleRate * 10.0))
            guard maxFrames > 0 else { return nil }

            let windowSamples = Int(sampleRate * 0.02) // 20ms windows
            guard windowSamples > 0, maxFrames >= windowSamples else { return nil }

            let chunkSize = 65536
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(chunkSize)) else {
                return nil
            }

            var rmsValues: [Float] = []
            var samplesRead = 0

            while samplesRead < maxFrames {
                let remaining = maxFrames - samplesRead
                let toRead = AVAudioFrameCount(min(remaining, chunkSize))

                audioFile.framePosition = AVAudioFramePosition(samplesRead)
                try audioFile.read(into: buffer, frameCount: toRead)

                guard let floatData = buffer.floatChannelData else { break }
                let actualFrames = Int(buffer.frameLength)

                // Compute RMS for each 20ms window in this chunk
                var offset = 0
                while offset + windowSamples <= actualFrames && (samplesRead + offset + windowSamples) <= maxFrames {
                    var maxChannelRMS: Float = 0
                    for ch in 0..<channelCount {
                        let channelData = floatData[ch]
                        var sumSquares: Float = 0
                        for i in offset..<(offset + windowSamples) {
                            let s = channelData[i]
                            sumSquares += s * s
                        }
                        let rms = sqrt(sumSquares / Float(windowSamples))
                        maxChannelRMS = max(maxChannelRMS, rms)
                    }
                    let dB: Float = maxChannelRMS > 0.000001 ? 20.0 * log10(maxChannelRMS) : -96.0
                    rmsValues.append(dB)
                    offset += windowSamples
                }

                samplesRead += actualFrames
            }

            guard !rmsValues.isEmpty else { return nil }

            // Sort and take the 10th percentile as the noise floor estimate
            rmsValues.sort()
            let percentileIndex = max(0, min(rmsValues.count - 1, rmsValues.count / 10))
            let noiseFloor = rmsValues[percentileIndex]

            logger.debug("Noise floor estimation: \(rmsValues.count) windows, p10=\(String(format: "%.1f", noiseFloor))dB")
            return noiseFloor
        } catch {
            logger.error("Noise floor estimation failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Clear analysis data
    func clear() {
        silenceRanges = []
        analyzedURL = nil
        lastSeekTime = -1
    }

    /// Reset for a new audio file
    func reset(for url: URL?) {
        if url != analyzedURL {
            clear()
        }
    }
}

// MARK: - Skip Silence View

import SwiftUI

struct SkipSilenceToggle: View {
    @Bindable var skipSilenceManager: SkipSilenceManager
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            // Toggle button
            Button {
                skipSilenceManager.isEnabled.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: skipSilenceManager.isEnabled ? "forward.fill" : "forward")
                        .font(.system(size: 12, weight: .semibold))

                    Text("Skip Silence")
                        .font(.caption)
                        .fontWeight(.medium)
                }
                .foregroundColor(skipSilenceManager.isEnabled ? .white : palette.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(skipSilenceManager.isEnabled ? palette.accent : palette.inputBackground)
                )
            }

            // Status indicator
            if skipSilenceManager.isAnalyzing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Analyzing...")
                        .font(.caption2)
                        .foregroundColor(palette.textTertiary)
                }
            } else if skipSilenceManager.isEnabled && skipSilenceManager.silenceSegmentCount > 0 {
                Text("\(skipSilenceManager.silenceSegmentCount) segments")
                    .font(.caption2)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }
}

// MARK: - Skip Silence Settings View

struct SkipSilenceSettingsView: View {
    @Bindable var skipSilenceManager: SkipSilenceManager
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Auto Threshold", isOn: $skipSilenceManager.settings.autoThreshold)

                    if !skipSilenceManager.settings.autoThreshold {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Silence Threshold")
                                Spacer()
                                Text("\(Int(skipSilenceManager.settings.thresholdDB)) dB")
                                    .foregroundColor(palette.textSecondary)
                                    .monospacedDigit()
                            }

                            Slider(
                                value: $skipSilenceManager.settings.thresholdDB,
                                in: -60...(-20),
                                step: 5
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Minimum Duration")
                            Spacer()
                            Text("\(Int(skipSilenceManager.settings.minSilenceDuration * 1000)) ms")
                                .foregroundColor(palette.textSecondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $skipSilenceManager.settings.minSilenceDuration,
                            in: 0.1...1.0,
                            step: 0.05
                        )
                    }

                    Toggle("Fade Transitions", isOn: $skipSilenceManager.settings.enableFade)
                } header: {
                    Text("Detection Settings")
                } footer: {
                    Text("Auto threshold analyzes the first 10 seconds to detect the noise floor and sets the threshold automatically. Lower manual threshold detects quieter sounds as silence. Longer duration skips only extended pauses.")
                }

                Section {
                    HStack {
                        Text("Silence Segments")
                        Spacer()
                        Text("\(skipSilenceManager.silenceSegmentCount)")
                            .foregroundColor(palette.textSecondary)
                    }

                    HStack {
                        Text("Total Silence")
                        Spacer()
                        Text(formatDuration(skipSilenceManager.totalSilenceDuration))
                            .foregroundColor(palette.textSecondary)
                    }

                    Button("Re-analyze Audio") {
                        Task {
                            await skipSilenceManager.reanalyze()
                        }
                    }
                    .disabled(skipSilenceManager.isAnalyzing)
                } header: {
                    Text("Analysis Results")
                }
            }
            .navigationTitle("Skip Silence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        SkipSilenceToggle(skipSilenceManager: SkipSilenceManager())

        Divider()

        SkipSilenceSettingsView(skipSilenceManager: SkipSilenceManager())
    }
    .padding()
}
