//
//  EditableWaveformView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/24/26.
//

import SwiftUI
import UIKit

/// Editable waveform view with selection handles, playhead, and markers
/// Supports 0.01s precision with tap-to-set-playhead and draggable markers
struct EditableWaveformView: View {
    let samples: [Float]
    let duration: TimeInterval
    @Binding var selectionStart: TimeInterval
    @Binding var selectionEnd: TimeInterval
    @Binding var playheadPosition: TimeInterval  // Tap-to-set playhead for marker placement
    let currentTime: TimeInterval  // Current playback time
    let isEditing: Bool
    let isPrecisionMode: Bool  // External precision mode from "Hold for Precision" button
    @Binding var markers: [Marker]
    let onScrub: (TimeInterval) -> Void
    let onMarkerTap: (Marker) -> Void
    let onMarkerMoved: ((Marker, TimeInterval) -> Void)?

    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    // MARK: - Precision Constants

    /// Quantization step for editing (0.01 seconds = 10ms precision)
    private let editStep: TimeInterval = 0.01

    /// Minimum gap between handles to prevent overlap
    private let minimumGap: TimeInterval = 0.05

    /// Precision mode drag sensitivity (0.25x normal speed)
    private let precisionMultiplier: CGFloat = 0.25

    // Handle dimensions
    private let handleWidth: CGFloat = 14
    private let handleHitAreaWidth: CGFloat = 44

    // Drag threshold to prevent accidental drags (increased from 1 to 10)
    private let dragMinDistance: CGFloat = 10

    // Marker dimensions
    private let markerHitWidth: CGFloat = 32

    // Drag state for left handle
    @State private var leftHandleDragStartTime: TimeInterval = 0
    @State private var leftHandleDragStartX: CGFloat = 0

    // Drag state for right handle
    @State private var rightHandleDragStartTime: TimeInterval = 0
    @State private var rightHandleDragStartX: CGFloat = 0

    // Marker drag state
    @State private var draggingMarkerId: UUID?
    @State private var markerDragStartTime: TimeInterval = 0
    @State private var markerDragCurrentTime: TimeInterval = 0
    @State private var showMarkerTimeReadout = false

    // Playhead drag state
    @State private var isDraggingPlayhead = false
    @State private var playheadDragStartTime: TimeInterval = 0

