//
//  TimelineRulerView.swift
//  Sonidea
//
//  Apple Voice Memos-style minimal timeline ruler with thin ticks, small labels,
//  and a draggable playhead overlay. Uses Canvas for high-performance rendering.
//
//  Designed to be a drop-in replacement for TimeRulerBar (ProWaveformEditor)
//  and TimeRulerView (ZoomableWaveformEditor).
//

import SwiftUI
import UIKit

// MARK: - Helper Functions

/// Choose the smallest "nice" major tick spacing such that labels don't overlap.
/// Candidates are standard human-friendly intervals in seconds.
func chooseMajorStep(pixelsPerSecond: CGFloat, minLabelWidth: CGFloat = 65) -> TimeInterval {
    let candidates: [TimeInterval] = [
        0.01, 0.02, 0.05,
        0.1, 0.2, 0.25, 0.5,
        1, 2, 5, 10, 15, 30, 60,
        120, 300, 600
    ]
    for spacing in candidates {
        let labelSpacingPx = spacing * Double(pixelsPerSecond)
        if labelSpacingPx >= Double(minLabelWidth) {
            return spacing
        }
    }
    return candidates.last ?? 3600
}

/// Format a time label depending on the major step size.
///   - majorStep < 1s  -> decimals e.g. "0.350", "1.400"
///   - 1s <= step < 60 -> seconds with appropriate precision e.g. "5", "12.5"
///   - step >= 60      -> mm:ss e.g. "1:00", "2:30"
func formatTimeLabel(time: TimeInterval, step: TimeInterval) -> String {
    // Snap near-zero
    if abs(time) < 0.0005 { return "0" }

    if step >= 60 {
        // mm:ss format
        let totalSeconds = Int(time.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    if step >= 1 {
        // Seconds, optionally with one decimal
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let fraction = time.truncatingRemainder(dividingBy: 1)

        if minutes > 0 {
            if abs(fraction) > 0.05 {
                let tenths = Int((fraction * 10).rounded())
                return String(format: "%d:%02d.%d", minutes, seconds, tenths)
            }
            return String(format: "%d:%02d", minutes, seconds)
        }

        // Sub-minute: show just seconds
        if step <= 2 && abs(fraction) > 0.05 {
            let tenths = Int((fraction * 10).rounded())
            return String(format: "%d.%d", seconds, tenths)
        }
        return "\(seconds)"
    }

    // Sub-second steps (step < 1)
    let totalSeconds = Int(time)
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    let fraction = time.truncatingRemainder(dividingBy: 1)

    if step >= 0.1 {
        // Show 1-2 decimals
        if minutes > 0 {
            return String(format: "%d:%02d.%01d", minutes, seconds, Int((fraction * 10).rounded()))
        }
        if totalSeconds > 0 {
            return String(format: "%d.%01d", seconds, Int((fraction * 10).rounded()))
        }
        return String(format: ".%01d", Int((fraction * 10).rounded()))
    }

    // Very fine: show 2-3 decimals
    if minutes > 0 {
        return String(format: "%d:%02d.%02d", minutes, seconds, Int((fraction * 100).rounded()))
    }
    if totalSeconds > 0 {
        if step < 0.02 {
            return String(format: "%d.%03d", seconds, Int((fraction * 1000).rounded()))
        }
        return String(format: "%d.%02d", seconds, Int((fraction * 100).rounded()))
    }
    if step < 0.02 {
        return String(format: ".%03d", Int((fraction * 1000).rounded()))
    }
    return String(format: ".%02d", Int((fraction * 100).rounded()))
}

/// Compute the visible time range given scroll/zoom parameters.
func visibleTimeRange(
    scrollOffset: CGFloat,
    viewWidth: CGFloat,
    pixelsPerSecond: CGFloat,
    duration: TimeInterval
) -> ClosedRange<TimeInterval> {
    guard pixelsPerSecond > 0 else { return 0...max(0, duration) }
    let startTime = max(0, Double(scrollOffset / pixelsPerSecond))
    let endTime = min(duration, Double((scrollOffset + viewWidth) / pixelsPerSecond))
    return startTime...max(startTime, endTime)
}

// MARK: - TimelineRulerView (Apple Voice Memos style)

/// A minimal, high-performance timeline ruler drawn with Canvas.
/// Matches the Apple Voice Memos aesthetic: thin ticks, small labels, compact height.
///
/// Can be driven by either:
///   - A `WaveformTimeline` object (for ProWaveformEditor / DetailsWaveformView)
///   - A `TimelineState` struct (for ZoomableWaveformEditor)
///   - Raw parameters (duration, pixelsPerSecond, scrollOffset)
struct TimelineRulerView_Minimal: View {
    let duration: TimeInterval
    let palette: ThemePalette

    // One of these must be provided for coordinate mapping:
    var timeline: WaveformTimeline? = nil       // ProWaveformEditor / DetailsWaveformView
    var timelineState: TimelineState? = nil      // ZoomableWaveformEditor

    /// Height of the ruler (default 28pt — room for labels above ticks)
    var rulerHeight: CGFloat = 28

    /// Whether to draw faint extension lines downward (for grid alignment with waveform)
    var showsGridExtensions: Bool = false

    /// Total height when grid extensions are shown (waveform area height)
    var gridExtensionHeight: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width

            Canvas { context, size in
                guard duration > 0 else { return }

                // Determine visible time range and pixels per second
                let visibleStart: TimeInterval
                let visibleEnd: TimeInterval
                let pps: CGFloat  // pixels per second

                if let tl = timeline {
                    visibleStart = tl.visibleStartTime
                    visibleEnd = tl.visibleEndTime
                    let visDur = tl.visibleDuration
                    pps = visDur > 0 ? width / CGFloat(visDur) : 100
                } else if let ts = timelineState {
                    visibleStart = ts.visibleStartTime
                    visibleEnd = ts.visibleEndTime
                    let visDur = ts.visibleDuration
                    pps = visDur > 0 ? width / CGFloat(visDur) : 100
                } else {
                    // Fallback: show full duration
                    visibleStart = 0
                    visibleEnd = duration
                    pps = duration > 0 ? width / CGFloat(duration) : 100
                }

                let visibleDuration = visibleEnd - visibleStart
                guard visibleDuration > 0 else { return }

                // Choose tick spacing
                let majorStep = chooseMajorStep(pixelsPerSecond: pps, minLabelWidth: 65)
                let minorStep = majorStep / 5.0  // 5 minor ticks between majors

                // Tick dimensions (Apple Voice Memos style - thin and minimal)
                let majorTickHeight: CGFloat = 12
                let minorTickHeight: CGFloat = 6
                let majorTickWidth: CGFloat = 1.0
                let minorTickWidth: CGFloat = 0.5

                // Colors
                let majorTickColor = palette.textSecondary
                let minorTickColor = palette.textTertiary
                let labelColor = palette.textTertiary
                let gridExtColor = palette.textTertiary.opacity(0.12)

                // Label font
                let labelFont = Font.system(size: 9, weight: .regular, design: .monospaced)

                // Edge inset to prevent label clipping
                let edgeInset: CGFloat = 20

                // --- Draw minor ticks ---
                let firstMinor = ceil(visibleStart / minorStep) * minorStep
                var minorTime = firstMinor
                // Safety: limit iterations to prevent runaway loops at extreme zoom
                let maxMinorTicks = Int(visibleDuration / minorStep) + 2
                var minorCount = 0
                while minorTime <= visibleEnd && minorCount < maxMinorTicks + 10 {
                    // Skip if this falls on a major tick (avoid double-drawing)
                    let isMajor = majorStep > 0 && abs(minorTime.remainder(dividingBy: majorStep)) < (minorStep * 0.1)
                    if !isMajor {
                        let x = timeToX(minorTime, visibleStart: visibleStart, visibleDuration: visibleDuration, width: size.width)
                        if x >= -1 && x <= size.width + 1 {
                            var tickPath = Path()
                            tickPath.move(to: CGPoint(x: x, y: size.height - minorTickHeight))
                            tickPath.addLine(to: CGPoint(x: x, y: size.height))
                            context.stroke(tickPath, with: .color(minorTickColor), lineWidth: minorTickWidth)
                        }
                    }
                    minorTime += minorStep
                    minorCount += 1
                }

                // --- Draw major ticks + labels ---
                let firstMajor = ceil(visibleStart / majorStep) * majorStep
                var majorTime = firstMajor
                let maxMajorTicks = Int(visibleDuration / majorStep) + 2
                var majorCount = 0
                while majorTime <= visibleEnd && majorCount < maxMajorTicks + 10 {
                    let x = timeToX(majorTime, visibleStart: visibleStart, visibleDuration: visibleDuration, width: size.width)
                    if x >= -1 && x <= size.width + 1 {
                        // Major tick line
                        var tickPath = Path()
                        tickPath.move(to: CGPoint(x: x, y: size.height - majorTickHeight))
                        tickPath.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(tickPath, with: .color(majorTickColor), lineWidth: majorTickWidth)

                        // Grid extension line (very faint, extends into waveform)
                        if showsGridExtensions && gridExtensionHeight > 0 {
                            var gridLine = Path()
                            gridLine.move(to: CGPoint(x: x, y: size.height))
                            gridLine.addLine(to: CGPoint(x: x, y: size.height + gridExtensionHeight))
                            context.stroke(gridLine, with: .color(gridExtColor), lineWidth: 0.5)
                        }

                        // Label
                        let labelText = formatTimeLabel(time: majorTime, step: majorStep)
                        let text = Text(labelText)
                            .font(labelFont)
                            .foregroundColor(labelColor)

                        // Position label just above the major tick (with padding so text isn't clipped)
                        let labelY = size.height - majorTickHeight - 4

                        // Anchor adjustment to prevent clipping at edges
                        let anchor: UnitPoint
                        if x < edgeInset {
                            anchor = UnitPoint(x: 0, y: 1)  // leading-bottom
                        } else if x > size.width - edgeInset {
                            anchor = UnitPoint(x: 1, y: 1)  // trailing-bottom
                        } else {
                            anchor = UnitPoint(x: 0.5, y: 1)  // center-bottom
                        }

                        context.draw(text, at: CGPoint(x: x, y: labelY), anchor: anchor)
                    }
                    majorTime += majorStep
                    majorCount += 1
                }
            }
        }
        .frame(height: rulerHeight)
    }

    // MARK: - Coordinate helpers

    private func timeToX(_ time: TimeInterval, visibleStart: TimeInterval, visibleDuration: TimeInterval, width: CGFloat) -> CGFloat {
        let progress = (time - visibleStart) / visibleDuration
        return CGFloat(progress) * width
    }
}

