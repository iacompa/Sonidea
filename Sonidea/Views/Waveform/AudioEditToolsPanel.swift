//
//  AudioEditToolsPanel.swift
//  Sonidea
//
//  Edit tool button, fade curve overlay, tool type enum, and slide-up tools panel.
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

        // Pre-compute curve points once (avoids calling curve.apply() twice per step)
        var curvePoints = [(x: CGFloat, y: CGFloat)]()
        curvePoints.reserveCapacity(steps + 1)

        for i in 0...steps {
            let t = Float(i) / Float(steps)
            let x = startX + CGFloat(t) * regionWidth
            let gain = isFadeIn ? curve.apply(t) : curve.apply(1.0 - t)
            // curveY: where gain=0 -> y=height (full dark), gain=1 -> y=0 (no dark)
            let curveY = height * (1.0 - CGFloat(gain))
            curvePoints.append((x: x, y: curveY))
        }

        // Build the darkened area above the gain curve using cached points
        var curvePath = Path()
        curvePath.move(to: CGPoint(x: startX, y: 0))
        for pt in curvePoints {
            curvePath.addLine(to: CGPoint(x: pt.x, y: pt.y))
        }
        curvePath.addLine(to: CGPoint(x: endX, y: 0))
        curvePath.closeSubpath()

        // Fill with semi-transparent dark overlay (represents volume reduction)
        context.fill(curvePath, with: .color(Color.black.opacity(0.35)))

        // Draw the gain curve line using the same cached points
        var linePath = Path()
        for (i, pt) in curvePoints.enumerated() {
            if i == 0 {
                linePath.move(to: CGPoint(x: pt.x, y: pt.y))
            } else {
                linePath.addLine(to: CGPoint(x: pt.x, y: pt.y))
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
    case eq, fade, peak, gate, compress, reverb, echo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .eq: return "EQ"
        case .fade: return "Fade"
        case .peak: return "Peak"
        case .gate: return "Gate"
        case .compress: return "Comp"
        case .reverb: return "Reverb"
        case .echo: return "Echo"
        }
    }

    var accessibilityName: String {
        switch self {
        case .eq: return "Equalizer"
        case .fade: return "Fade"
        case .peak: return "Normalize"
        case .gate: return "Noise Gate"
        case .compress: return "Compressor"
        case .reverb: return "Reverb"
        case .echo: return "Echo"
        }
    }

    var icon: String {
        switch self {
        case .eq: return "slider.horizontal.3"
        case .fade: return "waveform.path.ecg"
        case .peak: return "speaker.wave.3"
        case .gate: return "waveform.badge.minus"
        case .compress: return "waveform.badge.magnifyingglass"
        case .reverb: return "dot.radiowaves.left.and.right"
        case .echo: return "repeat"
        }
    }
}

// MARK: - Unified Edit Toolbar (scrollable buttons: Trim | Cut | Precision | -- | EQ | Fade | ...)

struct UnifiedEditToolbar: View {
    let canTrim: Bool
    let canCut: Bool
    let isProcessing: Bool
    @Binding var isPrecisionMode: Bool
    @Binding var activeEffect: EditToolType?
    let appliedEffects: Set<EditToolType>
    let isPro: Bool
    let onTrim: () -> Void
    let onCut: () -> Void
    let onProGate: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                // Trim
                EditActionButton(
                    icon: "crop",
                    label: "Trim",
                    isEnabled: canTrim && !isProcessing,
                    style: .primary,
                    action: onTrim
                )

                // Cut
                EditActionButton(
                    icon: "scissors",
                    label: "Cut",
                    isEnabled: canCut && !isProcessing,
                    style: .destructive,
                    action: onCut
                )

                // Precision
                HoldForPrecisionButton(isPrecisionMode: $isPrecisionMode)

                // Divider
                Rectangle()
                    .fill(palette.stroke.opacity(0.3))
                    .frame(width: 1, height: 24)
                    .padding(.horizontal, 2)

