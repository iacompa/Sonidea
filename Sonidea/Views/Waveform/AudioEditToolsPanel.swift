//
//  AudioEditToolsPanel.swift
//  Sonidea
//
//  Edit tool button, fade curve overlay, tool type enum, and slide-up tools panel.
//

import SwiftUI

// MARK: - Effect Presets

struct ReverbPreset: Identifiable {
    let id: String
    let name: String
    let roomSize: Float
    let preDelay: Float
    let decay: Float
    let damping: Float
    let wetDry: Float
}

struct CompressPreset: Identifiable {
    let id: String
    let name: String
    let gain: Float
    let reduction: Float
    let mix: Float
}

struct EchoPreset: Identifiable {
    let id: String
    let name: String
    let delay: Float
    let feedback: Float
    let damping: Float
    let wetDry: Float
}

struct GatePreset: Identifiable {
    let id: String
    let name: String
    let threshold: Float
    let attack: Float
    let release: Float
    let hold: Float
    let floor: Float
}

struct EQPreset: Identifiable {
    let id: String
    let name: String
    let bands: [EQBandSettings]  // 4 bands
}

struct MasterPreset: Identifiable {
    let id: String
    let name: String
    let icon: String
    // Compression
    let compGain: Float
    let compReduction: Float
    let compMix: Float
    // Reverb
    let reverbRoomSize: Float
    let reverbPreDelay: Float
    let reverbDecay: Float
    let reverbDamping: Float
    let reverbWetDry: Float
    // Echo
    let echoDelay: Float
    let echoFeedback: Float
    let echoDamping: Float
    let echoWetDry: Float
}

enum EffectPresets {
    // MARK: - EQ Presets
    static let eq: [EQPreset] = [
        EQPreset(id: "eq1", name: "Vocal Presence", bands: [
            EQBandSettings(frequency: 100, gain: 0, q: 1.0),
            EQBandSettings(frequency: 400, gain: -1.5, q: 0.8),
            EQBandSettings(frequency: 3000, gain: 4, q: 1.2),
            EQBandSettings(frequency: 10000, gain: 2, q: 0.7)
        ]),
        EQPreset(id: "eq2", name: "Bass Boost", bands: [
            EQBandSettings(frequency: 80, gain: 6, q: 0.8),
            EQBandSettings(frequency: 250, gain: 3, q: 1.0),
            EQBandSettings(frequency: 2000, gain: 0, q: 1.0),
            EQBandSettings(frequency: 8000, gain: -1, q: 0.7)
        ]),
        EQPreset(id: "eq3", name: "Bright & Airy", bands: [
            EQBandSettings(frequency: 100, gain: -1, q: 1.0),
            EQBandSettings(frequency: 350, gain: -2.5, q: 0.9),
            EQBandSettings(frequency: 5000, gain: 3, q: 1.0),
            EQBandSettings(frequency: 12000, gain: 5, q: 0.6)
        ]),
        EQPreset(id: "eq4", name: "Warm & Smooth", bands: [
            EQBandSettings(frequency: 120, gain: 3, q: 0.7),
            EQBandSettings(frequency: 500, gain: 1, q: 1.0),
            EQBandSettings(frequency: 3000, gain: -1, q: 1.2),
            EQBandSettings(frequency: 8000, gain: -3.5, q: 0.6)
        ]),
        EQPreset(id: "eq5", name: "De-Mud", bands: [
            EQBandSettings(frequency: 80, gain: -2, q: 1.0),
            EQBandSettings(frequency: 300, gain: -4, q: 1.2),
            EQBandSettings(frequency: 4000, gain: 3.5, q: 1.0),
            EQBandSettings(frequency: 10000, gain: 2.5, q: 0.7)
        ]),
    ]

