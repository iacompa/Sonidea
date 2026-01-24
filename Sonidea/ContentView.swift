//
//  ContentView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Route Enum
enum AppRoute: String, CaseIterable {
    case recordings
    case map
}

// MARK: - Search Scope Enum
enum SearchScope: String, CaseIterable {
    case recordings
    case projects
    case albums

    var displayName: String {
        switch self {
        case .recordings: return "Recordings"
        case .projects: return "Projects"
        case .albums: return "Albums"
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) var palette
    @Environment(\.scenePhase) private var scenePhase
    @State private var currentRoute: AppRoute = .recordings
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showTipJar = false
    @State private var showAskPromptFromMain = false
    @State private var showThankYouToast = false
    @State private var showRecoveryAlert = false

    // Drag state for record button
    @State private var dragStartPosition: CGPoint = .zero
    @State private var isDragging = false

    // Long-press reset pill
    @State private var showResetPill = false

    // Layout constants
    private let topBarHeight: CGFloat = 72
    private let buttonDiameter: CGFloat = 80

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let containerSize = geometry.size

            // Compute bounds
            let radius = buttonDiameter / 2
            let padding: CGFloat = 12
            let minX = padding + radius
            let maxX = containerSize.width - padding - radius
            let minY = topBarHeight + padding + radius
            // Allow button to go very low - just above the home indicator with minimal margin
            let maxY = containerSize.height - radius - 8

            // Default position (bottom-center, just above home indicator)
            let defaultPosition = CGPoint(
                x: containerSize.width / 2,
                y: containerSize.height - radius - 24
            )

            // Current button position
            let buttonPosition = appState.recordButtonPosition ?? defaultPosition

            ZStack(alignment: .top) {
                // Layer 1: Main Content
                mainContentLayer(safeArea: safeArea)

                // Layer 2: Fixed Top Bar
                fixedTopBar(safeAreaTop: safeArea.top)

                // Layer 3: Floating Record Button (absolute positioned overlay)
                if currentRoute == .recordings {
                    floatingRecordButtonOverlay(
                        buttonPosition: buttonPosition,
                        defaultPosition: defaultPosition,
                        minX: minX, maxX: maxX,
                        minY: minY, maxY: maxY,
                        containerSize: containerSize,
                        safeArea: safeArea
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                // Store UI metrics for Settings to use
                appState.uiMetrics = UIMetrics(
                    containerSize: containerSize,
                    safeAreaInsets: safeArea,
                    topBarHeight: topBarHeight,
                    buttonDiameter: buttonDiameter
                )

                // Clamp position on appear (in case screen size changed)
                if let pos = appState.recordButtonPosition {
                    let clamped = appState.clampRecordButtonPosition(
                        pos,
                        containerSize: containerSize,
                        safeInsets: safeArea,
                        topBarHeight: topBarHeight,
                        buttonDiameter: buttonDiameter
                    )
                    if clamped != pos {
                        appState.recordButtonPosition = clamped
                        appState.persistRecordButtonPosition()
                    }
                }
            }
            .onChange(of: geometry.size) { _, newSize in
                // Update metrics when size changes
                appState.uiMetrics = UIMetrics(
                    containerSize: newSize,
                    safeAreaInsets: safeArea,
                    topBarHeight: topBarHeight,
                    buttonDiameter: buttonDiameter
                )

                // Clamp position when size changes
                if let pos = appState.recordButtonPosition {
                    let newMaxY = newSize.height - safeArea.bottom - padding - radius
                    let newMaxX = newSize.width - padding - radius
                    let clamped = appState.clampRecordButtonPosition(
                        pos,
                        containerSize: newSize,
                        safeInsets: safeArea,
                        topBarHeight: topBarHeight,
                        buttonDiameter: buttonDiameter
                    )
                    if clamped != pos {
                        appState.recordButtonPosition = clamped
                        appState.persistRecordButtonPosition()
                    }
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            SearchSheetView()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .sheet(isPresented: $showTipJar) {
            TipJarView()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .sheet(isPresented: $showAskPromptFromMain) {
            AskPromptSheet {
                showTipJar = true
            }
            .environment(appState)
            .environment(\.themePalette, palette)
            .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.hidden)
        }
        .onChange(of: appState.supportManager.shouldShowAskPromptSheet) { _, shouldShow in
            if shouldShow {
                showAskPromptFromMain = true
                appState.supportManager.shouldShowAskPromptSheet = false
            }
        }
        .onChange(of: appState.recorder.recordingState) { _, newState in
            appState.onRecordingStateChanged(isRecording: newState.isActive)
        }
        .onChange(of: appState.supportManager.shouldShowThankYouToast) { _, shouldShow in
            if shouldShow {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                    showThankYouToast = true
                }
                appState.supportManager.shouldShowThankYouToast = false
                // Auto-dismiss after 3 seconds
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showThankYouToast = false
                    }
                }
            }
        }
        .onAppear {
            appState.onAppBecameActive()
            // Check for recoverable recording from a crash
            if appState.recorder.checkForRecoverableRecording() != nil {
                showRecoveryAlert = true
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Auto-pause when going to background to preserve audio
            if newPhase == .background && appState.recorder.recordingState == .recording {
                appState.recorder.pauseRecording()
            }
        }
        .alert("Recover Recording?", isPresented: $showRecoveryAlert) {
            Button("Recover") {
                if let fileURL = appState.recorder.checkForRecoverableRecording() {
                    // Create a recording from the recovered file
                    let duration = getAudioDuration(url: fileURL) ?? 0
                    let rawData = RawRecordingData(
                        fileURL: fileURL,
                        createdAt: Date(),
                        duration: duration,
                        latitude: nil,
                        longitude: nil,
                        locationLabel: ""
                    )
                    appState.addRecording(from: rawData)
                    appState.recorder.dismissRecoverableRecording()
                }
            }
            Button("Discard", role: .destructive) {
                appState.recorder.dismissRecoverableRecording()
            }
        } message: {
            Text("A recording was interrupted. Would you like to recover it?")
        }
        .overlay(alignment: .top) {
            if showThankYouToast {
                ThankYouToast()
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .padding(.top, 60)
            }
        }
    }

    // Helper to get audio duration for recovered recordings
    private func getAudioDuration(url: URL) -> TimeInterval? {
        let asset = AVURLAsset(url: url)
        return asset.duration.seconds.isNaN ? nil : asset.duration.seconds
    }

    // MARK: - Floating Record Button Overlay

    @ViewBuilder
    private func floatingRecordButtonOverlay(
        buttonPosition: CGPoint,
        defaultPosition: CGPoint,
        minX: CGFloat, maxX: CGFloat,
        minY: CGFloat, maxY: CGFloat,
        containerSize: CGSize,
        safeArea: EdgeInsets
    ) -> some View {
        ZStack {
            // Tap catcher to dismiss reset pill
            if showResetPill {
                Color.black.opacity(0.001)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.15)) {
                            showResetPill = false
                        }
                    }
            }

            // Reset pill (anchored below button)
            if showResetPill {
                resetPillView(buttonPosition: buttonPosition, containerSize: containerSize, safeArea: safeArea)
            }

            // Save/Discard pill (shown when recording is paused)
            if appState.recorder.isPaused && !showResetPill {
                saveDiscardPillView(buttonPosition: buttonPosition, containerSize: containerSize, safeArea: safeArea)
            }

            // The floating record button
            VoiceMemosRecordButton()
                .frame(width: buttonDiameter, height: buttonDiameter)
                .contentShape(Circle().inset(by: -20)) // Larger hit area
                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.2), radius: isDragging ? 12 : 8, y: isDragging ? 6 : 4)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .position(buttonPosition)
                .highPriorityGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            // Detect if this is a drag (moved more than 5 points)
                            let distance = sqrt(
                                value.translation.width * value.translation.width +
                                value.translation.height * value.translation.height
                            )

                            if distance > 5 {
                                if !isDragging {
                                    // Starting drag - capture the current button position
                                    isDragging = true
                                    dragStartPosition = buttonPosition
                                    // Hide reset pill when dragging
                                    if showResetPill {
                                        showResetPill = false
                                    }
                                }

                                // Calculate new position from drag start + translation
                                let newX = dragStartPosition.x + value.translation.width
                                let newY = dragStartPosition.y + value.translation.height

                                // Clamp to bounds (smooth, no snapping)
                                let clampedX = min(max(newX, minX), maxX)
                                let clampedY = min(max(newY, minY), maxY)

                                // Update position directly (smooth movement)
                                appState.recordButtonPosition = CGPoint(x: clampedX, y: clampedY)
                            }
                        }
                        .onEnded { value in
                            if isDragging {
                                // Commit the final position
                                let newX = dragStartPosition.x + value.translation.width
                                let newY = dragStartPosition.y + value.translation.height
                                let clampedX = min(max(newX, minX), maxX)
                                let clampedY = min(max(newY, minY), maxY)

                                appState.recordButtonPosition = CGPoint(x: clampedX, y: clampedY)
                                appState.persistRecordButtonPosition()

                                isDragging = false
                            } else {
                                // Was a tap (no significant movement)
                                if !showResetPill {
                                    handleRecordTap()
                                }
                            }
                        }
                )
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .onEnded { _ in
                            if !isDragging {
                                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    showResetPill = true
                                }
                                // Auto-dismiss after 3 seconds
                                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        showResetPill = false
                                    }
                                }
                            }
                        }
                )
        }
    }

    // MARK: - Reset Pill View

    private func resetPillView(buttonPosition: CGPoint, containerSize: CGSize, safeArea: EdgeInsets) -> some View {
        let pillHeight: CGFloat = 40
        let spacing: CGFloat = 12
        let buttonBottom = buttonPosition.y + buttonDiameter / 2
        let spaceBelow = containerSize.height - safeArea.bottom - buttonBottom

        // Show above if not enough space below
        let showAbove = spaceBelow < (pillHeight + spacing + 20)
        let pillY = showAbove
            ? buttonPosition.y - buttonDiameter / 2 - spacing - pillHeight / 2
            : buttonPosition.y + buttonDiameter / 2 + spacing + pillHeight / 2

        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appState.resetRecordButtonPosition()
                showResetPill = false
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 13, weight: .semibold))
                Text("Reset position")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
            )
        }
        .buttonStyle(.plain)
        .position(x: buttonPosition.x, y: pillY)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
    }

    // MARK: - Save Pill View

    private func saveDiscardPillView(buttonPosition: CGPoint, containerSize: CGSize, safeArea: EdgeInsets) -> some View {
        let pillHeight: CGFloat = 44
        let spacing: CGFloat = 16
        let buttonBottom = buttonPosition.y + buttonDiameter / 2
        let spaceBelow = containerSize.height - safeArea.bottom - buttonBottom

        // Show above if not enough space below
        let showAbove = spaceBelow < (pillHeight + spacing + 20)
        let pillY = showAbove
            ? buttonPosition.y - buttonDiameter / 2 - spacing - pillHeight / 2
            : buttonPosition.y + buttonDiameter / 2 + spacing + pillHeight / 2

        return Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            saveRecording()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                Text("Save")
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(palette.accent)
                    .shadow(color: palette.accent.opacity(0.3), radius: 4, y: 2)
            )
        }
        .buttonStyle(.plain)
        .position(x: buttonPosition.x, y: pillY)
        .transition(.scale(scale: 0.9).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: appState.recorder.isPaused)
    }

    // MARK: - Main Content Layer

    @ViewBuilder
    private func mainContentLayer(safeArea: EdgeInsets) -> some View {
        switch currentRoute {
        case .recordings:
            palette.background
                .ignoresSafeArea()
                .overlay(
                    VStack(spacing: 0) {
                        Color.clear.frame(height: topBarHeight + 16)

                        if appState.recorder.isActive {
                            RecordingHUDCard(
                                duration: appState.recorder.currentDuration,
                                liveSamples: appState.recorder.liveMeterSamples,
                                isPaused: appState.recorder.isPaused
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        RecordingsListView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                )

        case .map:
            GPSInsightsMapView()
                .ignoresSafeArea()
        }
    }

    // MARK: - Fixed Top Bar

    private func fixedTopBar(safeAreaTop: CGFloat) -> some View {
        let isCustomTheme = appState.selectedTheme.isCustomTheme

        return VStack(spacing: 0) {
            topNavigationBar
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(
                    Rectangle()
                        .fill(toolbarBackgroundStyle(isCustomTheme: isCustomTheme))
                        .ignoresSafeArea(edges: .top)
                )
            Spacer()
        }
    }

    /// Returns the appropriate toolbar background style
    /// Custom themes: Use explicit palette.navigationBarBackground
    /// System theme: Use iOS defaults (material for map, system background for recordings)
    private func toolbarBackgroundStyle(isCustomTheme: Bool) -> AnyShapeStyle {
        if isCustomTheme {
            // Custom themes always use their explicit nav bar background
            return AnyShapeStyle(palette.navigationBarBackground)
        } else {
            // System theme uses iOS defaults
            if currentRoute == .map {
                return AnyShapeStyle(.ultraThinMaterial)
            } else {
                return AnyShapeStyle(Color(.systemBackground))
            }
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        let isCustomTheme = appState.selectedTheme.isCustomTheme

        // For custom themes: use effective toolbar text colors for consistency
        // For system theme: use palette.textPrimary (iOS defaults)
        let iconColor = isCustomTheme ? palette.effectiveToolbarTextPrimary : palette.textPrimary
        let activeIconColor = palette.accent

        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                        .frame(width: 44, height: 44)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { currentRoute = .map }
                } label: {
                    Image(systemName: "map.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(currentRoute == .map ? activeIconColor : iconColor)
                        .frame(width: 44, height: 44)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { currentRoute = .recordings }
                } label: {
                    Image(systemName: "waveform")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(currentRoute == .recordings ? activeIconColor : iconColor)
                        .frame(width: 44, height: 44)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                        .frame(width: 44, height: 44)
                }

                Button { showTipJar = true } label: {
                    Image(systemName: "heart.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(iconColor)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    // MARK: - Record Button Handler

    private func handleRecordTap() {
        switch appState.recorder.recordingState {
        case .idle:
            // Start new recording
            appState.recorder.startRecording()
        case .recording:
            // Pause the recording
            appState.recorder.pauseRecording()
        case .paused:
            // Resume the recording
            appState.recorder.resumeRecording()
        }
    }

    // MARK: - Save Recording

    private func saveRecording() {
        if let rawData = appState.recorder.stopRecording() {
            appState.addRecording(from: rawData)
            appState.onRecordingSaved()
            currentRoute = .recordings
        }
    }
}

// MARK: - Voice Memos Style Record Button (Plain View - no Button to avoid gesture conflicts)

struct VoiceMemosRecordButton: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPulsing = false
    @State private var goldRingRotation: Double = 0

    private var recordingState: RecordingState {
        appState.recorder.recordingState
    }

    private var isActive: Bool {
        recordingState.isActive
    }

    private var isRecording: Bool {
        recordingState == .recording
    }

    private var isPaused: Bool {
        recordingState == .paused
    }

    private var isSupporter: Bool {
        appState.supportManager.hasTippedBefore
    }

    // Theme-aware record button color
    private var recordColor: Color {
        palette.recordButton
    }

    // Gold gradient for supporter ring
    private var goldGradient: AngularGradient {
        AngularGradient(
            gradient: Gradient(colors: [
                Color(red: 1.0, green: 0.84, blue: 0.0),      // Gold
                Color(red: 1.0, green: 0.92, blue: 0.5),      // Light gold
                Color(red: 0.85, green: 0.65, blue: 0.13),    // Dark gold
                Color(red: 1.0, green: 0.84, blue: 0.0),      // Gold
            ]),
            center: .center,
            startAngle: .degrees(goldRingRotation),
            endAngle: .degrees(goldRingRotation + 360)
        )
    }

    var body: some View {
        ZStack {
            // Supporter gold ring (behind main button)
            if isSupporter {
                Circle()
                    .stroke(goldGradient, lineWidth: 3)
                    .frame(width: 92, height: 92)
                    .opacity(isActive ? 0.3 : 0.9)
                    .onAppear {
                        // Only animate if Reduce Motion is off
                        if !reduceMotion {
                            withAnimation(.linear(duration: 25).repeatForever(autoreverses: false)) {
                                goldRingRotation = 360
                            }
                        }
                    }
            }

            // Main recording ring - pulsing when recording, solid when paused
            Circle()
                .stroke(isActive ? recordColor : recordColor.opacity(0.3), lineWidth: 4)
                .frame(width: 80, height: 80)
                .scaleEffect(isRecording && isPulsing ? 1.08 : 1.0)
                .animation(
                    isRecording ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                    value: isPulsing
                )

            // Fill circle - solid when idle/recording, with pause indicator when paused
            Circle()
                .fill(recordColor)
                .frame(width: 68, height: 68)

            // Icon: mic when idle, pause when recording, play when paused
            Group {
                if isPaused {
                    // Play icon to resume
                    Image(systemName: "play.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                        .offset(x: 2) // Visually center the play icon
                } else if isRecording {
                    // Pause icon while recording
                    Image(systemName: "pause.fill")
                        .font(.system(size: 26, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    // Mic icon when idle
                    Image(systemName: "mic.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
        .contentShape(Circle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .onChange(of: isRecording) { _, newValue in
            isPulsing = newValue
        }
        .onAppear {
            isPulsing = isRecording
        }
    }

    private var accessibilityLabel: String {
        switch recordingState {
        case .idle:
            return "Start recording"
        case .recording:
            return "Pause recording"
        case .paused:
            return "Resume recording"
        }
    }
}

// MARK: - Thank You Toast

struct ThankYouToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.orange)

            Text("Thank you for supporting Sonidea!")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.primary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        )
        .accessibilityLabel("Thank you for supporting Sonidea")
    }
}

// MARK: - Premium Recording HUD Card

struct RecordingHUDCard: View {
    let duration: TimeInterval
    let liveSamples: [Float]
    var isPaused: Bool = false

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette
    @State private var isPulsing = false

    private var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private var currentInputName: String {
        AudioSessionManager.shared.currentInput?.portName ?? "Built-in Microphone"
    }

    var body: some View {
        VStack(spacing: 0) {
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

                Text(formattedDuration)
                    .font(.system(size: 34, weight: .medium, design: .monospaced))
                    .monospacedDigit()
                    .foregroundColor(palette.liveRecordingAccent)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            ZStack {
                if liveSamples.isEmpty {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(palette.textPrimary.opacity(0.05))
                        .frame(height: 56)
                } else {
                    LiveWaveformView(samples: liveSamples, accentColor: palette.liveRecordingAccent)
                        .frame(height: 56)
                }
            }
            .padding(.horizontal, 20)

            Rectangle()
                .fill(palette.separator)
                .frame(height: 1)
                .padding(.horizontal, 20)
                .padding(.top, 16)

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

                if let lastSample = liveSamples.last {
                    PremiumLevelMeter(level: lastSample)
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
    }
}

// MARK: - Premium Level Meter

struct PremiumLevelMeter: View {
    let level: Float

    private let barCount = 6
    private let barWidth: CGFloat = 3
    private let barSpacing: CGFloat = 2
    private let maxHeight: CGFloat = 16

    private func barHeight(at index: Int) -> CGFloat {
        let baseHeight: CGFloat = 4
        let increment = (maxHeight - baseHeight) / CGFloat(barCount - 1)
        return baseHeight + increment * CGFloat(index)
    }

    private func isActive(at index: Int) -> Bool {
        Float(index) / Float(barCount) <= level
    }

    private func barColor(at index: Int) -> Color {
        guard isActive(at: index) else { return Color(.systemGray4) }
        if index >= barCount - 1 { return .red }
        if index >= barCount - 2 { return .orange }
        return .green
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: barSpacing) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(barColor(at: index))
                    .frame(width: barWidth, height: barHeight(at: index))
            }
        }
    }
}

// MARK: - Legacy Level Indicator
struct LevelIndicator: View {
    let level: Float
    private var barCount: Int { 5 }

    private func barColor(at index: Int) -> Color {
        let threshold = Float(index) / Float(barCount)
        if level >= threshold {
            if index >= barCount - 1 { return .red }
            if index >= barCount - 2 { return .orange }
            return .green
        }
        return Color(.systemGray4)
    }

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(barColor(at: index))
                    .frame(width: 4, height: CGFloat(8 + index * 3))
            }
        }
    }
}

// MARK: - Placeholder Views
struct MapPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Map")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Recording locations will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Search Sheet View
struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var searchScope: SearchScope = .recordings
    @State private var searchQuery = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?
    @State private var selectedAlbum: Album?
    @State private var selectedProject: Project?

    private var recordingResults: [RecordingItem] {
        appState.searchRecordings(query: searchQuery, filterTagIDs: selectedTagIDs)
    }

    private var albumResults: [Album] {
        appState.searchAlbums(query: searchQuery)
    }

    private var projectResults: [Project] {
        appState.searchProjects(query: searchQuery)
    }

    private var searchPlaceholder: String {
        switch searchScope {
        case .recordings: return "Search recordings..."
        case .projects: return "Search projects..."
        case .albums: return "Search albums..."
        }
    }

    // MARK: - Stats

    private var totalRecordingCount: Int {
        appState.activeRecordings.count
    }

    private var totalStorageUsed: String {
        let totalBytes = appState.activeRecordings.reduce(into: Int64(0)) { result, recording in
            let url = recording.fileURL
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let fileSize = attrs[.size] as? Int64 {
                result += fileSize
            }
        }
        return formatBytes(totalBytes)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 12) {
                    // Stats header
                    HStack(spacing: 16) {
                        HStack(spacing: 4) {
                            Image(systemName: "waveform")
                                .font(.caption)
                            Text("\(totalRecordingCount) recordings")
                        }

                        HStack(spacing: 4) {
                            Image(systemName: "internaldrive")
                                .font(.caption)
                            Text(totalStorageUsed)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Picker("Search Scope", selection: $searchScope) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(palette.textSecondary)
                        TextField(searchPlaceholder, text: $searchQuery)
                            .foregroundColor(palette.textPrimary)
                    }
                    .padding(12)
                    .background(palette.inputBackground)
                    .cornerRadius(10)
                    .padding(.horizontal)

                    if searchScope == .recordings && !appState.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    TagFilterChip(tag: tag, isSelected: selectedTagIDs.contains(tag.id)) {
                                        if selectedTagIDs.contains(tag.id) {
                                            selectedTagIDs.remove(tag.id)
                                        } else {
                                            selectedTagIDs.insert(tag.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    switch searchScope {
                    case .recordings:
                        recordingsResultsView
                    case .projects:
                        projectsResultsView
                    case .albums:
                        albumsResultsView
                    }
                }
                .padding(.top)
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(item: $selectedAlbum) { album in
                AlbumDetailSheet(album: album)
            }
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(project: project)
            }
            .onChange(of: searchScope) { _, _ in
                if searchScope != .recordings { selectedTagIDs.removeAll() }
            }
        }
    }

    @ViewBuilder
    private var recordingsResultsView: some View {
        if recordingResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty && selectedTagIDs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your recordings")
                        .font(.headline)
                    Text("Search by title, notes, location, tags, or album")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No recordings found")
                        .font(.headline)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(recordingResults) { recording in
                    SearchResultRow(recording: recording)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRecording = recording }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var albumsResultsView: some View {
        if albumResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your albums")
                        .font(.headline)
                    Text("Find albums by name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No albums found")
                        .font(.headline)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(albumResults) { album in
                    AlbumSearchRow(album: album)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAlbum = album }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var projectsResultsView: some View {
        if projectResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your projects")
                        .font(.headline)
                    Text("Find projects by name or notes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No projects found")
                        .font(.headline)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(projectResults) { project in
                    ProjectSearchRow(project: project)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedProject = project }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Project Search Row

struct ProjectSearchRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) var palette
    let project: Project

    private var versionCount: Int {
        appState.recordingCount(in: project)
    }

    private var stats: ProjectStats {
        appState.stats(for: project)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundColor(palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    if project.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(palette.textSecondary)
                    }

                    if stats.hasBestTake {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(versionCount) version\(versionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    Text(stats.formattedTotalDuration)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Album Search Row

struct AlbumSearchRow: View {
    @Environment(AppState.self) var appState
    let album: Album

    private var recordingCount: Int {
        appState.recordingCount(in: album)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "square.stack.fill")
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray4))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(album.name)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Album Detail Sheet

struct AlbumDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let album: Album

    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?

    private var albumRecordings: [RecordingItem] {
        let recordings = appState.recordings(in: album)
        if selectedTagIDs.isEmpty { return recordings }
        return recordings.filter { !selectedTagIDs.isDisjoint(with: Set($0.tagIDs)) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    if !appState.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    TagFilterChip(tag: tag, isSelected: selectedTagIDs.contains(tag.id)) {
                                        if selectedTagIDs.contains(tag.id) {
                                            selectedTagIDs.remove(tag.id)
                                        } else {
                                            selectedTagIDs.insert(tag.id)
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                    }

                    if albumRecordings.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            Text(selectedTagIDs.isEmpty ? "No recordings in this album" : "No recordings match selected tags")
                                .font(.headline)
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(albumRecordings) { recording in
                                SearchResultRow(recording: recording)
                                    .contentShape(Rectangle())
                                    .onTapGesture { selectedRecording = recording }
                                    .listRowBackground(Color.clear)
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
                .padding(.top)
            }
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
        }
    }
}

// MARK: - Tag Filter Chip

struct TagFilterChip: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : tag.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tag.color : Color.clear)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tag.color, lineWidth: 1)
                )
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme
    let recording: RecordingItem

    private var recordingTags: [Tag] { appState.tags(for: recording.tagIDs) }
    private var album: Album? { appState.album(for: recording.albumID) }

    var body: some View {
        HStack(spacing: 12) {
            RecordingIconTile(recording: recording, colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let album = album {
                        Text("•").font(.caption).foregroundColor(.secondary)
                        Text(album.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                if !recordingTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recordingTags.prefix(3)) { tag in
                            TagChipSmall(tag: tag)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Settings Sheet
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var showShareSheet = false
    @State private var exportedZIPURL: URL?
    @State private var showAlbumPicker = false
    @State private var showTagManager = false
    @State private var showTrashView = false
    @State private var showEmptyTrashAlert = false
    @State private var showFileImporter = false
    @State private var showImportDestinationSheet = false
    @State private var pendingImportURLs: [URL] = []
    @State private var importErrors: [String] = []
    @State private var showImportErrorAlert = false

    @State private var showLockScreenHelp = false
    @State private var showActionButtonHelp = false
    @State private var showSiriShortcutsHelp = false

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            List {
                // MARK: Supporter Badge (if tipped)
                if appState.supportManager.hasTippedBefore {
                    Section {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Supporter")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(palette.textPrimary)
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(palette.cardBackground)
                    }
                }

                // MARK: Quick Access Section
                Section {
                    Button { showLockScreenHelp = true } label: {
                        HStack {
                            Image(systemName: "lock.rectangle.on.rectangle")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Lock Screen Widget")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Button { showActionButtonHelp = true } label: {
                        HStack {
                            Image(systemName: "button.horizontal.top.press")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Action Button")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Button { showSiriShortcutsHelp = true } label: {
                        HStack {
                            Image(systemName: "mic.badge.plus")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Siri & Shortcuts")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Quick Access")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Set up fast ways to start recording from anywhere.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: Record Button Position Section
                Section {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        appState.resetRecordButtonPosition()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset Record Button Position")
                                    .foregroundColor(palette.textPrimary)
                                Text("Moves the floating button back to the default location.")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }

                // MARK: How It Works Section
                Section {
                    NavigationLink {
                        TagsInfoView()
                    } label: {
                        SettingsInfoRow(icon: "tag", title: "Tags")
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        AlbumsInfoView()
                    } label: {
                        SettingsInfoRow(icon: "folder", title: "Albums")
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ProjectsInfoView()
                    } label: {
                        SettingsInfoRow(icon: "folder.badge.plus", title: "Projects")
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        MapsInfoView()
                    } label: {
                        SettingsInfoRow(icon: "map", title: "Maps")
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        RecordButtonInfoView()
                    } label: {
                        SettingsInfoRow(icon: "hand.draw", title: "Movable Record Button")
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        SearchInfoView()
                    } label: {
                        SettingsInfoRow(icon: "magnifyingglass", title: "Search")
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        AppearanceInfoView()
                    } label: {
                        SettingsInfoRow(icon: "paintpalette", title: "Appearance")
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("How it works")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: Recording Quality Section
                Section {
                    Picker("Quality", selection: $appState.appSettings.recordingQuality) {
                        ForEach(RecordingQualityPreset.allCases) { preset in
                            Text(preset.displayName).tag(preset)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Recording Quality")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text(appState.appSettings.recordingQuality.description)
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    let availableInputs = AudioSessionManager.shared.availableInputs
                    if availableInputs.count > 1 {
                        // Multiple inputs available - show picker
                        ForEach(availableInputs, id: \.uid) { input in
                            Button {
                                try? AudioSessionManager.shared.setPreferredInput(input)
                            } label: {
                                HStack {
                                    Image(systemName: inputIcon(for: input))
                                        .foregroundColor(palette.accent)
                                        .frame(width: 24)
                                    Text(input.portName)
                                        .foregroundColor(palette.textPrimary)
                                    Spacer()
                                    if AudioSessionManager.shared.currentInput?.uid == input.uid {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(palette.accent)
                                    }
                                }
                            }
                            .listRowBackground(palette.cardBackground)
                        }
                    } else {
                        // Single or no inputs - just show current
                        HStack {
                            Image(systemName: "mic.fill")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Current Input")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text(AudioSessionManager.shared.currentInput?.portName ?? "Default")
                                .foregroundColor(palette.textSecondary)
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Audio Input")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Select your preferred microphone for recording.")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Picker("Skip Interval", selection: $appState.appSettings.skipInterval) {
                        ForEach(SkipInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    HStack {
                        Text("Playback Speed")
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        Text(String(format: "%.1fx", appState.appSettings.playbackSpeed))
                            .foregroundColor(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Playback")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Toggle("Auto-Transcribe", isOn: $appState.appSettings.autoTranscribe)
                        .tint(palette.toggleOnTint)
                        .listRowBackground(palette.cardBackground)

                    Picker("Language", selection: $appState.appSettings.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Transcription")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Auto-transcribe new recordings when saved.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: Theme Section
                Section {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            appState.selectedTheme = theme
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.displayName)
                                        .font(.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(theme.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                if appState.selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Theme")
                        .foregroundStyle(palette.textSecondary)
                } footer: {
                    Text("Not all pages will change themes.")
                        .foregroundStyle(palette.textSecondary)
                }

                Section {
                    Picker("Appearance", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Light/Dark Mode")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Applies when using the System theme.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - iCloud Sync Section
                Section {
                    Toggle("iCloud Sync", isOn: $appState.appSettings.iCloudSyncEnabled)
                        .tint(palette.toggleOnTint)
                        .listRowBackground(palette.cardBackground)
                        .onChange(of: appState.appSettings.iCloudSyncEnabled) { _, enabled in
                            Task {
                                if enabled {
                                    await appState.syncManager.enableSync()
                                } else {
                                    appState.syncManager.disableSync()
                                }
                            }
                        }
                } header: {
                    Text("iCloud")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Sync recordings, tags, albums, and projects across all your devices.")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Button { showTagManager = true } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(palette.accent)
                            Text("Manage Tags")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(appState.tags.count)")
                                .foregroundColor(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Tags")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Button { exportAllRecordings() } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(palette.accent)
                            Text("Export All Recordings")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if isExporting && exportProgress == "all" {
                                ProgressView()
                                    .tint(palette.accent)
                            }
                        }
                    }
                    .disabled(isExporting || appState.activeRecordings.isEmpty)
                    .listRowBackground(palette.cardBackground)

                    Button { showAlbumPicker = true } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundColor(palette.accent)
                            Text("Export Album...")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if isExporting && exportProgress == "album" {
                                ProgressView()
                                    .tint(palette.accent)
                            }
                        }
                    }
                    .disabled(isExporting || appState.albums.isEmpty)
                    .listRowBackground(palette.cardBackground)

                    Button { showFileImporter = true } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(palette.accent)
                            Text("Import Recordings")
                                .foregroundColor(palette.textPrimary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Export & Import")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Export as WAV files in ZIP. Import m4a, wav, mp3, or aiff files.")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Button { showTrashView = true } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("View Trash")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(appState.trashedCount) items")
                                .foregroundColor(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Button(role: .destructive) { showEmptyTrashAlert = true } label: {
                        HStack {
                            Image(systemName: "trash.slash")
                            Text("Empty Trash Now")
                        }
                    }
                    .disabled(appState.trashedCount == 0)
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Trash")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Items in trash are automatically deleted after 30 days.")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(palette.textSecondary)
                        Text("Sonidea")
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        Text("1.0")
                            .foregroundColor(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("About")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Sync Now Button (Bottom of Settings)
                if appState.appSettings.iCloudSyncEnabled {
                    Section {
                        Button {
                            Task { await appState.syncManager.syncNow() }
                        } label: {
                            HStack {
                                Spacer()
                                if appState.syncManager.isSyncing {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 8)
                                }
                                Text(appState.syncManager.isSyncing ? "Syncing..." : "Sync Now")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .background(appState.syncManager.isSyncing ? Color.gray : palette.accent)
                            .cornerRadius(10)
                        }
                        .disabled(appState.syncManager.isSyncing)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
            .tint(palette.accent)
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedZIPURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showAlbumPicker) {
                ExportAlbumPickerSheet { album in exportAlbum(album) }
            }
            .sheet(isPresented: $showTagManager) {
                TagManagerView()
            }
            .sheet(isPresented: $showTrashView) {
                TrashView()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3, .aiff],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    pendingImportURLs = urls
                    showImportDestinationSheet = true
                case .failure(let error):
                    importErrors = [error.localizedDescription]
                    showImportErrorAlert = true
                }
            }
            .sheet(isPresented: $showImportDestinationSheet) {
                ImportDestinationSheet(
                    urls: pendingImportURLs,
                    onImport: { albumID in
                        performImport(urls: pendingImportURLs, albumID: albumID)
                    }
                )
            }
            .alert("Import Error", isPresented: $showImportErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrors.joined(separator: "\n"))
            }
            .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) { appState.emptyTrash() }
            } message: {
                Text("This will permanently delete \(appState.trashedCount) items. This cannot be undone.")
            }
            .sheet(isPresented: $showLockScreenHelp) {
                LockScreenWidgetHelpSheet()
            }
            .sheet(isPresented: $showActionButtonHelp) {
                ActionButtonHelpSheet()
            }
            .sheet(isPresented: $showSiriShortcutsHelp) {
                SiriShortcutsHelpSheet()
            }
        }
    }

    private func exportAllRecordings() {
        isExporting = true
        exportProgress = "all"
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    appState.activeRecordings,
                    scope: .all,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                exportProgress = ""
                showShareSheet = true
                appState.onExportSuccess()
            } catch {
                isExporting = false
                exportProgress = ""
            }
        }
    }

    private func exportAlbum(_ album: Album) {
        isExporting = true
        exportProgress = "album"
        Task {
            do {
                let recordings = appState.recordings(in: album)
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    recordings,
                    scope: .album(album),
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                exportProgress = ""
                showShareSheet = true
                appState.onExportSuccess()
            } catch {
                isExporting = false
                exportProgress = ""
            }
        }
    }

    private func performImport(urls: [URL], albumID: UUID) {
        var errors: [String] = []

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else {
                errors.append("\(url.lastPathComponent): Access denied")
                continue
            }
            defer { url.stopAccessingSecurityScopedResource() }

            let duration = getAudioDuration(url: url)
            let title = titleFromFilename(url.lastPathComponent)

            do {
                try appState.importRecording(from: url, duration: duration, title: title, albumID: albumID)
            } catch {
                errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        pendingImportURLs = []

        if !errors.isEmpty {
            importErrors = errors
            showImportErrorAlert = true
        }
    }

    private func titleFromFilename(_ filename: String) -> String {
        // Remove extension
        var name = (filename as NSString).deletingPathExtension

        // Replace underscores and dashes with spaces
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "-", with: " ")

        // Collapse multiple spaces
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }

        // Trim whitespace
        name = name.trimmingCharacters(in: .whitespaces)

        // Fallback if empty
        if name.isEmpty {
            return "Imported Recording"
        }

        return name
    }

    private func getAudioDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            return Double(audioFile.length) / audioFile.processingFormat.sampleRate
        } catch {
            return 0
        }
    }

    private func inputIcon(for input: AVAudioSessionPortDescription) -> String {
        switch input.portType {
        case .builtInMic:
            return "mic.fill"
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return "airpodspro"
        case .headsetMic:
            return "headphones"
        case .usbAudio:
            return "cable.connector"
        default:
            return "mic"
        }
    }
}

// MARK: - Trash View
struct TrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            Group {
                if appState.trashedRecordings.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "trash")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text("Trash is Empty")
                            .font(.title2)
                            .fontWeight(.semibold)
                    }
                } else {
                    List {
                        ForEach(appState.trashedRecordings) { recording in
                            TrashItemRow(recording: recording)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct TrashItemRow: View {
    @Environment(AppState.self) private var appState
    let recording: RecordingItem

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)

                if let days = recording.daysUntilPurge {
                    Text("Deletes in \(days) day\(days == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }

            Spacer()

            Button { appState.restoreFromTrash(recording) } label: {
                Text("Restore")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button { appState.permanentlyDelete(recording) } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Import Destination Sheet
struct ImportDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let urls: [URL]
    let onImport: (UUID) -> Void

    @State private var selectedAlbumID: UUID = Album.draftsID

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        Image(systemName: "doc.badge.plus")
                            .foregroundColor(.blue)
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(urls.count) file\(urls.count == 1 ? "" : "s") selected")
                                .font(.headline)
                            Text(urls.map { $0.lastPathComponent }.prefix(3).joined(separator: ", ") + (urls.count > 3 ? "..." : ""))
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach(appState.albums) { album in
                        Button {
                            selectedAlbumID = album.id
                        } label: {
                            HStack {
                                Image(systemName: album.isSystem ? "folder.fill" : "folder")
                                    .foregroundColor(album.isSystem ? .orange : .blue)
                                Text(album.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedAlbumID == album.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Destination Album")
                } footer: {
                    Text("Choose where to save the imported recordings.")
                }
            }
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        dismiss()
                        onImport(selectedAlbumID)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Export Album Picker Sheet
struct ExportAlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let onSelect: (Album) -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.albums) { album in
                    Button {
                        dismiss()
                        onSelect(album)
                    } label: {
                        HStack {
                            Text(album.name)
                                .foregroundColor(.primary)
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(appState.recordingCount(in: album)) recordings")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(appState.albumTotalSizeFormatted(album))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Settings Info Row

struct SettingsInfoRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Info Card

struct InfoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Info Bullet Row

struct InfoBulletRow: View {
    let text: String
    var icon: String = "circle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 6))
                .foregroundColor(.secondary)
                .frame(width: 12, height: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Info Tip Row

struct InfoTipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
                .frame(width: 12)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Tags Info View

struct TagsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Tags help you label ideas fast so you can find them later.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How to use")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Add tags to recordings (e.g., beatbox, melody, lyrics, favorite)")
                        InfoBulletRow(text: "Use tags to filter and search quickly")
                        InfoBulletRow(text: "Change tag colors for personal organization")
                        InfoBulletRow(text: "Manage tags in Settings → Manage Tags")
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "Keep tags short and consistent for best results.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Albums Info View

struct AlbumsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Albums are folders for grouping recordings by project or vibe.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How to use")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Move recordings into albums to keep drafts organized")
                        InfoBulletRow(text: "Great for separating songs, clients, or sessions")
                        InfoBulletRow(text: "Works with search and tags together")
                        InfoBulletRow(text: "Swipe left on a recording to move it to an album")
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Projects Info View

struct ProjectsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Keep versions organized without clutter.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How to use")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "A Project groups related takes in one place (Hook v1, Chorus v2, Verse idea)")
                        InfoBulletRow(text: "Record New Version creates a linked take (V2, V3...) instead of scattering files")
                        InfoBulletRow(text: "Mark a take as Best Take to highlight the one you want to keep (optional)")
                        InfoBulletRow(text: "Projects don't replace Albums: Albums organize your library, Projects link versions")
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                        Text("Use \"Record New Version\" in any recording's Details screen to quickly capture a new take.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Projects")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Maps Info View

struct MapsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("If Location is enabled, Sonidea can pin where ideas were captured.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How to use")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Each recording can store an optional location")
                        InfoBulletRow(text: "Map view shows your recording spots over time")
                        InfoBulletRow(text: "Tap a pin to see the recording details")
                        InfoBulletRow(text: "You control this: turn Location on/off in iOS Settings")
                    }
                }
                .padding(.horizontal)

                // Note
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Location is optional. The app works perfectly without it.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Maps")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Record Button Info View

struct RecordButtonInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Move the record button anywhere to match your workflow.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How to use")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Drag freely anywhere on screen (below the top menu)")
                        InfoBulletRow(text: "Position is saved automatically")
                        InfoBulletRow(text: "Long-press the button to see a quick reset option")
                        InfoBulletRow(text: "If it ever feels off, use \"Reset Record Button Position\" in Settings")
                    }
                }
                .padding(.horizontal)

                // Note
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Reset returns the button to the default bottom-center position, just like Voice Memos.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Movable Record Button")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Search Info View

struct SearchInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Search finds recordings by title, tags, and metadata.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How to use")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Tap the magnifying glass in the top bar")
                        InfoBulletRow(text: "Search by recording name")
                        InfoBulletRow(text: "Search by tags (e.g., \"melody\")")
                        InfoBulletRow(text: "Filter results by selecting tag chips")
                        InfoBulletRow(text: "Quickly jump to the exact take you need")
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance Info View

struct AppearanceInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Make Sonidea feel like yours by customizing colors.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("What you can customize")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Change tag colors in Settings → Manage Tags")
                        InfoBulletRow(text: "Recording icon colors can vary based on favorite status")
                        InfoBulletRow(text: "Switch between Light, Dark, or System appearance")
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "Use color as a system: red for hooks, blue for beats, purple for lyrics — whatever works for you.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(AppState())
}
