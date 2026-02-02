//
//  ContentView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Combine
import MapKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Main Content View
struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var currentRoute: AppRoute = .recordings
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showWelcomeTutorial = false
    @State private var showTipJar = false
    @State private var showRecoveryAlert = false
    @State private var showSaveErrorAlert = false
    @State private var saveErrorMessage = ""

    // Drag state for record button
    @State private var dragStartPosition: CGPoint = .zero
    @State private var isDragging = false

    // Long-press reset pill
    @State private var showResetPill = false

    // Trial nudge state
    @State private var currentNudge: TrialNudge? = nil

    // Move hint animation state
    @State private var showMoveHint = false
    @State private var hintNudgeOffset: CGFloat = 0

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
                updateUIMetrics(containerSize: containerSize, safeArea: safeArea)
            }
            .onChange(of: geometry.size) { _, newSize in
                updateUIMetrics(containerSize: newSize, safeArea: safeArea)
            }
        }
        .iPadSheet(isPresented: $showSearch) {
            SearchSheetView()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .iPadSheet(isPresented: $showSettings) {
            SettingsSheetView()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .sheet(isPresented: $showWelcomeTutorial) {
            WelcomeTutorialSheet()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .iPadSheet(isPresented: $showTipJar) {
            TipJarView()
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .sheet(item: $currentNudge) { nudge in
            TrialNudgeSheet(
                nudge: nudge,
                recordingCount: appState.activeRecordings.count,
                onCTA: { action in
                    currentNudge = nil
                    handleTrialNudgeCTA(action)
                },
                onDismiss: {
                    currentNudge = nil
                }
            )
            .environment(\.themePalette, palette)
            .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
        }
        .onChange(of: appState.recorder.recordingState) { _, newState in
            appState.onRecordingStateChanged(isRecording: newState.isActive)
        }
        .onAppear {
            appState.onAppBecameActive()
            // Check for recoverable recording from a crash
            if appState.recorder.checkForRecoverableRecording() != nil {
                showRecoveryAlert = true
            }
            // Wire up Live Activity stop callback
            // Capture appState (a reference type) instead of self (a struct value)
            // to avoid stale closure over a copy of ContentView
            let state = appState
            appState.recorder.onStopAndSaveRequested = {
                guard let rawData = state.recorder.stopRecording() else {
                    return
                }
                let result = state.addRecording(from: rawData)
                if case .success = result {
                    state.onRecordingSaved()
                }
            }
            // Show welcome tutorial on first launch
            if !appState.appSettings.hasSeenWelcome {
                showWelcomeTutorial = true
                var settings = appState.appSettings
                settings.hasSeenWelcome = true
                appState.appSettings = settings
            }
            // Check if we should show the move hint
            checkAndShowMoveHint()
            // Check for trial nudge
            checkTrialNudge()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                // Check for pending stop request from Live Activity (when app was backgrounded)
                if appState.recorder.consumePendingStopRequest() && appState.recorder.recordingState.isActive {
                    saveRecording()
                }
                // Check for trial nudge on foreground
                checkTrialNudge()
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
                        locationLabel: "",
                        wasRecordedWithMetronome: false,
                        metronomeBPM: nil
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
        .alert("Recording Failed", isPresented: $showSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(saveErrorMessage)
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

            // Move hint overlay (shown once per install, subtle nudge animation)
            if showMoveHint && !appState.recorder.isActive {
                moveHintOverlay(buttonPosition: buttonPosition, containerSize: containerSize, safeArea: safeArea)
            }

            // The floating record button
            VoiceMemosRecordButton()
                .frame(width: buttonDiameter, height: buttonDiameter)
                .contentShape(Circle().inset(by: -20)) // Larger hit area
                .shadow(color: .black.opacity(isDragging ? 0.3 : 0.2), radius: isDragging ? 12 : 8, y: isDragging ? 6 : 4)
                .scaleEffect(isDragging ? 1.05 : 1.0)
                .offset(x: hintNudgeOffset) // Nudge animation offset
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
                                    // Dismiss move hint and mark as moved
                                    if showMoveHint {
                                        dismissMoveHint()
                                    }
                                    if !appState.appSettings.hasEverMovedRecordButton {
                                        var settings = appState.appSettings
                                        settings.hasEverMovedRecordButton = true
                                        appState.appSettings = settings
                                    }
                                }

                                // Clamp to bounds and update position (smooth movement)
                                appState.recordButtonPosition = clampedDragPosition(
                                    translation: value.translation,
                                    minX: minX, maxX: maxX, minY: minY, maxY: maxY
                                )
                            }
                        }
                        .onEnded { value in
                            if isDragging {
                                // Commit the final position
                                appState.recordButtonPosition = clampedDragPosition(
                                    translation: value.translation,
                                    minX: minX, maxX: maxX, minY: minY, maxY: maxY
                                )
                                appState.persistRecordButtonPosition()

                                isDragging = false
                            } else {
                                // Was a tap (no significant movement)
                                // Dismiss move hint on tap
                                if showMoveHint {
                                    dismissMoveHint()
                                }
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

    // MARK: - Move Hint Overlay

    private func moveHintOverlay(buttonPosition: CGPoint, containerSize: CGSize, safeArea: EdgeInsets) -> some View {
        let hintHeight: CGFloat = 28
        let spacing: CGFloat = 14
        let buttonTop = buttonPosition.y - buttonDiameter / 2

        // Always show above the button
        let hintY = buttonTop - spacing - hintHeight / 2

        return Text("Drag to move anywhere")
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
            )
            .position(x: buttonPosition.x + hintNudgeOffset, y: hintY)
            .transition(.opacity)
    }

    // MARK: - Move Hint Logic

    private func checkTrialNudge() {
        guard appState.supportManager.isOnTrial,
              let trialStart = appState.supportManager.trialStartDate else { return }
        guard appState.trialNudgeManager.canShowNudge(
            isRecording: appState.recorder.recordingState != .idle,
            isPlayingBack: false
        ) else { return }
        if let nudge = appState.trialNudgeManager.nextNudgeToShow(trialStartDate: trialStart, now: Date()) {
            currentNudge = nudge
        }
    }

    private func handleTrialNudgeCTA(_ action: TrialNudgeCTA) {
        switch action {
        case .openGuide:
            showSettings = true
            // The guide is inside SettingsSheetView; user can navigate from there
        case .openOverdub:
            // Overdub is accessed per-recording; just dismiss
            break
        case .openExport:
            break
        case .viewStats:
            break
        case .createSharedAlbum:
            showSettings = true
            // Shared album creation is in settings
        case .openPaywall:
            showTipJar = true
        case .dismiss:
            break
        }
    }

    private func updateUIMetrics(containerSize: CGSize, safeArea: EdgeInsets) {
        appState.uiMetrics = UIMetrics(
            containerSize: containerSize,
            safeAreaInsets: safeArea,
            topBarHeight: topBarHeight,
            buttonDiameter: buttonDiameter
        )
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

    private func clampedDragPosition(
        translation: CGSize,
        minX: CGFloat, maxX: CGFloat,
        minY: CGFloat, maxY: CGFloat
    ) -> CGPoint {
        let newX = dragStartPosition.x + translation.width
        let newY = dragStartPosition.y + translation.height
        return CGPoint(
            x: min(max(newX, minX), maxX),
            y: min(max(newY, minY), maxY)
        )
    }

    private func checkAndShowMoveHint() {
        // Don't show if currently recording
        guard !appState.recorder.isActive else { return }

        let settings = appState.appSettings

        // First-time hint: show if never shown before
        if !settings.hasShownMoveHint {
            // Delay slightly to let the UI settle
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                showMoveHintAnimation()
            }
            return
        }

        // Re-hint logic: show again if user never moved the button, has 10+ recordings, and 14+ days since last hint
        if !settings.hasEverMovedRecordButton,
           appState.recordings.count >= 10,
           let lastShown = settings.lastMoveHintShownAt,
           Date().timeIntervalSince(lastShown) >= 14 * 24 * 60 * 60 { // 14 days
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                showMoveHintAnimation()
            }
        }
    }

    private func showMoveHintAnimation() {
        // Mark as shown
        var settings = appState.appSettings
        settings.hasShownMoveHint = true
        settings.lastMoveHintShownAt = Date()
        appState.appSettings = settings

        // Show the hint
        withAnimation(.easeOut(duration: 0.25)) {
            showMoveHint = true
        }

        // Perform the nudge animation (3 oscillations over ~1.1 seconds)
        let nudgeDistance: CGFloat = 10
        let singleOscillationDuration: Double = 0.18

        // Oscillation sequence: right -> left with decreasing amplitude -> center
        let offsets: [CGFloat] = [1, -1, 0.6, -0.6, 0.3, 0]
        for (i, scale) in offsets.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + singleOscillationDuration * Double(i)) {
                withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                    hintNudgeOffset = nudgeDistance * scale
                }
            }
        }

        // Auto-dismiss after 2.5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if showMoveHint {
                dismissMoveHint()
            }
        }
    }

    private func dismissMoveHint() {
        withAnimation(.easeOut(duration: 0.2)) {
            showMoveHint = false
            hintNudgeOffset = 0
        }
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
                        Color.clear.frame(height: topBarHeight + 4)

                        if appState.recorder.isActive {
                            RecordingHUDCard(
                                duration: appState.recorder.currentDuration,
                                liveSamples: appState.recorder.liveMeterSamples,
                                isPaused: appState.recorder.isPaused,
                                onPause: {
                                    appState.recorder.pauseRecording()
                                },
                                onResume: {
                                    appState.recorder.resumeRecording()
                                },
                                onSave: {
                                    saveRecording()
                                }
                            )
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                            .iPadMaxWidth(iPadLayout.maxHUDWidth)
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
                .padding(.top, sizeClass == .regular ? 20 : 8)
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

    private func navBarIcon(_ systemName: String, color: Color) -> some View {
        Image(systemName: systemName)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: 24, weight: .medium))
            .foregroundColor(color)
            .frame(width: 44, height: 44)
    }

    private var topNavigationBar: some View {
        let isCustomTheme = appState.selectedTheme.isCustomTheme

        // For custom themes: use effective toolbar text colors for consistency
        // For system theme: use palette.textPrimary (iOS defaults)
        let iconColor = isCustomTheme ? palette.effectiveToolbarTextPrimary : palette.textPrimary
        let activeIconColor = palette.accent

        return HStack(spacing: 8) {
            HStack(spacing: 8) {
                Button { showSettings = true } label: {
                    navBarIcon("gearshape.fill", color: iconColor)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { currentRoute = .map }
                } label: {
                    navBarIcon("map.fill", color: currentRoute == .map ? activeIconColor : iconColor)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { currentRoute = .recordings }
                } label: {
                    navBarIcon("waveform", color: currentRoute == .recordings ? activeIconColor : iconColor)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Button { showSearch = true } label: {
                    navBarIcon("magnifyingglass", color: iconColor)
                }

                Button { showTipJar = true } label: {
                    navBarIcon(
                        appState.supportManager.canUseProFeatures ? "checkmark.seal.fill" : "star.circle.fill",
                        color: appState.supportManager.canUseProFeatures ? iconColor : palette.accent
                    )
                }
            }
        }
    }

    // MARK: - Record Button Handler

    private func handleRecordTap() {
        switch appState.recorder.recordingState {
        case .idle:
            // Start new recording
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            appState.recorder.startRecording()
            // Show alert if recording couldn't start (e.g. insufficient disk space)
            if let error = appState.recorder.recordingError {
                saveErrorMessage = error
                showSaveErrorAlert = true
            }
        case .recording:
            // Stop and save immediately (Apple-like behavior)
            saveRecording()
        case .paused:
            // Resume the recording
            appState.recorder.resumeRecording()
        }
    }

    // MARK: - Save Recording

    private func saveRecording() {
        #if DEBUG
        print("🎙️ [ContentView] saveRecording() called")
        #endif

        guard let rawData = appState.recorder.stopRecording() else {
            #if DEBUG
            print("ℹ️ [ContentView] stopRecording() returned nil - recording too short or no data")
            #endif
            // Check if there's an error message from the recorder (e.g. write failures)
            if let error = appState.recorder.recordingError {
                saveErrorMessage = error
                showSaveErrorAlert = true
                appState.recorder.clearRecordingError()
            }
            currentRoute = .recordings
            return
        }

        #if DEBUG
        print("🎙️ [ContentView] Got raw data, file: \(rawData.fileURL.lastPathComponent), duration: \(rawData.duration)s")
        #endif

        let result = appState.addRecording(from: rawData)

        switch result {
        case .success(let recording):
            #if DEBUG
            print("✅ [ContentView] Recording saved successfully: \(recording.title)")
            #endif
            appState.onRecordingSaved()
            currentRoute = .recordings
        case .failure(let errorMessage):
            #if DEBUG
            print("❌ [ContentView] Failed to save recording: \(errorMessage)")
            #endif
            saveErrorMessage = "Recording could not be saved: \(errorMessage)"
            showSaveErrorAlert = true
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(AppState())
}