    // MARK: - Reverb Presets
    static let reverb: [ReverbPreset] = [
        ReverbPreset(id: "r1", name: "Small Room", roomSize: 0.4, preDelay: 5, decay: 0.5, damping: 0.6, wetDry: 0.2),
        ReverbPreset(id: "r2", name: "Concert Hall", roomSize: 2.0, preDelay: 30, decay: 3.0, damping: 0.4, wetDry: 0.3),
        ReverbPreset(id: "r3", name: "Cathedral", roomSize: 3.0, preDelay: 50, decay: 5.0, damping: 0.3, wetDry: 0.35),
        ReverbPreset(id: "r4", name: "Plate", roomSize: 0.8, preDelay: 10, decay: 1.5, damping: 0.7, wetDry: 0.25),
        ReverbPreset(id: "r5", name: "Ambient", roomSize: 1.5, preDelay: 40, decay: 4.0, damping: 0.5, wetDry: 0.15),
    ]

    // MARK: - Compression Presets
    static let compress: [CompressPreset] = [
        CompressPreset(id: "c1", name: "Gentle", gain: 1.0, reduction: 2.0, mix: 1.0),
        CompressPreset(id: "c2", name: "Vocal", gain: 2.5, reduction: 4.0, mix: 1.0),
        CompressPreset(id: "c3", name: "Punchy", gain: 3.5, reduction: 6.0, mix: 0.8),
        CompressPreset(id: "c4", name: "Broadcast", gain: 4.5, reduction: 7.5, mix: 1.0),
        CompressPreset(id: "c5", name: "Squash", gain: 4.5, reduction: 7.0, mix: 1.0),
    ]

    // MARK: - Echo Presets
    static let echo: [EchoPreset] = [
        EchoPreset(id: "e1", name: "Slapback", delay: 0.08, feedback: 0.1, damping: 0.2, wetDry: 0.3),
        EchoPreset(id: "e2", name: "Doubler", delay: 0.03, feedback: 0.05, damping: 0.1, wetDry: 0.2),
        EchoPreset(id: "e3", name: "Tape Echo", delay: 0.35, feedback: 0.45, damping: 0.6, wetDry: 0.25),
        EchoPreset(id: "e4", name: "Spacious", delay: 0.5, feedback: 0.5, damping: 0.4, wetDry: 0.2),
        EchoPreset(id: "e5", name: "Rhythmic", delay: 0.2, feedback: 0.6, damping: 0.3, wetDry: 0.3),
    ]

    // MARK: - Gate Presets
    static let gate: [GatePreset] = [
        GatePreset(id: "g1", name: "Light", threshold: -50, attack: 3, release: 80, hold: 60, floor: -20),
        GatePreset(id: "g2", name: "Voice", threshold: -40, attack: 5, release: 50, hold: 50, floor: -40),
        GatePreset(id: "g3", name: "Interview", threshold: -35, attack: 5, release: 60, hold: 80, floor: -30),
        GatePreset(id: "g4", name: "Podcast", threshold: -30, attack: 3, release: 40, hold: 40, floor: -60),
        GatePreset(id: "g5", name: "Aggressive", threshold: -25, attack: 2, release: 30, hold: 30, floor: -80),
    ]

