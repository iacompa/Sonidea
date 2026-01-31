//
//  ZoomableWaveformEditor.swift
//  Sonidea
//
//  Pro-level waveform editor with pinch-to-zoom, horizontal pan, and time ruler.
//  Wraps EditableWaveformView with a timeline model for proper gesture separation.
//

import SwiftUI
import UIKit

// MARK: - Timeline State

/// Represents the visible portion of the waveform timeline
struct TimelineState: Equatable {
    /// The start time of the visible window
    var visibleStartTime: TimeInterval = 0

    /// The end time of the visible window
    var visibleEndTime: TimeInterval

    /// Total duration of the recording
    let totalDuration: TimeInterval

    /// Current zoom level (1.0 = full width, higher = more zoomed in)
    var zoomLevel: CGFloat = 1.0

    /// Visible duration based on zoom
    var visibleDuration: TimeInterval {
        totalDuration / Double(zoomLevel)
    }

    /// Minimum zoom (show entire waveform)
    static let minZoom: CGFloat = 1.0

    /// Maximum zoom (cap at 1000% for mobile usability)
    static let maxZoom: CGFloat = 10.0

    init(totalDuration: TimeInterval) {
        self.totalDuration = totalDuration
        self.visibleEndTime = totalDuration
    }

    /// Apply zoom centered on a specific time
    mutating func zoom(to newZoomLevel: CGFloat, centeredOn centerTime: TimeInterval) {
        let clampedZoom = Swift.min(Swift.max(newZoomLevel, Self.minZoom), Self.maxZoom)
        let newVisibleDuration = totalDuration / Double(clampedZoom)

        // Keep the center time at the same position
        let halfDuration = newVisibleDuration / 2
        var newStart = centerTime - halfDuration
        var newEnd = centerTime + halfDuration

        // Clamp to valid range
        if newStart < 0 {
            newStart = 0
            newEnd = newVisibleDuration
        } else if newEnd > totalDuration {
            newEnd = totalDuration
            newStart = Swift.max(0, totalDuration - newVisibleDuration)
        }

        zoomLevel = clampedZoom
        visibleStartTime = newStart
        visibleEndTime = newEnd
    }

    /// Pan the visible window by a time delta
    mutating func pan(by timeDelta: TimeInterval) {
        let newStart = visibleStartTime + timeDelta
        let newEnd = visibleEndTime + timeDelta

        // Clamp to valid range
        if newStart < 0 {
            visibleStartTime = 0
            visibleEndTime = visibleDuration
        } else if newEnd > totalDuration {
            visibleEndTime = totalDuration
            visibleStartTime = Swift.max(0, totalDuration - visibleDuration)
        } else {
            visibleStartTime = newStart
            visibleEndTime = newEnd
        }
    }

    /// Ensure a time is visible (scroll to show it)
    mutating func ensureVisible(_ time: TimeInterval, padding: TimeInterval = 0.5) {
        if time < visibleStartTime + padding {
            let shift = visibleStartTime + padding - time
            pan(by: -shift)
        } else if time > visibleEndTime - padding {
            let shift = time - (visibleEndTime - padding)
            pan(by: shift)
        }
    }
}

// MARK: - Zoomable Waveform Editor

struct ZoomableWaveformEditor: View {
    let samples: [Float]
    let duration: TimeInterval
    @Binding var selectionStart: TimeInterval
    @Binding var selectionEnd: TimeInterval
    @Binding var playheadPosition: TimeInterval
    let currentTime: TimeInterval
    let isEditing: Bool
    let isPrecisionMode: Bool
    @Binding var markers: [Marker]
    let onScrub: (TimeInterval) -> Void
    let onMarkerTap: (Marker) -> Void
    let onMarkerMoved: ((Marker, TimeInterval) -> Void)?

    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    // MARK: - Timeline State

    @State private var timelineState: TimelineState
    @State private var initialPinchZoom: CGFloat = 1.0
    @State private var isPanning = false
    @State private var panStartOffset: TimeInterval = 0

    // Pinch-zoom tracking: suppresses pan/selection gestures while pinching
    @State private var isPinching = false
    @GestureState private var pinchActive = false

    // MARK: - Constants

