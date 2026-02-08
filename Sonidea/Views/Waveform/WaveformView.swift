//
//  WaveformView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import UIKit

struct WaveformView: View {
    let samples: [Float]
    let minMaxSamples: [WaveformSamplePair]?  // Optional min/max for true waveform
    var progress: Double = 0
    @Binding var zoomScale: CGFloat

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 10.0
    private let cornerRadius: CGFloat = 12

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette
    @State private var initialPinchZoom: CGFloat? = nil

    /// Convenience initializer for backward compatibility (envelope only)
    init(samples: [Float], progress: Double = 0, zoomScale: Binding<CGFloat>) {
        self.samples = samples
        self.minMaxSamples = nil
        self.progress = progress
        self._zoomScale = zoomScale
    }

    /// Full initializer with min/max samples for true waveform rendering
    init(samples: [Float], minMaxSamples: [WaveformSamplePair]?, progress: Double = 0, zoomScale: Binding<CGFloat>) {
        self.samples = samples
        self.minMaxSamples = minMaxSamples
        self.progress = progress
        self._zoomScale = zoomScale
    }

    var body: some View {
        GeometryReader { geometry in
            let baseWidth = geometry.size.width
            let zoomedWidth = baseWidth * zoomScale

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: zoomScale > 1) {
                    WaveformCanvas(
                        samples: samples,
                        minMaxSamples: minMaxSamples,
                        progress: progress,
                        width: zoomedWidth,
                        height: geometry.size.height,
                        isDarkMode: colorScheme == .dark,
                        playheadColor: palette.playheadColor,
                        waveformBarColor: palette.waveformBarColor
                    )
                    .frame(width: zoomedWidth, height: geometry.size.height)
                    .id("waveform")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(palette.waveformBackground)
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        if initialPinchZoom == nil {
                            initialPinchZoom = zoomScale
                        }
                        let newScale = (initialPinchZoom ?? zoomScale) * value
                        zoomScale = min(max(newScale, minZoom), maxZoom)
                    }
                    .onEnded { _ in
                        initialPinchZoom = nil
                    }
            )
        }
    }
}

struct WaveformCanvas: View {
    let samples: [Float]
    let minMaxSamples: [WaveformSamplePair]?  // Optional true waveform data
    let progress: Double
    let width: CGFloat
    let height: CGFloat
    let isDarkMode: Bool
    var playheadColor: Color = .white
    var waveformBarColor: Color = .white

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let centerY = size.height / 2
            let padding: CGFloat = 4  // Internal padding from edges
            let maxAmplitude = (size.height / 2) - padding
            let playheadX = CGFloat(progress) * size.width

            // Theme-based colors
            let gridColor: Color = isDarkMode ? .white.opacity(0.08) : .black.opacity(0.06)
            // High-contrast neutral bar color
            let waveformColor: Color = waveformBarColor

            // === 1. Draw Grid (behind waveform) ===

