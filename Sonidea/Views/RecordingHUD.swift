//
//  RecordingHUD.swift
//  Sonidea
//

import AVFoundation
import SwiftUI

struct RecordingHUDCard: View {
    let duration: TimeInterval
    let liveSamples: [Float]
    var isPaused: Bool = false
    var onPause: (() -> Void)? = nil
    var onResume: (() -> Void)? = nil
    var onSave: (() -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette
    @Environment(AppState.self) private var appState
    @State private var isPulsing = false
    @State private var showRecordingControls = false

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private var currentInputName: String {
        AudioSessionManager.shared.currentInput?.portName ?? "Built-in Microphone"
    }

    /// Summary of non-default input settings
    private var inputSettingsSummary: String? {
        appState.appSettings.recordingInputSettings.summaryString
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header: Recording/Paused status + Timer + Menu button
            HStack(alignment: .center) {
                HStack(spacing: 10) {
                    if isPaused {
                        // Pause icon when paused
                        Image(systemName: "pause.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(palette.liveRecordingAccent)
                    } else {
                        // Pulsing circle when recording
                        Circle()
                            .fill(palette.recordButton)
                            .frame(width: 12, height: 12)
                            .scaleEffect(isPulsing ? 1.3 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)
                            .shadow(color: palette.recordButton.opacity(0.5), radius: isPulsing ? 6 : 2)
                    }

                    Text(isPaused ? "Paused" : "Recording")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.textPrimary)
                }

                Spacer()

                // Hamburger menu button for Recording Controls
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showRecordingControls = true
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(palette.textSecondary)
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Text(formattedDuration)
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(palette.liveRecordingAccent)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, inputSettingsSummary != nil ? 8 : 16)

            // Compact summary line for non-default settings
            if let summary = inputSettingsSummary {
                HStack {
                    Text(summary)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }

            // Waveform
            ZStack {
                if liveSamples.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(palette.textPrimary.opacity(0.05))
                        .frame(height: 56)
                } else {
                    LiveWaveformView(samples: liveSamples, accentColor: isPaused ? palette.textSecondary : palette.liveRecordingAccent)
                        .frame(height: 56)
                        .opacity(isPaused ? 0.5 : 1.0)
                }
            }
            .padding(.horizontal, 20)

            // Level meter (green → yellow → red with dB scale)
            LevelMeterBar(level: liveSamples.last ?? 0, isPaused: isPaused)
                .padding(.horizontal, 20)
                .padding(.top, 12)

            // Bottom row: Mic info + Controls
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "mic.fill")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.textSecondary)
                    Text(currentInputName)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                if isPaused {
                    // Paused state: Save + Resume buttons
                    pausedControlButtons
                } else {
                    // Recording state: Pause button + Level meter
                    recordingControlButtons
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(palette.useMaterials ? AnyShapeStyle(.thinMaterial) : AnyShapeStyle(palette.surface))
                .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.4 : 0.08), radius: 12, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(palette.stroke.opacity(0.3), lineWidth: 1)
        )
        .onAppear { isPulsing = !isPaused }
        .onChange(of: isPaused) { _, paused in
            isPulsing = !paused
        }
        .sheet(isPresented: $showRecordingControls) {
            RecordingControlsSheet()
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Recording Control Buttons

    private var recordingControlButtons: some View {
        HStack(spacing: 10) {
            // Pause button
            RecordingControlChip(
                icon: "pause.fill",
                label: "Pause",
                style: .secondary,
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onPause?()
                }
            )
        }
    }

    // MARK: - Paused Control Buttons

    private var pausedControlButtons: some View {
        HStack(spacing: 8) {
            // Save button (primary action)
            RecordingControlChip(
                icon: "checkmark",
                label: "Save",
                style: .primary,
                action: {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onSave?()
                }
            )

            // Resume button (secondary action)
            RecordingControlChip(
                icon: "play.fill",
                label: "Resume",
                style: .secondary,
                action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onResume?()
                }
            )
        }
    }
}

