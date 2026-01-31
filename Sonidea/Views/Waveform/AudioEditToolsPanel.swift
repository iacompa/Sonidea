//
//  AudioEditToolsPanel.swift
//  Sonidea
//
//  Individual tool sheets for Fade, Peak (Normalize), and Noise Gate.
//  Also includes EditToolButton for the inline toolbar and FadeCurveOverlay for waveform visualization.
//

import SwiftUI

// MARK: - Edit Tool Button (inline toolbar)

struct EditToolButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let isEnabled: Bool
    let action: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if !icon.isEmpty {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                }
                if !label.isEmpty {
                    Text(label)
                        .font(.system(size: 11, weight: .medium))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .foregroundColor(isActive ? .white : (isEnabled ? palette.accent : palette.textTertiary))
            .background(isActive ? palette.accent : (isEnabled ? palette.accent.opacity(0.12) : palette.inputBackground))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isActive ? Color.clear : palette.accent.opacity(isEnabled ? 0.25 : 0), lineWidth: isActive ? 0 : 1)
            )
        }
        .disabled(!isEnabled && !isActive)
    }
}

// MARK: - Fade Tool Sheet

struct FadeToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var isProcessing: Bool
    let duration: TimeInterval
    @Binding var fadeInDuration: Double
    @Binding var fadeOutDuration: Double
    @Binding var fadeCurve: FadeCurve
    let isApplied: Bool
    let onApply: (TimeInterval, TimeInterval, FadeCurve) -> Void
    let onRemove: () -> Void

    private static let defaultFadeIn: Double = 0
    private static let defaultFadeOut: Double = 0
    private static let defaultCurve: FadeCurve = .sCurve

    private var maxFade: Double { min(5.0, duration / 2) }

    private var isDefault: Bool {
        fadeInDuration == Self.defaultFadeIn
            && fadeOutDuration == Self.defaultFadeOut
            && fadeCurve == Self.defaultCurve
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Fade In", systemImage: "arrow.up.right")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1fs", fadeInDuration))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $fadeInDuration, in: 0...maxFade, step: 0.1)
                            .tint(palette.accent)

                        HStack {
                            Label("Fade Out", systemImage: "arrow.down.right")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1fs", fadeOutDuration))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $fadeOutDuration, in: 0...maxFade, step: 0.1)
                            .tint(palette.accent)

                        Picker("Curve", selection: $fadeCurve) {
                            ForEach(FadeCurve.allCases) { curve in
                                Text(curve.displayName).tag(curve)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                } header: {
                    Text("Settings")
                }

                Section {
                    Button {
                        dismiss()
                        onApply(fadeInDuration, fadeOutDuration, fadeCurve)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Apply Fade", systemImage: "waveform.path.ecg")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || (fadeInDuration == 0 && fadeOutDuration == 0))

                    if isApplied {
                        Button(role: .destructive) {
                            dismiss()
                            onRemove()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Remove Fade", systemImage: "arrow.uturn.backward")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }

                    if !isDefault && !isApplied {
                        Button {
                            fadeInDuration = Self.defaultFadeIn
                            fadeOutDuration = Self.defaultFadeOut
                            fadeCurve = Self.defaultCurve
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Fade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Peak (Normalize) Tool Sheet

struct PeakToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var isProcessing: Bool
    @Binding var normalizeTarget: Float
    let isApplied: Bool
    let onApply: (Float) -> Void
    let onRemove: () -> Void

    private static let defaultTarget: Float = -0.3

    private var isDefault: Bool {
        normalizeTarget == Self.defaultTarget
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Target Peak")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f dB", normalizeTarget))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $normalizeTarget, in: -6...0, step: 0.1)
                            .tint(palette.accent)
                        Text("Adjusts volume so the loudest peak reaches the target level.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } header: {
                    Label("Normalize", systemImage: "speaker.wave.3")
                }

                Section {
                    Button {
                        dismiss()
                        onApply(normalizeTarget)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Normalize", systemImage: "speaker.wave.3")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isProcessing)

                    if isApplied {
                        Button(role: .destructive) {
                            dismiss()
                            onRemove()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Remove Normalize", systemImage: "arrow.uturn.backward")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }

                    if !isDefault && !isApplied {
                        Button {
                            normalizeTarget = Self.defaultTarget
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Peak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Gate Tool Sheet

struct GateToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var isProcessing: Bool
    @Binding var gateThreshold: Float
    let isApplied: Bool
    let onApply: (Float) -> Void
    let onRemove: () -> Void

    private static let defaultThreshold: Float = -40

    private var isDefault: Bool {
        gateThreshold == Self.defaultThreshold
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Threshold")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.0f dB", gateThreshold))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $gateThreshold, in: -60...(-10), step: 1)
                            .tint(palette.accent)
                        Text("Silences audio below the threshold. Useful for removing background noise between phrases.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } header: {
                    Label("Noise Gate", systemImage: "waveform.badge.minus")
                }

                Section {
                    Button {
                        dismiss()
                        onApply(gateThreshold)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Apply Gate", systemImage: "waveform.badge.minus")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isProcessing)

                    if isApplied {
                        Button(role: .destructive) {
                            dismiss()
                            onRemove()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Remove Gate", systemImage: "arrow.uturn.backward")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }

                    if !isDefault && !isApplied {
                        Button {
                            gateThreshold = Self.defaultThreshold
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Gate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Compress Tool Sheet

struct CompressToolSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var isProcessing: Bool
    @Binding var makeupGain: Float
    @Binding var peakReduction: Float
    let isApplied: Bool
    let onApply: (Float, Float) -> Void
    let onRemove: () -> Void

    private static let defaultGain: Float = 0
    private static let defaultReduction: Float = 0

    private var isDefault: Bool {
        makeupGain == Self.defaultGain && peakReduction == Self.defaultReduction
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Gain")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f dB", makeupGain))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $makeupGain, in: 0...10, step: 0.1)
                            .tint(palette.accent)
                        Text("Boosts overall output level after compression.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } header: {
                    Label("Makeup Gain", systemImage: "speaker.wave.2")
                }

                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Peak Reduction")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f", peakReduction))
                                .font(.subheadline.monospacedDigit())
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $peakReduction, in: 0...10, step: 0.1)
                            .tint(palette.accent)
                        Text("Controls how aggressively peaks are reduced. Higher values = more compression.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                } header: {
                    Label("Peak Reduction", systemImage: "waveform.path.ecg.rectangle")
                }

                Section {
                    Button {
                        dismiss()
                        onApply(makeupGain, peakReduction)
                    } label: {
                        HStack {
                            Spacer()
                            Label("Apply Compression", systemImage: "waveform.badge.magnifyingglass")
                                .fontWeight(.medium)
                            Spacer()
                        }
                    }
                    .disabled(isProcessing || (makeupGain == 0 && peakReduction == 0))

                    if isApplied {
                        Button(role: .destructive) {
                            dismiss()
                            onRemove()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Remove Compression", systemImage: "arrow.uturn.backward")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    }

                    if !isDefault && !isApplied {
                        Button {
                            makeupGain = Self.defaultGain
                            peakReduction = Self.defaultReduction
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Compress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Fade Curve Preview (inside sheet)

struct FadeCurvePreview: View {
    let fadeInDuration: TimeInterval
    let fadeOutDuration: TimeInterval
    let curve: FadeCurve
    let totalDuration: TimeInterval

    @Environment(\.themePalette) private var palette

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            guard totalDuration > 0 else { return }

            // Draw baseline
            let baselineY = h - 4
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: baselineY))
                    p.addLine(to: CGPoint(x: w, y: baselineY))
                },
                with: .color(palette.textTertiary.opacity(0.3)),
                lineWidth: 1
            )

            // Draw top line
            let topY: CGFloat = 4
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: 0, y: topY))
                    p.addLine(to: CGPoint(x: w, y: topY))
                },
                with: .color(palette.textTertiary.opacity(0.15)),
                lineWidth: 0.5
            )

            // Build the fade envelope path
            let fadeInFraction = CGFloat(fadeInDuration / totalDuration)
            let fadeOutFraction = CGFloat(fadeOutDuration / totalDuration)
            let fadeInEndX = fadeInFraction * w
            let fadeOutStartX = w - (fadeOutFraction * w)

            let steps = 60
            var envelopePath = Path()

            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = t * w

                var gain: CGFloat = 1.0

                // Fade in region
                if fadeInDuration > 0 && x < fadeInEndX {
                    let fadeT = Float(x / fadeInEndX)
                    gain = CGFloat(curve.apply(fadeT))
                }

                // Fade out region
                if fadeOutDuration > 0 && x > fadeOutStartX {
                    let fadeT = Float((w - x) / (w - fadeOutStartX))
                    let fadeOutGain = CGFloat(curve.apply(fadeT))
                    gain = min(gain, fadeOutGain)
                }

                let y = baselineY - gain * (baselineY - topY)

                if i == 0 {
                    envelopePath.move(to: CGPoint(x: x, y: y))
                } else {
                    envelopePath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Stroke the envelope
            context.stroke(envelopePath, with: .color(palette.accent), lineWidth: 2)

            // Fill under the envelope
            var fillPath = envelopePath
            fillPath.addLine(to: CGPoint(x: w, y: baselineY))
            fillPath.addLine(to: CGPoint(x: 0, y: baselineY))
            fillPath.closeSubpath()
            context.fill(fillPath, with: .color(palette.accent.opacity(0.15)))

            // Draw fade boundary markers
            if fadeInDuration > 0 {
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: fadeInEndX, y: topY))
                        p.addLine(to: CGPoint(x: fadeInEndX, y: baselineY))
                    },
                    with: .color(palette.accent.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }
            if fadeOutDuration > 0 {
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: fadeOutStartX, y: topY))
                        p.addLine(to: CGPoint(x: fadeOutStartX, y: baselineY))
                    },
                    with: .color(palette.accent.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1, dash: [4, 3])
                )
            }

            // Time labels
            if fadeInDuration > 0 {
                let label = String(format: "%.1fs", fadeInDuration)
                context.draw(
                    Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(palette.accent),
                    at: CGPoint(x: fadeInEndX / 2, y: h - 14),
                    anchor: .center
                )
            }
            if fadeOutDuration > 0 {
                let label = String(format: "%.1fs", fadeOutDuration)
                context.draw(
                    Text(label).font(.system(size: 9, weight: .medium)).foregroundColor(palette.accent),
                    at: CGPoint(x: fadeOutStartX + (w - fadeOutStartX) / 2, y: h - 14),
                    anchor: .center
                )
            }
        }
        .background(palette.inputBackground.opacity(0.5))
        .cornerRadius(8)
    }
}

// MARK: - Fade Curve Overlay (on waveform)

struct FadeCurveOverlay: View {
    let fadeInDuration: TimeInterval
    let fadeOutDuration: TimeInterval
    let curve: FadeCurve
    let totalDuration: TimeInterval

    @Environment(\.themePalette) private var palette

    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height

            guard totalDuration > 0 else { return }

            let fadeInFraction = CGFloat(fadeInDuration / totalDuration)
            let fadeOutFraction = CGFloat(fadeOutDuration / totalDuration)
            let fadeInEndX = fadeInFraction * w
            let fadeOutStartX = w - (fadeOutFraction * w)

            // Draw fade-in shading
            if fadeInDuration > 0 {
                drawFadeRegion(
                    context: context,
                    startX: 0,
                    endX: fadeInEndX,
                    height: h,
                    isFadeIn: true
                )
            }

            // Draw fade-out shading
            if fadeOutDuration > 0 {
                drawFadeRegion(
                    context: context,
                    startX: fadeOutStartX,
                    endX: w,
                    height: h,
                    isFadeIn: false
                )
            }
        }
        .allowsHitTesting(false)
    }

    private func drawFadeRegion(
        context: GraphicsContext,
        startX: CGFloat,
        endX: CGFloat,
        height: CGFloat,
        isFadeIn: Bool
    ) {
        let regionWidth = endX - startX
        guard regionWidth > 0 else { return }

        let steps = max(20, Int(regionWidth / 2))

        // Build the darkened area above the gain curve
        // Where gain is low, more darkness; where gain is 1.0, no darkness
        var curvePath = Path()
        curvePath.move(to: CGPoint(x: startX, y: 0))

        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let x = startX + CGFloat(t) * regionWidth

            let gain: Float
            if isFadeIn {
                gain = curve.apply(t)
            } else {
                gain = curve.apply(1.0 - t)
            }

            // curveY: where gain=0 → y=height (full dark), gain=1 → y=0 (no dark)
            let curveY = height * (1.0 - CGFloat(gain))
            curvePath.addLine(to: CGPoint(x: x, y: curveY))
        }

        // Close along the top edge
        curvePath.addLine(to: CGPoint(x: endX, y: 0))
        curvePath.closeSubpath()

        // Fill with semi-transparent dark overlay (represents volume reduction)
        context.fill(curvePath, with: .color(Color.black.opacity(0.35)))

        // Draw the gain curve line
        var linePath = Path()
        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let x = startX + CGFloat(t) * regionWidth

            let gain: Float
            if isFadeIn {
                gain = curve.apply(t)
            } else {
                gain = curve.apply(1.0 - t)
            }

            let curveY = height * (1.0 - CGFloat(gain))

            if i == 0 {
                linePath.move(to: CGPoint(x: x, y: curveY))
            } else {
                linePath.addLine(to: CGPoint(x: x, y: curveY))
            }
        }

        context.stroke(linePath, with: .color(palette.accent.opacity(0.8)), lineWidth: 1.5)

        // Dashed boundary line at fade edge
        let boundaryX = isFadeIn ? endX : startX
        context.stroke(
            Path { p in
                p.move(to: CGPoint(x: boundaryX, y: 0))
                p.addLine(to: CGPoint(x: boundaryX, y: height))
            },
            with: .color(palette.accent.opacity(0.5)),
            style: StrokeStyle(lineWidth: 1, dash: [3, 2])
        )
    }
}

