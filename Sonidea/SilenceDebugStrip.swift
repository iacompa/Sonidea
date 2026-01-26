//
//  SilenceDebugStrip.swift
//  Sonidea
//
//  Visual debug strip showing RMS levels vs silence threshold in Edit Mode.
//  Helps users understand why "Highlight Silent Parts" finds or doesn't find silence.
//

import SwiftUI
import AVFoundation
import Accelerate

// MARK: - RMS Meter for Silence Debug

/// Computes RMS levels from audio data for the silence debug strip
@MainActor
@Observable
final class SilenceRMSMeter {
    // MARK: - Observable State

    /// Current RMS level in dBFS (smoothed for display)
    private(set) var currentDBFS: Float = -96.0

    /// Whether currently below silence threshold
    private(set) var isBelowThreshold: Bool = true

    /// Silence threshold in dBFS
    var thresholdDBFS: Float = -45.0

    /// Hysteresis offset (enter at threshold - offset, exit at threshold + offset)
    var hysteresisDB: Float = 2.0

    // MARK: - Private State

    private var audioFile: AVAudioFile?
    private var audioBuffer: AVAudioPCMBuffer?
    private var sampleRate: Double = 48000
    private var duration: TimeInterval = 0
    private var smoothedRMS: Float = 0

    /// EMA smoothing factor (higher = more responsive, lower = smoother)
    private let smoothingFactor: Float = 0.3

    /// RMS window size in seconds
    private let windowSize: TimeInterval = 0.03 // 30ms

    /// Update throttle
    private var lastUpdateTime: Date = .distantPast
    private let minUpdateInterval: TimeInterval = 1.0 / 15.0 // 15 Hz max

    // MARK: - Public API

    /// Load audio file for RMS analysis
    func loadAudio(from url: URL) {
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else { return }

            let format = file.processingFormat
            sampleRate = format.sampleRate
            duration = Double(file.length) / sampleRate

            // Read entire file into buffer for fast random access
            let frameCount = AVAudioFrameCount(file.length)
            audioBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)

            if let buffer = audioBuffer {
                try file.read(into: buffer)
            }

            // Reset state
            currentDBFS = -96.0
            isBelowThreshold = true
            smoothedRMS = 0

        } catch {
            print("SilenceRMSMeter: Failed to load audio: \(error)")
        }
    }

    /// Update RMS for a given time position (call during playback or scrubbing)
    func updateRMS(at time: TimeInterval) {
        // Throttle updates
        let now = Date()
        guard now.timeIntervalSince(lastUpdateTime) >= minUpdateInterval else { return }
        lastUpdateTime = now

        guard let buffer = audioBuffer,
              let channelData = buffer.floatChannelData,
              duration > 0 else {
            return
        }

        let channelCount = Int(buffer.format.channelCount)
        let totalFrames = Int(buffer.frameLength)

        // Calculate window bounds
        let windowFrames = Int(sampleRate * windowSize)
        let centerFrame = Int(time * sampleRate)
        let startFrame = max(0, centerFrame - windowFrames / 2)
        let endFrame = min(totalFrames, startFrame + windowFrames)
        let frameCount = endFrame - startFrame

        guard frameCount > 0 else {
            currentDBFS = -96.0
            isBelowThreshold = true
            return
        }

        // Calculate max-channel RMS
        var maxRMS: Float = 0

        for ch in 0..<channelCount {
            let samples = channelData[ch]
            var sumSquares: Float = 0

            for i in startFrame..<endFrame {
                let sample = samples[i]
                sumSquares += sample * sample
            }

            let channelRMS = sqrt(sumSquares / Float(frameCount))
            maxRMS = max(maxRMS, channelRMS)
        }

        // Apply EMA smoothing
        smoothedRMS = smoothingFactor * maxRMS + (1 - smoothingFactor) * smoothedRMS

        // Convert to dBFS
        let rawDBFS: Float = smoothedRMS > 0.000001 ? 20.0 * log10(smoothedRMS) : -96.0
        currentDBFS = max(-96.0, min(0, rawDBFS))

        // Update threshold state with hysteresis
        if isBelowThreshold {
            // Currently below threshold - need to exceed threshold + hysteresis to exit
            if currentDBFS > (thresholdDBFS + hysteresisDB) {
                isBelowThreshold = false
            }
        } else {
            // Currently above threshold - need to drop below threshold - hysteresis to enter
            if currentDBFS <= (thresholdDBFS - hysteresisDB) {
                isBelowThreshold = true
            }
        }
    }

    /// Reset meter state
    func reset() {
        currentDBFS = -96.0
        isBelowThreshold = true
        smoothedRMS = 0
    }

    /// Clear loaded audio
    func clear() {
        audioFile = nil
        audioBuffer = nil
        reset()
    }
}

