//
//  ProWaveformEditor.swift
//  Sonidea
//
//  Voice Memos-style high-detail waveform editor with zoom, pan, and precision editing.
//  Uses LOD pyramid for efficient rendering at any zoom level.
//

import SwiftUI
import UIKit

// MARK: - Timeline Model

/// Represents the visible portion of the waveform timeline
@Observable
final class WaveformTimeline {
    /// Total duration of the audio
    let duration: TimeInterval

    /// Current zoom level (1.0 = full width, higher = more zoomed in)
    /// NOTE: No didSet - clamping happens at call sites to avoid recursion with @Observable
    var zoomScale: CGFloat = 1.0

    /// Start time of the visible window
    /// NOTE: No didSet - clamping happens at call sites to avoid recursion with @Observable
    var visibleStartTime: TimeInterval = 0

    /// Computed end time of the visible window
    var visibleEndTime: TimeInterval {
        visibleStartTime + visibleDuration
    }

    /// Duration currently visible based on zoom
    var visibleDuration: TimeInterval {
        duration / Double(zoomScale)
    }

    /// Seconds per point (pixel) at current zoom - useful for determining precision
    func secondsPerPoint(width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0.01 }
        return visibleDuration / Double(width)
    }

    /// Returns the appropriate quantization step based on current zoom level
    /// - High zoom (< 2s visible): 0.01s (10ms) steps
    /// - Medium zoom (2-20s visible): 0.1s steps
    /// - Low zoom (> 20s visible): 1.0s steps
    func quantizationStep() -> TimeInterval {
        switch visibleDuration {
        case 0..<2:    return 0.01  // Very zoomed in: 10ms precision
        case 2..<10:   return 0.05  // Zoomed in: 50ms precision
        case 10..<30:  return 0.1   // Medium zoom: 100ms precision
        case 30..<120: return 0.5   // Zoomed out: 500ms precision
        default:       return 1.0   // Very zoomed out: 1s precision
        }
    }

    /// Quantize a time value based on current zoom level
    func quantize(_ time: TimeInterval) -> TimeInterval {
        let step = quantizationStep()
        return (time / step).rounded() * step
    }

    static let minZoom: CGFloat = 1.0
    static let maxZoom: CGFloat = 10.0  // Cap at 1000% for mobile usability

    init(duration: TimeInterval) {
        self.duration = max(0.01, duration)
    }

    /// Zoom centered on a specific time
    /// Clamps zoom to valid range and prevents redundant updates
    func zoom(to newScale: CGFloat, centeredOn centerTime: TimeInterval) {
        // Clamp the new scale to valid range
        let clampedScale = max(Self.minZoom, min(newScale, Self.maxZoom))

        // Skip if no meaningful change (prevents redundant updates)
        guard abs(clampedScale - zoomScale) > 0.0001 else { return }

        let oldVisibleDuration = visibleDuration
        zoomScale = clampedScale
        let newVisibleDuration = visibleDuration

        // Adjust start time to keep center point stable
        let centerProgress = (centerTime - visibleStartTime) / oldVisibleDuration
        let newStartTime = centerTime - (centerProgress * newVisibleDuration)

        // Clamp visibleStartTime inline (no separate call to avoid re-entrancy)
        visibleStartTime = max(0, min(newStartTime, duration - newVisibleDuration))
    }

    /// Pan by a time delta
    func pan(by timeDelta: TimeInterval) {
        let newStartTime = visibleStartTime + timeDelta
        // Clamp inline
        visibleStartTime = max(0, min(newStartTime, duration - visibleDuration))
    }

    /// Ensure a time is visible
    func ensureVisible(_ time: TimeInterval, padding: TimeInterval = 0) {
        let paddedPadding = min(padding, visibleDuration * 0.1)
        var newStartTime = visibleStartTime

        if time < visibleStartTime + paddedPadding {
            newStartTime = max(0, time - paddedPadding)
        } else if time > visibleEndTime - paddedPadding {
            newStartTime = min(duration - visibleDuration, time - visibleDuration + paddedPadding)
        }

        // Only assign if changed
        if abs(newStartTime - visibleStartTime) > 0.0001 {
            visibleStartTime = newStartTime
        }
    }

    /// Reset to full view
    func reset() {
        zoomScale = Self.minZoom
        visibleStartTime = 0
    }

    // MARK: - Coordinate Conversion

    func timeToX(_ time: TimeInterval, width: CGFloat) -> CGFloat {
        let progress = (time - visibleStartTime) / visibleDuration
        return CGFloat(progress) * width
    }

    func xToTime(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        let progress = Double(x / width)
        return visibleStartTime + (progress * visibleDuration)
    }
}