    // Haptic feedback generator
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)
    private let selectionGenerator = UISelectionFeedbackGenerator()

    // Track last haptic time for throttling
    @State private var lastHapticTime: TimeInterval = 0

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
    }

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height

            ZStack(alignment: .leading) {
                // Background waveform
                waveformCanvas(width: width, height: height)

                // Selection overlay (only in edit mode)
                if isEditing {
                    selectionOverlay(width: width, height: height)
                }

                // Markers
                markersOverlay(width: width, height: height)

                // Playhead line (tap-to-set cursor in edit mode)
                if isEditing {
                    editPlayheadLine(width: width, height: height)
                } else {
                    playbackPlayheadLine(width: width, height: height)
                }

                // Selection handles (only in edit mode)
                if isEditing {
                    leftHandle(width: width, height: height)
                    rightHandle(width: width, height: height)
                }

                // Marker time readout (shown while dragging)
                if showMarkerTimeReadout {
                    markerTimeReadout(width: width, height: height)
                }
            }
            .contentShape(Rectangle())
            .gesture(tapGesture(width: width))
        }
        .onAppear {
            impactGenerator.prepare()
            selectionGenerator.prepare()
        }
    }

    // MARK: - Waveform Canvas

    private func waveformCanvas(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let barCount = samples.count
            let barSpacing: CGFloat = 2
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = Swift.max(2, availableWidth / CGFloat(barCount))
            let cornerRadius: CGFloat = 1.5

            // Determine colors based on edit mode and selection
            let playedColor = colorScheme == .dark ? Color.white : palette.accent
            let unplayedColor = colorScheme == .dark ? Color.white.opacity(0.3) : Color(.systemGray3)
            let selectedColor = palette.accent.opacity(0.7)

            let playheadProgress = duration > 0 ? currentTime / duration : 0
            let playheadIndex = Int(playheadProgress * Double(barCount))

            let selectionStartProgress = duration > 0 ? selectionStart / duration : 0
            let selectionEndProgress = duration > 0 ? selectionEnd / duration : 1
            let selectionStartIndex = Int(selectionStartProgress * Double(barCount))
            let selectionEndIndex = Int(selectionEndProgress * Double(barCount))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = Swift.max(4, CGFloat(sample) * size.height * 0.9)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: cornerRadius).path(in: rect)

                let color: Color
                if isEditing {
                    // In edit mode: show selection highlighting
                    let isInSelection = index >= selectionStartIndex && index <= selectionEndIndex
                    if isInSelection {
                        color = selectedColor
                    } else {
                        color = unplayedColor.opacity(0.5)
                    }
                } else {
                    // Normal playback mode
                    color = index < playheadIndex ? playedColor : unplayedColor
                }

                context.fill(path, with: .color(color))
            }
        }
    }

    // MARK: - Selection Overlay

    private func selectionOverlay(width: CGFloat, height: CGFloat) -> some View {
        let startX = timeToX(selectionStart, width: width)
        let endX = timeToX(selectionEnd, width: width)
        let selectionWidth = Swift.max(0, endX - startX)

        return Rectangle()
            .fill(palette.accent.opacity(0.18))
            .frame(width: selectionWidth, height: height)
            .offset(x: startX)
            .allowsHitTesting(false)
    }

    // MARK: - Markers Overlay

    private func markersOverlay(width: CGFloat, height: CGFloat) -> some View {
        ForEach(markers) { marker in
            let isDragging = draggingMarkerId == marker.id
            let displayTime = isDragging ? markerDragCurrentTime : marker.time
            let x = timeToX(displayTime, width: width)

            MarkerView(
                marker: marker,
                height: height,
                isDragging: isDragging,
                palette: palette
            )
            .position(x: x, y: height / 2)
            .frame(width: markerHitWidth)
            .contentShape(Rectangle().size(width: markerHitWidth, height: height))
            .onTapGesture {
                if !isDragging {
                    onMarkerTap(marker)
                    impactGenerator.impactOccurred(intensity: 0.5)
                }
            }
            .gesture(
                LongPressGesture(minimumDuration: 0.2)
                    .sequenced(before: DragGesture(minimumDistance: 1))
                    .onChanged { value in
                        switch value {
                        case .first(true):
                            // Long press recognized - start drag mode
                            draggingMarkerId = marker.id
                            markerDragStartTime = marker.time
                            markerDragCurrentTime = marker.time
                            showMarkerTimeReadout = true
                            impactGenerator.impactOccurred(intensity: 0.6)

                        case .second(true, let drag):
                            guard let drag = drag else { return }
                            var deltaX = drag.translation.width

                            // Apply precision mode scaling
                            if isPrecisionMode {
                                deltaX *= precisionMultiplier
                            }

                            let deltaTime = xToTime(deltaX, width: width, asDelta: true)
                            var newTime = markerDragStartTime + deltaTime

                            // Clamp to valid range
                            newTime = Swift.max(0, Swift.min(newTime, duration))

                            // Quantize to 0.01s
                            newTime = quantize(newTime)

                            // Haptic feedback every 0.05s change
                            if abs(newTime - lastHapticTime) >= 0.05 {
                                selectionGenerator.selectionChanged()
                                lastHapticTime = newTime
                            }

                            markerDragCurrentTime = newTime

                        default:
                            break
                        }
                    }
                    .onEnded { value in
                        if let markerId = draggingMarkerId,
                           let markerIndex = markers.firstIndex(where: { $0.id == markerId }) {
                            // Apply the new time
                            markers[markerIndex].time = markerDragCurrentTime
                            onMarkerMoved?(markers[markerIndex], markerDragCurrentTime)
                            impactGenerator.impactOccurred(intensity: 0.4)
                        }

                        draggingMarkerId = nil
                        showMarkerTimeReadout = false
                    }
            )
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

    // MARK: - Marker Time Readout

    private func markerTimeReadout(width: CGFloat, height: CGFloat) -> some View {
        let x = timeToX(markerDragCurrentTime, width: width)

        return Text(formatTimeWithCentiseconds(markerDragCurrentTime))
            .font(.caption2)
            .fontWeight(.medium)
            .monospacedDigit()
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(palette.accent.opacity(0.9))
            .cornerRadius(4)
            .position(x: x, y: -8)
    }

    // MARK: - Edit Mode Playhead (tap-to-set cursor)

    private func editPlayheadLine(width: CGFloat, height: CGFloat) -> some View {
        let x = timeToX(playheadPosition, width: width)

        return ZStack {
            // Playhead line
            Rectangle()
                .fill(Color.white)
                .frame(width: 2, height: height)

            // Draggable handle at top
            Circle()
                .fill(Color.white)
                .frame(width: 12, height: 12)
                .offset(y: -height / 2 + 6)
                .shadow(color: Color.black.opacity(0.3), radius: 2, x: 0, y: 1)
        }
        .offset(x: x - 1)
        .highPriorityGesture(
            DragGesture(minimumDistance: dragMinDistance)
                .onChanged { value in
                    if !isDraggingPlayhead {
                        isDraggingPlayhead = true
                        playheadDragStartTime = playheadPosition
                        impactGenerator.impactOccurred(intensity: 0.4)
                    }

                    var deltaX = value.translation.width

                    // Apply precision mode scaling
                    if isPrecisionMode {
                        deltaX *= precisionMultiplier
                    }

                    let rawTime = xToTime(value.location.x, width: width, asDelta: false)
                    var newTime = Swift.max(0, Swift.min(rawTime, duration))

                    // Quantize to 0.01s
                    newTime = quantize(newTime)

                    // Haptic feedback every 0.05s change
                    if abs(newTime - lastHapticTime) >= 0.05 {
                        selectionGenerator.selectionChanged()
                        lastHapticTime = newTime
                    }

                    playheadPosition = newTime
                }
                .onEnded { _ in
                    isDraggingPlayhead = false
                    impactGenerator.impactOccurred(intensity: 0.3)
                }
        )
        .zIndex(5)
    }

    // MARK: - Playback Playhead Line (non-edit mode)

    private func playbackPlayheadLine(width: CGFloat, height: CGFloat) -> some View {
        let x = timeToX(currentTime, width: width)

        return Rectangle()
            .fill(palette.accent)
            .frame(width: 2, height: height)
            .offset(x: x - 1)
            .allowsHitTesting(false)
    }

    // MARK: - Selection Handles

    private func leftHandle(width: CGFloat, height: CGFloat) -> some View {
        let x = timeToX(selectionStart, width: width)

        return ZStack {
            // Visual handle
            HandleShape(isLeft: true)
                .fill(palette.accent)
                .frame(width: handleWidth, height: height * 0.7)
        }
        .frame(width: handleHitAreaWidth, height: height)
        .contentShape(Rectangle())
        .offset(x: x - handleHitAreaWidth / 2)
        .highPriorityGesture(
            DragGesture(minimumDistance: dragMinDistance)
                .onChanged { value in
                    // Initialize on first change
                    if leftHandleDragStartTime == 0 && leftHandleDragStartX == 0 {
                        leftHandleDragStartTime = selectionStart
                        leftHandleDragStartX = value.startLocation.x
                        impactGenerator.impactOccurred(intensity: 0.5)
                    }

                    // Calculate delta
                    var deltaX = value.translation.width

                    // Apply precision mode scaling
                    if isPrecisionMode {
                        deltaX *= precisionMultiplier
                    }

                    let deltaTime = xToTime(deltaX, width: width, asDelta: true)
                    var newTime = leftHandleDragStartTime + deltaTime

                    // Quantize to 0.01s
                    newTime = quantize(newTime)

                    // Clamp: 0 <= newTime <= selectionEnd - minimumGap
                    let maxTime = selectionEnd - minimumGap
                    newTime = Swift.max(0, Swift.min(newTime, maxTime))

                    // Haptic feedback every 0.05s change
                    if abs(newTime - lastHapticTime) >= 0.05 {
                        selectionGenerator.selectionChanged()
                        lastHapticTime = newTime
                    }

                    selectionStart = newTime
                }
                .onEnded { _ in
                    leftHandleDragStartTime = 0
                    leftHandleDragStartX = 0
                    impactGenerator.impactOccurred(intensity: 0.3)
                }
        )
        .zIndex(10)
    }

    private func rightHandle(width: CGFloat, height: CGFloat) -> some View {
        let x = timeToX(selectionEnd, width: width)

        return ZStack {
            // Visual handle
            HandleShape(isLeft: false)
                .fill(palette.accent)
                .frame(width: handleWidth, height: height * 0.7)
        }
        .frame(width: handleHitAreaWidth, height: height)
        .contentShape(Rectangle())
        .offset(x: x - handleHitAreaWidth / 2)
        .highPriorityGesture(
            DragGesture(minimumDistance: dragMinDistance)
                .onChanged { value in
                    // Initialize on first change
                    if rightHandleDragStartTime == 0 && rightHandleDragStartX == 0 {
                        rightHandleDragStartTime = selectionEnd
                        rightHandleDragStartX = value.startLocation.x
                        impactGenerator.impactOccurred(intensity: 0.5)
                    }

                    // Calculate delta
                    var deltaX = value.translation.width

                    // Apply precision mode scaling
                    if isPrecisionMode {
                        deltaX *= precisionMultiplier
                    }

                    let deltaTime = xToTime(deltaX, width: width, asDelta: true)
                    var newTime = rightHandleDragStartTime + deltaTime

                    // Quantize to 0.01s
                    newTime = quantize(newTime)

                    // Clamp: selectionStart + minimumGap <= newTime <= duration
                    let minTime = selectionStart + minimumGap
                    newTime = Swift.max(minTime, Swift.min(newTime, duration))

                    // Haptic feedback every 0.05s change
                    if abs(newTime - lastHapticTime) >= 0.05 {
                        selectionGenerator.selectionChanged()
                        lastHapticTime = newTime
                    }

                    selectionEnd = newTime
                }
                .onEnded { _ in
                    rightHandleDragStartTime = 0
                    rightHandleDragStartX = 0
                    impactGenerator.impactOccurred(intensity: 0.3)
                }
        )
        .zIndex(10)
    }

    // MARK: - Tap Gesture (tap-to-set-playhead in edit mode, scrub in playback mode)

    private func tapGesture(width: CGFloat) -> some Gesture {
        SpatialTapGesture()
            .onEnded { value in
                if isEditing {
                    // In edit mode: tap sets the playhead position for marker placement
                    var newTime = xToTime(value.location.x, width: width, asDelta: false)
                    newTime = Swift.max(0, Swift.min(newTime, duration))
                    newTime = quantize(newTime)
                    playheadPosition = newTime
                    impactGenerator.impactOccurred(intensity: 0.4)
                } else {
                    // In playback mode: tap seeks to position
                    let time = xToTime(value.location.x, width: width, asDelta: false)
                    onScrub(time)
                }
            }
    }

    // MARK: - Coordinate Conversion

    private func timeToX(_ time: TimeInterval, width: CGFloat) -> CGFloat {
        guard duration > 0 else { return 0 }
        let progress = time / duration
        return CGFloat(progress) * width
    }

    private func xToTime(_ x: CGFloat, width: CGFloat, asDelta: Bool) -> TimeInterval {
        guard width > 0 else { return 0 }
        if asDelta {
            // Convert x delta to time delta
            return (Double(x) / Double(width)) * duration
        } else {
            // Convert absolute x to time
            let progress = Swift.max(0, Swift.min(1, x / width))
            return progress * duration
        }
    }

    // MARK: - Quantization

    /// Quantize time to nearest editStep (0.01s)
    private func quantize(_ time: TimeInterval) -> TimeInterval {
        return (time / editStep).rounded() * editStep
    }

    // MARK: - Time Formatting (2 decimal places for edit mode)

    private func formatTimeWithCentiseconds(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

// MARK: - Handle Shape

struct HandleShape: Shape {
    let isLeft: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let cornerRadius: CGFloat = 4

        if isLeft {
            // Left handle: rounded on left, flat on right
            path.move(to: CGPoint(x: rect.minX + cornerRadius, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY))
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(90),
                endAngle: .degrees(180),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + cornerRadius))
            path.addArc(
                center: CGPoint(x: rect.minX + cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(180),
                endAngle: .degrees(270),
                clockwise: false
            )
        } else {
            // Right handle: flat on left, rounded on right
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY))
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: rect.minY + cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(270),
                endAngle: .degrees(0),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - cornerRadius))
            path.addArc(
                center: CGPoint(x: rect.maxX - cornerRadius, y: rect.maxY - cornerRadius),
                radius: cornerRadius,
                startAngle: .degrees(0),
                endAngle: .degrees(90),
                clockwise: false
            )
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }

        path.closeSubpath()
        return path
    }
}

