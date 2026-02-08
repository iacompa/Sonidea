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

            // Waveform - Apple Voice Memos style
            ZStack {
                // Background with subtle rounded container
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.textPrimary.opacity(0.03))
                    .frame(height: 72)

                if liveSamples.isEmpty {
                    // Subtle center line when no samples yet
                    Rectangle()
                        .fill(palette.textPrimary.opacity(0.08))
                        .frame(height: 1)
                } else {
                    LiveWaveformView(samples: liveSamples, accentColor: isPaused ? palette.textSecondary : palette.liveRecordingAccent)
                        .frame(height: 72)
                        .opacity(isPaused ? 0.5 : 1.0)
                        .animation(.easeOut(duration: 0.1), value: liveSamples.count)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
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
    let level: Float   // 0.0 – 1.0 normalized (represents -60 to +6 dB from RecorderManager)
    var isPaused: Bool = false

    @Environment(\.themePalette) private var palette
    @Environment(AppState.self) private var appState

    // Input level mapping: level 0.0 = -60 dB, level 1.0 = +6 dB (66 dB range from RecorderManager)
    private let inputMinDB: Float = -60
    private let inputMaxDB: Float = 6

    // Visible meter range: -48 to 0 dB
    // Below -48 = bar is empty. At/above 0 = bar is full + clip indicator.
    private let meterMinDB: Float = -48
    private let meterMaxDB: Float = 0

    // Color boundaries:
    //   Green:  -48 to -12 dB (safe)
    //   Yellow: -12 to  -6 dB (optimal)
    //   Orange:  -6 to  -3 dB (hot)
    //   Red:     -3 to   0 dB (near clipping)

    // Limiter ceiling drag range
    private let limiterMinDB: Float = -6
    private let limiterMaxDB: Float = 0

    // Tick marks at key dB boundaries
    private var scaleMarks: [(db: String, position: CGFloat)] {
        [
            ("-36", dbToPosition(-36)),
            ("-24", dbToPosition(-24)),
            ("-12", dbToPosition(-12)),
            ("-6",  dbToPosition(-6)),
            ("0",   dbToPosition(0)),
        ]
    }

    // Meter color based on current dB level
    private var meterColor: Color {
        let dB = displayLevelDb
        if dB >= -3 {
            return .red
        } else if dB >= -6 {
            return .orange
        } else if dB >= -12 {
            return .yellow
        } else {
            return .green
        }
    }

    // Current display level in dB (for color logic)
    private var displayLevelDb: Float {
        Float(displayLevel) * (meterMaxDB - meterMinDB) + meterMinDB
    }

    @State private var displayLevel: CGFloat = 0
    @State private var peakHoldLevel: CGFloat = 0
    @State private var isClipping = false
    @State private var clipTask: Task<Void, Never>?
    @State private var peakHoldTask: Task<Void, Never>?

    // Limiter ceiling drag state
    @State private var isDraggingCeiling = false
    @State private var dragStartDb: Float?
    @State private var showCeilingLabel = false
    @State private var ceilingLabelTask: Task<Void, Never>?

    /// Convert a dB value to a normalized position (0..1) on the visible meter (-12..0).
    private func dbToPosition(_ dB: Float) -> CGFloat {
        let clamped = max(meterMinDB, min(meterMaxDB, dB))
        return CGFloat((clamped - meterMinDB) / (meterMaxDB - meterMinDB))
    }

    /// Convert a normalized meter position (0..1) back to dB value (-12..0)
    private func positionToDb(_ position: CGFloat) -> Float {
        return Float(position) * (meterMaxDB - meterMinDB) + meterMinDB
    }

    /// Convert input level (0..1 representing -60..+6 dB) to display position (0..1 on -12..0 range).
    /// Levels below -12 dB map to 0 (empty bar). Levels at/above 0 dB map to 1 (full bar).
    private func levelToPosition(_ level: Float) -> CGFloat {
        // Convert input level to dB
        let inputRange = inputMaxDB - inputMinDB  // 66
        let dB = Float(level) * inputRange + inputMinDB
        // Map to display range
        let displayRange = meterMaxDB - meterMinDB  // 12
        let position = (dB - meterMinDB) / displayRange
        return CGFloat(max(0, min(1, position)))
    }

    /// Check if the input level is at or above 0 dBFS (clipping)
    private func isLevelClipping(_ level: Float) -> Bool {
        let inputRange = inputMaxDB - inputMinDB
        let dB = Float(level) * inputRange + inputMinDB
        return dB >= 0
    }

    /// Snap a dB value to the nearest 0.5 dB increment, clamped to limiter range
    private func snapCeilingDb(_ dB: Float) -> Float {
        let clamped = max(limiterMinDB, min(limiterMaxDB, dB))
        return (clamped * 2).rounded() / 2
    }

    /// Current limiter ceiling dB from app state
    private var limiterCeilingDb: Float {
        appState.appSettings.recordingInputSettings.limiterCeilingDb
    }

    /// Whether the limiter is enabled
    private var limiterEnabled: Bool {
        appState.appSettings.recordingInputSettings.limiterEnabled
    }

    /// Format ceiling dB for display
    private var ceilingDisplayString: String {
        let db = limiterCeilingDb
        if db == 0 { return "0 dB" }
        return String(format: "%.1f dB", db)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Combined meter + limiter in a single geometry
            GeometryReader { geo in
                let width = geo.size.width
                let meterY: CGFloat = 22 // vertical center of the 4pt meter bar
                let meterHeight: CGFloat = 4

                ZStack(alignment: .topLeading) {
                    // ── Meter bar (centered at meterY) ──
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.gray.opacity(0.15))

                        // Filled meter
                        Capsule()
                            .fill(meterColor)
                            .frame(width: max(0, min(displayLevel * width, width)))

                        // Peak hold indicator
                        if peakHoldLevel > 0.01 && !isPaused {
                            let peakX = min(peakHoldLevel * width, width - 1)
                            Rectangle()
                                .fill(Color.white.opacity(0.9))
                                .frame(width: 2, height: meterHeight)
                                .position(x: peakX, y: meterHeight / 2)
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

                        // dB tick lines
                        ForEach(scaleMarks, id: \.db) { mark in
                            let x = mark.position * width
                            Rectangle()
                                .fill(palette.textSecondary.opacity(0.3))
                                .frame(width: 1, height: meterHeight)
                                .position(x: min(x, width - 1), y: meterHeight / 2)
                        }
                    }
                    .frame(height: meterHeight)
                    .clipShape(Capsule())
                    .offset(y: meterY - meterHeight / 2)

                    // ── Limiter ceiling handle ──
                    let ceilingPos = dbToPosition(limiterCeilingDb) * width
                    let handleX = min(max(ceilingPos, 6), width - 6)
                    let isActive = limiterEnabled || isDraggingCeiling

                    // Vertical line from handle down through meter
                    if isActive {
                        Rectangle()
                            .fill(Color.orange.opacity(isDraggingCeiling ? 0.9 : 0.5))
                            .frame(width: isDraggingCeiling ? 2 : 1.5, height: 28)
                            .position(x: handleX, y: meterY - 2)
                    }

                    // Handle pill — larger, clearly draggable
                    Group {
                        if isActive || showCeilingLabel {
                            // Active state: orange capsule with dB label
                            HStack(spacing: 2) {
                                if isDraggingCeiling || showCeilingLabel {
                                    Text(ceilingDisplayString)
                                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white)
                                        .transition(.opacity)
                                }
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                            }
                            .padding(.horizontal, isDraggingCeiling || showCeilingLabel ? 6 : 4)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(Color.orange)
                                    .shadow(color: Color.orange.opacity(0.4), radius: isDraggingCeiling ? 4 : 2)
                            )
                            .position(x: handleX, y: 8)
                            .animation(.easeInOut(duration: 0.15), value: isDraggingCeiling)
                            .animation(.easeInOut(duration: 0.15), value: showCeilingLabel)
                        } else {
                            // Inactive ghost: subtle capsule at 0 dB
                            let ghostX = min(max(dbToPosition(0) * width, 6), width - 6)
                            HStack(spacing: 2) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 7, weight: .medium))
                                    .foregroundColor(palette.textSecondary.opacity(0.3))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(
                                Capsule()
                                    .fill(palette.textSecondary.opacity(0.1))
                            )
                            .position(x: ghostX, y: 8)
                        }
                    }

                    // ── dB labels below meter ──
                    let labelMarks: [(db: String, position: CGFloat)] = [
                        ("-12", dbToPosition(-12)),
                        ("-6",  dbToPosition(-6)),
                        ("0",   dbToPosition(0)),
                    ]
                    ForEach(labelMarks, id: \.db) { mark in
                        let x = mark.position * width
                        Text(mark.db)
                            .font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundColor(palette.textSecondary.opacity(0.6))
                            .position(x: min(max(x, 10), width - 8), y: meterY + meterHeight / 2 + 7)
                    }
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if !isDraggingCeiling {
                                isDraggingCeiling = true
                                showCeilingLabel = true
                                dragStartDb = limiterCeilingDb
                                ceilingLabelTask?.cancel()
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            }
                            let normalizedX = value.location.x / width
                            let rawDb = positionToDb(normalizedX)
                            let snappedDb = snapCeilingDb(rawDb)

                            appState.appSettings.recordingInputSettings.limiterCeilingDb = snappedDb
                            if !appState.appSettings.recordingInputSettings.limiterEnabled {
                                appState.appSettings.recordingInputSettings.limiterEnabled = true
                            }
                            appState.recorder.inputSettings = appState.appSettings.recordingInputSettings
                        }
                        .onEnded { _ in
                            isDraggingCeiling = false
                            dragStartDb = nil
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            // Keep label visible for 2 seconds after release
                            ceilingLabelTask?.cancel()
                            ceilingLabelTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_000_000_000)
                                guard !Task.isCancelled else { return }
                                showCeilingLabel = false
                            }
                        }
                )
                .onTapGesture {
                    // Single tap toggles the dB label visibility
                    if limiterEnabled {
                        showCeilingLabel.toggle()
                        if showCeilingLabel {
                            ceilingLabelTask?.cancel()
                            ceilingLabelTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 3_000_000_000)
                                guard !Task.isCancelled else { return }
                                showCeilingLabel = false
                            }
                        }
                    }
                }
            }
            .frame(height: 34)
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
            if isLevelClipping(newLevel) && !isPaused {
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