// MARK: - Selectable Silence Range (for 2-step removal with toggle)

struct SelectableSilenceRange: Equatable, Identifiable {
    let id: UUID
    let range: SilenceRange
    var isSelected: Bool

    init(range: SilenceRange, isSelected: Bool = true) {
        self.id = UUID()
        self.range = range
        self.isSelected = isSelected
    }
}

// MARK: - Pro Waveform Editor

struct ProWaveformEditor: View {
    // Data
    let waveformData: WaveformData?
    let duration: TimeInterval

    // Bindings
    @Binding var selectionStart: TimeInterval
    @Binding var selectionEnd: TimeInterval
    @Binding var playheadPosition: TimeInterval
    @Binding var markers: [Marker]

    // Highlighted silence ranges (for 2-step removal flow)
    let silenceRanges: [SelectableSilenceRange]

    // Callbacks
    let onSilenceRangeTap: ((UUID) -> Void)?

    // State
    let currentTime: TimeInterval
    let isPlaying: Bool
    @Binding var isPrecisionMode: Bool

    // Callbacks
    let onSeek: (TimeInterval) -> Void
    let onMarkerTap: (Marker) -> Void

    // Environment
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    // Internal state
    @State private var timeline: WaveformTimeline
    @State private var initialPinchZoom: CGFloat = 1.0
    @State private var isPanning = false
    @State private var panStartTime: TimeInterval = 0

    // Handle tooltip state (moved to parent to render outside clipped area)
    @State private var leftHandleDragging = false
    @State private var rightHandleDragging = false
    @State private var leftHandleDragTime: TimeInterval = 0
    @State private var rightHandleDragTime: TimeInterval = 0

    // Constants
    private let waveformHeight: CGFloat = 240  // Increased ~20% (from 200) for more editing space
    private let timeRulerHeight: CGFloat = 36  // Reduced ~20% from 44
    private let handleWidth: CGFloat = 16
    private let handleHitArea: CGFloat = 44

    // Haptics
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    init(
        waveformData: WaveformData?,
        duration: TimeInterval,
        selectionStart: Binding<TimeInterval>,
        selectionEnd: Binding<TimeInterval>,
        playheadPosition: Binding<TimeInterval>,
        markers: Binding<[Marker]>,
        silenceRanges: [SelectableSilenceRange] = [],
        currentTime: TimeInterval,
        isPlaying: Bool,
        isPrecisionMode: Binding<Bool>,
        onSeek: @escaping (TimeInterval) -> Void,
        onMarkerTap: @escaping (Marker) -> Void,
        onSilenceRangeTap: ((UUID) -> Void)? = nil
    ) {
        self.waveformData = waveformData
        self.duration = duration
        self._selectionStart = selectionStart
        self._selectionEnd = selectionEnd
        self._playheadPosition = playheadPosition
        self._markers = markers
        self.silenceRanges = silenceRanges
        self.currentTime = currentTime
        self.isPlaying = isPlaying
        self._isPrecisionMode = isPrecisionMode
        self.onSeek = onSeek
        self.onMarkerTap = onMarkerTap
        self.onSilenceRangeTap = onSilenceRangeTap
        self._timeline = State(initialValue: WaveformTimeline(duration: duration))
    }