    private var waveformHeight: CGFloat { sizeClass == .regular ? 220 : 160 }
    private let timeRulerHeight: CGFloat = 22  // Apple Voice Memos-style compact ruler
    private let handleMinDistance: CGFloat = 10  // Increased from 1 to prevent accidental drags

    // Haptic generators
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    init(
        samples: [Float],
        duration: TimeInterval,
        selectionStart: Binding<TimeInterval>,
        selectionEnd: Binding<TimeInterval>,
        playheadPosition: Binding<TimeInterval>,
        currentTime: TimeInterval,
        isEditing: Bool,
        isPrecisionMode: Bool = false,
        markers: Binding<[Marker]>,
        onScrub: @escaping (TimeInterval) -> Void,
        onMarkerTap: @escaping (Marker) -> Void,
        onMarkerMoved: ((Marker, TimeInterval) -> Void)? = nil
    ) {
        self.samples = samples
        self.duration = duration
        self._selectionStart = selectionStart
        self._selectionEnd = selectionEnd
        self._playheadPosition = playheadPosition
        self.currentTime = currentTime
        self.isEditing = isEditing
        self.isPrecisionMode = isPrecisionMode
        self._markers = markers
        self.onScrub = onScrub
        self.onMarkerTap = onMarkerTap
        self.onMarkerMoved = onMarkerMoved

        self._timelineState = State(initialValue: TimelineState(totalDuration: duration))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Apple Voice Memos-style minimal time ruler
            if isEditing {
                TimelineRulerView_Minimal(
                    timelineState: timelineState,
                    palette: palette,
                    rulerHeight: timeRulerHeight
                )
            }

            // Zoomable waveform area
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Waveform content (clipped to visible range)
                    ZoomableWaveformCanvas(
                        samples: samples,
                        duration: duration,
                        timelineState: timelineState,
                        selectionStart: selectionStart,
                        selectionEnd: selectionEnd,
                        currentTime: currentTime,
                        isEditing: isEditing,
                        palette: palette,
                        colorScheme: colorScheme
                    )

                    // Selection overlay (only when there is an active selection)
                    if isEditing && (selectionEnd - selectionStart) > 0.02 {
                        SelectionOverlayView(
                            selectionStart: selectionStart,
                            selectionEnd: selectionEnd,
                            timelineState: timelineState,
                            width: geometry.size.width,
                            height: geometry.size.height,
                            palette: palette
                        )
                    }

                    // Markers
                    MarkersLayerView(
                        markers: $markers,
                        timelineState: timelineState,
                        duration: duration,
                        isPrecisionMode: isPrecisionMode,
                        width: geometry.size.width,
                        height: geometry.size.height,
                        palette: palette,
                        onMarkerTap: onMarkerTap,
                        onMarkerMoved: onMarkerMoved
                    )

                    // Playhead
                    PlayheadView(
                        playheadPosition: $playheadPosition,
                        currentTime: currentTime,
                        timelineState: timelineState,
                        duration: duration,
                        isEditing: isEditing,
                        isPrecisionMode: isPrecisionMode,
                        width: geometry.size.width,
                        height: geometry.size.height,
                        palette: palette
                    )

                    // Selection handles (only when there is an active selection)
                    if isEditing && (selectionEnd - selectionStart) > 0.02 {
                        SelectionHandlesView(
                            selectionStart: $selectionStart,
                            selectionEnd: $selectionEnd,
                            timelineState: timelineState,
                            duration: duration,
                            isPrecisionMode: isPrecisionMode,
                            width: geometry.size.width,
                            height: geometry.size.height,
                            palette: palette
                        )
                    }
                }
                .contentShape(Rectangle())
                // Pan gesture (lower priority than handle drags)
                .gesture(panGesture(width: geometry.size.width))
                // Tap gesture for seeking
                .gesture(tapGesture(width: geometry.size.width))
                // Pinch to zoom (simultaneous so it is recognised alongside pan)
                .simultaneousGesture(zoomGesture)
            }
            .frame(height: isEditing ? waveformHeight : (sizeClass == .regular ? 140 : 100))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.inputBackground.opacity(0.5))
            )

            // Zoom indicator
            if isEditing && timelineState.zoomLevel > 1.05 {
                ZoomIndicatorView(
                    zoomLevel: timelineState.zoomLevel,
                    palette: palette,
                    onReset: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            timelineState = TimelineState(totalDuration: duration)
                        }
                    }
                )
                .padding(.top, 8)
            }
        }
        .onAppear {
            impactGenerator.prepare()
            selectionGenerator.prepare()
        }
        .onChange(of: currentTime) { _, newTime in
            // Auto-scroll to keep playhead visible during playback
            if !isEditing {
                timelineState.ensureVisible(newTime)
            }
        }
        .onChange(of: pinchActive) { _, active in
            // Safety net: @GestureState resets to false when pinch ends.
            // Clear isPinching if .onEnded was not called (gesture cancelled).
            if !active && isPinching {
                isPinching = false
                isPanning = false
            }
        }
    }

    // MARK: - Gestures

    private var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($pinchActive) { _, state, _ in
                state = true
            }
            .onChanged { scale in
                // Mark pinching so pan gesture is suppressed
                if !isPinching {
                    isPinching = true
                    // Cancel any in-progress pan that started before pinch recognition
                    isPanning = false
                }

                if initialPinchZoom == 1.0 {
                    initialPinchZoom = timelineState.zoomLevel
                }

                let newZoom = initialPinchZoom * scale
                let centerTime = (timelineState.visibleStartTime + timelineState.visibleEndTime) / 2

                withAnimation(.interactiveSpring(response: 0.15, dampingFraction: 0.8)) {
                    timelineState.zoom(to: newZoom, centeredOn: centerTime)
                }
            }
            .onEnded { _ in
                initialPinchZoom = 1.0
                isPinching = false
                impactGenerator.impactOccurred(intensity: 0.3)
            }
    }

    private func panGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 15)  // Higher threshold to avoid conflicts with handles
            .onChanged { value in
                // Suppress pan while pinch-zooming
                if isPinching || pinchActive { return }

                if !isPanning {
                    isPanning = true
                    panStartOffset = timelineState.visibleStartTime
                }

                // Convert drag distance to time
                let pixelsPerSecond = width / timelineState.visibleDuration
                var timeDelta = -Double(value.translation.width) / pixelsPerSecond

                // Apply precision mode scaling
                if isPrecisionMode {
                    timeDelta *= 0.25
                }

                timelineState.visibleStartTime = panStartOffset
                timelineState.pan(by: timeDelta)
            }
            .onEnded { _ in
                isPanning = false
                isPinching = false  // Safety: clear pinch flag if drag ended
                panStartOffset = 0
            }
    }

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                let tappedTime = xToTime(value.location.x, width: width)

                if isEditing {
                    // Set playhead position for marker placement
                    playheadPosition = tappedTime
                    impactGenerator.impactOccurred(intensity: 0.4)
                } else {
                    // Seek to position
                    onScrub(tappedTime)
                }
            }
    }

    // MARK: - Coordinate Conversion

    private func xToTime(_ x: CGFloat, width: CGFloat) -> TimeInterval {
        guard width > 0 else { return 0 }
        let progress = x / width
        let time = timelineState.visibleStartTime + (Double(progress) * timelineState.visibleDuration)
        return Swift.max(0, Swift.min(time, duration))
    }
}