// MARK: - Marker View

struct MarkerView: View {
    let marker: Marker
    let height: CGFloat
    let isDragging: Bool
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 0) {
            // Marker dot
            Circle()
                .fill(isDragging ? palette.accent : palette.accent.opacity(0.9))
                .frame(width: isDragging ? 10 : 8, height: isDragging ? 10 : 8)

            // Marker line
            Rectangle()
                .fill(isDragging ? palette.accent : palette.accent.opacity(0.7))
                .frame(width: isDragging ? 3 : 2, height: height - 16)
        }
        .scaleEffect(isDragging ? 1.1 : 1.0)
        .animation(.easeInOut(duration: 0.15), value: isDragging)
    }
}

// MARK: - Edit Actions Row (Single Row, Compact)
// Note: Undo/Redo moved to top bar (near Done button) to free space here

struct WaveformEditActionsView: View {
    let canTrim: Bool
    let canCut: Bool
    let isProcessing: Bool
    @Binding var isPrecisionMode: Bool
    let onTrim: () -> Void
    let onCut: () -> Void
    let onAddMarker: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 8) {
            // Trim button
            EditActionButton(
                icon: "crop",
                label: "Trim",
                isEnabled: canTrim && !isProcessing,
                style: .primary,
                action: onTrim
            )

            // Cut button
            EditActionButton(
                icon: "scissors",
                label: "Cut",
                isEnabled: canCut && !isProcessing,
                style: .destructive,
                action: onCut
            )

            // Divider
            Rectangle()
                .fill(palette.stroke.opacity(0.3))
                .frame(width: 1, height: 28)
                .padding(.horizontal, 4)

            // Add Marker button
            EditActionButton(
                icon: "flag.fill",
                label: "Marker",
                isEnabled: !isProcessing,
                style: .secondary,
                action: onAddMarker
            )

            // Precision toggle
            HoldForPrecisionButton(isPrecisionMode: $isPrecisionMode)
        }
        .padding(.horizontal, 4)
    }
}