    var body: some View {
        VStack(spacing: 4) {  // Small gap between ruler and waveform
            // Time ruler at top - labels and ticks are fully visible
            TimeRulerBar(timeline: timeline, palette: palette)
                .frame(height: timeRulerHeight)

            // Main waveform area
            GeometryReader { geometry in
                let width = geometry.size.width

                ZStack(alignment: .leading) {
                    // Waveform bars
                    WaveformBarsView(
                        waveformData: waveformData,
                        timeline: timeline,
                        selectionStart: selectionStart,
                        selectionEnd: selectionEnd,
                        width: width,
                        height: waveformHeight,
                        palette: palette,
                        colorScheme: colorScheme
                    )

                    // Silence highlight overlay (red regions for 2-step removal)
                    if !silenceRanges.isEmpty {
                        SilenceHighlightOverlay(
                            silenceRanges: silenceRanges,
                            timeline: timeline,
                            width: width,
                            height: waveformHeight,
                            onTap: onSilenceRangeTap
                        )
                    }

                    // Selection overlay (uses same timeToX as handles)
                    SelectionRegionView(
                        selectionStart: selectionStart,
                        selectionEnd: selectionEnd,
                        timeline: timeline,
                        width: width,
                        height: waveformHeight,
                        palette: palette
                    )

                    // Markers
                    MarkersView(
                        markers: $markers,
                        timeline: timeline,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: width,
                        height: waveformHeight,
                        palette: palette,
                        onMarkerTap: onMarkerTap
                    )

                    // Playhead (centered white line)
                    PlayheadLineView(
                        playheadPosition: $playheadPosition,
                        timeline: timeline,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: width,
                        height: waveformHeight,
                        palette: palette
                    )

                    // Selection handles
                    SelectionHandleView(
                        time: $selectionStart,
                        otherTime: selectionEnd,
                        isLeft: true,
                        timeline: timeline,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: width,
                        height: waveformHeight,
                        palette: palette,
                        isDraggingExternal: $leftHandleDragging,
                        dragTimeExternal: $leftHandleDragTime
                    )

                    SelectionHandleView(
                        time: $selectionEnd,
                        otherTime: selectionStart,
                        isLeft: false,
                        timeline: timeline,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: width,
                        height: waveformHeight,
                        palette: palette,
                        isDraggingExternal: $rightHandleDragging,
                        dragTimeExternal: $rightHandleDragTime
                    )

                    // Marker flags overlay (rendered last so always visible above playhead)
                    MarkerFlagsOverlay(
                        markers: markers,
                        playheadPosition: playheadPosition,
                        timeline: timeline,
                        width: width,
                        palette: palette
                    )
                }
                .frame(height: waveformHeight)
                .contentShape(Rectangle())
                .gesture(panGesture(width: width))
                .gesture(tapGesture(width: width))
                .gesture(doubleTapGesture(width: width))
                .simultaneousGesture(zoomGesture)
            }
            .frame(height: waveformHeight)
            .background(palette.inputBackground.opacity(0.3))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Zoom indicator
            if timeline.zoomScale > 1.05 {
                ZoomInfoBar(
                    zoomScale: timeline.zoomScale,
                    visibleStart: timeline.visibleStartTime,
                    visibleEnd: timeline.visibleEndTime,
                    palette: palette,
                    onReset: { withAnimation(.easeInOut(duration: 0.2)) { timeline.reset() } }
                )
                .padding(.top, 8)
            }
        }
        // Tooltip overlay - rendered at VStack level so it can appear above the waveform
        .overlay(alignment: .top) {
            GeometryReader { geometry in
                handleTooltipOverlay(width: geometry.size.width)
            }
            .allowsHitTesting(false)
        }
        .onAppear {
            impactGenerator.prepare()
            selectionGenerator.prepare()
        }
        .onChange(of: currentTime) { _, newTime in
            if isPlaying && timeline.zoomScale > 1.0 {
                timeline.ensureVisible(newTime, padding: timeline.visibleDuration * 0.2)
            }
        }
    }

    // MARK: - Tooltip Overlay (outside clipped container)

    @ViewBuilder
    private func handleTooltipOverlay(width: CGFloat) -> some View {
        // Tooltip y position: just above the waveform area
        // VStack layout: ruler (36) + spacing (4) + waveform starts at 40
        // We want tooltip ~14pt above waveform, so y = 40 - 14 = 26
        let tooltipY: CGFloat = timeRulerHeight + 4 - 14

        ZStack {
            // Left handle tooltip
            if leftHandleDragging {
                handleTooltip(time: leftHandleDragTime, width: width)
                    .position(x: timeline.timeToX(leftHandleDragTime, width: width), y: tooltipY)
            }
            // Right handle tooltip
            if rightHandleDragging {
                handleTooltip(time: rightHandleDragTime, width: width)
                    .position(x: timeline.timeToX(rightHandleDragTime, width: width), y: tooltipY)
            }
        }
        .zIndex(1000)  // Ensure tooltips are above everything
    }