// MARK: - Time Ruler View (DEPRECATED - replaced by TimelineRulerView_Minimal)
// The old TimeRulerView has been replaced by TimelineRulerView_Minimal in TimelineRulerView.swift
// for a sleeker Apple Voice Memos-style appearance.

// MARK: - Zoomable Waveform Canvas

struct ZoomableWaveformCanvas: View {
    let samples: [Float]
    let duration: TimeInterval
    let timelineState: TimelineState
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let currentTime: TimeInterval
    let isEditing: Bool
    let palette: ThemePalette
    let colorScheme: ColorScheme

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty && duration > 0 else { return }

            // Determine which samples are visible
            let samplesPerSecond = Double(samples.count) / duration
            let visibleStartIndex = Int(timelineState.visibleStartTime * samplesPerSecond)
            let visibleEndIndex = Int(timelineState.visibleEndTime * samplesPerSecond)
            let visibleCount = Swift.max(1, visibleEndIndex - visibleStartIndex)

            // Clamp indices
            let startIdx = Swift.max(0, Swift.min(visibleStartIndex, samples.count - 1))
            let endIdx = Swift.max(startIdx + 1, Swift.min(visibleEndIndex, samples.count))

            let visibleSamples = Array(samples[startIdx..<endIdx])

            // Draw bars
            let barCount = visibleSamples.count
            guard barCount > 0 else { return }