// MARK: - Edit Tool Type

enum EditToolType: String, CaseIterable, Identifiable {
    case fade, peak, gate, compress, reverb, echo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fade: return "Fade"
        case .peak: return "Peak"
        case .gate: return "Gate"
        case .compress: return "Comp"
        case .reverb: return "Reverb"
        case .echo: return "Echo"
        }
    }

    var icon: String {
        switch self {
        case .fade: return "waveform.path.ecg"
        case .peak: return "speaker.wave.3"
        case .gate: return "waveform.badge.minus"
        case .compress: return "waveform.badge.magnifyingglass"
        case .reverb: return "dot.radiowaves.left.and.right"
        case .echo: return "repeat"
        }
    }
}

// MARK: - Slide-Up Tools Panel

struct EditToolsSlidePanel: View {
    @Environment(\.themePalette) private var palette

    @Binding var selectedTool: EditToolType
    @Binding var isProcessing: Bool

    // Fade
    @Binding var fadeIn: Double
    @Binding var fadeOut: Double
    @Binding var fadeCurve: FadeCurve
    let fadeDuration: TimeInterval
    let hasFadeApplied: Bool
    let onApplyFade: (TimeInterval, TimeInterval, FadeCurve) -> Void
    let onRemoveFade: () -> Void

    // Peak
    @Binding var peakTarget: Float
    let hasPeakApplied: Bool
    let onApplyPeak: (Float) -> Void
    let onRemovePeak: () -> Void