    private func handleTooltip(time: TimeInterval, width: CGFloat) -> some View {
        let tooltipWidth: CGFloat = 70
        // Clamp tooltip x position to stay on screen
        let handleX = timeline.timeToX(time, width: width)
        let clampedX = max(tooltipWidth / 2 + 8, min(handleX, width - tooltipWidth / 2 - 8))
        let offsetX = clampedX - handleX

        return Text(formatPreciseTime(time))
            .font(.system(size: 13, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.85))
            )
            .offset(x: offsetX)
    }

    private func formatPreciseTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                if initialPinchZoom == 1.0 {
                    initialPinchZoom = timeline.zoomScale
                    impactGenerator.impactOccurred(intensity: 0.3)
                }
                let centerTime = timeline.visibleStartTime + timeline.visibleDuration / 2
                timeline.zoom(to: initialPinchZoom * scale, centeredOn: centerTime)
            }
            .onEnded { _ in
                initialPinchZoom = 1.0
                impactGenerator.impactOccurred(intensity: 0.2)
            }
    }

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                if !isPanning {
                    isPanning = true
                    panStartTime = timeline.visibleStartTime
                }

                var deltaX = -value.translation.width
                if isPrecisionMode { deltaX *= 0.25 }

                let timeDelta = Double(deltaX) / Double(width) * timeline.visibleDuration
                let newStartTime = panStartTime + timeDelta

                // Clamp at call site to avoid any potential recursion issues
                // (safe even if @Observable implementation changes)
                let clampedStart = max(0, min(newStartTime, timeline.duration - timeline.visibleDuration))

                // Only assign if meaningfully different (prevents redundant updates)
                if abs(clampedStart - timeline.visibleStartTime) > 0.0001 {
                    timeline.visibleStartTime = clampedStart
                }
            }
            .onEnded { _ in
                isPanning = false
            }
    }

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                var tappedTime = timeline.xToTime(value.location.x, width: width)
                tappedTime = max(0, min(tappedTime, duration))
                // Use zoom-adaptive quantization
                tappedTime = timeline.quantize(tappedTime)
                playheadPosition = tappedTime
                impactGenerator.impactOccurred(intensity: 0.4)
            }
    }

    /// Double-tap to toggle zoom (zoomed out → 4x zoom, zoomed in → reset)
    private func doubleTapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                let tappedTime = timeline.xToTime(value.location.x, width: width)
                withAnimation(.easeInOut(duration: 0.25)) {
                    if timeline.zoomScale > 1.5 {
                        // Zoomed in → reset to full view
                        timeline.reset()
                    } else {
                        // Zoomed out → zoom to 4x centered on tap
                        timeline.zoom(to: 4.0, centeredOn: tappedTime)
                    }
                }
                impactGenerator.impactOccurred(intensity: 0.5)
            }
    }
}

// MARK: - Time Ruler Bar

struct TimeRulerBar: View {
    let timeline: WaveformTimeline
    let palette: ThemePalette

    // Layout constants (adjusted for 36px total height)
    private let labelAreaHeight: CGFloat = 18  // Top area for labels
    private let tickAreaHeight: CGFloat = 18   // Bottom area for ticks

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let visibleDuration = timeline.visibleDuration
                let (majorInterval, minorInterval) = tickIntervals(for: visibleDuration)

                // Draw minor ticks (shorter, no labels)
                drawTicks(context: context, size: size, interval: minorInterval, tickHeight: 5, showLabel: false)