    // MARK: - Master Presets (combined genre presets)
    static let master: [MasterPreset] = [
        // 1. Sonidea Signature — balanced warmth, polished
        MasterPreset(id: "m1", name: "Sonidea", icon: "waveform",
                     compGain: 2.0, compReduction: 3.5, compMix: 1.0,
                     reverbRoomSize: 1.0, reverbPreDelay: 20, reverbDecay: 1.8, reverbDamping: 0.5, reverbWetDry: 0.2,
                     echoDelay: 0.25, echoFeedback: 0.0, echoDamping: 0.3, echoWetDry: 0.0),
        // 2. Hip-Hop / Rap — punchy compression, tight room
        MasterPreset(id: "m2", name: "Hip-Hop", icon: "beats.headphones",
                     compGain: 3.0, compReduction: 5.0, compMix: 0.9,
                     reverbRoomSize: 0.4, reverbPreDelay: 5, reverbDecay: 0.4, reverbDamping: 0.7, reverbWetDry: 0.1,
                     echoDelay: 0.15, echoFeedback: 0.15, echoDamping: 0.5, echoWetDry: 0.08),
        // 3. Reggaeton — warm compression, medium hall, rhythmic echo
        MasterPreset(id: "m3", name: "Reggaeton", icon: "music.note.list",
                     compGain: 3.0, compReduction: 5.0, compMix: 1.0,
                     reverbRoomSize: 1.2, reverbPreDelay: 25, reverbDecay: 1.5, reverbDamping: 0.4, reverbWetDry: 0.2,
                     echoDelay: 0.22, echoFeedback: 0.35, echoDamping: 0.4, echoWetDry: 0.2),
        // 4. Pop Vocal — bright, polished, plate reverb
        MasterPreset(id: "m4", name: "Pop", icon: "star",
                     compGain: 2.5, compReduction: 4.5, compMix: 1.0,
                     reverbRoomSize: 0.8, reverbPreDelay: 15, reverbDecay: 1.2, reverbDamping: 0.6, reverbWetDry: 0.22,
                     echoDelay: 0.3, echoFeedback: 0.1, echoDamping: 0.3, echoWetDry: 0.08),
        // 5. R&B Smooth — warm reverb, gentle compression, subtle echo
        MasterPreset(id: "m5", name: "R&B", icon: "moon.stars",
                     compGain: 1.5, compReduction: 3.0, compMix: 1.0,
                     reverbRoomSize: 1.5, reverbPreDelay: 30, reverbDecay: 2.5, reverbDamping: 0.4, reverbWetDry: 0.25,
                     echoDelay: 0.4, echoFeedback: 0.2, echoDamping: 0.5, echoWetDry: 0.12),
        // 6. Lo-Fi — warm compression, damped echo, dark reverb
        MasterPreset(id: "m6", name: "Lo-Fi", icon: "radio",
                     compGain: 3.0, compReduction: 5.5, compMix: 0.9,
                     reverbRoomSize: 1.0, reverbPreDelay: 10, reverbDecay: 1.8, reverbDamping: 0.8, reverbWetDry: 0.15,
                     echoDelay: 0.3, echoFeedback: 0.3, echoDamping: 0.7, echoWetDry: 0.15),
        // 7. Robot — tight compression, metallic short echo
        MasterPreset(id: "m7", name: "Robot", icon: "cpu",
                     compGain: 4.0, compReduction: 6.5, compMix: 1.0,
                     reverbRoomSize: 0.3, reverbPreDelay: 0, reverbDecay: 0.2, reverbDamping: 0.9, reverbWetDry: 0.08,
                     echoDelay: 0.05, echoFeedback: 0.5, echoDamping: 0.1, echoWetDry: 0.3),
        // 8. Podcast — clean, tight compression, no effects
        MasterPreset(id: "m8", name: "Podcast", icon: "mic.badge.plus",
                     compGain: 3.0, compReduction: 5.5, compMix: 1.0,
                     reverbRoomSize: 1.0, reverbPreDelay: 20, reverbDecay: 2.0, reverbDamping: 0.5, reverbWetDry: 0.0,
                     echoDelay: 0.25, echoFeedback: 0.0, echoDamping: 0.3, echoWetDry: 0.0),
        // 9. Cinematic — cathedral reverb, gentle compression, long echo
        MasterPreset(id: "m9", name: "Cinematic", icon: "film",
                     compGain: 1.5, compReduction: 2.5, compMix: 1.0,
                     reverbRoomSize: 2.5, reverbPreDelay: 45, reverbDecay: 4.5, reverbDamping: 0.3, reverbWetDry: 0.3,
                     echoDelay: 0.6, echoFeedback: 0.35, echoDamping: 0.4, echoWetDry: 0.15),
        // 10. Live Stage — natural room, light compression
        MasterPreset(id: "m10", name: "Live", icon: "person.wave.2",
                     compGain: 1.0, compReduction: 2.0, compMix: 1.0,
                     reverbRoomSize: 1.8, reverbPreDelay: 20, reverbDecay: 2.0, reverbDamping: 0.5, reverbWetDry: 0.18,
                     echoDelay: 0.25, echoFeedback: 0.0, echoDamping: 0.3, echoWetDry: 0.0),
    ]
}