// MARK: - Edit Action Button Style Enum

enum EditActionStyle {
    case primary
    case secondary
    case destructive
}

// MARK: - Unified Edit Action Button

struct EditActionButton: View {
    let icon: String
    let label: String
    let isEnabled: Bool
    let style: EditActionStyle
    let action: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .foregroundColor(foregroundColor)
            .background(backgroundColor)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(borderColor, lineWidth: style == .secondary ? 1 : 0)
            )
        }
        .disabled(!isEnabled)
    }

    private var foregroundColor: Color {
        guard isEnabled else { return palette.textTertiary }
        switch style {
        case .primary: return .white
        case .secondary: return palette.accent
        case .destructive: return .red
        }
    }

    private var backgroundColor: Color {
        guard isEnabled else { return palette.inputBackground }
        switch style {
        case .primary: return palette.accent
        case .secondary: return palette.accent.opacity(0.12)
        case .destructive: return Color.red.opacity(0.12)
        }
    }

    private var borderColor: Color {
        guard isEnabled else { return Color.clear }
        switch style {
        case .primary: return Color.clear
        case .secondary: return palette.accent.opacity(0.25)
        case .destructive: return Color.red.opacity(0.25)
        }
    }
}

// MARK: - Primary Edit Button Style

struct PrimaryEditButtonStyle: ButtonStyle {
    let isEnabled: Bool
    @Environment(\.themePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? .white : palette.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? palette.accent : palette.inputBackground)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Secondary Edit Button Style

struct SecondaryEditButtonStyle: ButtonStyle {
    let isEnabled: Bool
    var isDestructive: Bool = false
    @Environment(\.themePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? (isDestructive ? .red : palette.accent) : palette.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isEnabled ? (isDestructive ? Color.red.opacity(0.15) : palette.accent.opacity(0.15)) : palette.inputBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isEnabled ? (isDestructive ? Color.red.opacity(0.3) : palette.accent.opacity(0.3)) : Color.clear, lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Compact Edit Button Style

struct CompactEditButtonStyle: ButtonStyle {
    let isEnabled: Bool
    @Environment(\.themePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(isEnabled ? palette.accent : palette.textTertiary)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isEnabled ? palette.accent.opacity(0.15) : Color.clear)
            )
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

// MARK: - Hold for Precision Button (Compact)

struct HoldForPrecisionButton: View {
    @Binding var isPrecisionMode: Bool

    @Environment(\.themePalette) private var palette

    private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: isPrecisionMode ? "scope" : "hand.tap")
                .font(.system(size: 11, weight: .medium))

            Text(isPrecisionMode ? "0.01s" : "Precision")
                .font(.caption2)
                .fontWeight(.medium)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
        }
        .foregroundColor(isPrecisionMode ? .white : palette.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isPrecisionMode ? palette.accent : palette.inputBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isPrecisionMode ? Color.clear : palette.stroke.opacity(0.5), lineWidth: 1)
        )
        .scaleEffect(isPrecisionMode ? 1.03 : 1.0)
        .animation(.easeInOut(duration: 0.1), value: isPrecisionMode)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isPrecisionMode {
                        isPrecisionMode = true
                        impactGenerator.impactOccurred(intensity: 0.6)
                    }
                }
                .onEnded { _ in
                    isPrecisionMode = false
                    impactGenerator.impactOccurred(intensity: 0.3)
                }
        )
    }
}

