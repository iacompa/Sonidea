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

    @State private var debounceTask: Task<Void, Never>?

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
                    if isApplied || !isDefault {
                        Button {
                            debounceTask?.cancel()
                            fadeInDuration = Self.defaultFadeIn
                            fadeOutDuration = Self.defaultFadeOut
                            fadeCurve = Self.defaultCurve
                            if isApplied { onRemove() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }

                    if isProcessing {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("Processing...")
                                .font(.subheadline)
                                .foregroundColor(palette.textTertiary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Fade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        debounceTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onChange(of: fadeInDuration) { debouncedApply() }
            .onChange(of: fadeOutDuration) { debouncedApply() }
            .onChange(of: fadeCurve) { debouncedApply() }
        }
    }

    private func debouncedApply() {
        guard fadeInDuration > 0 || fadeOutDuration > 0 else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            onApply(fadeInDuration, fadeOutDuration, fadeCurve)
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

    @State private var debounceTask: Task<Void, Never>?

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
                    if isApplied || !isDefault {
                        Button {
                            debounceTask?.cancel()
                            normalizeTarget = Self.defaultTarget
                            if isApplied { onRemove() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }

                    if isProcessing {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("Processing...")
                                .font(.subheadline)
                                .foregroundColor(palette.textTertiary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Peak")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        debounceTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onChange(of: normalizeTarget) {
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    onApply(normalizeTarget)
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

    @State private var debounceTask: Task<Void, Never>?

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
                    if isApplied || !isDefault {
                        Button {
                            debounceTask?.cancel()
                            gateThreshold = Self.defaultThreshold
                            if isApplied { onRemove() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }

                    if isProcessing {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("Processing...")
                                .font(.subheadline)
                                .foregroundColor(palette.textTertiary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Gate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        debounceTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onChange(of: gateThreshold) {
                debounceTask?.cancel()
                debounceTask = Task {
                    try? await Task.sleep(nanoseconds: 400_000_000)
                    guard !Task.isCancelled else { return }
                    onApply(gateThreshold)
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

    @State private var debounceTask: Task<Void, Never>?

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
                    if isApplied || !isDefault {
                        Button {
                            debounceTask?.cancel()
                            makeupGain = Self.defaultGain
                            peakReduction = Self.defaultReduction
                            if isApplied { onRemove() }
                        } label: {
                            HStack {
                                Spacer()
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }

                    if isProcessing {
                        HStack {
                            Spacer()
                            ProgressView()
                                .padding(.trailing, 6)
                            Text("Processing...")
                                .font(.subheadline)
                                .foregroundColor(palette.textTertiary)
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Compress")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        debounceTask?.cancel()
                        dismiss()
                    }
                }
            }
            .onChange(of: makeupGain) { debouncedApply() }
            .onChange(of: peakReduction) { debouncedApply() }
        }
    }

    private func debouncedApply() {
        guard makeupGain > 0 || peakReduction > 0 else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            onApply(makeupGain, peakReduction)
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

    // Debounce task for real-time apply
    @State private var debounceTask: Task<Void, Never>?

    // Debounce interval in nanoseconds (400ms)
    private let debounceNanos: UInt64 = 400_000_000

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

    // MARK: - Default values for each tool

    private static let defaultFadeIn: Double = 0
    private static let defaultFadeOut: Double = 0
    private static let defaultFadeCurve: FadeCurve = .sCurve
    private static let defaultPeakTarget: Float = -0.3
    private static let defaultGateThreshold: Float = -40
    private static let defaultCompGain: Float = 0
    private static let defaultCompReduction: Float = 0
    private static let defaultReverbRoomSize: Float = 1.0
    private static let defaultReverbPreDelay: Float = 20
    private static let defaultReverbDecay: Float = 2.0
    private static let defaultReverbDamping: Float = 0.5
    private static let defaultReverbWetDry: Float = 0.3
    private static let defaultEchoDelay: Float = 0.25
    private static let defaultEchoFeedback: Float = 0.3
    private static let defaultEchoDamping: Float = 0.3
    private static let defaultEchoWetDry: Float = 0.3

    private var isCurrentToolDefault: Bool {
        switch selectedTool {
        case .fade:
            return fadeIn == Self.defaultFadeIn && fadeOut == Self.defaultFadeOut && fadeCurve == Self.defaultFadeCurve
        case .peak:
            return peakTarget == Self.defaultPeakTarget
        case .gate:
            return gateThreshold == Self.defaultGateThreshold
        case .compress:
            return compGain == Self.defaultCompGain && compReduction == Self.defaultCompReduction
        case .reverb:
            return reverbRoomSize == Self.defaultReverbRoomSize && reverbPreDelay == Self.defaultReverbPreDelay
                && reverbDecay == Self.defaultReverbDecay && reverbDamping == Self.defaultReverbDamping
                && reverbWetDry == Self.defaultReverbWetDry
        case .echo:
            return echoDelay == Self.defaultEchoDelay && echoFeedback == Self.defaultEchoFeedback
                && echoDamping == Self.defaultEchoDamping && echoWetDry == Self.defaultEchoWetDry
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            grabHandle
            toolTabs
            Divider().padding(.top, 6)
            toolScrollContent
            Divider()
            actionButtons
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.cardBackground.opacity(0.97))
                .shadow(color: .black.opacity(0.15), radius: 8, y: -2)
        )
    }

    private var grabHandle: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(palette.textTertiary.opacity(0.3))
            .frame(width: 36, height: 4)
            .padding(.top, 8)
            .padding(.bottom, 6)
    }

    private var toolTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(EditToolType.allCases) { tool in
                    toolTabButton(tool)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func toolTabButton(_ tool: EditToolType) -> some View {
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

    private var toolScrollContent: some View {
        ScrollView {
            toolContent
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(maxHeight: 190)
        .onChange(of: fadeIn) { debouncedApplyFade() }
        .onChange(of: fadeOut) { debouncedApplyFade() }
        .onChange(of: fadeCurve) { debouncedApplyFade() }
        .onChange(of: peakTarget) { debouncedApplyPeak() }
        .onChange(of: gateThreshold) { debouncedApplyGate() }
        .onChange(of: compGain) { debouncedApplyCompress() }
        .onChange(of: compReduction) { debouncedApplyCompress() }
        .onChange(of: reverbRoomSize) { debouncedApplyReverb() }
        .onChange(of: reverbPreDelay) { debouncedApplyReverb() }
        .onChange(of: reverbDecay) { debouncedApplyReverb() }
        .onChange(of: reverbDamping) { debouncedApplyReverb() }
        .onChange(of: reverbWetDry) { debouncedApplyReverb() }
        .onChange(of: echoDelay) { debouncedApplyEcho() }
        .onChange(of: echoFeedback) { debouncedApplyEcho() }
        .onChange(of: echoDamping) { debouncedApplyEcho() }
        .onChange(of: echoWetDry) { debouncedApplyEcho() }
    }

    private var actionButtons: some View {
        HStack(spacing: 10) {
            if !isCurrentToolDefault || isApplied(for: selectedTool) {
                resetButton
            }
            if isProcessing {
                processingIndicator
            }
            closeButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var resetButton: some View {
        Button {
            resetCurrentTool()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 12, weight: .semibold))
                Text("Reset")
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundColor(palette.textSecondary)
            .background(palette.inputBackground)
            .cornerRadius(10)
        }
        .disabled(isProcessing)
    }

    private var processingIndicator: some View {
        HStack(spacing: 6) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Processing...")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }

    private var closeButton: some View {
        Button {
            debounceTask?.cancel()
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

    // MARK: - Debounced Real-Time Apply

    private func debouncedApplyFade() {
        guard selectedTool == .fade else { return }
        guard fadeIn > 0 || fadeOut > 0 else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyFade(fadeIn, fadeOut, fadeCurve)
        }
    }

    private func debouncedApplyPeak() {
        guard selectedTool == .peak else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyPeak(peakTarget)
        }
    }

    private func debouncedApplyGate() {
        guard selectedTool == .gate else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyGate(gateThreshold)
        }
    }

    private func debouncedApplyCompress() {
        guard selectedTool == .compress else { return }
        guard compGain > 0 || compReduction > 0 else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyCompress(compGain, compReduction)
        }
    }

    private func debouncedApplyReverb() {
        guard selectedTool == .reverb else { return }
        guard reverbWetDry > 0 else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyReverb(reverbRoomSize, reverbPreDelay, reverbDecay, reverbDamping, reverbWetDry)
        }
    }

    private func debouncedApplyEcho() {
        guard selectedTool == .echo else { return }
        guard echoWetDry > 0 else { return }
        debounceTask?.cancel()
        debounceTask = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyEcho(echoDelay, echoFeedback, echoDamping, echoWetDry)
        }
    }

    // MARK: - Reset Actions

    private func resetCurrentTool() {
        debounceTask?.cancel()
        switch selectedTool {
        case .fade:
            if hasFadeApplied { onRemoveFade() }
            fadeIn = Self.defaultFadeIn
            fadeOut = Self.defaultFadeOut
            fadeCurve = Self.defaultFadeCurve
        case .peak:
            if hasPeakApplied { onRemovePeak() }
            peakTarget = Self.defaultPeakTarget
        case .gate:
            if hasGateApplied { onRemoveGate() }
            gateThreshold = Self.defaultGateThreshold
        case .compress:
            if hasCompressApplied { onRemoveCompress() }
            compGain = Self.defaultCompGain
            compReduction = Self.defaultCompReduction
        case .reverb:
            if hasReverbApplied { onRemoveReverb() }
            reverbRoomSize = Self.defaultReverbRoomSize
            reverbPreDelay = Self.defaultReverbPreDelay
            reverbDecay = Self.defaultReverbDecay
            reverbDamping = Self.defaultReverbDamping
            reverbWetDry = Self.defaultReverbWetDry
        case .echo:
            if hasEchoApplied { onRemoveEcho() }
            echoDelay = Self.defaultEchoDelay
            echoFeedback = Self.defaultEchoFeedback
            echoDamping = Self.defaultEchoDamping
            echoWetDry = Self.defaultEchoWetDry
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