// MARK: - PlayheadOverlayView

/// A vertical playhead line with a draggable triangular/diamond knob at the top.
/// Intended to be layered on top of the waveform + ruler in a ZStack.
///
/// Works with WaveformTimeline (ProWaveformEditor) or TimelineState (ZoomableWaveformEditor).
struct PlayheadOverlayView: View {
    @Binding var playheadPosition: TimeInterval
    let duration: TimeInterval
    let palette: ThemePalette
    let isPrecisionMode: Bool

    // One of these for coordinate mapping:
    var timeline: WaveformTimeline? = nil
    var timelineState: TimelineState? = nil

    /// Total height of the overlay (ruler + waveform)
    let totalHeight: CGFloat

    /// Height of just the ruler area (knob is positioned here)
    let rulerHeight: CGFloat

    /// Whether the playhead is draggable (false for pure playback views)
    var isDraggable: Bool = true

    /// Callback for seek during drag (optional, for views that need it)
    var onSeek: ((TimeInterval) -> Void)? = nil

    // Internal state
    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0

    // Haptics
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // Constants
    private let knobSize: CGFloat = 10
    private let lineWidth: CGFloat = 1.5
    private let hitTargetWidth: CGFloat = 44
    private let precisionMultiplier: CGFloat = 0.25

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let x = computeX(width: width)