            let barSpacing: CGFloat = 2
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = Swift.max(2, availableWidth / CGFloat(barCount))
            let cornerRadius: CGFloat = 1.5

            // DAW-style waveform: always use accent color for visibility on all themes
            let waveformColor = palette.accent
            let playedColor = waveformColor
            let unplayedColor = colorScheme == .dark ? waveformColor.opacity(0.6) : waveformColor.opacity(0.5)

            // Playhead and selection indices
            let playheadProgress = (currentTime - timelineState.visibleStartTime) / timelineState.visibleDuration
            let playheadIndex = Int(playheadProgress * Double(barCount))

            let selectionStartProgress = (selectionStart - timelineState.visibleStartTime) / timelineState.visibleDuration
            let selectionEndProgress = (selectionEnd - timelineState.visibleStartTime) / timelineState.visibleDuration
            let selectionStartIndex = Int(selectionStartProgress * Double(barCount))
            let selectionEndIndex = Int(selectionEndProgress * Double(barCount))
            let hasActiveSelection = isEditing && selectionEndIndex > selectionStartIndex

            for (index, sample) in visibleSamples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = Swift.max(4, CGFloat(sample) * size.height * 0.9)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)

                let color: Color
                if isEditing {
                    // DAW-style: accent color waveform, dim unselected when selection exists
                    if hasActiveSelection {
                        let isInSelection = index >= selectionStartIndex && index <= selectionEndIndex
                        color = isInSelection ? waveformColor : waveformColor.opacity(0.5)
                    } else {
                        // No selection: full brightness
                        color = waveformColor
                    }
                } else {
                    color = index < playheadIndex ? playedColor : unplayedColor
                }

                context.fill(path, with: .color(color))
            }
        }
    }
}

// MARK: - Selection Overlay View

struct SelectionOverlayView: View {
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let timelineState: TimelineState
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette

    var body: some View {
        let startX = timeToX(selectionStart)
        let endX = timeToX(selectionEnd)
        let selectionWidth = Swift.max(0, endX - startX)

        Rectangle()
            .fill(palette.accent.opacity(0.18))
            .frame(width: selectionWidth, height: height)
            .offset(x: startX)
            .allowsHitTesting(false)
    }

    private func timeToX(_ time: TimeInterval) -> CGFloat {
        let progress = (time - timelineState.visibleStartTime) / timelineState.visibleDuration
        return CGFloat(progress) * width
    }
}

// MARK: - Playhead View

struct PlayheadView: View {
    @Binding var playheadPosition: TimeInterval
    let currentTime: TimeInterval
    let timelineState: TimelineState
    let duration: TimeInterval
    let isEditing: Bool
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette

    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0

    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        let time = isEditing ? playheadPosition : currentTime
        let x = timeToX(time)

        // Only show if visible
        if x >= -10 && x <= width + 10 {
            ZStack {
                Rectangle()
                    .fill(palette.playheadColor)
                    .frame(width: 2, height: height)

                if isEditing {
                    Circle()
                        .fill(palette.playheadColor)
                        .frame(width: 14, height: 14)
                        .offset(y: -height / 2 + 7)
                        .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
                }
            }
            .offset(x: x - 1)
            .highPriorityGesture(
                isEditing ? playheadDragGesture : nil
            )
            .zIndex(5)
        }
    }

    private var playheadDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartTime = playheadPosition
                    impactGenerator.impactOccurred(intensity: 0.4)
                }

                var newTime = xToTime(value.location.x)

                // Apply precision mode scaling
                if isPrecisionMode {
                    let delta = value.translation.width
                    let scaledDelta = delta * 0.25
                    let timeDelta = scaledDelta / width * timelineState.visibleDuration
                    newTime = dragStartTime + timeDelta
                }

                // Quantize to 0.01s
                newTime = (newTime / 0.01).rounded() * 0.01
                newTime = Swift.max(0, Swift.min(newTime, duration))

                // Haptic feedback
                if abs(newTime - lastHapticTime) >= 0.05 {
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

    private func timeToX(_ time: TimeInterval) -> CGFloat {
        let progress = (time - timelineState.visibleStartTime) / timelineState.visibleDuration
        return CGFloat(progress) * width
    }

    private func xToTime(_ x: CGFloat) -> TimeInterval {
        let progress = x / width
        return timelineState.visibleStartTime + (Double(progress) * timelineState.visibleDuration)
    }
}