            // Vertical grid lines (time markers)
            let verticalGridCount = 20
            let verticalSpacing = size.width / CGFloat(verticalGridCount)
            for i in 1..<verticalGridCount {
                let x = CGFloat(i) * verticalSpacing
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: 0))
                gridLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(gridLine, with: .color(gridColor), lineWidth: 0.5)
            }

            // Horizontal grid lines (amplitude markers)
            let horizontalGridCount = 4
            let horizontalSpacing = size.height / CGFloat(horizontalGridCount)
            for i in 1..<horizontalGridCount {
                let y = CGFloat(i) * horizontalSpacing
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: y))
                gridLine.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(gridLine, with: .color(gridColor), lineWidth: 0.5)
            }

            // Center line (more visible)
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: centerY))
            centerLine.addLine(to: CGPoint(x: size.width, y: centerY))
            context.stroke(centerLine, with: .color(isDarkMode ? Color.white.opacity(0.15) : Color.black.opacity(0.12)), lineWidth: 0.5)

            // === 2. Draw Waveform (Apple Voice Memos style) ===
            // Thin bars with rounded caps, high density, centered on midline

            let sampleCount = samples.count
            let xStep = size.width / CGFloat(sampleCount)

            // Apple Voice Memos style: thin bars (1-1.5pt) with small gaps
            // barWidth is the stroke width; gap is implicit from xStep - barWidth
            let barWidth: CGFloat = min(1.5, max(0.75, xStep * 0.55))

            // Minimum bar height ensures silent sections still show a subtle mark
            let minBarHeight: CGFloat = 1.5

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * xStep + xStep / 2

                // Sample is 0-1 normalized amplitude (louder = higher value)
                let amplitude = max(minBarHeight, CGFloat(sample) * maxAmplitude)

                // Draw symmetric around center - louder sounds = taller bars
                let yTop = centerY - amplitude
                let yBottom = centerY + amplitude

                var linePath = Path()
                linePath.move(to: CGPoint(x: x, y: yTop))
                linePath.addLine(to: CGPoint(x: x, y: yBottom))

                context.stroke(
                    linePath,
                    with: .color(waveformColor),
                    style: StrokeStyle(lineWidth: barWidth, lineCap: .round)
                )
            }

            // === 3. Draw Playhead (on top) ===
            if progress > 0.001 && progress < 0.999 {
                var playheadPath = Path()
                playheadPath.move(to: CGPoint(x: playheadX, y: 0))
                playheadPath.addLine(to: CGPoint(x: playheadX, y: size.height))
                context.stroke(playheadPath, with: .color(playheadColor), lineWidth: 2)
            }
        }
    }
}

// MARK: - Details Waveform View (uses same renderer as Edit mode)