            if x >= -hitTargetWidth / 2 && x <= width + hitTargetWidth / 2 {
                // Clamp knob center to keep it visible
                let clampedKnobX = min(max(x, knobSize / 2), width - knobSize / 2)

                ZStack {
                    // Invisible hit target for grabbing
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: hitTargetWidth, height: totalHeight)
                        .contentShape(Rectangle())

                    // Vertical line (full height)
                    Rectangle()
                        .fill(palette.accent)
                        .frame(width: lineWidth, height: totalHeight)

                    // Triangular knob at the top (in the ruler area)
                    PlayheadKnob(color: palette.accent, size: knobSize)
                        .offset(x: clampedKnobX - x, y: -totalHeight / 2 + rulerHeight - 2)
                        .shadow(color: Color.black.opacity(0.25), radius: 1.5, y: 0.5)
                }
                .frame(width: hitTargetWidth, height: totalHeight)
                .position(x: x, y: totalHeight / 2)
                .highPriorityGesture(isDraggable ? dragGesture(width: width) : nil)
                .zIndex(100)
            }
        }
        .frame(height: totalHeight)
        .allowsHitTesting(isDraggable)
    }

    // MARK: - Coordinate mapping

    private func computeX(width: CGFloat) -> CGFloat {
        if let tl = timeline {
            return tl.timeToX(playheadPosition, width: width)
        } else if let ts = timelineState {
            let progress = (playheadPosition - ts.visibleStartTime) / ts.visibleDuration
            return CGFloat(progress) * width
        } else {
            guard duration > 0 else { return 0 }
            return CGFloat(playheadPosition / duration) * width
        }
    }

    private func xToTime(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        if let tl = timeline {
            return tl.xToTime(x, width: width)
        } else if let ts = timelineState {
            let progress = Double(x / width)
            return ts.visibleStartTime + (progress * ts.visibleDuration)
        } else {
            guard duration > 0 && width > 0 else { return 0 }
            return Double(x / width) * duration
        }
    }

    private func currentVisibleDuration(width: CGFloat) -> TimeInterval {
        if let tl = timeline {
            return tl.visibleDuration
        } else if let ts = timelineState {
            return ts.visibleDuration
        } else {
            return duration
        }
    }

    // MARK: - Drag gesture

    private func dragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartTime = playheadPosition
                    lastHapticTime = playheadPosition
                    impactGenerator.impactOccurred(intensity: 0.5)
                }

                let deltaX = value.translation.width
                let effectiveMultiplier = isPrecisionMode ? precisionMultiplier : 1.0

                let visDur = currentVisibleDuration(width: width)
                let secondsPerPoint = visDur / Double(width)
                let timeDelta = Double(deltaX) * secondsPerPoint * Double(effectiveMultiplier)

                var newTime = dragStartTime + timeDelta
                newTime = max(0, min(newTime, duration))

                // Quantize (use timeline's quantization if available)
                if let tl = timeline {
                    newTime = tl.quantize(newTime)
                } else {
                    // Simple quantization based on visible duration
                    let step: TimeInterval
                    switch visDur {
                    case 0..<2:    step = 0.01
                    case 2..<10:   step = 0.05
                    case 10..<30:  step = 0.1
                    case 30..<120: step = 0.5
                    default:       step = 1.0
                    }
                    newTime = (newTime / step).rounded() * step
                }

                // Haptic at quantization boundaries
                let hapticStep: TimeInterval = 0.05
                if abs(newTime - lastHapticTime) >= hapticStep {
                    selectionGenerator.selectionChanged()
                    lastHapticTime = newTime
                }

                playheadPosition = newTime
                onSeek?(newTime)
            }
            .onEnded { _ in
                isDragging = false
                impactGenerator.impactOccurred(intensity: 0.3)
            }
    }
}

