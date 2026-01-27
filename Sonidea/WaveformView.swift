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
                        isDarkMode: colorScheme == .dark
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
                        let newScale = zoomScale * value
                        zoomScale = min(max(newScale, minZoom), maxZoom)
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
            let playheadColor: Color = isDarkMode ? .white : .accentColor

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
            context.stroke(centerLine, with: .color(gridColor.opacity(1.5)), lineWidth: 0.5)

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

// MARK: - Details Waveform View (matches Edit mode style)

/// Waveform view for Details panel that matches the Edit mode visual style.
/// Supports zoom, pan, and follow-track (center playhead during playback).
struct DetailsWaveformView: View {
    let waveformData: WaveformData?
    let fallbackSamples: [Float]  // Used if high-res data not loaded yet
    let progress: Double
    let duration: TimeInterval
    var isPlaying: Bool = false

    @Environment(\.colorScheme) private var colorScheme

    // Zoom and pan state
    @State private var zoomScale: CGFloat = 1.0
    @State private var visibleStartProgress: Double = 0  // 0-1 progress into the track
    @State private var initialPinchZoom: CGFloat = 1.0
    @State private var isPanning = false
    @State private var panStartProgress: Double = 0

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 100.0  // Match Edit mode max zoom

    private var palette: ThemePalette {
        colorScheme == .dark ? ThemePalette.systemDark : ThemePalette.systemLight
    }

    /// Visible duration as fraction of total (0-1)
    private var visibleDurationFraction: Double {
        1.0 / Double(zoomScale)
    }

    /// End progress of visible window
    private var visibleEndProgress: Double {
        min(1.0, visibleStartProgress + visibleDurationFraction)
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            DetailsWaveformCanvas(
                waveformData: waveformData,
                fallbackSamples: fallbackSamples,
                progress: progress,
                duration: duration,
                zoomScale: zoomScale,
                visibleStartProgress: visibleStartProgress,
                visibleDurationFraction: visibleDurationFraction,
                width: width,
                height: height,
                colorScheme: colorScheme,
                palette: palette
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white.opacity(0.05) : Color.black.opacity(0.03))
            )
            // Pinch to zoom
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        if initialPinchZoom == 1.0 {
                            initialPinchZoom = zoomScale
                        }
                        let newScale = initialPinchZoom * value
                        zoomScale = min(max(newScale, minZoom), maxZoom)
                        // Clamp visible start
                        let maxStart = max(0, 1.0 - visibleDurationFraction)
                        visibleStartProgress = min(visibleStartProgress, maxStart)
                    }
                    .onEnded { _ in
                        initialPinchZoom = 1.0
                    }
            )
            // Pan when zoomed
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if zoomScale > 1.0 {
                            if !isPanning {
                                isPanning = true
                                panStartProgress = visibleStartProgress
                            }
                            // Convert drag to progress delta
                            let progressDelta = -Double(value.translation.width / width) * visibleDurationFraction
                            var newStart = panStartProgress + progressDelta
                            // Clamp to valid range
                            let maxStart = max(0, 1.0 - visibleDurationFraction)
                            newStart = max(0, min(newStart, maxStart))
                            visibleStartProgress = newStart
                        }
                    }
                    .onEnded { _ in
                        isPanning = false
                    }
            )
            // Double-tap to toggle zoom
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) {
                    if zoomScale > 1.5 {
                        // Reset to full view
                        zoomScale = 1.0
                        visibleStartProgress = 0
                    } else {
                        // Zoom to 4x centered on playhead
                        zoomScale = 4.0
                        let halfVisible = visibleDurationFraction / 2
                        visibleStartProgress = max(0, min(progress - halfVisible, 1.0 - visibleDurationFraction))
                    }
                }
            }
            // Zoom indicator
            .overlay(alignment: .topTrailing) {
                if zoomScale > 1.05 {
                    HStack(spacing: 4) {
                        Text("\(Int(zoomScale * 100))%")
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(palette.textSecondary)
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                zoomScale = 1.0
                                visibleStartProgress = 0
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
        }
        // Follow-track: center playhead when zoomed and playing
        .onChange(of: progress) { _, newProgress in
            if isPlaying && zoomScale > 1.0 && !isPanning {
                // Center the playhead
                let halfVisible = visibleDurationFraction / 2
                var newStart = newProgress - halfVisible
                // Clamp to valid range
                let maxStart = max(0, 1.0 - visibleDurationFraction)
                newStart = max(0, min(newStart, maxStart))
                visibleStartProgress = newStart
            }
        }
    }
}

/// Canvas component for DetailsWaveformView - matches Edit mode (WaveformBarsView) exactly
/// Uses time-based grid lines for proper alignment at all zoom levels
private struct DetailsWaveformCanvas: View {
    let waveformData: WaveformData?
    let fallbackSamples: [Float]
    let progress: Double
    let duration: TimeInterval
    let zoomScale: CGFloat
    let visibleStartProgress: Double
    let visibleDurationFraction: Double
    let width: CGFloat
    let height: CGFloat
    let colorScheme: ColorScheme
    let palette: ThemePalette

    // Calculate tick intervals based on visible duration (matches Edit mode exactly)
    private func tickIntervals(visibleDuration: TimeInterval) -> (major: TimeInterval, minor: TimeInterval) {
        switch visibleDuration {
        case 0..<0.05:   return (0.01, 0.002)   // 10ms major, 2ms minor (extreme zoom)
        case 0.05..<0.2: return (0.05, 0.01)    // 50ms major, 10ms minor
        case 0.2..<0.5:  return (0.1, 0.02)     // 100ms major, 20ms minor
        case 0.5..<1:    return (0.2, 0.05)     // 200ms major, 50ms minor
        case 1..<2:      return (0.5, 0.1)      // 500ms major, 100ms minor
        case 2..<5:      return (1, 0.2)        // 1s major, 200ms minor
        case 5..<10:     return (2, 0.5)        // 2s major, 500ms minor
        case 10..<30:    return (5, 1)          // 5s major, 1s minor
        case 30..<60:    return (10, 2)         // 10s major, 2s minor
        case 60..<120:   return (15, 5)         // 15s major, 5s minor
        case 120..<300:  return (30, 10)        // 30s major, 10s minor
        case 300..<600:  return (60, 15)        // 1min major, 15s minor
        default:         return (120, 30)       // 2min major, 30s minor
        }
    }

