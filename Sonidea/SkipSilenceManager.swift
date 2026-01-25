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
    /// Silence threshold in dBFS (default: -40 dB)
    var thresholdDB: Float = -40.0

    /// Minimum silence duration to skip (default: 300ms)
    var minSilenceDuration: TimeInterval = 0.3

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
            let ranges = try await AudioWaveformExtractor.shared.detectSilence(
                from: url,
                threshold: settings.thresholdDB,
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

    /// Check if a time position is in a silence range and get the end time to skip to
    /// - Parameter currentTime: Current playback time
    /// - Returns: The time to seek to if in silence, nil if not in silence
    func shouldSkip(at currentTime: TimeInterval) -> TimeInterval? {
        guard isEnabled && !isAnalyzing else { return nil }

        // Prevent rapid repeated seeks (debounce)
        let now = Date()
        if abs(currentTime - lastSeekTime) < 0.1 && now.timeIntervalSince(lastSeekTimestamp) < 0.5 {
            return nil
        }

        // Find silence range that contains current time
        for range in silenceRanges {
            // Check if we're at the start of a silence range (with small tolerance)
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
                    Text("Lower threshold detects quieter sounds as silence. Longer duration skips only extended pauses.")
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