                // Draw major ticks with labels
                drawTicks(context: context, size: size, interval: majorInterval, tickHeight: 10, showLabel: true)
            }
        }
        .background(palette.inputBackground.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8))  // Match waveform corners
    }

    private func tickIntervals(for duration: TimeInterval) -> (major: TimeInterval, minor: TimeInterval) {
        // Adaptive tick intervals based on visible duration (zoom level)
        // More granular at high zoom for DAW-like precision editing
        switch duration {
        case 0..<0.5:    return (0.1, 0.01)   // Very high zoom: major every 100ms, minor every 10ms
        case 0.5..<1:    return (0.2, 0.05)   // High zoom: major every 200ms, minor every 50ms
        case 1..<2:      return (0.5, 0.1)    // Zoomed in: major every 500ms, minor every 100ms
        case 2..<5:      return (1.0, 0.2)    // Medium-high: major every 1s, minor every 200ms
        case 5..<15:     return (2.0, 0.5)    // Medium: major every 2s, minor every 500ms
        case 15..<30:    return (5.0, 1.0)    // Medium-low: major every 5s, minor every 1s
        case 30..<60:    return (10.0, 2.0)   // Low: major every 10s, minor every 2s
        case 60..<180:   return (30.0, 5.0)   // Very low: major every 30s, minor every 5s
        case 180..<600:  return (60.0, 10.0)  // Ultra low: major every 1min, minor every 10s
        default:         return (120.0, 30.0) // Extreme: major every 2min, minor every 30s
        }
    }

    private func drawTicks(context: GraphicsContext, size: CGSize, interval: TimeInterval, tickHeight: CGFloat, showLabel: Bool) {
        let startTime = timeline.visibleStartTime
        let endTime = timeline.visibleEndTime

        let firstTick = ceil(startTime / interval) * interval

        // Inset to prevent labels from being clipped at edges
        let labelInset: CGFloat = 24

        var time = firstTick
        while time <= endTime {
            let progress = (time - startTime) / timeline.visibleDuration
            let x = CGFloat(progress) * size.width

            // Draw tick line from bottom of view
            let tickPath = Path { path in
                path.move(to: CGPoint(x: x, y: size.height - tickHeight))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            context.stroke(tickPath, with: .color(palette.textTertiary.opacity(0.6)), lineWidth: 1)

            // Draw label in the upper area (well above ticks)
            if showLabel {
                let labelText = formatTime(time)
                let text = Text(labelText)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(palette.textTertiary)
                // Position label centered in the top label area
                let labelY = (size.height - tickAreaHeight) / 2

                // Determine anchor based on position to prevent clipping at edges:
                // - Near left edge: use .leading anchor so label extends rightward
                // - Near right edge: use .trailing anchor so label extends leftward
                // - Middle: use .center anchor (default)
                let anchor: UnitPoint
                if x < labelInset {
                    anchor = .leading
                } else if x > size.width - labelInset {
                    anchor = .trailing
                } else {
                    anchor = .center
                }

                context.draw(text, at: CGPoint(x: x, y: labelY), anchor: anchor)
            }

            time += interval
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let totalSeconds = Int(time)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let fraction = time.truncatingRemainder(dividingBy: 1)

        // Show milliseconds when zoomed in enough to see 10ms ticks
        if timeline.visibleDuration < 1 {
            // Very high zoom: show centiseconds (0:00.05)
            let centiseconds = Int(fraction * 100)
            return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
        } else if timeline.visibleDuration < 5 {
            // High zoom: show tenths (0:00.5)
            let tenths = Int(fraction * 10)
            if tenths > 0 {
                return String(format: "%d:%02d.%d", minutes, seconds, tenths)
            }
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Waveform Bars View

struct WaveformBarsView: View {
    let waveformData: WaveformData?
    let timeline: WaveformTimeline
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette
    let colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            guard let data = waveformData else { return }

            // Use Canvas size.width which is always valid (never 0)
            // The passed `width` parameter can be 0 on first GeometryReader layout
            let actualWidth = size.width
            guard actualWidth > 0 else { return }

            // Get samples for visible range
            let targetBars = max(1, Int(actualWidth / 3)) // ~3pt per bar for dense look, minimum 1
            let samples = data.samples(
                from: timeline.visibleStartTime,
                to: timeline.visibleEndTime,
                targetCount: targetBars
            )

            guard !samples.isEmpty else { return }

            let barCount = samples.count
            let barSpacing: CGFloat = 1.5
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let barWidth = max(1.5, (actualWidth - totalSpacing) / CGFloat(barCount))

            // Colors
            let selectedColor = palette.accent
            let unselectedColor = colorScheme == .dark
                ? Color.white.opacity(0.4)
                : Color(.systemGray3)

            // Selection indices
            let visibleDuration = timeline.visibleDuration
            let selStartProgress = (selectionStart - timeline.visibleStartTime) / visibleDuration
            let selEndProgress = (selectionEnd - timeline.visibleStartTime) / visibleDuration
            let selStartIndex = Int(selStartProgress * Double(barCount))
            let selEndIndex = Int(selEndProgress * Double(barCount))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = max(2, CGFloat(sample) * size.height * 0.85)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: barWidth / 2).path(in: rect)

                let isInSelection = index >= selStartIndex && index <= selEndIndex
                let color = isInSelection ? selectedColor : unselectedColor

                context.fill(path, with: .color(color))
            }
        }
    }
}

// MARK: - Selection Region View

struct SelectionRegionView: View {
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let timeline: WaveformTimeline
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette

    var body: some View {
        // Use Canvas for pixel-perfect alignment with handles
        // Both use exactly timeline.timeToX() for coordinate mapping
        Canvas { context, size in
            // Use the SAME timeToX function as handles for exact alignment
            let startX = timeline.timeToX(selectionStart, width: size.width)
            let endX = timeline.timeToX(selectionEnd, width: size.width)
            let selectionWidth = max(0, endX - startX)

            guard selectionWidth > 0 else { return }

            // Selection background rectangle (with inset from top/bottom)
            let backgroundRect = CGRect(
                x: startX,
                y: 4,
                width: selectionWidth,
                height: size.height - 8
            )
            let backgroundPath = RoundedRectangle(cornerRadius: 4).path(in: backgroundRect)
            context.fill(backgroundPath, with: .color(palette.waveformSelectionBackground))

            // Top accent line
            let topLineRect = CGRect(x: startX, y: 4, width: selectionWidth, height: 1)
            context.fill(Path(topLineRect), with: .color(palette.accent.opacity(0.4)))

            // Bottom accent line
            let bottomLineRect = CGRect(x: startX, y: size.height - 5, width: selectionWidth, height: 1)
            context.fill(Path(bottomLineRect), with: .color(palette.accent.opacity(0.4)))
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Playhead Line View

struct PlayheadLineView: View {
    @Binding var playheadPosition: TimeInterval
    let timeline: WaveformTimeline
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette

    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0

    // Precision mode multiplier (0.25 = 4x finer control)
    private let precisionMultiplier: CGFloat = 0.25

    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        let x = timeline.timeToX(playheadPosition, width: width)

        if x >= -20 && x <= width + 20 {
            ZStack {
                // Main line
                Rectangle()
                    .fill(Color.white)
                    .frame(width: 2, height: height)

                // Top handle
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(y: -height / 2 + 8)
            }
            // Use .position() to center the playhead exactly at x, matching marker positioning
            .frame(width: 20, height: height)
            .position(x: x, y: height / 2)
            .highPriorityGesture(dragGesture)
            .zIndex(100)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartTime = playheadPosition
                    lastHapticTime = playheadPosition
                    impactGenerator.impactOccurred(intensity: 0.5)
                }

                // UNIFIED ANCHOR-BASED DRAG MAPPING
                // Always use translation from drag start, apply precision multiplier
                let deltaX = value.translation.width
                let effectiveMultiplier = isPrecisionMode ? precisionMultiplier : 1.0

                // Convert pixel delta to time delta: secondsPerPoint * dx * multiplier
                let secondsPerPoint = timeline.visibleDuration / Double(width)
                let timeDelta = Double(deltaX) * secondsPerPoint * Double(effectiveMultiplier)

                var newTime = dragStartTime + timeDelta

                // Clamp to valid range
                newTime = max(0, min(newTime, duration))

                // Use zoom-adaptive quantization
                newTime = timeline.quantize(newTime)

                // Haptic feedback at quantization step boundaries
                let step = timeline.quantizationStep()
                if abs(newTime - lastHapticTime) >= step {
                    selectionGenerator.selectionChanged()
                    lastHapticTime = newTime
                }

                playheadPosition = newTime
            }
            .onEnded { _ in
                isDragging = false
                impactGenerator.impactOccurred(intensity: 0.3)
            }
    }
}

// MARK: - Selection Handle View

struct SelectionHandleView: View {
    @Binding var time: TimeInterval
    let otherTime: TimeInterval
    let isLeft: Bool
    let timeline: WaveformTimeline
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette

    // External bindings for tooltip rendering in parent (outside clipped area)
    @Binding var isDraggingExternal: Bool
    @Binding var dragTimeExternal: TimeInterval

    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0
    @State private var last100msHapticTime: TimeInterval = 0  // For 0.1s boundary haptics

    private let handleWidth: CGFloat = 14
    private let hitAreaWidth: CGFloat = 44
    private let minGap: TimeInterval = 0.02

    // Precision mode multiplier (0.25 = 4x finer control) - SAME AS PLAYHEAD
    private let precisionMultiplier: CGFloat = 0.25

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private let boundaryGenerator = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        // Use the unified timeToX for consistent coordinate mapping
        let x = timeline.timeToX(time, width: width)

        if x >= -hitAreaWidth && x <= width + hitAreaWidth {
            // Visual handle only - tooltip is rendered in parent overlay
            SelectionHandleShape(isLeft: isLeft)
                .fill(palette.accent)
                .frame(width: handleWidth, height: height * 0.6)
                .frame(width: hitAreaWidth, height: height)
                .contentShape(Rectangle())
                .offset(x: x - hitAreaWidth / 2)
                .highPriorityGesture(dragGesture)
                .zIndex(isDragging ? 200 : 50)  // Bring to front while dragging
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    isDraggingExternal = true
                    dragStartTime = time
                    dragTimeExternal = time
                    lastHapticTime = time
                    last100msHapticTime = time
                    impactGenerator.impactOccurred(intensity: 0.6)
                    boundaryGenerator.prepare()
                }

                // UNIFIED ANCHOR-BASED DRAG MAPPING (same as PlayheadLineView)
                let deltaX = value.translation.width
                let effectiveMultiplier = isPrecisionMode ? precisionMultiplier : 1.0