                // Effect buttons
                ForEach(EditToolType.allCases) { tool in
                    effectToolButton(tool)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func effectToolButton(_ tool: EditToolType) -> some View {
        Button {
            if !isPro {
                onProGate()
                return
            }
            withAnimation(.easeInOut(duration: 0.15)) {
                if activeEffect == tool {
                    activeEffect = nil
                } else {
                    activeEffect = tool
                }
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: tool.icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(tool.displayName)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .foregroundColor(buttonForeground(for: tool))
            .background(buttonBackground(for: tool))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(buttonBorder(for: tool), lineWidth: activeEffect == tool ? 0 : 1)
            )
            .overlay(alignment: .topTrailing) {
                // Applied-effect dot indicator
                if appliedEffects.contains(tool) && activeEffect != tool {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 6, height: 6)
                        .offset(x: -2, y: 2)
                }
            }
        }
        .disabled(isProcessing)
        .accessibilityLabel("\(tool.accessibilityName) effect\(appliedEffects.contains(tool) ? ", applied" : "")")
    }

    private func buttonForeground(for tool: EditToolType) -> Color {
        if activeEffect == tool { return .white }
        if !isPro { return palette.textTertiary }
        if appliedEffects.contains(tool) { return palette.accent }
        return palette.accent
    }

    private func buttonBackground(for tool: EditToolType) -> Color {
        if activeEffect == tool { return palette.accent }
        if !isPro { return palette.inputBackground }
        if appliedEffects.contains(tool) { return palette.accent.opacity(0.15) }
        return palette.accent.opacity(0.12)
    }

    private func buttonBorder(for tool: EditToolType) -> Color {
        if activeEffect == tool { return Color.clear }
        if !isPro { return Color.clear }
        return palette.accent.opacity(0.25)
    }
}

// MARK: - Effect Parameter Panel (auto-height, no chrome)

struct EffectParameterPanel: View {
    @Environment(\.themePalette) private var palette

    let activeEffect: EditToolType
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
    @Binding var compMix: Float
    let hasCompressApplied: Bool
    let onApplyCompress: (Float, Float, Float) -> Void
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

    // EQ (real-time playback, non-destructive)
    @Binding var eqSettings: EQSettings
    let onEQChanged: () -> Void

    // Per-tool debounce tasks
    @State private var debounceTasks: [EditToolType: Task<Void, Never>] = [:]

    // Debounce interval in nanoseconds (400ms)
    private let debounceNanos: UInt64 = 400_000_000

    private var maxFade: Double { min(5.0, fadeDuration / 2) }

    private func isApplied(for tool: EditToolType) -> Bool {
        switch tool {
        case .eq: return eqSettings != .flat
        case .fade: return hasFadeApplied
        case .peak: return hasPeakApplied
        case .gate: return hasGateApplied
        case .compress: return hasCompressApplied
        case .reverb: return hasReverbApplied
        case .echo: return hasEchoApplied
        }
    }

    // MARK: - Default values

    static let defaultFadeIn: Double = 0
    static let defaultFadeOut: Double = 0
    static let defaultFadeCurve: FadeCurve = .sCurve
    static let defaultPeakTarget: Float = -0.3
    static let defaultGateThreshold: Float = -40
    static let defaultCompGain: Float = 0
    static let defaultCompReduction: Float = 0
    static let defaultCompMix: Float = 1.0
    static let defaultReverbRoomSize: Float = 1.0
    static let defaultReverbPreDelay: Float = 20
    static let defaultReverbDecay: Float = 2.0
    static let defaultReverbDamping: Float = 0.5
    static let defaultReverbWetDry: Float = 0.3
    static let defaultEchoDelay: Float = 0.25
    static let defaultEchoFeedback: Float = 0.3
    static let defaultEchoDamping: Float = 0.3
    static let defaultEchoWetDry: Float = 0.3

