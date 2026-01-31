//
//  TrackAlignmentView.swift
//  Sonidea
//
//  DAW-style track alignment view for visually syncing overdub layers.
//

import SwiftUI

struct TrackAlignmentView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let baseRecording: RecordingItem
    let layers: [RecordingItem]
    let unsavedLayerURL: URL?
    @Binding var unsavedLayerOffset: Double
    let mixSettings: MixSettings
    let onOffsetsChanged: ([(UUID, Double)]) -> Void

    private let maxOffset: Double = 1.5
    private let waveformHeight: CGFloat = 68
    private let headerHeight: CGFloat = 30
    private let laneSpacing: CGFloat = 4

    @State private var layerOffsets: [UUID: Double] = [:]
    @State private var localUnsavedOffset: Double = 0
    @State private var waveformSamples: [String: [Float]] = [:]
    @State private var zoomScale: CGFloat = 1.0
    @State private var pinchAnchorZoom: CGFloat = 0
    @State private var isLoading = true
    @State private var dragStartOffset: Double?
    @State private var containerWidth: CGFloat = 0

    private var baseDuration: TimeInterval { baseRecording.duration }
    private var totalTimeRange: Double { baseDuration + 2 * maxOffset }
    private var contentWidth: CGFloat { max(containerWidth, containerWidth * zoomScale) }

    private var isDirty: Bool {
        for layer in layers {
            let working = layerOffsets[layer.id] ?? layer.overdubOffsetSeconds
            if abs(working - layer.overdubOffsetSeconds) > 0.0001 { return true }
        }
        if abs(localUnsavedOffset - unsavedLayerOffset) > 0.0001 { return true }
        return false
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                GeometryReader { outerGeo in
                    let _ = updateContainerWidth(outerGeo.size.width)

                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(spacing: 0) {
                            timelineRuler
                                .frame(width: contentWidth, height: 28)

                            VStack(spacing: laneSpacing) {
                                trackUnit(
                                    label: "Base",
                                    color: palette.textSecondary.opacity(0.6),
                                    duration: baseDuration,
                                    offset: .constant(0),
                                    isBase: true,
                                    isLooped: mixSettings.baseChannel.isLooped,
                                    sampleKey: baseRecording.fileURL.path
                                )

                                ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                                    let layerLooped = index < mixSettings.layerChannels.count && mixSettings.layerChannels[index].isLooped
                                    trackUnit(
                                        label: "Layer \(index + 1)",
                                        color: layerColor(index: index),
                                        duration: layer.duration,
                                        offset: layerBinding(for: layer.id, default: layer.overdubOffsetSeconds),
                                        isBase: false,
                                        isLooped: layerLooped,
                                        sampleKey: layer.fileURL.path
                                    )
                                }

                                if unsavedLayerURL != nil {
                                    trackUnit(
                                        label: "New Layer",
                                        color: palette.recordButton,
                                        duration: baseDuration,
                                        offset: $localUnsavedOffset,
                                        isBase: false,
                                        isLooped: false,
                                        sampleKey: unsavedLayerURL?.path ?? ""
                                    )
                                }
                            }
                            .padding(.top, 4)
                            .padding(.horizontal, 4)
                            .frame(width: contentWidth)
                        }
                        .simultaneousGesture(
                            MagnificationGesture()
                                .onChanged { scale in
                                    if pinchAnchorZoom == 0 { pinchAnchorZoom = zoomScale }
                                    zoomScale = max(1.0, min(50.0, pinchAnchorZoom * scale))
                                }
                                .onEnded { _ in pinchAnchorZoom = 0 }
                        )
                    }
                }

                Divider()

                zoomBar
            }
            .background(palette.background)
            .navigationTitle("Align Tracks")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Apply") { applyChanges() }
                        .fontWeight(.semibold)
                        .disabled(!isDirty)
                }
            }
            .task { await loadWaveforms() }
            .onAppear {
                localUnsavedOffset = unsavedLayerOffset
                for layer in layers {
                    layerOffsets[layer.id] = layer.overdubOffsetSeconds
                }
            }
        }
    }

    // MARK: - Track Unit (pinned header + scrollable waveform)

    private func trackUnit(
        label: String,
        color: Color,
        duration: TimeInterval,
        offset: Binding<Double>,
        isBase: Bool,
        isLooped: Bool = false,
        sampleKey: String
    ) -> some View {
        VStack(spacing: 0) {
            // Header bar — pinned to visible area
            Color.clear
                .frame(height: headerHeight)
                .overlay {
                    GeometryReader { geo in
                        let scrollX = -geo.frame(in: .global).minX
                        pinnedHeader(
                            label: label,
                            color: color,
                            offset: offset,
                            isBase: isBase,
                            isLooped: isLooped
                        )
                        .frame(width: containerWidth)
                        .offset(x: scrollX)
                    }
                }
                .clipped()

            // Waveform — scrolls with zoom
            waveformLane(
                color: color,
                duration: duration,
                offset: offset,
                isBase: isBase,
                isLooped: isLooped,
                sampleKey: sampleKey
            )
        }
    }

    // MARK: - Pinned Header

    private func pinnedHeader(
        label: String,
        color: Color,
        offset: Binding<Double>,
        isBase: Bool,
        isLooped: Bool = false
    ) -> some View {
        HStack(spacing: 0) {
            // Left: track identity
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: 4, height: 16)

                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.textPrimary)

                if isLooped {
                    Image(systemName: "repeat.1")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.blue)
                }
            }
            .padding(.leading, 8)

            Spacer()

            // Right: offset + controls (layers only)
            if !isBase {
                HStack(spacing: 6) {
                    Text(formatOffsetMs(offset.wrappedValue))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(offset.wrappedValue == 0 ? palette.textTertiary : palette.accent)
                        .frame(minWidth: 60, alignment: .trailing)

                    Button {
                        offset.wrappedValue = max(-maxOffset, offset.wrappedValue - 0.001)
                    } label: {
                        Text("-1")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.textPrimary)
                            .frame(width: 28, height: 22)
                            .background(palette.inputBackground)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        offset.wrappedValue = min(maxOffset, offset.wrappedValue + 0.001)
                    } label: {
                        Text("+1")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.textPrimary)
                            .frame(width: 28, height: 22)
                            .background(palette.inputBackground)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Text("ms")
                        .font(.system(size: 9))
                        .foregroundColor(palette.textTertiary)
                }
                .padding(.trailing, 8)
            }
        }
        .frame(height: headerHeight)
        .background(color.opacity(0.08))
    }

    // MARK: - Waveform Lane

    private func waveformLane(
        color: Color,
        duration: TimeInterval,
        offset: Binding<Double>,
        isBase: Bool,
        isLooped: Bool = false,
        sampleKey: String
    ) -> some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // Lane background
            context.fill(
                Path(roundedRect: CGRect(x: 0, y: 0, width: width, height: height), cornerRadius: 0),
                with: .color(palette.inputBackground.opacity(0.15))
            )

            // Zero reference line
            let zeroX = timeToX(0, width: width)
            if zeroX >= 0 && zeroX <= width {
                var zeroPath = Path()
                zeroPath.move(to: CGPoint(x: zeroX, y: 0))
                zeroPath.addLine(to: CGPoint(x: zeroX, y: height))
                context.stroke(zeroPath, with: .color(palette.accent.opacity(0.5)), lineWidth: 1.5)
            }

            // End-of-base dashed line
            let endBaseX = timeToX(baseDuration, width: width)
            if endBaseX >= 0 && endBaseX <= width {
                var endPath = Path()
                endPath.move(to: CGPoint(x: endBaseX, y: 0))
                endPath.addLine(to: CGPoint(x: endBaseX, y: height))
                context.stroke(endPath, with: .color(palette.textTertiary.opacity(0.3)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // Waveform block
            let trackOffset = isBase ? 0 : offset.wrappedValue
            let blockStartX = timeToX(trackOffset, width: width)
            let blockEndX = timeToX(trackOffset + duration, width: width)
            let blockW = max(4, blockEndX - blockStartX)

            let samples = waveformSamples[sampleKey] ?? []

            // Helper to draw a waveform block at a given startX with given opacity
            func drawBlock(startX: CGFloat, blockWidth: CGFloat, opacity: Double) {
                let visStart = max(0, startX)
                let visEnd = min(width, startX + blockWidth)
                guard visEnd > visStart else { return }

                let clipRect = CGRect(x: visStart, y: 0, width: visEnd - visStart, height: height)

                // Block fill
                context.fill(
                    Path(CGRect(x: startX, y: 0, width: blockWidth, height: height)),
                    with: .color(color.opacity(0.12 * opacity))
                )

                // Block edges
                var lEdge = Path()
                lEdge.move(to: CGPoint(x: startX, y: 0))
                lEdge.addLine(to: CGPoint(x: startX, y: height))
                context.stroke(lEdge, with: .color(color.opacity(0.6 * opacity)), lineWidth: opacity < 1 ? 1 : 1.5)

                var rEdge = Path()
                rEdge.move(to: CGPoint(x: startX + blockWidth, y: 0))
                rEdge.addLine(to: CGPoint(x: startX + blockWidth, y: height))
                context.stroke(rEdge, with: .color(color.opacity(0.3 * opacity)), lineWidth: 1)

                // Waveform bars
                if !samples.isEmpty {
                    let centerY = height / 2
                    let maxAmplitude = (height / 2) - 2
                    let sampleCount = samples.count
                    let xStep = blockWidth / CGFloat(sampleCount)
                    let barWidth = max(0.5, min(3, xStep * 0.7))

                    context.clip(to: Path(clipRect))

                    for (i, sample) in samples.enumerated() {
                        let x = startX + CGFloat(i) * xStep + xStep / 2
                        guard x >= visStart - barWidth && x <= visEnd + barWidth else { continue }
                        let amplitude = CGFloat(sample) * maxAmplitude

                        var barPath = Path()
                        barPath.move(to: CGPoint(x: x, y: centerY - amplitude))
                        barPath.addLine(to: CGPoint(x: x, y: centerY + amplitude))
                        context.stroke(barPath, with: .color(color.opacity(0.85 * opacity)), style: StrokeStyle(lineWidth: barWidth, lineCap: .round))
                    }
                }
            }

            // Draw primary block
            drawBlock(startX: blockStartX, blockWidth: blockW, opacity: 1.0)

            // Draw ghost loop repetitions if looped
            if isLooped && duration > 0 {
                let totalVisible = totalTimeRange
                var repeatTime = trackOffset + duration
                while repeatTime < totalVisible {
                    let ghostStartX = timeToX(repeatTime, width: width)
                    let ghostEndX = timeToX(repeatTime + duration, width: width)
                    let ghostW = max(4, ghostEndX - ghostStartX)

                    // Only draw if visible
                    if ghostStartX < width && ghostEndX > 0 {
                        drawBlock(startX: ghostStartX, blockWidth: ghostW, opacity: 0.35)

                        // Dashed separator at loop boundary
                        var dashPath = Path()
                        dashPath.move(to: CGPoint(x: ghostStartX, y: 0))
                        dashPath.addLine(to: CGPoint(x: ghostStartX, y: height))
                        context.stroke(dashPath, with: .color(color.opacity(0.4)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }

                    repeatTime += duration
                    // Safety: don't draw more than 50 repetitions
                    if repeatTime > totalVisible + duration { break }
                }
            }

            // Loading indicator
            if samples.isEmpty && isLoading {
                let text = Text("Loading...")
                    .font(.system(size: 10))
                    .foregroundColor(color.opacity(0.5))
                let centerX = blockStartX + blockW / 2
                context.draw(context.resolve(text), at: CGPoint(x: centerX, y: height / 2), anchor: .center)
            }
        }
        .frame(height: waveformHeight)
        .contentShape(Rectangle())
        .gesture(isBase ? nil : layerDragGesture(offset: offset))
    }

    // MARK: - Timeline Ruler

    private var timelineRuler: some View {
        Canvas { context, size in
            context.fill(
                Path(CGRect(origin: .zero, size: size)),
                with: .color(palette.cardBackground)
            )

            let width = size.width
            let pxPerSecond = width / CGFloat(totalTimeRange)
            let tickInterval = rulerTickInterval(pxPerSecond: pxPerSecond)
            let majorInterval = tickInterval * 5

            let rangeStart = -maxOffset
            let rangeEnd = baseDuration + maxOffset
            var t = (rangeStart / tickInterval).rounded(.down) * tickInterval

            while t <= rangeEnd {
                let x = timeToX(t, width: width)
                let isMajor = abs(t.remainder(dividingBy: majorInterval)) < tickInterval * 0.1
                let isZero = abs(t) < 0.0001

                if x >= 0 && x <= width {
                    if isZero {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(palette.accent), lineWidth: 2)

                        let text = Text("0ms")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(palette.accent)
                        context.draw(context.resolve(text), at: CGPoint(x: x + 3, y: 3), anchor: .topLeading)
                    } else if isMajor {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height * 0.35))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(palette.textSecondary.opacity(0.6)), lineWidth: 1)

                        let ms = Int(t * 1000)
                        let label = ms > 0 ? "+\(ms)ms" : "\(ms)ms"
                        let text = Text(label).font(.system(size: 8)).foregroundColor(palette.textTertiary)
                        context.draw(context.resolve(text), at: CGPoint(x: x, y: size.height * 0.1), anchor: .center)
                    } else {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: size.height * 0.65))
                        path.addLine(to: CGPoint(x: x, y: size.height))
                        context.stroke(path, with: .color(palette.textTertiary.opacity(0.3)), lineWidth: 0.5)
                    }
                }
                t += tickInterval
            }

            // End-of-base marker
            let endX = timeToX(baseDuration, width: width)
            if endX >= 0 && endX <= width {
                var endPath = Path()
                endPath.move(to: CGPoint(x: endX, y: 0))
                endPath.addLine(to: CGPoint(x: endX, y: size.height))
                context.stroke(endPath, with: .color(palette.textTertiary.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            // Bottom border
            var border = Path()
            border.move(to: CGPoint(x: 0, y: size.height))
            border.addLine(to: CGPoint(x: width, y: size.height))
            context.stroke(border, with: .color(palette.stroke.opacity(0.3)), lineWidth: 0.5)
        }
    }

    // MARK: - Drag Gesture

    private func layerDragGesture(offset: Binding<Double>) -> some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                if dragStartOffset == nil {
                    dragStartOffset = offset.wrappedValue
                }

                let pxPerSecond = contentWidth / CGFloat(totalTimeRange)
                let timeDelta = Double(value.translation.width) / Double(pxPerSecond)
                let rawNew = (dragStartOffset ?? 0) + timeDelta

                var newOffset = (rawNew * 1000).rounded() / 1000
                newOffset = max(-maxOffset, min(maxOffset, newOffset))

                if abs(newOffset) < 0.003 { newOffset = 0 }

                offset.wrappedValue = newOffset
            }
            .onEnded { _ in
                dragStartOffset = nil
            }
    }

    // MARK: - Zoom Bar

    private var zoomBar: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    zoomScale = max(1.0, zoomScale / 1.5)
                }
            } label: {
                Image(systemName: "minus.magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Slider(value: $zoomScale, in: 1...50)
                .tint(palette.accent)

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    zoomScale = min(50.0, zoomScale * 1.5)
                }
            } label: {
                Image(systemName: "plus.magnifyingglass")
                    .font(.system(size: 16))
                    .foregroundColor(palette.textSecondary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)

            Text(String(format: "%.0fx", zoomScale))
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(palette.textSecondary)
                .frame(width: 35)

            Button {
                withAnimation(.easeInOut(duration: 0.2)) { zoomScale = 1.0 }
            } label: {
                Text("Fit")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.inputBackground)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func updateContainerWidth(_ width: CGFloat) {
        if abs(containerWidth - width) > 1 {
            DispatchQueue.main.async { containerWidth = width }
        }
    }

    private func timeToX(_ time: Double, width: CGFloat) -> CGFloat {
        let fraction = (time + maxOffset) / totalTimeRange
        return CGFloat(fraction) * width
    }

    private func rulerTickInterval(pxPerSecond: CGFloat) -> Double {
        let intervals: [Double] = [0.001, 0.002, 0.005, 0.01, 0.02, 0.05, 0.1, 0.2, 0.5, 1.0]
        for interval in intervals {
            let pxPerTick = pxPerSecond * CGFloat(interval)
            if pxPerTick >= 20 { return interval }
        }
        return 1.0
    }

    private func layerBinding(for id: UUID, default defaultValue: Double) -> Binding<Double> {
        Binding(
            get: { layerOffsets[id] ?? defaultValue },
            set: { layerOffsets[id] = $0 }
        )
    }

    private func layerColor(index: Int) -> Color {
        switch index {
        case 0: return palette.accent
        case 1: return .green
        case 2: return .orange
        default: return palette.accent
        }
    }

    private func formatOffsetMs(_ value: Double) -> String {
        let ms = Int(value * 1000)
        return ms >= 0 ? "+\(ms)ms" : "\(ms)ms"
    }

    private func applyChanges() {
        var changes: [(UUID, Double)] = []
        for layer in layers {
            let newOffset = layerOffsets[layer.id] ?? layer.overdubOffsetSeconds
            if abs(newOffset - layer.overdubOffsetSeconds) > 0.0001 {
                changes.append((layer.id, newOffset))
            }
        }
        if !changes.isEmpty {
            onOffsetsChanged(changes)
        }
        unsavedLayerOffset = localUnsavedOffset
        dismiss()
    }

    private func loadWaveforms() async {
        let baseSamples = await WaveformSampler.shared.samples(for: baseRecording.fileURL, targetSampleCount: 800)
        waveformSamples[baseRecording.fileURL.path] = baseSamples

        for layer in layers {
            let samples = await WaveformSampler.shared.samples(for: layer.fileURL, targetSampleCount: 800)
            waveformSamples[layer.fileURL.path] = samples
        }

        if let url = unsavedLayerURL {
            let samples = await WaveformSampler.shared.samples(for: url, targetSampleCount: 800)
            waveformSamples[url.path] = samples
        }

        isLoading = false
    }
}