// MARK: - Selection Handles View

struct SelectionHandlesView: View {
    @Binding var selectionStart: TimeInterval
    @Binding var selectionEnd: TimeInterval
    let timelineState: TimelineState
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette

    private let handleWidth: CGFloat = 14
    private let handleHitAreaWidth: CGFloat = 44
    private let minimumGap: TimeInterval = 0.05

    var body: some View {
        ZStack {
            // Left handle
            HandleView(
                time: $selectionStart,
                otherTime: selectionEnd,
                isLeft: true,
                timelineState: timelineState,
                duration: duration,
                isPrecisionMode: isPrecisionMode,
                width: width,
                height: height,
                minimumGap: minimumGap,
                palette: palette
            )

            // Right handle
            HandleView(
                time: $selectionEnd,
                otherTime: selectionStart,
                isLeft: false,
                timelineState: timelineState,
                duration: duration,
                isPrecisionMode: isPrecisionMode,
                width: width,
                height: height,
                minimumGap: minimumGap,
                palette: palette
            )
        }
    }
}

struct HandleView: View {
    @Binding var time: TimeInterval
    let otherTime: TimeInterval
    let isLeft: Bool
    let timelineState: TimelineState
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let minimumGap: TimeInterval
    let palette: ThemePalette

    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0

    private let handleWidth: CGFloat = 14
    private let handleHitAreaWidth: CGFloat = 44

    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        let x = timeToX(time)

        // Only show if visible
        if x >= -handleHitAreaWidth && x <= width + handleHitAreaWidth {
            ZStack {
                HandleShape(isLeft: isLeft)
                    .fill(palette.accent)
                    .frame(width: handleWidth, height: height * 0.7)
            }
            .frame(width: handleHitAreaWidth, height: height)
            .contentShape(Rectangle())
            .offset(x: x - handleHitAreaWidth / 2)
            .highPriorityGesture(handleDragGesture)
            .zIndex(10)
        }
    }

    private var handleDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)  // Increased from 1 to prevent accidental drags
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    dragStartTime = time
                    impactGenerator.impactOccurred(intensity: 0.5)
                }

                var deltaX = value.translation.width

                // Apply precision mode scaling
                if isPrecisionMode {
                    deltaX *= 0.25
                }

                // Convert to time delta
                let timeDelta = deltaX / width * timelineState.visibleDuration
                var newTime = dragStartTime + timeDelta

                // Quantize to 0.01s
                newTime = (newTime / 0.01).rounded() * 0.01

                // Clamp based on whether this is left or right handle
                if isLeft {
                    let maxTime = otherTime - minimumGap
                    newTime = Swift.max(0, Swift.min(newTime, maxTime))
                } else {
                    let minTime = otherTime + minimumGap
                    newTime = Swift.max(minTime, Swift.min(newTime, duration))
                }

                // Haptic feedback
                if abs(newTime - lastHapticTime) >= 0.05 {
                    selectionGenerator.selectionChanged()
                    lastHapticTime = newTime
                }

                time = newTime
            }
            .onEnded { _ in
                isDragging = false
                impactGenerator.impactOccurred(intensity: 0.3)
            }
    }

    private func timeToX(_ t: TimeInterval) -> CGFloat {
        let progress = (t - timelineState.visibleStartTime) / timelineState.visibleDuration
        return CGFloat(progress) * width
    }
}

// MARK: - Markers Layer View

struct MarkersLayerView: View {
    @Binding var markers: [Marker]
    let timelineState: TimelineState
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette
    let onMarkerTap: (Marker) -> Void
    let onMarkerMoved: ((Marker, TimeInterval) -> Void)?

    var body: some View {
        ForEach(markers) { marker in
            MarkerLayerItem(
                marker: marker,
                markers: $markers,
                timelineState: timelineState,
                duration: duration,
                isPrecisionMode: isPrecisionMode,
                width: width,
                height: height,
                palette: palette,
                onMarkerTap: onMarkerTap,
                onMarkerMoved: onMarkerMoved
            )
        }
    }
}