    private var isCurrentToolDefault: Bool {
        switch activeEffect {
        case .eq:
            return eqSettings == .flat
        case .fade:
            return fadeIn == Self.defaultFadeIn && fadeOut == Self.defaultFadeOut && fadeCurve == Self.defaultFadeCurve
        case .peak:
            return peakTarget == Self.defaultPeakTarget
        case .gate:
            return gateThreshold == Self.defaultGateThreshold
        case .compress:
            return compGain == Self.defaultCompGain && compReduction == Self.defaultCompReduction && compMix == Self.defaultCompMix
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
        VStack(spacing: 8) {
            toolContent
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

            if !isCurrentToolDefault || isApplied(for: activeEffect) {
                resetButton
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.cardBackground.opacity(0.97))
                .shadow(color: .black.opacity(0.1), radius: 6, y: 2)
        )
        .modifier(ToolOnChangeModifier(
            selectedTool: activeEffect,
            onFadeChanged: debouncedApplyFade,
            onPeakChanged: debouncedApplyPeak,
            onGateChanged: debouncedApplyGate,
            onCompressChanged: debouncedApplyCompress,
            onReverbChanged: debouncedApplyReverb,
            onEchoChanged: debouncedApplyEcho,
            fadeIn: fadeIn, fadeOut: fadeOut, fadeCurve: fadeCurve,
            peakTarget: peakTarget,
            gateThreshold: gateThreshold,
            compGain: compGain, compReduction: compReduction, compMix: compMix,
            reverbRoomSize: reverbRoomSize, reverbPreDelay: reverbPreDelay,
            reverbDecay: reverbDecay, reverbDamping: reverbDamping, reverbWetDry: reverbWetDry,
            echoDelay: echoDelay, echoFeedback: echoFeedback,
            echoDamping: echoDamping, echoWetDry: echoWetDry
        ))
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

    // MARK: - Tool Content

    @ViewBuilder
    private var toolContent: some View {
        switch activeEffect {
        case .eq: eqControls
        case .fade: fadeControls
        case .peak: peakControls
        case .gate: gateControls
        case .compress: compressControls
        case .reverb: reverbControls
        case .echo: echoControls
        }
    }

    private var eqControls: some View {
        ParametricEQView(
            settings: $eqSettings,
            onSettingsChanged: {
                debouncedApplyEQ()
            }
        )
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
        HStack(spacing: 0) {
            VStack(spacing: 4) {
                Text("Gain")
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
                EQKnob(
                    value: $compGain,
                    range: 0...10,
                    color: palette.accent
                )
                Text(String(format: "%.1f dB", compGain))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("Reduction")
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
                EQKnob(
                    value: $compReduction,
                    range: 0...10,
                    color: palette.accent
                )
                Text(String(format: "%.1f", compReduction))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 4) {
                Text("Mix")
                    .font(.caption2)
                    .foregroundColor(palette.textSecondary)
                EQKnob(
                    value: $compMix,
                    range: 0...1,
                    color: palette.accent
                )
                Text(String(format: "%.0f%%", compMix * 100))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var reverbControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Room")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $reverbRoomSize,
                        range: 0.3...3.0,
                        color: palette.accent
                    )
                    Text(String(format: "%.1f", reverbRoomSize))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Pre-Delay")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $reverbPreDelay,
                        range: 0...200,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f ms", reverbPreDelay))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Decay")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $reverbDecay,
                        range: 0.1...10,
                        color: palette.accent
                    )
                    Text(String(format: "%.1fs", reverbDecay))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Damping")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $reverbDamping,
                        range: 0...1,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f%%", reverbDamping * 100))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Wet/Dry")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $reverbWetDry,
                        range: 0...1,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f%%", reverbWetDry * 100))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                // Spacer column to balance the 3-2 layout
                Color.clear
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var echoControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Delay")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $echoDelay,
                        range: 0.05...2.0,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f ms", echoDelay * 1000))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Feedback")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $echoFeedback,
                        range: 0...0.9,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f%%", echoFeedback * 100))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Damping")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $echoDamping,
                        range: 0...1,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f%%", echoDamping * 100))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Wet/Dry")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $echoWetDry,
                        range: 0...1,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f%%", echoWetDry * 100))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }
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

    private func cancelAllDebounceTasks() {
        for task in debounceTasks.values { task.cancel() }
        debounceTasks.removeAll()
    }

    private func debouncedApplyEQ() {
        debounceTasks[.eq]?.cancel()
        debounceTasks[.eq] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onEQChanged()
        }
    }

    private func debouncedApplyFade() {
        guard fadeIn > 0 || fadeOut > 0 else { return }
        debounceTasks[.fade]?.cancel()
        debounceTasks[.fade] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyFade(fadeIn, fadeOut, fadeCurve)
        }
    }

    private func debouncedApplyPeak() {
        debounceTasks[.peak]?.cancel()
        debounceTasks[.peak] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyPeak(peakTarget)
        }
    }

    private func debouncedApplyGate() {
        debounceTasks[.gate]?.cancel()
        debounceTasks[.gate] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyGate(gateThreshold)
        }
    }

    private func debouncedApplyCompress() {
        guard compGain > 0 || compReduction > 0 || compMix < 1.0 else { return }
        debounceTasks[.compress]?.cancel()
        debounceTasks[.compress] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyCompress(compGain, compReduction, compMix)
        }
    }

    private func debouncedApplyReverb() {
        guard reverbWetDry > 0 else { return }
        debounceTasks[.reverb]?.cancel()
        debounceTasks[.reverb] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyReverb(reverbRoomSize, reverbPreDelay, reverbDecay, reverbDamping, reverbWetDry)
        }
    }

    private func debouncedApplyEcho() {
        guard echoWetDry > 0 else { return }
        debounceTasks[.echo]?.cancel()
        debounceTasks[.echo] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyEcho(echoDelay, echoFeedback, echoDamping, echoWetDry)
        }
    }

    // MARK: - Reset Actions

    private func resetCurrentTool() {
        debounceTasks[activeEffect]?.cancel()
        debounceTasks[activeEffect] = nil
        switch activeEffect {
        case .eq:
            eqSettings = .flat
            onEQChanged()
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
            compMix = Self.defaultCompMix
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

// MARK: - Tool onChange Modifier

private struct ToolOnChangeModifier: ViewModifier {
    let selectedTool: EditToolType
    let onFadeChanged: () -> Void
    let onPeakChanged: () -> Void
    let onGateChanged: () -> Void
    let onCompressChanged: () -> Void
    let onReverbChanged: () -> Void
    let onEchoChanged: () -> Void

    // Values to observe
    let fadeIn: Double, fadeOut: Double, fadeCurve: FadeCurve
    let peakTarget: Float
    let gateThreshold: Float
    let compGain: Float, compReduction: Float, compMix: Float
    let reverbRoomSize: Float, reverbPreDelay: Float, reverbDecay: Float, reverbDamping: Float, reverbWetDry: Float
    let echoDelay: Float, echoFeedback: Float, echoDamping: Float, echoWetDry: Float

    func body(content: Content) -> some View {
        switch selectedTool {
        case .eq:
            content
        case .fade:
            content
                .onChange(of: fadeIn) { onFadeChanged() }
                .onChange(of: fadeOut) { onFadeChanged() }
                .onChange(of: fadeCurve) { onFadeChanged() }
        case .peak:
            content
                .onChange(of: peakTarget) { onPeakChanged() }
        case .gate:
            content
                .onChange(of: gateThreshold) { onGateChanged() }
        case .compress:
            content
                .onChange(of: compGain) { onCompressChanged() }
                .onChange(of: compReduction) { onCompressChanged() }
                .onChange(of: compMix) { onCompressChanged() }
        case .reverb:
            content
                .onChange(of: reverbRoomSize) { onReverbChanged() }
                .onChange(of: reverbPreDelay) { onReverbChanged() }
                .onChange(of: reverbDecay) { onReverbChanged() }
                .onChange(of: reverbDamping) { onReverbChanged() }
                .onChange(of: reverbWetDry) { onReverbChanged() }
        case .echo:
            content
                .onChange(of: echoDelay) { onEchoChanged() }
                .onChange(of: echoFeedback) { onEchoChanged() }
                .onChange(of: echoDamping) { onEchoChanged() }
                .onChange(of: echoWetDry) { onEchoChanged() }
        }
    }
}