// MARK: - Silence Debug Strip View

/// Thin horizontal strip showing RMS level vs silence threshold
struct SilenceDebugStrip: View {
    let currentDBFS: Float
    let thresholdDBFS: Float
    let isBelowThreshold: Bool

    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    // Visual constants
    private let stripHeight: CGFloat = 12
    private let minDBFS: Float = -60.0  // Left edge of meter
    private let maxDBFS: Float = 0.0    // Right edge of meter

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            ZStack(alignment: .leading) {
                // Background
                RoundedRectangle(cornerRadius: 3)
                    .fill(palette.surface.opacity(0.3))

                // Base line (very subtle)
                Rectangle()
                    .fill(palette.textTertiary.opacity(0.2))
                    .frame(height: 1)
                    .frame(maxWidth: .infinity)
                    .offset(y: stripHeight / 2 - 0.5)

                // RMS level bar
                let levelWidth = levelPosition(for: currentDBFS, in: width)
                RoundedRectangle(cornerRadius: 2)
                    .fill(levelColor)
                    .frame(width: max(2, levelWidth), height: stripHeight - 4)
                    .offset(x: 2, y: 2)

                // Threshold marker
                let thresholdX = levelPosition(for: thresholdDBFS, in: width)
                Rectangle()
                    .fill(palette.accent)
                    .frame(width: 2, height: stripHeight)
                    .offset(x: thresholdX - 1)

                // Small threshold indicator notch at top
                Triangle()
                    .fill(palette.accent)
                    .frame(width: 6, height: 4)
                    .offset(x: thresholdX - 3, y: 0)

                // dBFS readout (right-aligned inside strip)
                HStack(spacing: 0) {
                    Spacer()
                    Text(readoutText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.textTertiary)
                        .padding(.trailing, 4)
                }
            }
        }
        .frame(height: stripHeight)
    }

    // MARK: - Computed Properties

    private var levelColor: Color {
        if isBelowThreshold {
            // Below threshold - muted/silent indicator
            return colorScheme == .dark
                ? Color.gray.opacity(0.4)
                : Color.gray.opacity(0.3)
        } else {
            // Above threshold - active audio
            return palette.accent.opacity(0.7)
        }
    }

    private var readoutText: String {
        let dbText = currentDBFS <= -60 ? "-\u{221E}" : String(format: "%.0f", currentDBFS)
        return "\(dbText) dB | thr \(Int(thresholdDBFS))"
    }

    // MARK: - Helpers

    private func levelPosition(for dbfs: Float, in width: CGFloat) -> CGFloat {
        let clampedDB = max(minDBFS, min(maxDBFS, dbfs))
        let normalized = (clampedDB - minDBFS) / (maxDBFS - minDBFS)
        return CGFloat(normalized) * width
    }
}

// MARK: - Triangle Shape for Threshold Notch

private struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Below threshold
        SilenceDebugStrip(
            currentDBFS: -52,
            thresholdDBFS: -45,
            isBelowThreshold: true
        )
        .padding(.horizontal)

        // Above threshold
        SilenceDebugStrip(
            currentDBFS: -35,
            thresholdDBFS: -45,
            isBelowThreshold: false
        )
        .padding(.horizontal)

        // At threshold
        SilenceDebugStrip(
            currentDBFS: -45,
            thresholdDBFS: -45,
            isBelowThreshold: true
        )
        .padding(.horizontal)

        // Very quiet
        SilenceDebugStrip(
            currentDBFS: -96,
            thresholdDBFS: -45,
            isBelowThreshold: true
        )
        .padding(.horizontal)
    }
    .padding()
    .background(Color.black.opacity(0.9))
}