/// Waveform view for Details panel - uses the SAME WaveformBarsView as Edit mode.
/// This is a compact/mini version with no edit overlays (selection, handles, etc).
/// Supports zoom, pan, and follow-track (center playhead during playback).
struct DetailsWaveformView: View {
    let waveformData: WaveformData?
    let fallbackSamples: [Float]  // Unused - kept for API compatibility
    let progress: Double
    let duration: TimeInterval
    var isPlaying: Bool = false
    var markers: [Marker] = []
    /// Callback when user taps or drags to seek to a time position (in seconds)
    var onSeek: ((TimeInterval) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette

    // Use the SAME WaveformTimeline as Edit mode for identical zoom/pan behavior
    @State private var timeline: WaveformTimeline?
    @State private var isPanning = false
    @State private var isSeeking = false  // Track whether user is scrubbing the playhead
    @State private var panStartTime: TimeInterval = 0
    @State private var initialPinchZoom: CGFloat? = nil

    // Compact ruler height for Details view
    private let detailsRulerHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let totalHeight = geometry.size.height
            let waveformHeight = totalHeight

            if let timeline = timeline, waveformData != nil {
                ZStack {
                    // Waveform bars (no selection, no grid — clean playback look)
                    WaveformBarsView(
                        waveformData: waveformData,
                        timeline: timeline,
                        selectionStart: 0,
                        selectionEnd: 0,
                        width: width,
                        height: waveformHeight,
                        palette: palette,
                        colorScheme: colorScheme,
                        showsSelectionHighlight: false,
                        showsHorizontalGrid: false
                    )

                    // Marker flags
                    if !markers.isEmpty {
                        MarkerFlagsOverlay(
                            markers: markers,
                            playheadPosition: progress * duration,
                            timeline: timeline,
                            width: width,
                            palette: palette
                        )
                    }

                    // Playhead overlay
                    DetailsPlayheadView(
                        progress: progress,
                        timeline: timeline,
                        width: width,
                        height: waveformHeight,
                        palette: palette,
                        isPlaying: isPlaying
                    )
                }
                .frame(height: waveformHeight)
                .background(palette.waveformBackground)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                // Pinch to zoom (same as Edit mode)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if initialPinchZoom == nil {
                                initialPinchZoom = timeline.zoomScale
                            }
                            let newScale = (initialPinchZoom ?? timeline.zoomScale) * value
                            let clampedScale = min(max(newScale, 1.0), WaveformTimeline.maxZoom)
                            // Use zoom(to:centeredOn:) to keep visibleStartTime in sync
                            let centerTime = timeline.visibleStartTime + timeline.visibleDuration / 2
                            timeline.zoom(to: clampedScale, centeredOn: centerTime)
                        }
                        .onEnded { _ in
                            initialPinchZoom = nil
                        }
                )
                // Drag gesture: pan when zoomed, scrub playhead when not zoomed
                .simultaneousGesture(
                    DragGesture(minimumDistance: 5)
                        .onChanged { value in
                            if timeline.zoomScale > 1.0 {
                                // Zoomed in: pan the visible window
                                if !isPanning {
                                    isPanning = true
                                    panStartTime = timeline.visibleStartTime
                                }
                                let deltaX = -value.translation.width
                                let timeDelta = Double(deltaX) / Double(width) * timeline.visibleDuration
                                let newStartTime = panStartTime + timeDelta
                                let clampedStart = max(0, min(newStartTime, timeline.duration - timeline.visibleDuration))
                                if abs(clampedStart - timeline.visibleStartTime) > 0.0001 {
                                    timeline.visibleStartTime = clampedStart
                                }
                            } else {
                                // Not zoomed: scrub playhead to drag position
                                guard duration > 0 else { return }
                                if !isSeeking {
                                    isSeeking = true
                                    // Light haptic on scrub start
                                    let impact = UIImpactFeedbackGenerator(style: .light)
                                    impact.impactOccurred()
                                }
                                let dragX = value.location.x
                                let draggedTime = timeline.xToTime(dragX, width: width)
                                let clampedTime = max(0, min(draggedTime, duration))
                                onSeek?(clampedTime)
                            }
                        }
                        .onEnded { _ in
                            isPanning = false
                            isSeeking = false
                        }
                )
                // Double-tap to toggle zoom (must be registered before single-tap)
                .onTapGesture(count: 2) {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        if timeline.zoomScale > 1.5 {
                            timeline.reset()
                        } else {
                            let currentTime = progress * duration
                            timeline.zoom(to: 4.0, centeredOn: currentTime)
                        }
                    }
                }
                // Single-tap to seek playhead to tapped position
                .onTapGesture(count: 1) { location in
                    guard duration > 0 else { return }
                    let tappedTime = timeline.xToTime(location.x, width: width)
                    let clampedTime = max(0, min(tappedTime, duration))
                    // Light haptic feedback
                    let impact = UIImpactFeedbackGenerator(style: .light)
                    impact.impactOccurred()
                    onSeek?(clampedTime)
                }
                // Zoom indicator
                .overlay(alignment: .topTrailing) {
                    if timeline.zoomScale > 1.05 {
                        HStack(spacing: 4) {
                            Text("\(Int(timeline.zoomScale * 100))%")
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(palette.textSecondary)
                            Button {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    timeline.reset()
                                }
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(palette.accent)
                            }
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(palette.inputBackground.opacity(0.9))
                        .clipShape(Capsule())
                        .padding(6)
                    }
                }
            } else {
                // Loading state - show empty container
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.inputBackground.opacity(0.3))
            }
        }
        .onAppear {
            if timeline == nil && duration > 0 {
                timeline = WaveformTimeline(duration: duration)
            }
        }
        .onChange(of: duration) { _, newDuration in
            if newDuration > 0 && (timeline == nil || timeline?.duration != newDuration) {
                timeline = WaveformTimeline(duration: newDuration)
            }
        }
        // Follow-track: center playhead when zoomed and playing
        .onChange(of: progress) { _, newProgress in
            guard let timeline = timeline else { return }
            if isPlaying && timeline.zoomScale > 1.0 && !isPanning {
                // Apply audio latency compensation (same as Edit mode)
                let audioLatencyCompensation: TimeInterval = 0.05
                let compensatedTime = max(0, newProgress * duration - audioLatencyCompensation)
                let compensatedProgress = compensatedTime / duration
                let currentTime = compensatedProgress * duration
                timeline.centerOnTime(currentTime)
            }
        }
    }

    /// Audio latency compensation for playhead display (matches Edit mode)
    private static let audioLatencyCompensation: TimeInterval = 0.05
}