struct MarkerLayerItem: View {
    let marker: Marker
    @Binding var markers: [Marker]
    let timelineState: TimelineState
    let duration: TimeInterval
    let isPrecisionMode: Bool
    let width: CGFloat
    let height: CGFloat
    let palette: ThemePalette
    let onMarkerTap: (Marker) -> Void
    let onMarkerMoved: ((Marker, TimeInterval) -> Void)?

    @State private var isDragging = false
    @State private var dragStartTime: TimeInterval = 0
    @State private var currentDragTime: TimeInterval = 0
    @State private var lastHapticTime: TimeInterval = 0

    private let markerHitWidth: CGFloat = 32
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    var body: some View {
        let displayTime = isDragging ? currentDragTime : marker.time
        let x = timeToX(displayTime)

        // Only show if visible
        if x >= -markerHitWidth && x <= width + markerHitWidth {
            VStack(spacing: 0) {
                Circle()
                    .fill(isDragging ? palette.accent : palette.accent.opacity(0.9))
                    .frame(width: isDragging ? 10 : 8, height: isDragging ? 10 : 8)

                Rectangle()
                    .fill(isDragging ? palette.accent : palette.accent.opacity(0.7))
                    .frame(width: isDragging ? 3 : 2, height: height - 16)
            }
            .scaleEffect(isDragging ? 1.1 : 1.0)
            .animation(.easeInOut(duration: 0.15), value: isDragging)
            .position(x: x, y: height / 2)
            .frame(width: markerHitWidth)
            .contentShape(Rectangle().size(width: markerHitWidth, height: height))
            .onTapGesture {
                if !isDragging {
                    onMarkerTap(marker)
                    impactGenerator.impactOccurred(intensity: 0.5)
                }
            }
            .gesture(markerDragGesture)
            .contextMenu {
                Button(role: .destructive) {
                    if let index = markers.firstIndex(where: { $0.id == marker.id }) {
                        markers.remove(at: index)
                    }
                } label: {
                    Label("Delete Marker", systemImage: "trash")
                }
            }
        }
    }

    private var markerDragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.2)
            .sequenced(before: DragGesture(minimumDistance: 1))
            .onChanged { value in
                switch value {
                case .first(true):
                    isDragging = true
                    dragStartTime = marker.time
                    currentDragTime = marker.time
                    impactGenerator.impactOccurred(intensity: 0.6)

                case .second(true, let drag):
                    guard let drag = drag else { return }
                    var deltaX = drag.translation.width

                    if isPrecisionMode {
                        deltaX *= 0.25
                    }

                    let timeDelta = deltaX / width * timelineState.visibleDuration
                    var newTime = dragStartTime + timeDelta

                    newTime = Swift.max(0, Swift.min(newTime, duration))
                    newTime = (newTime / 0.01).rounded() * 0.01

                    if abs(newTime - lastHapticTime) >= 0.05 {
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
                    onMarkerMoved?(markers[index], currentDragTime)
                    impactGenerator.impactOccurred(intensity: 0.4)
                }
                isDragging = false
            }
    }

    private func timeToX(_ t: TimeInterval) -> CGFloat {
        let progress = (t - timelineState.visibleStartTime) / timelineState.visibleDuration
        return CGFloat(progress) * width
    }
}

// MARK: - Zoom Indicator View

struct ZoomIndicatorView: View {
    let zoomLevel: CGFloat
    let palette: ThemePalette
    let onReset: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.caption2)
                .foregroundColor(palette.textSecondary)

            Text("\(Int(zoomLevel * 100))%")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(palette.textSecondary)
                .monospacedDigit()

            Button {
                onReset()
            } label: {
                Text("Reset")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(palette.accent)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(palette.inputBackground)
        )
    }
}

// MARK: - Preview

#Preview {
    VStack {
        ZoomableWaveformEditor(
            samples: (0..<100).map { _ in Float.random(in: 0.1...1.0) },
            duration: 120,
            selectionStart: .constant(20),
            selectionEnd: .constant(80),
            playheadPosition: .constant(50),
            currentTime: 50,
            isEditing: true,
            isPrecisionMode: false,
            markers: .constant([
                Marker(time: 30, label: "Intro"),
                Marker(time: 70, label: "Chorus")
            ]),
            onScrub: { _ in },
            onMarkerTap: { _ in },
            onMarkerMoved: nil
        )
        .padding()
    }
    .background(Color(.systemBackground))
}