    // Convert time to x coordinate (matches Edit mode exactly)
    private func timeToX(_ time: TimeInterval, visibleStartTime: TimeInterval, visibleDuration: TimeInterval, width: CGFloat) -> CGFloat {
        let progress = (time - visibleStartTime) / visibleDuration
        return CGFloat(progress) * width
    }

    var body: some View {
        Canvas { context, size in
            let actualWidth = size.width
            let actualHeight = size.height
            guard actualWidth > 0, actualHeight > 0, duration > 0 else { return }

            // Calculate visible time range
            let visibleStartTime = visibleStartProgress * duration
            let visibleEndTime = min(duration, (visibleStartProgress + visibleDurationFraction) * duration)
            let visibleDuration = visibleEndTime - visibleStartTime

            // Get samples for visible range
            let samples: [Float]
            if let data = waveformData {
                let targetSamples = max(1, Int(actualWidth / 2))
                samples = data.samples(from: visibleStartTime, to: visibleEndTime, targetCount: targetSamples)
            } else {
                // Slice fallback samples for visible range
                let startIdx = Int(visibleStartProgress * Double(fallbackSamples.count))
                let endIdx = min(fallbackSamples.count, Int((visibleStartProgress + visibleDurationFraction) * Double(fallbackSamples.count)))
                if startIdx < endIdx {
                    samples = Array(fallbackSamples[startIdx..<endIdx])
                } else {
                    samples = fallbackSamples
                }
            }

            guard !samples.isEmpty else { return }

            let centerY = actualHeight / 2
            let padding: CGFloat = 4
            let maxAmplitude = (actualHeight / 2) - padding

            // Calculate playhead position within visible window
            let playheadProgress = (progress - visibleStartProgress) / visibleDurationFraction
            let playheadX = CGFloat(playheadProgress) * actualWidth

            // Theme colors (matching Edit mode exactly)
            let gridColor: Color = colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
            let waveformColor: Color = colorScheme == .dark ? .white.opacity(0.5) : Color(.systemGray)
            let playheadColor: Color = colorScheme == .dark ? .white : palette.accent

            // === 1. Draw Grid (time-based, matching Edit mode) ===

            // Get tick intervals based on visible duration
            let (majorInterval, minorInterval) = tickIntervals(visibleDuration: visibleDuration)

            // Draw minor vertical grid lines (lighter)
            let firstMinorTick = ceil(visibleStartTime / minorInterval) * minorInterval
            var minorTime = firstMinorTick
            while minorTime <= visibleEndTime {
                let x = timeToX(minorTime, visibleStartTime: visibleStartTime, visibleDuration: visibleDuration, width: actualWidth)
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: 0))
                gridLine.addLine(to: CGPoint(x: x, y: actualHeight))
                context.stroke(gridLine, with: .color(gridColor.opacity(0.5)), lineWidth: 0.5)
                minorTime += minorInterval
            }

            // Draw major vertical grid lines (more visible)
            let firstMajorTick = ceil(visibleStartTime / majorInterval) * majorInterval
            var majorTime = firstMajorTick
            while majorTime <= visibleEndTime {
                let x = timeToX(majorTime, visibleStartTime: visibleStartTime, visibleDuration: visibleDuration, width: actualWidth)
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: 0))
                gridLine.addLine(to: CGPoint(x: x, y: actualHeight))
                context.stroke(gridLine, with: .color(gridColor), lineWidth: 0.5)
                majorTime += majorInterval
            }

            // Horizontal grid lines (amplitude markers)
            let horizontalGridCount = 4
            let horizontalSpacing = actualHeight / CGFloat(horizontalGridCount)
            for i in 1..<horizontalGridCount {
                let y = CGFloat(i) * horizontalSpacing
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: 0, y: y))
                gridLine.addLine(to: CGPoint(x: actualWidth, y: y))
                context.stroke(gridLine, with: .color(gridColor), lineWidth: 0.5)
            }

            // Center line
            var centerLine = Path()
            centerLine.move(to: CGPoint(x: 0, y: centerY))
            centerLine.addLine(to: CGPoint(x: actualWidth, y: centerY))
            context.stroke(centerLine, with: .color(gridColor.opacity(1.5)), lineWidth: 0.5)

            // === 2. Draw Waveform (same as Edit mode, without selection coloring) ===

            let sampleCount = samples.count
            let xStep = actualWidth / CGFloat(sampleCount)

            // Cap line width: minimum 1, maximum 3 (same as Edit mode)
            let lineWidth = min(3, max(1, xStep * 0.7))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * xStep + xStep / 2

                // Sample is 0-1 normalized amplitude
                let amplitude = CGFloat(sample) * maxAmplitude

                // Draw symmetric around center
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

            // === 3. Draw Playhead (matching Edit mode style) ===
            if progress > 0.001 && progress < 0.999 {
                var playheadPath = Path()
                playheadPath.move(to: CGPoint(x: playheadX, y: 0))
                playheadPath.addLine(to: CGPoint(x: playheadX, y: actualHeight))
                context.stroke(playheadPath, with: .color(playheadColor), lineWidth: 2)
            }
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