    // Gate
    @Binding var gateThreshold: Float
    let hasGateApplied: Bool
    let onApplyGate: (Float) -> Void
    let onRemoveGate: () -> Void

    // Compress
    @Binding var compGain: Float
    @Binding var compReduction: Float
    let hasCompressApplied: Bool
    let onApplyCompress: (Float, Float) -> Void
    let onRemoveCompress: () -> Void

    // Reverb
    @Binding var reverbRoomSize: Float
    @Binding var reverbPreDelay: Float
    @Binding var reverbDecay: Float
    @Binding var reverbDamping: Float
    @Binding var reverbWetDry: Float
    let hasReverbApplied: Bool
    let onApplyReverb: (Float, Float, Float, Float, Float) -> Void
    let onRemoveReverb: () -> Void

    // Echo
    @Binding var echoDelay: Float
    @Binding var echoFeedback: Float
    @Binding var echoDamping: Float
    @Binding var echoWetDry: Float
    let hasEchoApplied: Bool
    let onApplyEcho: (Float, Float, Float, Float) -> Void
    let onRemoveEcho: () -> Void

    let onClose: () -> Void

    private var maxFade: Double { min(5.0, fadeDuration / 2) }

    private func isApplied(for tool: EditToolType) -> Bool {
        switch tool {
        case .fade: return hasFadeApplied
        case .peak: return hasPeakApplied
        case .gate: return hasGateApplied
        case .compress: return hasCompressApplied
        case .reverb: return hasReverbApplied
        case .echo: return hasEchoApplied
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Grab handle
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.textTertiary.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 6)

            // Tool tabs
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(EditToolType.allCases) { tool in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedTool = tool
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: tool.icon)
                                    .font(.system(size: 11))
                                Text(tool.displayName)
                                    .font(.system(size: 12, weight: .medium))
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .foregroundColor(selectedTool == tool ? .white : (isApplied(for: tool) ? palette.accent : palette.textPrimary))
                            .background(selectedTool == tool ? palette.accent : (isApplied(for: tool) ? palette.accent.opacity(0.15) : palette.inputBackground))
                            .cornerRadius(12)
                        }
                    }
                }
                .padding(.horizontal, 12)
            }

            Divider()
                .padding(.top, 6)

            // Tool content
            ScrollView {
                toolContent
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
            .frame(maxHeight: 190)

            Divider()

            // Action buttons
            HStack(spacing: 10) {
                // Apply
                Button {
                    applyCurrentTool()
                } label: {
                    Text("Apply")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .foregroundColor(.white)
                        .background(palette.accent)
                        .cornerRadius(10)
                }
                .disabled(isProcessing || !canApplyCurrentTool)

                // Remove (only if applied)
                if isApplied(for: selectedTool) {
                    Button {
                        removeCurrentTool()
                    } label: {
                        Text("Remove")
                            .font(.system(size: 14, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .foregroundColor(.red)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(10)
                    }
                    .disabled(isProcessing)
                }

                // Close
                Button {
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(10)
                        .foregroundColor(palette.textSecondary)
                        .background(palette.inputBackground)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.cardBackground.opacity(0.97))
                .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        )
    }

    // MARK: - Tool Content

    @ViewBuilder
    private var toolContent: some View {
        switch selectedTool {
        case .fade: fadeControls
        case .peak: peakControls
        case .gate: gateControls
        case .compress: compressControls
        case .reverb: reverbControls
        case .echo: echoControls
        }
    }

    private var fadeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowDouble("Fade In", value: $fadeIn, range: 0...maxFade, step: 0.1, display: String(format: "%.1fs", fadeIn))
            sliderRowDouble("Fade Out", value: $fadeOut, range: 0...maxFade, step: 0.1, display: String(format: "%.1fs", fadeOut))
            Picker("Curve", selection: $fadeCurve) {
                ForEach(FadeCurve.allCases) { curve in
                    Text(curve.displayName).tag(curve)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var peakControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowFloat("Target Peak", value: $peakTarget, range: -6...0, step: 0.1, display: String(format: "%.1f dB", peakTarget))
            Text("Adjusts volume so the loudest peak reaches the target level.")
                .font(.caption2)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var gateControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowFloat("Threshold", value: $gateThreshold, range: -60...(-10), step: 1, display: String(format: "%.0f dB", gateThreshold))
            Text("Silences audio below the threshold. Removes background noise between phrases.")
                .font(.caption2)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var compressControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowFloat("Gain", value: $compGain, range: 0...10, step: 0.1, display: String(format: "%.1f dB", compGain))
            sliderRowFloat("Peak Reduction", value: $compReduction, range: 0...10, step: 0.1, display: String(format: "%.1f", compReduction))
        }
    }

    private var reverbControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowFloat("Room Size", value: $reverbRoomSize, range: 0.3...3.0, step: 0.1, display: String(format: "%.1f", reverbRoomSize))
            sliderRowFloat("Pre-Delay", value: $reverbPreDelay, range: 0...200, step: 1, display: String(format: "%.0f ms", reverbPreDelay))
            sliderRowFloat("Decay", value: $reverbDecay, range: 0.1...10, step: 0.1, display: String(format: "%.1fs", reverbDecay))
            sliderRowFloat("Damping", value: $reverbDamping, range: 0...1, step: 0.05, display: String(format: "%.0f%%", reverbDamping * 100))
            sliderRowFloat("Wet/Dry", value: $reverbWetDry, range: 0...1, step: 0.05, display: String(format: "%.0f%%", reverbWetDry * 100))
        }
    }

    private var echoControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowFloat("Delay", value: $echoDelay, range: 0.05...2.0, step: 0.01, display: String(format: "%.0f ms", echoDelay * 1000))
            sliderRowFloat("Feedback", value: $echoFeedback, range: 0...0.9, step: 0.05, display: String(format: "%.0f%%", echoFeedback * 100))
            sliderRowFloat("Damping", value: $echoDamping, range: 0...1, step: 0.05, display: String(format: "%.0f%%", echoDamping * 100))
            sliderRowFloat("Wet/Dry", value: $echoWetDry, range: 0...1, step: 0.05, display: String(format: "%.0f%%", echoWetDry * 100))
        }
    }

    // MARK: - Helpers

    private func sliderRowFloat(_ label: String, value: Binding<Float>, range: ClosedRange<Float>, step: Float, display: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(palette.accent)
        }
    }

    private func sliderRowDouble(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double, display: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundColor(palette.textSecondary)
            }
            Slider(value: value, in: range, step: step)
                .tint(palette.accent)
        }
    }

    // MARK: - Actions

    private var canApplyCurrentTool: Bool {
        switch selectedTool {
        case .fade: return fadeIn > 0 || fadeOut > 0
        case .peak: return true
        case .gate: return true
        case .compress: return compGain > 0 || compReduction > 0
        case .reverb: return reverbWetDry > 0
        case .echo: return echoWetDry > 0
        }
    }

    private func applyCurrentTool() {
        switch selectedTool {
        case .fade: onApplyFade(fadeIn, fadeOut, fadeCurve)
        case .peak: onApplyPeak(peakTarget)
        case .gate: onApplyGate(gateThreshold)
        case .compress: onApplyCompress(compGain, compReduction)
        case .reverb: onApplyReverb(reverbRoomSize, reverbPreDelay, reverbDecay, reverbDamping, reverbWetDry)
        case .echo: onApplyEcho(echoDelay, echoFeedback, echoDamping, echoWetDry)
        }
    }

    private func removeCurrentTool() {
        switch selectedTool {
        case .fade: onRemoveFade()
        case .peak: onRemovePeak()
        case .gate: onRemoveGate()
        case .compress: onRemoveCompress()
        case .reverb: onRemoveReverb()
        case .echo: onRemoveEcho()
        }
    }
}

// MARK: - Legacy AudioEditToolsPanel (kept for compatibility)

struct AudioEditToolsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var isProcessing: Bool

    let onFade: (TimeInterval, TimeInterval, FadeCurve) -> Void
    let onNormalize: (Float) -> Void
    let onNoiseGate: (Float) -> Void

    var body: some View {
        NavigationStack {
            List {
                Text("Use the Fade, Peak, and Gate buttons in the toolbar.")
                    .foregroundColor(palette.textSecondary)
            }
            .navigationTitle("Audio Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
