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
    /// Total duration of the audio (mutable to allow sync with playback engine)
    var duration: TimeInterval

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
        duration / Double(max(zoomScale, 1.0))
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
    static let maxZoom: CGFloat = 200.0  // Cap at 20,000% for detailed editing

    // MARK: - Grid/Tick Intervals (shared between ruler and waveform grid)

    /// Returns tick intervals for the current visible duration
    /// This is the single source of truth for both time ruler and waveform grid alignment
    func tickIntervals() -> (major: TimeInterval, minor: TimeInterval) {
        let duration = visibleDuration
        switch duration {
        case 0..<0.05:   return (0.01, 0.002)   // Extreme zoom: major every 10ms, minor every 2ms
        case 0.05..<0.2: return (0.05, 0.01)    // Ultra high zoom: major every 50ms, minor every 10ms
        case 0.2..<0.5:  return (0.1, 0.02)     // Very high zoom: major every 100ms, minor every 20ms
        case 0.5..<1:    return (0.2, 0.05)     // High zoom: major every 200ms, minor every 50ms
        case 1..<2:      return (0.5, 0.1)      // Zoomed in: major every 500ms, minor every 100ms
        case 2..<5:      return (1.0, 0.2)      // Medium-high: major every 1s, minor every 200ms
        case 5..<15:     return (2.0, 0.5)      // Medium: major every 2s, minor every 500ms
        case 15..<30:    return (5.0, 1.0)      // Medium-low: major every 5s, minor every 1s
        case 30..<60:    return (10.0, 2.0)     // Low: major every 10s, minor every 2s
        case 60..<180:   return (30.0, 5.0)     // Very low: major every 30s, minor every 5s
        case 180..<600:  return (60.0, 10.0)    // Ultra low: major every 1min, minor every 10s
        default:         return (120.0, 30.0)   // Extreme: major every 2min, minor every 30s
        }
    }

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

    /// Ensure a time is visible (scrolls only when near edges)
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

    /// Center the visible window on a specific time (follow-track mode)
    /// Keeps the playhead in the center of the screen during playback
    func centerOnTime(_ time: TimeInterval) {
        // Calculate start time that puts the given time at center
        let halfVisible = visibleDuration / 2
        var newStartTime = time - halfVisible

        // Clamp to valid range
        newStartTime = max(0, min(newStartTime, duration - visibleDuration))

        // Only assign if changed (prevents excessive updates)
        if abs(newStartTime - visibleStartTime) > 0.001 {
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

    /// When true, dragging on the waveform body selects a region (sets IN/OUT)
    /// instead of panning. Panning is still available via pinch-zoom repositioning.
    let isEditing: Bool

    // Callbacks
    let onSeek: (TimeInterval) -> Void
    let onMarkerTap: (Marker) -> Void
    var onResetAll: (() -> Void)?  // Called when user requests full reset (zoom + height)

    // Environment
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    // Internal state
    @State private var timeline: WaveformTimeline
    @State private var initialPinchZoom: CGFloat? = nil
    @State private var isPanning = false
    @State private var panStartTime: TimeInterval = 0

    // Handle tooltip state (moved to parent to render outside clipped area)
    @State private var leftHandleDragging = false
    @State private var rightHandleDragging = false
    @State private var leftHandleDragTime: TimeInterval = 0
    @State private var rightHandleDragTime: TimeInterval = 0

    // Region selection state (hold-to-select in edit mode)
    @State private var isRegionSelecting = false
    @State private var regionSelectAnchorTime: TimeInterval = 0

    // Pinch-zoom tracking: suppresses edit drag while pinching
    @State private var isPinching = false
    @GestureState private var pinchActive = false

    // Unified edit-mode drag: decides pan vs region-select based on hold duration
    enum EditDragMode { case undecided, panning, selecting }
    @State private var editDragMode: EditDragMode = .undecided
    @State private var editDragStartDate: Date = .distantPast
    @State private var editDragStartTranslation: CGSize = .zero

    // Height (configurable)
    let waveformHeight: CGFloat

    /// Whether there is a meaningful selection (not zero-length)
    private var hasActiveSelection: Bool {
        selectionEnd - selectionStart > 0.02
    }

    // Constants
    private let timeRulerHeight: CGFloat = 28  // Apple Voice Memos-style compact ruler
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
        isEditing: Bool = false,
        waveformHeight: CGFloat = 240,
        onSeek: @escaping (TimeInterval) -> Void,
        onMarkerTap: @escaping (Marker) -> Void,
        onSilenceRangeTap: ((UUID) -> Void)? = nil,
        onResetAll: (() -> Void)? = nil
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
        self.isEditing = isEditing
        self.waveformHeight = waveformHeight
        self.onSeek = onSeek
        self.onMarkerTap = onMarkerTap
        self.onSilenceRangeTap = onSilenceRangeTap
        self.onResetAll = onResetAll
        self._timeline = State(initialValue: WaveformTimeline(duration: duration))
    }

    var body: some View {
        VStack(spacing: 0) {  // No gap - ruler blends naturally into waveform
            // Apple Voice Memos-style minimal time ruler at top
            TimelineRulerView_Minimal(
                timeline: timeline,
                palette: palette,
                rulerHeight: timeRulerHeight
            )

            // Main waveform area
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = waveformHeight  // Use known height, not geometry (avoids feedback loop during resize)

                ZStack(alignment: .leading) {
                    // Waveform bars
                    WaveformBarsView(
                        waveformData: waveformData,
                        timeline: timeline,
                        selectionStart: selectionStart,
                        selectionEnd: selectionEnd,
                        width: width,
                        height: height,
                        palette: palette,
                        colorScheme: colorScheme
                    )

                    // Silence highlight overlay (red regions for 2-step removal)
                    if !silenceRanges.isEmpty {
                        SilenceHighlightOverlay(
                            silenceRanges: silenceRanges,
                            timeline: timeline,
                            width: width,
                            height: height,
                            onTap: onSilenceRangeTap
                        )
                    }

                    // Selection overlay and handles (only shown when there is an active selection)
                    if hasActiveSelection || isRegionSelecting {
                        SelectionRegionView(
                            selectionStart: selectionStart,
                            selectionEnd: selectionEnd,
                            timeline: timeline,
                            width: width,
                            height: height,
                            palette: palette
                        )
                    }

                    // Markers
                    MarkersView(
                        markers: $markers,
                        timeline: timeline,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: width,
                        height: height,
                        palette: palette,
                        onMarkerTap: onMarkerTap
                    )

                    // NOTE: Playhead moved to overlay outside clipped container to prevent clipping at edges

                    // Selection handles (only shown when there is an active selection)
                    if hasActiveSelection || isRegionSelecting {
                        SelectionHandleView(
                            time: $selectionStart,
                            otherTime: selectionEnd,
                            isLeft: true,
                            timeline: timeline,
                            duration: duration,
                            isPrecisionMode: isPrecisionMode,
                            width: width,
                            height: height,
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
                            height: height,
                            palette: palette,
                            isDraggingExternal: $rightHandleDragging,
                            dragTimeExternal: $rightHandleDragTime
                        )
                    }

                    // Marker flags overlay (rendered last so always visible above playhead)
                    MarkerFlagsOverlay(
                        markers: markers,
                        playheadPosition: playheadPosition,
                        timeline: timeline,
                        width: width,
                        palette: palette
                    )
                }
                .contentShape(Rectangle())
                .accessibilityLabel("Waveform editor")
                .accessibilityHint("Double tap to play or pause. Drag to scrub.")
                .gesture(isEditing
                    ? AnyGesture(editModeDragGesture(width: width).map { _ in })
                    : AnyGesture(panGesture(width: width).map { _ in })
                )
                .gesture(tapGesture(width: width))
                .gesture(doubleTapGesture(width: width))
                .simultaneousGesture(zoomGesture)
            }
            .frame(height: waveformHeight)
            .background(palette.waveformBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // Playhead overlay - rendered outside clipped container to prevent edge clipping
            .overlay {
                GeometryReader { overlayGeometry in
                    PlayheadLineView(
                        playheadPosition: $playheadPosition,
                        timeline: timeline,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: overlayGeometry.size.width,
                        height: waveformHeight,
                        palette: palette
                    )
                    .transaction { t in t.disablesAnimations = true }
                }
            }

            // Zoom indicator (shows when zoomed only - NOT based on height to avoid jitter during resize)
            if timeline.zoomScale > 1.05 {
                ZoomInfoBar(
                    zoomScale: timeline.zoomScale,
                    visibleStart: timeline.visibleStartTime,
                    visibleEnd: timeline.visibleEndTime,
                    palette: palette,
                    onReset: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timeline.reset()
                            onResetAll?()  // Also reset height if callback provided
                        }
                    }
                )
                .padding(.top, 8)
            }
        }
        .animation(nil, value: waveformHeight)
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
            // Sync timeline duration on appear (in case @State wasn't recreated properly)
            if abs(timeline.duration - duration) > 0.001 {
                timeline.duration = max(0.01, duration)
            }
        }
        .onChange(of: currentTime) { _, newTime in
            // Sync playhead position with playback time when playing
            // Apply audio latency compensation - AVAudioPlayer.currentTime is ahead of actual audio output
            // Typical iOS audio output latency is 20-80ms; we use 50ms as a reasonable default
            let audioLatencyCompensation: TimeInterval = 0.05
            let compensatedTime = isPlaying ? max(0, newTime - audioLatencyCompensation) : newTime

            if isPlaying {
                playheadPosition = compensatedTime
            }
            // Follow-track: center playhead on screen when zoomed and playing
            if isPlaying && timeline.zoomScale > 1.0 {
                timeline.centerOnTime(compensatedTime)
            }
        }
        .onChange(of: duration) { _, newDuration in
            // Sync timeline duration with playback duration
            // This ensures playhead position calculation uses correct duration
            if abs(timeline.duration - newDuration) > 0.001 {
                timeline.duration = max(0.01, newDuration)
            }
        }
        .onChange(of: pinchActive) { _, active in
            // @GestureState resets to false when the pinch gesture ends.
            // Use this as a safety net to clear isPinching in case .onEnded
            // was not called (e.g., gesture cancelled by the system).
            if !active && isPinching {
                isPinching = false
                // Also clean up any stale edit drag state
                if editDragMode != .undecided {
                    if editDragMode == .selecting {
                        isRegionSelecting = false
                    }
                    isPanning = false
                    editDragMode = .undecided
                    editDragStartDate = .distantPast
                }
            }
        }
    }

    // MARK: - Tooltip Overlay (outside clipped container)

    @ViewBuilder
    private func handleTooltipOverlay(width: CGFloat) -> some View {
        // Tooltip y position: just above the waveform area
        // VStack layout: ruler (22) + spacing (0) + waveform starts at 22
        // We want tooltip ~14pt above waveform, so y = 22 - 14 = 8
        let tooltipY: CGFloat = timeRulerHeight - 14

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
            .updating($pinchActive) { _, state, _ in
                state = true
            }
            .onChanged { scale in
                // Mark pinching immediately so editModeDragGesture is suppressed
                if !isPinching {
                    isPinching = true
                    // Cancel any in-progress edit drag that may have started
                    // before the pinch was recognized
                    if editDragMode != .undecided {
                        // Reset selection if it was being created during this touch
                        if editDragMode == .selecting {
                            isRegionSelecting = false
                            if selectionEnd - selectionStart < 0.02 {
                                selectionStart = 0
                                selectionEnd = 0
                            }
                        }
                        isPanning = false
                        editDragMode = .undecided
                        editDragStartDate = .distantPast
                    }
                }

                if initialPinchZoom == nil {
                    initialPinchZoom = timeline.zoomScale
                    impactGenerator.impactOccurred(intensity: 0.3)
                }
                let centerTime = timeline.visibleStartTime + timeline.visibleDuration / 2
                timeline.zoom(to: (initialPinchZoom ?? timeline.zoomScale) * scale, centeredOn: centerTime)
            }
            .onEnded { _ in
                initialPinchZoom = nil
                isPinching = false
                impactGenerator.impactOccurred(intensity: 0.2)
            }
    }

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                // Suppress pan while pinch-zooming
                if isPinching || pinchActive { return }

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

    /// Unified edit-mode drag gesture:
    /// - Tap (lift quickly, minimal movement) → sets playhead
    /// - Quick swipe (moved >15pt before 0.4s) → pans the waveform
    /// - Hold in place for 0.4s then drag → selects IN/OUT region
    ///
    /// Uses minimumDistance: 0 so the hold timer starts immediately on touch.
    /// Time check is evaluated before movement check so that a hold always
    /// wins, even if the user moves quickly after the 0.4s threshold.
    private func editModeDragGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // --- Pinch guard: suppress ALL edit drag logic while pinching ---
                // When 2 fingers are down, the drag gesture fires for individual
                // touch points before MagnificationGesture is recognised. We must
                // ignore those spurious single-finger events.
                if isPinching || pinchActive {
                    return
                }

                // First call — record start time immediately on touch
                if editDragMode == .undecided && editDragStartDate == .distantPast {
                    editDragStartDate = Date()
                    editDragStartTranslation = value.translation
                    panStartTime = timeline.visibleStartTime
                }

                let elapsed = Date().timeIntervalSince(editDragStartDate)
                let movedX = abs(value.translation.width - editDragStartTranslation.width)
                let movedY = abs(value.translation.height - editDragStartTranslation.height)
                let totalMoved = sqrt(movedX * movedX + movedY * movedY)

                // Decide mode if still undecided
                if editDragMode == .undecided {
                    // Time check FIRST: held >= 0.4s → region select (always wins over movement)
                    if elapsed >= 0.4 {
                        editDragMode = .selecting
                        impactGenerator.impactOccurred(intensity: 0.5)
                        var anchor = timeline.xToTime(value.startLocation.x, width: width)
                        anchor = max(0, min(anchor, duration))
                        anchor = timeline.quantize(anchor)
                        regionSelectAnchorTime = anchor
                        isRegionSelecting = true
                        // Fall through to selecting handler below
                    } else if totalMoved > 15 {
                        // Moved enough before hold threshold → pan mode
                        editDragMode = .panning
                        isPanning = true
                        // Fall through to panning handler below
                    } else {
                        return  // Still undecided — wait
                    }
                }

                // --- Panning ---
                if editDragMode == .panning {
                    var deltaX = -value.translation.width
                    if isPrecisionMode { deltaX *= 0.25 }
                    let timeDelta = Double(deltaX) / Double(width) * timeline.visibleDuration
                    let newStartTime = panStartTime + timeDelta
                    let clampedStart = max(0, min(newStartTime, timeline.duration - timeline.visibleDuration))
                    if abs(clampedStart - timeline.visibleStartTime) > 0.0001 {
                        timeline.visibleStartTime = clampedStart
                    }
                }

                // --- Region selecting ---
                if editDragMode == .selecting {
                    let x = value.location.x

                    // Auto-scroll near edges
                    let edgeZone: CGFloat = 30
                    let scrollSpeed = timeline.visibleDuration * 0.03
                    if x < edgeZone && timeline.visibleStartTime > 0 {
                        let factor = Double(1 - x / edgeZone)
                        timeline.pan(by: -scrollSpeed * factor)
                    } else if x > width - edgeZone && timeline.visibleEndTime < duration {
                        let factor = Double(1 - (width - x) / edgeZone)
                        timeline.pan(by: scrollSpeed * factor)
                    }

                    var current = timeline.xToTime(x, width: width)
                    current = max(0, min(current, duration))
                    current = timeline.quantize(current)

                    selectionStart = min(regionSelectAnchorTime, current)
                    selectionEnd = max(regionSelectAnchorTime, current)
                }
            }
            .onEnded { value in
                // If the drag ended because of a pinch, just clean up silently
                if isPinching || pinchActive {
                    isPanning = false
                    editDragMode = .undecided
                    editDragStartDate = .distantPast
                    return
                }

                if editDragMode == .selecting {
                    isRegionSelecting = false
                    // If the selection is too small (accidental tap-drag), clear it
                    if selectionEnd - selectionStart < 0.02 {
                        selectionStart = 0
                        selectionEnd = 0
                    }
                    impactGenerator.impactOccurred(intensity: 0.3)
                } else if editDragMode == .undecided {
                    // Finger lifted before mode was decided — treat as a tap (set playhead)
                    var tappedTime = timeline.xToTime(value.startLocation.x, width: width)
                    tappedTime = max(0, min(tappedTime, duration))
                    tappedTime = timeline.quantize(tappedTime)
                    playheadPosition = tappedTime
                    // Clear any active selection on tap
                    selectionStart = 0
                    selectionEnd = 0
                    onSeek(tappedTime)
                    impactGenerator.impactOccurred(intensity: 0.4)
                }
                isPanning = false
                editDragMode = .undecided
                editDragStartDate = .distantPast
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
                // Clear any active selection when tapping to set playhead
                selectionStart = 0
                selectionEnd = 0
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

// MARK: - Time Ruler Bar (DEPRECATED - replaced by TimelineRulerView_Minimal)
// The old TimeRulerBar has been replaced by TimelineRulerView_Minimal in TimelineRulerView.swift
// for a sleeker Apple Voice Memos-style appearance.

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
    var showsSelectionHighlight: Bool = true  // Set to false for Details (non-edit) mode
    var showsHorizontalGrid: Bool = true      // Set to false for Details (cleaner look)

    /// Cached grid line x-positions to avoid recalculating when visible range hasn't changed
    private struct GridCache {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let width: CGFloat
        let height: CGFloat
        let majorXPositions: [CGFloat]
        let minorXPositions: [CGFloat]
        let horizontalYPositions: [CGFloat]
        let centerY: CGFloat
    }

    /// Build or reuse cached grid positions. Only recalculates when visible range or size changes.
    private func gridPositions(actualWidth: CGFloat, height: CGFloat) -> GridCache {
        let startTime = timeline.visibleStartTime
        let endTime = timeline.visibleEndTime
        let (majorInterval, minorInterval) = timeline.tickIntervals()

        // Minor vertical grid positions
        var minorXs: [CGFloat] = []
        let firstMinorTick = ceil(startTime / minorInterval) * minorInterval
        var minorTime = firstMinorTick
        while minorTime <= endTime {
            minorXs.append(timeline.timeToX(minorTime, width: actualWidth))
            minorTime += minorInterval
        }

        // Major vertical grid positions
        var majorXs: [CGFloat] = []
        let firstMajorTick = ceil(startTime / majorInterval) * majorInterval
        var majorTime = firstMajorTick
        while majorTime <= endTime {
            majorXs.append(timeline.timeToX(majorTime, width: actualWidth))
            majorTime += majorInterval
        }

        // Horizontal grid positions
        var hYs: [CGFloat] = []
        if showsHorizontalGrid {
            let horizontalGridCount = 4
            let horizontalSpacing = height / CGFloat(horizontalGridCount)
            for i in 1..<horizontalGridCount {
                hYs.append(CGFloat(i) * horizontalSpacing)
            }
        }

        return GridCache(
            startTime: startTime, endTime: endTime,
            width: actualWidth, height: height,
            majorXPositions: majorXs, minorXPositions: minorXs,
            horizontalYPositions: hYs, centerY: height / 2
        )
    }

    var body: some View {
        Canvas { context, size in
            guard let data = waveformData else { return }

            let actualWidth = size.width
            guard actualWidth > 0 else { return }

            // Get samples for visible range - high density for Apple Voice Memos style
            // Target ~1 sample per 1.5pt for dense, detailed waveform bars
            let targetSamples = max(1, Int(actualWidth / 1.5))
            let samples = data.samples(
                from: timeline.visibleStartTime,
                to: timeline.visibleEndTime,
                targetCount: targetSamples
            )

            guard !samples.isEmpty else { return }

            let centerY = size.height / 2
            let padding: CGFloat = 4
            let maxAmplitude = (size.height / 2) - padding

            // Theme colors
            let gridColor: Color = colorScheme == .dark ? .white.opacity(0.08) : .black.opacity(0.06)
            // High-contrast neutral bars by default; accent color only when selection is active
            let neutralBarColor = palette.waveformBarColor

            // === 1. Draw Grid (aligned with time ruler, using cached positions) ===

            let grid = gridPositions(actualWidth: actualWidth, height: size.height)

            // Draw minor vertical grid lines (lighter)
            for x in grid.minorXPositions {
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: 0))
                gridLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(gridLine, with: .color(gridColor.opacity(0.5)), lineWidth: 0.5)
            }

            // Draw major vertical grid lines (more visible)
            for x in grid.majorXPositions {
                var gridLine = Path()
                gridLine.move(to: CGPoint(x: x, y: 0))
                gridLine.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(gridLine, with: .color(gridColor), lineWidth: 0.5)
            }

            // Horizontal grid lines (amplitude markers) - only in Edit mode
            if showsHorizontalGrid {
                for y in grid.horizontalYPositions {
                    var gridLine = Path()
                    gridLine.move(to: CGPoint(x: 0, y: y))
                    gridLine.addLine(to: CGPoint(x: actualWidth, y: y))
                    context.stroke(gridLine, with: .color(gridColor), lineWidth: 0.5)
                }

                // Center line
                var centerLine = Path()
                centerLine.move(to: CGPoint(x: 0, y: centerY))
                centerLine.addLine(to: CGPoint(x: actualWidth, y: centerY))
                context.stroke(centerLine, with: .color(colorScheme == .dark ? Color.white.opacity(0.15) : Color.black.opacity(0.12)), lineWidth: 0.5)
            }

            // === 2. Draw Waveform (Apple Voice Memos style thin bars) ===

            // Selection bounds in x coordinates (only used if showsSelectionHighlight)
            let visibleDuration = timeline.visibleDuration
            let selStartX = CGFloat((selectionStart - timeline.visibleStartTime) / visibleDuration) * actualWidth
            let selEndX = CGFloat((selectionEnd - timeline.visibleStartTime) / visibleDuration) * actualWidth

            let sampleCount = samples.count
            let xStep = actualWidth / CGFloat(sampleCount)

            // Apple Voice Memos style: thin bars (1-1.5pt) with rounded caps
            let barWidth: CGFloat = min(1.5, max(0.75, xStep * 0.55))
            let minBarHeight: CGFloat = 1.0

            // Determine if there is an active selection (not zero-length)
            let hasActiveSelection = showsSelectionHighlight && (selEndX - selStartX) > 1

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * xStep + xStep / 2

                // Sample is 0-1 normalized amplitude (louder = higher value)
                let amplitude = max(minBarHeight, CGFloat(sample) * maxAmplitude)

                // Draw symmetric around center - louder sounds = taller bars
                let yTop = centerY - amplitude
                let yBottom = centerY + amplitude

                // Neutral bars always. Selected region switches to accent color.
                // Non-selected bars stay unchanged (no dimming).
                let barColor: Color
                if hasActiveSelection {
                    let isInSelection = x >= selStartX && x <= selEndX
                    barColor = isInSelection ? palette.accent : neutralBarColor
                } else {
                    barColor = neutralBarColor
                }

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

    // Hit target width for easier grabbing (44pt is Apple's minimum recommended)
    private let hitTargetWidth: CGFloat = 44

    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        // Use actual time-to-x mapping (no artificial inset)
        // Playhead is in an overlay outside the clipped container, so knob won't be clipped
        let x = timeline.timeToX(playheadPosition, width: width)

        if x >= -hitTargetWidth && x <= width + hitTargetWidth {
            ZStack {
                // Invisible expanded hit target for easier grabbing
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: hitTargetWidth, height: height)
                    .contentShape(Rectangle())

                // Main line
                Rectangle()
                    .fill(palette.playheadColor)
                    .frame(width: 2, height: height)

                // Top handle (knob)
                Circle()
                    .fill(palette.playheadColor)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(y: -height / 2 + 8)

                // Time readout (shown while dragging)
                if isDragging {
                    Text(PlayheadLineView.formatPlayheadTime(playheadPosition))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(palette.playheadColor)
                                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                        )
                        .offset(y: -height / 2 - 14)
                }
            }
            // Use .position() to center the playhead exactly at x
            .frame(width: hitTargetWidth, height: height)
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

    /// Format time as mm:ss.ms for playhead readout
    static func formatPlayheadTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let hundredths = Int((time - Double(Int(time))) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, hundredths)
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

    private let handleWidth: CGFloat = 6
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
            // Invisible drag zone at selection edge
            Color.clear
                .frame(width: hitAreaWidth, height: height)
                .contentShape(Rectangle())
                .offset(x: x - hitAreaWidth / 2)
                .highPriorityGesture(dragGesture)
                .zIndex(isDragging ? 200 : 50)
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
        let cornerRadius: CGFloat = 3

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