                // Convert pixel delta to time delta: secondsPerPoint * dx * multiplier
                let secondsPerPoint = timeline.visibleDuration / Double(width)
                let timeDelta = Double(deltaX) * secondsPerPoint * Double(effectiveMultiplier)

                var newTime = dragStartTime + timeDelta

                // Clamp to prevent crossing handles
                if isLeft {
                    newTime = max(0, min(newTime, otherTime - minGap))
                } else {
                    newTime = max(otherTime + minGap, min(newTime, duration))
                }

                // Use zoom-adaptive quantization
                let step = timeline.quantizationStep()
                newTime = (newTime / step).rounded() * step

                // Re-clamp after quantization (quantization might push past limits)
                if isLeft {
                    newTime = max(0, min(newTime, otherTime - minGap))
                } else {
                    newTime = max(otherTime + minGap, min(newTime, duration))
                }

                // Haptic at quantization step boundaries
                if abs(newTime - lastHapticTime) >= step {
                    selectionGenerator.selectionChanged()
                    lastHapticTime = newTime
                }

                // Stronger haptic when crossing 0.1s boundaries
                let oldTenths = Int(last100msHapticTime * 10)
                let newTenths = Int(newTime * 10)
                if oldTenths != newTenths {
                    boundaryGenerator.impactOccurred(intensity: 0.5)
                    last100msHapticTime = newTime
                }

                time = newTime
                dragTimeExternal = newTime
            }
            .onEnded { _ in
                isDragging = false
                isDraggingExternal = false
                impactGenerator.impactOccurred(intensity: 0.3)
            }
    }
}

// MARK: - Selection Handle Shape

struct SelectionHandleShape: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 4

        if isLeft {
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addArc(center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addArc(center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                       radius: cornerRadius, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Markers View

struct MarkersView: View {
    @Binding var markers: [Marker]
    let timeline: WaveformTimeline
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette
    let onMarkerTap: (Marker) -> Void

    var body: some View {
        ForEach(markers) { marker in
            MarkerItemView(
                marker: marker,
                markers: $markers,
                timeline: timeline,
                duration: duration,
                isPrecisionMode: isPrecisionMode,
                width: width,
                height: height,
                palette: palette,
                onMarkerTap: onMarkerTap
            )
        }
    }
}

struct MarkerItemView: View {
    let marker: Marker
    @Binding var markers: [Marker]
    let timeline: WaveformTimeline
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette
    let onMarkerTap: (Marker) -> Void

    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var currentDragTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0

    private let hitWidth: CGFloat = 32

    // Precision mode multiplier (0.25 = 4x finer control) - SAME AS PLAYHEAD/HANDLES
    private let precisionMultiplier: CGFloat = 0.25

    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        let displayTime = isDragging ? currentDragTime : marker.time
        let x = timeline.timeToX(displayTime, width: width)

        if x >= -hitWidth && x <= width + hitWidth {
            // Only render the vertical line here (flag is rendered in MarkerFlagsOverlay)
            Rectangle()
                .fill(isDragging ? palette.accent : Color.orange.opacity(0.7))
                .frame(width: isDragging ? 2.5 : 1.5, height: height)
                .scaleEffect(x: isDragging ? 1.2 : 1.0, y: 1.0)
                .animation(.easeInOut(duration: 0.15), value: isDragging)
                .position(x: x, y: height / 2)
                .frame(width: hitWidth)
                .contentShape(Rectangle().size(width: hitWidth, height: height))
                .onTapGesture {
                    if !isDragging {
                        onMarkerTap(marker)
                        impactGenerator.impactOccurred(intensity: 0.5)
                    }
                }
                .gesture(markerDragGesture)
                .contextMenu {
                    Button(role: .destructive) {
                        markers.removeAll { $0.id == marker.id }
                    } label: {
                        Label("Delete Marker", systemImage: "trash")
                    }
                }
        }
    }

    private var markerDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.15)
            .sequenced(before: DragGesture(minimumDistance: 1))
            .onChanged { value in
                switch value {
                case .first(true):
                    isDragging = true
                    dragStartTime = marker.time
                    currentDragTime = marker.time
                    lastHapticTime = marker.time
                    impactGenerator.impactOccurred(intensity: 0.6)

                case .second(true, let drag):
                    guard let drag = drag else { return }

                    // UNIFIED ANCHOR-BASED DRAG MAPPING (same as PlayheadLineView/SelectionHandleView)
                    let deltaX = drag.translation.width
                    let effectiveMultiplier = isPrecisionMode ? precisionMultiplier : 1.0

                    // Convert pixel delta to time delta: secondsPerPoint * dx * multiplier
                    let secondsPerPoint = timeline.visibleDuration / Double(width)
                    let timeDelta = Double(deltaX) * secondsPerPoint * Double(effectiveMultiplier)

                    var newTime = dragStartTime + timeDelta

                    // Clamp to valid range
                    newTime = max(0, min(newTime, duration))

                    // Use zoom-adaptive quantization
                    newTime = timeline.quantize(newTime)

                    // Haptic at quantization step boundaries
                    let step = timeline.quantizationStep()
                    if abs(newTime - lastHapticTime) >= step {
                        selectionGenerator.selectionChanged()
                        lastHapticTime = newTime
                    }

                    currentDragTime = newTime

                default:
                    break
                }
            }
            .onEnded { _ in
                if let index = markers.firstIndex(where: { $0.id == marker.id }) {
                    markers[index].time = currentDragTime
                }
                isDragging = false
                impactGenerator.impactOccurred(intensity: 0.4)
            }
    }
}