/// Simple playhead line for Details mode (no drag interaction)
private struct DetailsPlayheadView: View {
    let progress: Double
    let timeline: WaveformTimeline
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette
    var isPlaying: Bool = false

    // Audio latency compensation - matches Edit mode (50ms)
    private let audioLatencyCompensation: TimeInterval = 0.05

    private var compensatedProgress: Double {
        if isPlaying && timeline.duration > 0 {
            return max(0, progress - (audioLatencyCompensation / timeline.duration))
        }
        return progress
    }

    var body: some View {
        let currentTime = compensatedProgress * timeline.duration
        let x = timeline.timeToX(currentTime, width: width)

        // Only show if playhead is in visible range
        if x >= 0 && x <= width && compensatedProgress > 0.001 && compensatedProgress < 0.999 {
            Path { path in
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: height))
            }
            .stroke(palette.playheadColor, lineWidth: 2)
        }
    }
}

// MARK: - Mini Waveform for List Rows

struct MiniWaveformView: View {
    let samples: [Float]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let centerY = size.height / 2
            let maxAmplitude = size.height / 2 * 0.85

            // Apple Voice Memos style: thin bars, rounded caps, centered on midline
            let barCount = samples.count
            let xStep = size.width / CGFloat(barCount)
            let barWidth: CGFloat = min(1.25, max(0.75, xStep * 0.55))
            let minBarHeight: CGFloat = 1.0

            let barColor: Color = colorScheme == .dark ? .white.opacity(0.5) : Color(.systemGray3)

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * xStep + xStep / 2

                let amplitude = max(minBarHeight, CGFloat(sample) * maxAmplitude)

                let yTop = centerY - amplitude
                let yBottom = centerY + amplitude

                var linePath = Path()
                linePath.move(to: CGPoint(x: x, y: yTop))
                linePath.addLine(to: CGPoint(x: x, y: yBottom))

