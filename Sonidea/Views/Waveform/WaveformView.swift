//
//  WaveformView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

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
    @State private var initialPinchZoom: CGFloat = 1.0

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
                        playheadColor: palette.playheadColor
                    )
                    .frame(width: zoomedWidth, height: geometry.size.height)
                    .id("waveform")
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        if initialPinchZoom == 1.0 {
                            initialPinchZoom = zoomScale
                        }
                        let newScale = initialPinchZoom * value
                        zoomScale = min(max(newScale, minZoom), maxZoom)
                    }
                    .onEnded { _ in
                        initialPinchZoom = 1.0
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

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let centerY = size.height / 2
            let padding: CGFloat = 4  // Internal padding from edges
            let maxAmplitude = (size.height / 2) - padding
            let playheadX = CGFloat(progress) * size.width

            // Theme-based colors
            let gridColor: Color = isDarkMode ? .white.opacity(0.08) : .black.opacity(0.06)
            let waveformColor: Color = isDarkMode ? .white.opacity(0.7) : Color(.systemGray)

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

            // === 2. Draw Waveform ===
            // Use envelope samples for reliable display - mirrored around center line
            // This creates the classic waveform look: louder = taller bars

            let sampleCount = samples.count
            let xStep = size.width / CGFloat(sampleCount)

            // Cap line width: minimum 1, maximum 3 (prevents spider-web on zoom)
            let lineWidth = min(3, max(1, xStep * 0.7))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * xStep + xStep / 2

                // Sample is 0-1 normalized amplitude (louder = higher value)
                let amplitude = CGFloat(sample) * maxAmplitude

                // Draw symmetric around center - louder sounds = taller bars
                let yTop = centerY - amplitude
                let yBottom = centerY + amplitude

                var linePath = Path()
                linePath.move(to: CGPoint(x: x, y: yTop))
                linePath.addLine(to: CGPoint(x: x, y: yBottom))

                context.stroke(
                    linePath,
                    with: .color(waveformColor),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
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

    @Environment(\.colorScheme) private var colorScheme

    // Use the SAME WaveformTimeline as Edit mode for identical zoom/pan behavior
    @State private var timeline: WaveformTimeline?
    @State private var isPanning = false
    @State private var panStartTime: TimeInterval = 0
    @State private var initialPinchZoom: CGFloat = 1.0

    private var palette: ThemePalette {
        colorScheme == .dark ? ThemePalette.systemDark : ThemePalette.systemLight
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            if let timeline = timeline, waveformData != nil {
                ZStack {
                    // Use the SAME WaveformBarsView as Edit mode, but simplified for Details:
                    // - No selection highlight
                    // - No horizontal grid lines (cleaner look)
                    WaveformBarsView(
                        waveformData: waveformData,
                        timeline: timeline,
                        selectionStart: 0,  // No selection in Details mode
                        selectionEnd: 0,
                        width: width,
                        height: height,
                        palette: palette,
                        colorScheme: colorScheme,
                        showsSelectionHighlight: false,
                        showsHorizontalGrid: false  // Cleaner look for Details
                    )

                    // Playhead overlay (same style as Edit mode)
                    DetailsPlayheadView(
                        progress: progress,
                        timeline: timeline,
                        width: width,
                        height: height,
                        palette: palette,
                        isPlaying: isPlaying
                    )
                }
                .frame(height: height)
                // Pinch to zoom (same as Edit mode)
                .gesture(
                    MagnificationGesture()
                        .onChanged { value in
                            if initialPinchZoom == 1.0 {
                                initialPinchZoom = timeline.zoomScale
                            }
                            let newScale = initialPinchZoom * value
                            timeline.zoomScale = min(max(newScale, 1.0), WaveformTimeline.maxZoom)
                        }
                        .onEnded { _ in
                            initialPinchZoom = 1.0
                        }
                )
                // Pan when zoomed (same as Edit mode)
                .simultaneousGesture(
                    DragGesture()
                        .onChanged { value in
                            if timeline.zoomScale > 1.0 {
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
                            }
                        }
                        .onEnded { _ in
                            isPanning = false
                        }
                )
                // Double-tap to toggle zoom (same as Edit mode)
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
                let compensatedProgress = max(0, newProgress - (audioLatencyCompensation / duration))
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

            let barCount = samples.count
            let barSpacing: CGFloat = 1
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = max(1, availableWidth / CGFloat(barCount))

            let barColor: Color = colorScheme == .dark ? .white.opacity(0.5) : Color(.systemGray3)

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = max(2, CGFloat(sample) * size.height * 0.85)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: 0.5)
                    .path(in: rect)

                context.fill(path, with: .color(barColor))
            }
        }
    }
}

// MARK: - Live Waveform View for Recording

struct LiveWaveformView: View {
    let samples: [Float]
    var accentColor: Color = .red  // Default to red for backward compatibility

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let barCount = samples.count
            let barSpacing: CGFloat = 2
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = max(2, availableWidth / CGFloat(barCount))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = max(4, CGFloat(sample) * size.height * 0.9)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: 1.5)
                    .path(in: rect)

                // Gradient effect: more recent samples are brighter
                let alpha = 0.3 + (Double(index) / Double(barCount)) * 0.7
                context.fill(path, with: .color(accentColor.opacity(alpha)))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Static waveform
        WaveformView(
            samples: (0..<100).map { _ in Float.random(in: 0.1...1.0) },
            progress: 0.4,
            zoomScale: .constant(1.0)
        )
        .frame(height: 80)

        // Live waveform
        LiveWaveformView(
            samples: (0..<60).map { _ in Float.random(in: 0.1...1.0) }
        )
        .frame(height: 60)

        // Mini waveform
        MiniWaveformView(
            samples: (0..<30).map { _ in Float.random(in: 0.1...1.0) }
        )
        .frame(width: 60, height: 30)
    }
    .padding()
}