// MARK: - Silence Highlight Overlay (red regions for 2-step removal)

struct SilenceHighlightOverlay: View {
    let silenceRanges: [SelectableSilenceRange]
    let timeline: WaveformTimeline
    let width: CGFloat
    let height: CGFloat
    let onTap: ((UUID) -> Void)?

    var body: some View {
        ForEach(silenceRanges) { selectableRange in
            let range = selectableRange.range
            let startX = timeline.timeToX(range.start, width: width)
            let endX = timeline.timeToX(range.end, width: width)
            let rangeWidth = endX - startX

            // Only render if visible
            if endX >= 0 && startX <= width && rangeWidth > 0 {
                Rectangle()
                    .fill(selectableRange.isSelected ? Color.red.opacity(0.4) : Color.gray.opacity(0.25))
                    .frame(width: max(2, rangeWidth), height: height)
                    .overlay(
                        // Show strikethrough for deselected ranges
                        !selectableRange.isSelected ?
                        Rectangle()
                            .fill(Color.gray.opacity(0.4))
                            .frame(height: 2)
                        : nil
                    )
                    // CRITICAL: contentShape MUST be before position() to set hit area correctly
                    // After position(), the view's frame becomes the full container width
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onTap?(selectableRange.id)
                    }
                    .position(x: startX + rangeWidth / 2, y: height / 2)
            }
        }
    }
}

// MARK: - Marker Flags Overlay (rendered above playhead for visibility)

struct MarkerFlagsOverlay: View {
    let markers: [Marker]
    let playheadPosition: TimeInterval
    let timeline: WaveformTimeline
    let width: CGFloat
    let palette: ThemePalette

    var body: some View {
        ForEach(markers) { marker in
            let x = timeline.timeToX(marker.time, width: width)

            if x >= -20 && x <= width + 20 {
                // Check if marker is very close to playhead (within 8px)
                let playheadX = timeline.timeToX(playheadPosition, width: width)
                let isNearPlayhead = abs(x - playheadX) < 8

                // Flag badge at top - offset slightly if near playhead
                ZStack {
                    // Background pill for better visibility
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.orange)
                        .frame(width: 18, height: 14)

                    // Flag icon
                    Image(systemName: "flag.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                }
                .position(x: x + (isNearPlayhead ? 10 : 0), y: 7)
            }
        }
    }
}

// MARK: - Zoom Info Bar

struct ZoomInfoBar: View {
    let zoomScale: CGFloat
    let visibleStart: TimeInterval
    let visibleEnd: TimeInterval
    let palette: ThemePalette
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundColor(palette.textSecondary)

            Text("\(Int(zoomScale * 100))%")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(palette.textSecondary)

            Text("•")
                .foregroundColor(palette.textTertiary)

            Text("\(formatTime(visibleStart)) – \(formatTime(visibleEnd))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(palette.textTertiary)

            Spacer()

            Button("Reset", action: onReset)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.accent)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(palette.inputBackground.opacity(0.8))
        .cornerRadius(8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ProWaveformEditor(
            waveformData: nil,
            duration: 120,
            selectionStart: .constant(20),
            selectionEnd: .constant(80),
            playheadPosition: .constant(50),
            markers: .constant([Marker(time: 30, label: "Intro"), Marker(time: 70, label: "Chorus")]),
            currentTime: 50,
            isPlaying: false,
            isPrecisionMode: .constant(false),
            onSeek: { _ in },
            onMarkerTap: { _ in }
        )
        .padding()
    }
    .background(Color(.systemBackground))
}