                context.stroke(
                    linePath,
                    with: .color(barColor),
                    style: StrokeStyle(lineWidth: barWidth, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Live Waveform View for Recording (Apple Voice Memos Style)

/// A professional live waveform visualization that matches Apple Voice Memos.
/// Features:
/// - Clean vertical bars that animate smoothly
/// - Bars grow from center outward (mirrored top/bottom)
/// - Consistent bar width with small gaps
/// - Smooth amplitude animation without jitter
/// - Gradient from left (older/dimmer) to right (newer/brighter)
/// - New audio appears on the right, older audio scrolls left
struct LiveWaveformView: View {
    let samples: [Float]
    var accentColor: Color = .red  // Default to red for backward compatibility

    // Configuration for Apple Voice Memos style
    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 2.0
    private let cornerRadius: CGFloat = 1.5
    private let minBarHeightRatio: CGFloat = 0.04  // Minimum visible bar (4% of height)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centerY = size.height / 2
            let maxAmplitude = (size.height / 2) * 0.92  // Leave small margin at top/bottom

            // Calculate how many bars fit in the available width
            let totalBarWidth = barWidth + barSpacing
            let maxBars = Int(size.width / totalBarWidth)

            // Use the samples we have, up to maxBars
            let displaySamples = samples.suffix(maxBars)
            let barCount = displaySamples.count

            // Calculate starting X position to right-align the bars
            // New audio appears on the right, older scrolls left
            let totalContentWidth = CGFloat(barCount) * totalBarWidth - barSpacing
            let startX = size.width - totalContentWidth

            Canvas { context, _ in
                guard barCount > 0 else { return }

                for (index, sample) in displaySamples.enumerated() {
                    // X position for this bar (right-aligned, newest on right)
                    let x = startX + CGFloat(index) * totalBarWidth

                    // Calculate bar height with smooth amplitude scaling
                    // Apply a subtle power curve for more dynamic range visualization
                    let normalizedSample = CGFloat(max(0, min(1, sample)))
                    let curvedSample = pow(normalizedSample, 0.7)  // Slight compression for smoother look
                    let minHeight = size.height * minBarHeightRatio
                    let barHeight = max(minHeight, curvedSample * maxAmplitude * 2)

                    // Bar grows from center (mirrored top/bottom)
                    let halfHeight = barHeight / 2
                    let barRect = CGRect(
                        x: x,
                        y: centerY - halfHeight,
                        width: barWidth,
                        height: barHeight
                    )

                    // Gradient opacity: older samples (left) are dimmer, newer (right) are brighter
                    // This creates the scrolling fade effect like Apple Voice Memos
                    let progress = CGFloat(index) / CGFloat(max(1, barCount - 1))
                    let fadeStart: CGFloat = 0.25  // Oldest bars at 25% opacity
                    let fadeEnd: CGFloat = 1.0     // Newest bars at full opacity
                    let opacity = fadeStart + (fadeEnd - fadeStart) * progress

                    // Draw rounded rectangle bar
                    let roundedBar = RoundedRectangle(cornerRadius: cornerRadius)
                        .path(in: barRect)

                    context.fill(roundedBar, with: .color(accentColor.opacity(opacity)))
                }
            }
        }
    }
}

/// A more advanced live waveform with smooth interpolation and glow effects.
/// Use this for higher-end visual presentation when performance allows.
struct LiveWaveformViewPro: View {
    let samples: [Float]
    var accentColor: Color = .red

    // Smoothed samples for jitter reduction
    @State private var smoothedSamples: [Float] = []

    private let barWidth: CGFloat = 3.0
    private let barSpacing: CGFloat = 2.0
    private let cornerRadius: CGFloat = 1.5
    private let minBarHeightRatio: CGFloat = 0.04
    private let smoothingFactor: Float = 0.4  // 0 = no smoothing, 1 = max smoothing

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let centerY = size.height / 2
            let maxAmplitude = (size.height / 2) * 0.92

            let totalBarWidth = barWidth + barSpacing
            let maxBars = Int(size.width / totalBarWidth)

            let displaySamples = smoothedSamples.suffix(maxBars)
            let barCount = displaySamples.count

            let totalContentWidth = CGFloat(barCount) * totalBarWidth - barSpacing
            let startX = size.width - totalContentWidth