// MARK: - Recording Controls Sheet (Gain + Limiter)

struct RecordingControlsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @Environment(AppState.self) private var appState

    // Local state that syncs with appState
    @State private var gainDb: Float = 0
    @State private var limiterEnabled: Bool = false
    @State private var limiterCeilingDb: Float = -1

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // MARK: - Gain Section
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Gain")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        Text(gainDisplayString)
                            .font(.system(.body, design: .monospaced))
                            .fontWeight(.medium)
                            .foregroundColor(palette.accent)
                    }

                    HStack(spacing: 12) {
                        Text("-6")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

                        Slider(
                            value: Binding(
                                get: { gainDb },
                                set: { newValue in
                                    // Snap to 0.5 dB steps
                                    gainDb = (newValue * 2).rounded() / 2
                                    updateSettings()
                                }
                            ),
                            in: RecordingInputSettings.minGainDb...RecordingInputSettings.maxGainDb,
                            step: RecordingInputSettings.gainStep
                        )
                        .tint(palette.accent)

                        Text("+6")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Text("Adjusts input level before recording")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.surface)
                )

                // MARK: - Limiter Section
                VStack(alignment: .leading, spacing: 12) {
                    Toggle(isOn: Binding(
                        get: { limiterEnabled },
                        set: { newValue in
                            limiterEnabled = newValue
                            updateSettings()
                        }
                    )) {
                        Text("Limiter")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                    }
                    .tint(palette.accent)

                    if limiterEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Ceiling")
                                    .font(.subheadline)
                                    .foregroundColor(palette.textSecondary)
                                Spacer()
                                Text(ceilingDisplayString)
                                    .font(.system(.body, design: .monospaced))
                                    .fontWeight(.medium)
                                    .foregroundColor(palette.accent)
                            }

                            // Discrete ceiling picker
                            HStack(spacing: 8) {
                                ForEach(RecordingInputSettings.ceilingOptions, id: \.self) { ceiling in
                                    Button {
                                        limiterCeilingDb = ceiling
                                        updateSettings()
                                    } label: {
                                        Text(ceiling == 0 ? "0" : String(format: "%.0f", ceiling))
                                            .font(.system(.caption, design: .monospaced))
                                            .fontWeight(limiterCeilingDb == ceiling ? .bold : .regular)
                                            .frame(width: 36, height: 32)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(limiterCeilingDb == ceiling ? palette.accent : palette.background)
                                            )
                                            .foregroundColor(limiterCeilingDb == ceiling ? .white : palette.textPrimary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Text(limiterEnabled ? "Prevents clipping by limiting peaks" : "Enable to prevent audio clipping")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(palette.surface)
                )
                .animation(.easeInOut(duration: 0.2), value: limiterEnabled)

                Spacer()

                // Reset button
                if !isDefault {
                    Button {
                        gainDb = 0
                        limiterEnabled = false
                        limiterCeilingDb = -1
                        updateSettings()
                    } label: {
                        Text("Reset to Defaults")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
            .background(palette.background)
            .navigationTitle("Recording Controls")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            // Load current settings
            let settings = appState.appSettings.recordingInputSettings
            gainDb = settings.gainDb
            limiterEnabled = settings.limiterEnabled
            limiterCeilingDb = settings.limiterCeilingDb
        }
    }

    // MARK: - Helpers

    private var gainDisplayString: String {
        if gainDb > 0 {
            return String(format: "+%.1f dB", gainDb)
        } else if gainDb < 0 {
            return String(format: "%.1f dB", gainDb)
        } else {
            return "0 dB"
        }
    }

    private var ceilingDisplayString: String {
        if limiterCeilingDb == 0 {
            return "0 dB"
        } else {
            return String(format: "%.0f dB", limiterCeilingDb)
        }
    }

    private var isDefault: Bool {
        abs(gainDb) < 0.1 && !limiterEnabled
    }

    private func updateSettings() {
        var settings = appState.appSettings.recordingInputSettings
        settings.gainDb = gainDb
        settings.limiterEnabled = limiterEnabled
        settings.limiterCeilingDb = limiterCeilingDb

        // Update appState - this triggers live update in RecorderManager
        appState.appSettings.recordingInputSettings = settings
        appState.recorder.inputSettings = settings
    }
}

// MARK: - Level Meter Bar (professional DAW-style dB meter)

struct LevelMeterBar: View {
    let level: Float   // 0.0 – 1.0 normalized (represents -60 to +6 dB)
    var isPaused: Bool = false

    @Environment(\.themePalette) private var palette

    // Professional DAW dB color ranges:
    //   Green:  -60 dB to -12 dB  (safe recording level)
    //   Yellow: -12 dB to  -6 dB  (optimal level)
    //   Orange:  -6 dB to   0 dB  (hot)
    //   Red:      0 dB to  +6 dB  (clipping / over)

    // Meter range constants
    private let meterMinDB: Float = -60
    private let meterMaxDB: Float = 6

    // Color boundary dB values
    private let greenEndDB: Float = -12
    private let yellowEndDB: Float = -6
    private let orangeEndDB: Float = 0
    // Red ends at +6 dB

    // dB scale tick marks at key boundaries (positions computed from dB)
    private var scaleMarks: [(db: String, position: CGFloat)] {
        [
            ("-48", dbToPosition(-48)),
            ("-36", dbToPosition(-36)),
            ("-24", dbToPosition(-24)),
            ("-18", dbToPosition(-18)),
            ("-12", dbToPosition(-12)),
            ("-6",  dbToPosition(-6)),
            ("0",   dbToPosition(0)),
            ("+6",  dbToPosition(6)),
        ]
    }

    // Single flat color based on current peak level
    private var meterColor: Color {
        let greenEnd = dbToPosition(greenEndDB)   // -18 dB → ~0.70
        let yellowEnd = dbToPosition(yellowEndDB)  // -12 dB → ~0.80
        let orangeEnd = dbToPosition(orangeEndDB)  // -6 dB → ~0.90
        if displayLevel >= orangeEnd {
            return .red
        } else if displayLevel >= yellowEnd {
            return .orange
        } else if displayLevel >= greenEnd {
            return .yellow
        } else {
            return .green
        }
    }

    private let clipThreshold: Float = 60.0 / 66.0  // 0 dBFS triggers clip indicator (0 dB position in -60..+6 range)

    @State private var displayLevel: CGFloat = 0
    @State private var peakHoldLevel: CGFloat = 0
    @State private var isClipping = false
    @State private var clipTask: Task<Void, Never>?
    @State private var peakHoldTask: Task<Void, Never>?

    /// Convert a dB value (-60..+6) to a normalized position (0..1) on the meter.
    /// Uses a linear dB scale — since dB is already logarithmic, a linear mapping
    /// of dB values produces the correct perceptual spacing for a professional meter.
    private func dbToPosition(_ dB: Float) -> CGFloat {
        let clamped = max(meterMinDB, min(meterMaxDB, dB))
        return CGFloat((clamped - meterMinDB) / (meterMaxDB - meterMinDB))
    }

    /// Convert a normalized level (0..1, representing -60..+6 dB linearly)
    /// to a meter display position. Since the input is already in linear-dB space
    /// (computed in RecorderManager), we use it directly — no additional warping needed.
    private func levelToPosition(_ level: Float) -> CGFloat {
        return CGFloat(max(0, min(1, level)))
    }

    var body: some View {
        VStack(spacing: 2) {
            // Meter bar with gradient
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Background track with subtle segmented dB marks
                    Capsule()
                        .fill(Color.gray.opacity(0.15))

                    // Filled meter with single flat color based on level
                    Capsule()
                        .fill(meterColor)
                        .frame(width: max(0, min(displayLevel * width, width)))

                    // Peak hold indicator (thin white line that holds then decays)
                    if peakHoldLevel > 0.01 && !isPaused {
                        let peakX = min(peakHoldLevel * width, width - 1)
                        Rectangle()
                            .fill(Color.white.opacity(0.9))
                            .frame(width: 2, height: geo.size.height)
                            .position(x: peakX, y: geo.size.height / 2)
                            .shadow(color: .white.opacity(0.5), radius: 1)
                    }

                    // Clip dot at far right
                    if isClipping && !isPaused {
                        HStack {
                            Spacer()
                            Circle()
                                .fill(Color.red)
                                .frame(width: 6, height: 6)
                                .shadow(color: .red.opacity(0.8), radius: 3)
                        }
                    }

                    // dB tick lines at key boundaries
                    ForEach(scaleMarks, id: \.db) { mark in
                        let x = mark.position * width
                        Rectangle()
                            .fill(palette.textSecondary.opacity(0.3))
                            .frame(width: 1)
                            .position(x: min(x, width - 1), y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())

            // dB labels below the meter
            GeometryReader { geo in
                let width = geo.size.width
                // Show a subset of labels to avoid crowding
                let labelMarks: [(db: String, position: CGFloat)] = [
                    ("-48", dbToPosition(-48)),
                    ("-24", dbToPosition(-24)),
                    ("-12", dbToPosition(-12)),
                    ("-6",  dbToPosition(-6)),
                    ("0",   dbToPosition(0)),
                    ("+6",  dbToPosition(6)),
                ]
                ForEach(labelMarks, id: \.db) { mark in
                    let x = mark.position * width
                    Text(mark.db)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.textSecondary.opacity(0.6))
                        .position(x: min(max(x, 10), width - 8), y: 5)
                }
            }
            .frame(height: 10)
        }
        .animation(.easeOut(duration: 0.08), value: displayLevel)
        .onChange(of: level) { _, newLevel in
            let newDisplay = isPaused ? CGFloat(0) : levelToPosition(newLevel)
            displayLevel = newDisplay

            // Peak hold: capture new peaks, hold for 1.5 seconds, then drop
            if newDisplay > peakHoldLevel {
                peakHoldLevel = newDisplay
                // Reset the decay timer on each new peak
                peakHoldTask?.cancel()
                peakHoldTask = Task { @MainActor in
                    // Hold the peak for 1.5 seconds
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    guard !Task.isCancelled else { return }
                    // Decay the peak hold over ~500ms (10 steps)
                    for _ in 0..<10 {
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        guard !Task.isCancelled else { return }
                        peakHoldLevel = max(peakHoldLevel - 0.1, 0)
                    }
                    peakHoldLevel = 0
                }
            }

            // Hold clip indicator for 1 second after clipping detected
            if newLevel >= clipThreshold && !isPaused {
                isClipping = true
                clipTask?.cancel()
                clipTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    guard !Task.isCancelled else { return }
                    isClipping = false
                }
            }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                displayLevel = 0
                peakHoldLevel = 0
                isClipping = false
                peakHoldTask?.cancel()
                clipTask?.cancel()
            }
        }
    }
}

// MARK: - Recording Control Chip (Apple-like compact button)

private struct RecordingControlChip: View {
    let icon: String
    let label: String
    let style: ChipStyle
    let action: () -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    enum ChipStyle {
        case primary    // Accent-colored, for main actions like Save
        case secondary  // Neutral/subtle, for Pause/Resume
    }

    private var foregroundColor: Color {
        switch style {
        case .primary:
            return .white
        case .secondary:
            return palette.textPrimary
        }
    }

    private var backgroundColor: Color {
        switch style {
        case .primary:
            return palette.accent
        case .secondary:
            return colorScheme == .dark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.06)
        }
    }

    private var borderColor: Color {
        switch style {
        case .primary:
            return Color.clear
        case .secondary:
            return palette.separator.opacity(0.3)
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(label)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
            .overlay(
                Capsule()
                    .strokeBorder(borderColor, lineWidth: 0.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