// MARK: - Selection Time Display (Compact Card)

struct SelectionTimeDisplay: View {
    @Binding var selectionStart: TimeInterval
    @Binding var selectionEnd: TimeInterval
    let duration: TimeInterval

    @Environment(\.themePalette) private var palette

    private let nudgeStep: TimeInterval = 0.01
    private let impactGenerator = UIImpactFeedbackGenerator(style: .light)

    private var selectionDuration: TimeInterval {
        selectionEnd - selectionStart
    }

    private var minimumGap: TimeInterval { 0.05 }

    var body: some View {
        HStack(spacing: 0) {
            // Start time with nudge
            SelectionEndpointControl(
                label: "IN",
                time: selectionStart,
                onNudge: { delta in nudgeStart(by: delta) },
                palette: palette
            )

            // Duration badge in center - clean typography, no blocky highlight
            VStack(spacing: 2) {
                Text("DURATION")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(palette.textTertiary)

                Text(formatTime(selectionDuration))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.accent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)

            // End time with nudge
            SelectionEndpointControl(
                label: "OUT",
                time: selectionEnd,
                onNudge: { delta in nudgeEnd(by: delta) },
                palette: palette
            )
        }
        .background(palette.inputBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(palette.stroke.opacity(0.3), lineWidth: 1)
        )
    }