            ZStack {
                // Glow layer (subtle blur behind bars for polish)
                Canvas { context, _ in
                    guard barCount > 0 else { return }

                    for (index, sample) in displaySamples.enumerated() {
                        let x = startX + CGFloat(index) * totalBarWidth

                        let normalizedSample = CGFloat(max(0, min(1, sample)))
                        let curvedSample = pow(normalizedSample, 0.7)
                        let minHeight = size.height * minBarHeightRatio
                        let barHeight = max(minHeight, curvedSample * maxAmplitude * 2)

                        let halfHeight = barHeight / 2
                        let glowRect = CGRect(
                            x: x - 1,
                            y: centerY - halfHeight - 1,
                            width: barWidth + 2,
                            height: barHeight + 2
                        )

                        let progress = CGFloat(index) / CGFloat(max(1, barCount - 1))
                        let opacity = 0.1 + 0.2 * progress

                        let glowPath = RoundedRectangle(cornerRadius: cornerRadius + 1)
                            .path(in: glowRect)

                        context.fill(glowPath, with: .color(accentColor.opacity(opacity)))
                    }
                }
                .blur(radius: 4)

                // Main bars layer
                Canvas { context, _ in
                    guard barCount > 0 else { return }

                    for (index, sample) in displaySamples.enumerated() {
                        let x = startX + CGFloat(index) * totalBarWidth

                        let normalizedSample = CGFloat(max(0, min(1, sample)))
                        let curvedSample = pow(normalizedSample, 0.7)
                        let minHeight = size.height * minBarHeightRatio
                        let barHeight = max(minHeight, curvedSample * maxAmplitude * 2)

                        let halfHeight = barHeight / 2
                        let barRect = CGRect(
                            x: x,
                            y: centerY - halfHeight,
                            width: barWidth,
                            height: barHeight
                        )

                        let progress = CGFloat(index) / CGFloat(max(1, barCount - 1))
                        let opacity = 0.25 + 0.75 * progress

                        let roundedBar = RoundedRectangle(cornerRadius: cornerRadius)
                            .path(in: barRect)

                        context.fill(roundedBar, with: .color(accentColor.opacity(opacity)))
                    }
                }
            }
        }
        .onChange(of: samples) { _, newSamples in
            updateSmoothedSamples(newSamples)
        }
        .onAppear {
            smoothedSamples = samples
        }
    }

    private func updateSmoothedSamples(_ newSamples: [Float]) {
        // If we don't have existing samples, just use the new ones
        guard !smoothedSamples.isEmpty else {
            smoothedSamples = newSamples
            return
        }

        // Apply exponential smoothing to reduce jitter
        var result: [Float] = []
        let oldCount = smoothedSamples.count
        let newCount = newSamples.count

        // For existing positions, blend old and new
        let overlap = min(oldCount, newCount)
        let offset = newCount - overlap

        for i in 0..<newCount {
            if i >= offset && (i - offset) < oldCount {
                // Blend with existing sample
                let oldSample = smoothedSamples[i - offset]
                let newSample = newSamples[i]
                result.append(oldSample * smoothingFactor + newSample * (1 - smoothingFactor))
            } else {
                // New sample, no blending
                result.append(newSamples[i])
            }
        }

        smoothedSamples = result
    }
}

// MARK: - Preview

#Preview("Waveform Views") {
    VStack(spacing: 24) {
        // Static waveform
        VStack(alignment: .leading, spacing: 4) {
            Text("Static Waveform")
                .font(.caption)
                .foregroundColor(.secondary)
            WaveformView(
                samples: (0..<100).map { _ in Float.random(in: 0.1...1.0) },
                progress: 0.4,
                zoomScale: .constant(1.0)
            )
            .frame(height: 80)
        }

        // Live waveform (Apple Voice Memos style)
        VStack(alignment: .leading, spacing: 4) {
            Text("Live Recording Waveform")
                .font(.caption)
                .foregroundColor(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.03))
                LiveWaveformView(
                    samples: (0..<60).map { _ in Float.random(in: 0.05...1.0) },
                    accentColor: .red
                )
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        // Live waveform with custom accent
        VStack(alignment: .leading, spacing: 4) {
            Text("Live Waveform (Custom Accent)")
                .font(.caption)
                .foregroundColor(.secondary)
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.03))
                LiveWaveformView(
                    samples: (0..<45).map { _ in Float.random(in: 0.1...0.9) },
                    accentColor: .purple
                )
            }
            .frame(height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        // Mini waveform
        VStack(alignment: .leading, spacing: 4) {
            Text("Mini Waveform (List Row)")
                .font(.caption)
                .foregroundColor(.secondary)
            MiniWaveformView(
                samples: (0..<30).map { _ in Float.random(in: 0.1...1.0) }
            )
            .frame(width: 80, height: 30)
        }
    }
    .padding()
}