// MARK: - Playhead Knob Shape (downward-pointing triangle)

struct PlayheadKnob: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        Canvas { context, canvasSize in
            let w = canvasSize.width
            let h = canvasSize.height

            // Downward-pointing triangle
            var path = Path()
            path.move(to: CGPoint(x: w / 2, y: h))           // bottom center (point)
            path.addLine(to: CGPoint(x: 0, y: 0))             // top left
            path.addLine(to: CGPoint(x: w, y: 0))             // top right
            path.closeSubpath()

            context.fill(path, with: .color(color))
        }
        .frame(width: size, height: size * 0.8)
    }
}

// MARK: - Convenience Initializers for Common Use Cases

extension TimelineRulerView_Minimal {
    /// Initialize with a WaveformTimeline (for ProWaveformEditor and DetailsWaveformView)
    init(timeline: WaveformTimeline, palette: ThemePalette, rulerHeight: CGFloat = 22) {
        self.duration = timeline.duration
        self.palette = palette
        self.timeline = timeline
        self.timelineState = nil
        self.rulerHeight = rulerHeight
        self.showsGridExtensions = false
        self.gridExtensionHeight = 0
    }

    /// Initialize with a TimelineState (for ZoomableWaveformEditor)
    init(timelineState: TimelineState, palette: ThemePalette, rulerHeight: CGFloat = 22) {
        self.duration = timelineState.totalDuration
        self.palette = palette
        self.timeline = nil
        self.timelineState = timelineState
        self.rulerHeight = rulerHeight
        self.showsGridExtensions = false
        self.gridExtensionHeight = 0
    }
}

// MARK: - Preview

#Preview("Timeline Ruler - Various Zoom Levels") {
    VStack(spacing: 16) {
        // Simulated full-width view (2 min recording)
        let tl1 = WaveformTimeline(duration: 120)
        VStack(alignment: .leading, spacing: 2) {
            Text("Full view (120s)")
                .font(.caption2)
                .foregroundColor(.secondary)
            TimelineRulerView_Minimal(timeline: tl1, palette: .systemDark)
                .background(Color.black.opacity(0.05))
        }

        // Zoomed in (10s visible)
        let tl2: WaveformTimeline = {
            let t = WaveformTimeline(duration: 120)
            t.zoom(to: 12, centeredOn: 30)
            return t
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text("Zoomed 12x (~10s visible)")
                .font(.caption2)
                .foregroundColor(.secondary)
            TimelineRulerView_Minimal(timeline: tl2, palette: .systemDark)
                .background(Color.black.opacity(0.05))
        }

        // Very zoomed (sub-second)
        let tl3: WaveformTimeline = {
            let t = WaveformTimeline(duration: 120)
            t.zoom(to: 200, centeredOn: 5)
            return t
        }()
        VStack(alignment: .leading, spacing: 2) {
            Text("Zoomed 200x (sub-second)")
                .font(.caption2)
                .foregroundColor(.secondary)
            TimelineRulerView_Minimal(timeline: tl3, palette: .systemDark)
                .background(Color.black.opacity(0.05))
        }

        Spacer()
    }
    .padding()
    .background(Color(.systemBackground))
}