// MARK: - Preset Picker (horizontal stepper with arrows)

struct PresetPicker<P: Identifiable>: View {
    let presets: [P]
    let nameKeyPath: KeyPath<P, String>
    @Binding var selectedIndex: Int  // -1 = Default (no preset)
    let onSelect: (P?) -> Void

    @Environment(\.themePalette) private var palette

    private var displayName: String {
        if selectedIndex < 0 || selectedIndex >= presets.count {
            return "Default"
        }
        return presets[selectedIndex][keyPath: nameKeyPath]
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if selectedIndex <= -1 {
                    selectedIndex = presets.count - 1
                } else {
                    selectedIndex -= 1
                }
                onSelect(selectedIndex >= 0 ? presets[selectedIndex] : nil)
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.accent)
                    .frame(width: 24, height: 24)
                    .background(palette.accent.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)

            Text(displayName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(selectedIndex >= 0 ? palette.accent : palette.textSecondary)
                .frame(minWidth: 70)
                .lineLimit(1)

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                if selectedIndex >= presets.count - 1 {
                    selectedIndex = -1
                } else {
                    selectedIndex += 1
                }
                onSelect(selectedIndex >= 0 ? presets[selectedIndex] : nil)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(palette.accent)
                    .frame(width: 24, height: 24)
                    .background(palette.accent.opacity(0.12))
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
        }
    }
}

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
    let fadeInCurve: FadeCurve
    let fadeOutCurve: FadeCurve
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
                    isFadeIn: true,
                    curve: fadeInCurve
                )
            }

            // Draw fade-out shading
            if fadeOutDuration > 0 {
                drawFadeRegion(
                    context: context,
                    startX: fadeOutStartX,
                    endX: w,
                    height: h,
                    isFadeIn: false,
                    curve: fadeOutCurve
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
        isFadeIn: Bool,
        curve: FadeCurve
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
    case presets, eq, fade, peak, gate, compress, reverb, echo

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
        case .presets: return "Presets"
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
        case .presets: return "Master Presets"
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
        case .presets: return "sparkles"
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
        if tool == .presets { return .white }
        if appliedEffects.contains(tool) { return palette.accent }
        return palette.accent
    }

    private func buttonBackground(for tool: EditToolType) -> Color {
        if activeEffect == tool { return palette.accent }
        if !isPro { return palette.inputBackground }
        if tool == .presets { return palette.accent.opacity(0.7) }
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
    @Binding var fadeInCurve: FadeCurve
    @Binding var fadeOutCurve: FadeCurve
    let fadeDuration: TimeInterval
    let hasFadeApplied: Bool
    let onApplyFade: (TimeInterval, TimeInterval, FadeCurve, FadeCurve) -> Void
    let onRemoveFade: () -> Void

    // Peak / LUFS Normalize
    @Binding var normalizeMode: NormalizeMode
    @Binding var peakTarget: Float
    @Binding var lufsTarget: Float
    let hasPeakApplied: Bool
    let onApplyPeak: (NormalizeMode, Float) -> Void
    let onRemovePeak: () -> Void

    // Gate
    @Binding var gateThreshold: Float
    @Binding var gateAttack: Float
    @Binding var gateRelease: Float
    @Binding var gateHold: Float
    @Binding var gateFloor: Float
    let hasGateApplied: Bool
    let onApplyGate: (Float, Float, Float, Float, Float) -> Void
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

    // Combined preset (single atomic operation)
    let onApplyPreset: (AudioEditor.CombinedPresetParams) -> Void
    let onRemovePreset: () -> Void

    // Reset to Original
    let hasOriginalBackup: Bool
    let onResetToOriginal: () -> Void

    // Preset selection indices (-1 = default/no preset)
    @State private var gatePresetIndex: Int = -1
    @State private var compPresetIndex: Int = -1
    @State private var reverbPresetIndex: Int = -1
    @State private var echoPresetIndex: Int = -1
    @State private var eqPresetIndex: Int = -1
    @State private var masterPresetIndex: Int = -1

    // Per-tool debounce tasks (only used for EQ which is non-destructive real-time)
    @State private var debounceTasks: [EditToolType: Task<Void, Never>] = [:]

    // Debounce interval in nanoseconds (400ms) - only for EQ
    private let debounceNanos: UInt64 = 400_000_000

    // Reset to Original confirmation alert
    @State private var showResetToOriginalAlert = false

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
        case .presets: return masterPresetIndex >= 0
        }
    }

    // MARK: - Default values

    static let defaultFadeIn: Double = 0
    static let defaultFadeOut: Double = 0
    static let defaultFadeInCurve: FadeCurve = .sCurve
    static let defaultFadeOutCurve: FadeCurve = .sCurve
    static let defaultNormalizeMode: NormalizeMode = .peak
    static let defaultPeakTarget: Float = -0.3
    static let defaultLufsTarget: Float = -16.0
    static let defaultGateThreshold: Float = -40
    static let defaultGateAttack: Float = 5
    static let defaultGateRelease: Float = 50
    static let defaultGateHold: Float = 50
    static let defaultGateFloor: Float = -80
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
            return fadeIn == Self.defaultFadeIn && fadeOut == Self.defaultFadeOut && fadeInCurve == Self.defaultFadeInCurve && fadeOutCurve == Self.defaultFadeOutCurve
        case .peak:
            return normalizeMode == Self.defaultNormalizeMode && peakTarget == Self.defaultPeakTarget && lufsTarget == Self.defaultLufsTarget
        case .gate:
            return gateThreshold == Self.defaultGateThreshold && gateAttack == Self.defaultGateAttack
                && gateRelease == Self.defaultGateRelease && gateHold == Self.defaultGateHold
                && gateFloor == Self.defaultGateFloor
        case .compress:
            return compGain == Self.defaultCompGain && compReduction == Self.defaultCompReduction && compMix == Self.defaultCompMix
        case .reverb:
            return reverbRoomSize == Self.defaultReverbRoomSize && reverbPreDelay == Self.defaultReverbPreDelay
                && reverbDecay == Self.defaultReverbDecay && reverbDamping == Self.defaultReverbDamping
                && reverbWetDry == Self.defaultReverbWetDry
        case .echo:
            return echoDelay == Self.defaultEchoDelay && echoFeedback == Self.defaultEchoFeedback
                && echoDamping == Self.defaultEchoDamping && echoWetDry == Self.defaultEchoWetDry
        case .presets:
            return masterPresetIndex < 0
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

            if hasOriginalBackup && activeEffect == .presets {
                Button {
                    showResetToOriginalAlert = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Reset to Original")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundColor(.red)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
                }
                .disabled(isProcessing)
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
        .alert("Reset to Original", isPresented: $showResetToOriginalAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Reset", role: .destructive) {
                onResetToOriginal()
            }
        } message: {
            Text("This will discard all audio edits and restore the original recording. This cannot be undone.")
        }
        .modifier(ToolOnChangeModifier(
            selectedTool: activeEffect,
            onFadeChanged: debouncedApplyFade,
            onPeakChanged: debouncedApplyPeak,
            onGateChanged: debouncedApplyGate,
            onCompressChanged: debouncedApplyCompress,
            onReverbChanged: debouncedApplyReverb,
            onEchoChanged: debouncedApplyEcho,
            fadeIn: fadeIn, fadeOut: fadeOut, fadeInCurve: fadeInCurve, fadeOutCurve: fadeOutCurve,
            normalizeMode: normalizeMode, peakTarget: peakTarget, lufsTarget: lufsTarget,
            gateThreshold: gateThreshold, gateAttack: gateAttack, gateRelease: gateRelease, gateHold: gateHold, gateFloor: gateFloor,
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
        case .presets: presetsControls
        }
    }

    private var eqControls: some View {
        VStack(spacing: 10) {
            PresetPicker(presets: EffectPresets.eq, nameKeyPath: \.name, selectedIndex: $eqPresetIndex) { preset in
                if let p = preset {
                    eqSettings = EQSettings(bands: p.bands)
                } else {
                    eqSettings = .flat
                }
                onEQChanged()
            }

            ParametricEQView(
                settings: $eqSettings,
                onSettingsChanged: {
                    eqPresetIndex = -1
                    debouncedApplyEQ()
                }
            )
        }
    }

    private var fadeControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            sliderRowDouble("Fade In", value: $fadeIn, range: 0...maxFade, step: 0.1, display: String(format: "%.1fs", fadeIn))
            Picker("In Curve", selection: $fadeInCurve) {
                ForEach(FadeCurve.allCases) { curve in
                    Text(curve.displayName).tag(curve)
                }
            }
            .pickerStyle(.segmented)

            sliderRowDouble("Fade Out", value: $fadeOut, range: 0...maxFade, step: 0.1, display: String(format: "%.1fs", fadeOut))
            Picker("Out Curve", selection: $fadeOutCurve) {
                ForEach(FadeCurve.allCases) { curve in
                    Text(curve.displayName).tag(curve)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var peakControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Mode", selection: $normalizeMode) {
                ForEach(NormalizeMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if normalizeMode == .peak {
                sliderRowFloat("Target Peak", value: $peakTarget, range: -6...0, step: 0.1, display: String(format: "%.1f dB", peakTarget))
                Text("Adjusts volume so the loudest peak reaches the target level.")
                    .font(.caption2)
                    .foregroundColor(palette.textTertiary)
            } else {
                sliderRowFloat("Target LUFS", value: $lufsTarget, range: -24...(-9), step: 0.5, display: String(format: "%.1f LUFS", lufsTarget))
                Text("Adjusts volume to match a target loudness (ITU-R BS.1770-4). -16 LUFS is standard for podcasts.")
                    .font(.caption2)
                    .foregroundColor(palette.textTertiary)
            }
        }
    }

    private var gateControls: some View {
        VStack(spacing: 10) {
        PresetPicker(presets: EffectPresets.gate, nameKeyPath: \.name, selectedIndex: $gatePresetIndex) { preset in
            if let p = preset {
                gateThreshold = p.threshold; gateAttack = p.attack; gateRelease = p.release
                gateHold = p.hold; gateFloor = p.floor
            } else {
                gateThreshold = Self.defaultGateThreshold; gateAttack = Self.defaultGateAttack
                gateRelease = Self.defaultGateRelease; gateHold = Self.defaultGateHold
                gateFloor = Self.defaultGateFloor
            }
        }
        VStack(spacing: 12) {
            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Threshold")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $gateThreshold,
                        range: -60...(-10),
                        color: palette.accent
                    )
                    Text(String(format: "%.0f dB", gateThreshold))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Floor")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $gateFloor,
                        range: -80...(-6),
                        color: palette.accent
                    )
                    Text(String(format: "%.0f dB", gateFloor))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Attack")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $gateAttack,
                        range: 1...50,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f ms", gateAttack))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 0) {
                VStack(spacing: 4) {
                    Text("Hold")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $gateHold,
                        range: 10...500,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f ms", gateHold))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity)

                VStack(spacing: 4) {
                    Text("Release")
                        .font(.caption2)
                        .foregroundColor(palette.textSecondary)
                    EQKnob(
                        value: $gateRelease,
                        range: 10...500,
                        color: palette.accent
                    )
                    Text(String(format: "%.0f ms", gateRelease))
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
        Text("Attenuates audio below the threshold. Removes background noise between phrases.")
            .font(.caption2)
            .foregroundColor(palette.textTertiary)
        }
    }

    private var compressControls: some View {
        VStack(spacing: 10) {
        PresetPicker(presets: EffectPresets.compress, nameKeyPath: \.name, selectedIndex: $compPresetIndex) { preset in
            if let p = preset {
                compGain = p.gain; compReduction = p.reduction; compMix = p.mix
            } else {
                compGain = Self.defaultCompGain; compReduction = Self.defaultCompReduction; compMix = Self.defaultCompMix
            }
        }
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
    }

    private var reverbControls: some View {
        VStack(spacing: 10) {
        PresetPicker(presets: EffectPresets.reverb, nameKeyPath: \.name, selectedIndex: $reverbPresetIndex) { preset in
            if let p = preset {
                reverbRoomSize = p.roomSize; reverbPreDelay = p.preDelay; reverbDecay = p.decay
                reverbDamping = p.damping; reverbWetDry = p.wetDry
            } else {
                reverbRoomSize = Self.defaultReverbRoomSize; reverbPreDelay = Self.defaultReverbPreDelay
                reverbDecay = Self.defaultReverbDecay; reverbDamping = Self.defaultReverbDamping
                reverbWetDry = Self.defaultReverbWetDry
            }
        }
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
    }

    private var echoControls: some View {
        VStack(spacing: 10) {
        PresetPicker(presets: EffectPresets.echo, nameKeyPath: \.name, selectedIndex: $echoPresetIndex) { preset in
            if let p = preset {
                echoDelay = p.delay; echoFeedback = p.feedback
                echoDamping = p.damping; echoWetDry = p.wetDry
            } else {
                echoDelay = Self.defaultEchoDelay; echoFeedback = Self.defaultEchoFeedback
                echoDamping = Self.defaultEchoDamping; echoWetDry = Self.defaultEchoWetDry
            }
        }
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
                        range: 0...0.95,
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
    }

    private var presetsControls: some View {
        VStack(spacing: 12) {
            Text("Master Presets")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(palette.textPrimary)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 10) {
                ForEach(Array(EffectPresets.master.enumerated()), id: \.element.id) { index, preset in
                    Button {
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        if masterPresetIndex == index {
                            // Deselect
                            masterPresetIndex = -1
                        } else {
                            masterPresetIndex = index
                            applyMasterPreset(preset)
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: preset.icon)
                                .font(.system(size: 16, weight: .medium))
                                .frame(width: 36, height: 36)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(masterPresetIndex == index ? palette.accent : palette.inputBackground)
                                )
                                .foregroundColor(masterPresetIndex == index ? .white : palette.textSecondary)
                            Text(preset.name)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(masterPresetIndex == index ? palette.accent : palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            if masterPresetIndex >= 0, masterPresetIndex < EffectPresets.master.count {
                let preset = EffectPresets.master[masterPresetIndex]
                VStack(spacing: 4) {
                    Text("Applies: Compression + Reverb + Echo")
                        .font(.system(size: 10))
                        .foregroundColor(palette.textTertiary)
                    Text("Comp \(String(format: "%.0f", preset.compGain))dB · Reverb \(String(format: "%.0f%%", preset.reverbWetDry * 100)) · Echo \(String(format: "%.0f%%", preset.echoWetDry * 100))")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundColor(palette.textSecondary)
                }
            }
        }
    }

    private func applyMasterPreset(_ preset: MasterPreset) {
        // Set all UI parameters for display
        compGain = preset.compGain
        compReduction = preset.compReduction
        compMix = preset.compMix
        reverbRoomSize = preset.reverbRoomSize
        reverbPreDelay = preset.reverbPreDelay
        reverbDecay = preset.reverbDecay
        reverbDamping = preset.reverbDamping
        reverbWetDry = preset.reverbWetDry
        echoDelay = preset.echoDelay
        echoFeedback = preset.echoFeedback
        echoDamping = preset.echoDamping
        echoWetDry = preset.echoWetDry

        // Reset per-effect preset indices
        compPresetIndex = -1
        reverbPresetIndex = -1
        echoPresetIndex = -1

        // Build combined params and apply as single atomic operation
        cancelAllDebounceTasks()
        let params = AudioEditor.CombinedPresetParams(
            compGain: preset.compGain,
            compReduction: preset.compReduction,
            compMix: preset.compMix,
            reverbRoomSize: preset.reverbRoomSize,
            reverbPreDelayMs: preset.reverbPreDelay,
            reverbDecay: preset.reverbDecay,
            reverbDamping: preset.reverbDamping,
            reverbWetDry: preset.reverbWetDry,
            echoDelay: preset.echoDelay,
            echoFeedback: preset.echoFeedback,
            echoDamping: preset.echoDamping,
            echoWetDry: preset.echoWetDry
        )
        onApplyPreset(params)
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
            onApplyFade(fadeIn, fadeOut, fadeInCurve, fadeOutCurve)
        }
    }

    private func debouncedApplyPeak() {
        debounceTasks[.peak]?.cancel()
        debounceTasks[.peak] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            let target = normalizeMode == .peak ? peakTarget : lufsTarget
            onApplyPeak(normalizeMode, target)
        }
    }

    private func debouncedApplyGate() {
        debounceTasks[.gate]?.cancel()
        debounceTasks[.gate] = Task {
            try? await Task.sleep(nanoseconds: debounceNanos)
            guard !Task.isCancelled else { return }
            onApplyGate(gateThreshold, gateAttack, gateRelease, gateHold, gateFloor)
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
            eqPresetIndex = -1
            onEQChanged()
        case .fade:
            if hasFadeApplied { onRemoveFade() }
            fadeIn = Self.defaultFadeIn
            fadeOut = Self.defaultFadeOut
            fadeInCurve = Self.defaultFadeInCurve
            fadeOutCurve = Self.defaultFadeOutCurve
        case .peak:
            if hasPeakApplied { onRemovePeak() }
            normalizeMode = Self.defaultNormalizeMode
            peakTarget = Self.defaultPeakTarget
            lufsTarget = Self.defaultLufsTarget
        case .gate:
            if hasGateApplied { onRemoveGate() }
            gateThreshold = Self.defaultGateThreshold
            gateAttack = Self.defaultGateAttack
            gateRelease = Self.defaultGateRelease
            gateHold = Self.defaultGateHold
            gateFloor = Self.defaultGateFloor
            gatePresetIndex = -1
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
        case .presets:
            masterPresetIndex = -1
            onRemovePreset()
            // Reset UI parameters to defaults
            compGain = Self.defaultCompGain
            compReduction = Self.defaultCompReduction
            compMix = Self.defaultCompMix
            compPresetIndex = -1
            reverbRoomSize = Self.defaultReverbRoomSize
            reverbPreDelay = Self.defaultReverbPreDelay
            reverbDecay = Self.defaultReverbDecay
            reverbDamping = Self.defaultReverbDamping
            reverbWetDry = Self.defaultReverbWetDry
            reverbPresetIndex = -1
            echoDelay = Self.defaultEchoDelay
            echoFeedback = Self.defaultEchoFeedback
            echoDamping = Self.defaultEchoDamping
            echoWetDry = Self.defaultEchoWetDry
            echoPresetIndex = -1
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
    let fadeIn: Double, fadeOut: Double, fadeInCurve: FadeCurve, fadeOutCurve: FadeCurve
    let normalizeMode: NormalizeMode, peakTarget: Float, lufsTarget: Float
    let gateThreshold: Float, gateAttack: Float, gateRelease: Float, gateHold: Float, gateFloor: Float
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
                .onChange(of: fadeInCurve) { onFadeChanged() }
                .onChange(of: fadeOutCurve) { onFadeChanged() }
        case .peak:
            content
                .onChange(of: normalizeMode) { onPeakChanged() }
                .onChange(of: peakTarget) { onPeakChanged() }
                .onChange(of: lufsTarget) { onPeakChanged() }
        case .gate:
            content
                .onChange(of: gateThreshold) { onGateChanged() }
                .onChange(of: gateAttack) { onGateChanged() }
                .onChange(of: gateRelease) { onGateChanged() }
                .onChange(of: gateHold) { onGateChanged() }
                .onChange(of: gateFloor) { onGateChanged() }
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
        case .presets:
            content
        }
    }
}