    private func nudgeStart(by delta: TimeInterval) {
        var newStart = selectionStart + delta
        newStart = Swift.max(0, Swift.min(newStart, selectionEnd - minimumGap))
        selectionStart = newStart
        impactGenerator.impactOccurred(intensity: 0.4)
    }

    private func nudgeEnd(by delta: TimeInterval) {
        var newEnd = selectionEnd + delta
        newEnd = Swift.max(selectionStart + minimumGap, Swift.min(newEnd, duration))
        selectionEnd = newEnd
        impactGenerator.impactOccurred(intensity: 0.4)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

// MARK: - Selection Endpoint Control

struct SelectionEndpointControl: View {
    let label: String
    let time: TimeInterval
    let onNudge: (TimeInterval) -> Void
    let palette: ThemePalette

    private let nudgeStep: TimeInterval = 0.01

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(palette.textTertiary)

            Text(formatTime(time))
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(palette.textPrimary)

            // Nudge buttons
            HStack(spacing: 2) {
                Button {
                    onNudge(-nudgeStep)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(NudgeButtonStyle())

                Button {
                    onNudge(nudgeStep)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 26, height: 22)
                }
                .buttonStyle(NudgeButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        let centiseconds = Int((time.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }
}

// MARK: - Nudge Button Style

struct NudgeButtonStyle: ButtonStyle {
    @Environment(\.themePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundColor(palette.accent)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(palette.accent.opacity(configuration.isPressed ? 0.25 : 0.15))
            )
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        EditableWaveformView(
            samples: (0..<100).map { _ in Float.random(in: 0.1...1.0) },
            duration: 60,
            selectionStart: .constant(10),
            selectionEnd: .constant(40),
            playheadPosition: .constant(25),
            currentTime: 25,
            isEditing: true,
            isPrecisionMode: false,
            markers: .constant([
                Marker(time: 15, label: "Intro"),
                Marker(time: 35, label: "Chorus")
            ]),
            onScrub: { _ in },
            onMarkerTap: { _ in },
            onMarkerMoved: nil
        )
        .frame(height: 180)

        WaveformEditActionsView(
            canTrim: true,
            canCut: true,
            isProcessing: false,
            isPrecisionMode: .constant(false),
            onTrim: {},
            onCut: {},
            onAddMarker: {}
        )

        SelectionTimeDisplay(
            selectionStart: .constant(10),
            selectionEnd: .constant(40),
            duration: 60
        )
    }
    .padding()
    .background(Color(.systemBackground))
}
