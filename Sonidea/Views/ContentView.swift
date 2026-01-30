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

// MARK: - Search Mode Enum
enum SearchMode: String, CaseIterable {
    case `default`
    case calendar
    case timeline

    var iconName: String {
        switch self {
        case .default: return "magnifyingglass"
        case .calendar: return "calendar"
        case .timeline: return "clock"
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) var palette
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var currentRoute: AppRoute = .recordings
    @State private var showSearch = false
    @State private var showSettings = false
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
            appState.recorder.onStopAndSaveRequested = { [self] in
                saveRecording()
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
        // Trial nudges are disabled - trials are now only via StoreKit intro offer
        // When user is in a trial (annual plan intro offer), they appear as subscribed
        // No local trial tracking means no nudge system needed
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

        // Oscillation sequence: right -> left -> right -> left -> right -> center
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                hintNudgeOffset = nudgeDistance
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + singleOscillationDuration) {
            withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                hintNudgeOffset = -nudgeDistance
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + singleOscillationDuration * 2) {
            withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                hintNudgeOffset = nudgeDistance * 0.6
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + singleOscillationDuration * 3) {
            withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                hintNudgeOffset = -nudgeDistance * 0.6
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + singleOscillationDuration * 4) {
            withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                hintNudgeOffset = nudgeDistance * 0.3
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 + singleOscillationDuration * 5) {
            withAnimation(.easeInOut(duration: singleOscillationDuration)) {
                hintNudgeOffset = 0
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
                    Image(systemName: appState.supportManager.canUseProFeatures ? "checkmark.seal.fill" : "star.circle.fill")
                        .symbolRenderingMode(.monochrome)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(appState.supportManager.canUseProFeatures ? iconColor : palette.accent)
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
            // Stop and save immediately (Apple-like behavior)
            saveRecording()
        case .paused:
            // Resume the recording
            appState.recorder.resumeRecording()
        }
    }

    // MARK: - Save Recording

    private func saveRecording() {
        print("🎙️ [ContentView] saveRecording() called")

        guard let rawData = appState.recorder.stopRecording() else {
            print("❌ [ContentView] stopRecording() returned nil - no data to save")
            saveErrorMessage = "Recording failed: No audio data was captured. Please check your microphone permissions and try again."
            showSaveErrorAlert = true
            return
        }

        print("🎙️ [ContentView] Got raw data, file: \(rawData.fileURL.lastPathComponent), duration: \(rawData.duration)s")

        let result = appState.addRecording(from: rawData)

        switch result {
        case .success(let recording):
            print("✅ [ContentView] Recording saved successfully: \(recording.title)")
            appState.onRecordingSaved()
            currentRoute = .recordings
        case .failure(let errorMessage):
            print("❌ [ContentView] Failed to save recording: \(errorMessage)")
            saveErrorMessage = "Recording could not be saved: \(errorMessage)"
            showSaveErrorAlert = true
        }
    }
}

// MARK: - Voice Memos Style Record Button (Plain View - no Button to avoid gesture conflicts)

struct VoiceMemosRecordButton: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    @State private var isPulsing = false

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

    // Theme-aware record button color
    private var recordColor: Color {
        palette.recordButton
    }

    var body: some View {
        ZStack {
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

// MARK: - Premium Recording HUD Card

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

// MARK: - Level Meter Bar (green → yellow → red with dB scale)

struct LevelMeterBar: View {
    let level: Float   // 0.0 – 1.0 normalized
    var isPaused: Bool = false

    @Environment(\.themePalette) private var palette

    // dB scale marks placed evenly across the bar at 25%, 50%, 75%, 100%
    private let scaleMarks: [(db: String, normalized: CGFloat)] = [
        ("-6", 0.25),
        ("-3", 0.50),
        ("0",  0.75),
        ("+3", 1.0),
    ]

    private let clipThreshold: Float = 0.97  // ~-1.5 dB input level

    @State private var displayLevel: CGFloat = 0
    @State private var isClipping = false
    @State private var clipTimer: Timer?

    /// Convert normalized level (0-1, representing -50 to 0 dB) to display position.
    /// Piecewise mapping so dB marks are evenly spaced:
    ///   below -6 dB → 0% to 25%  (compressed)
    ///   -6 to -3 dB → 25% to 50%
    ///   -3 to  0 dB → 50% to 75%
    ///    0 to +3 dB → 75% to 100% (clipping zone)
    private func levelToPosition(_ level: Float) -> CGFloat {
        let dB = level * 50 - 50
        if dB <= -6 {
            return CGFloat(max(0, (dB + 50) / 44.0 * 0.25))
        } else if dB <= -3 {
            return CGFloat(0.25 + (dB + 6) / 3.0 * 0.25)
        } else if dB <= 0 {
            return CGFloat(0.50 + (dB + 3) / 3.0 * 0.25)
        } else {
            return CGFloat(min(1.0, 0.75 + dB / 3.0 * 0.25))
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            // Meter bar with gradient
            GeometryReader { geo in
                let width = geo.size.width

                ZStack(alignment: .leading) {
                    // Background track
                    Capsule()
                        .fill(Color.gray.opacity(0.15))

                    // Filled meter with gradient
                    Capsule()
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .green, location: 0),
                                    .init(color: .green, location: 0.40),
                                    .init(color: .yellow, location: 0.55),
                                    .init(color: .orange, location: 0.70),
                                    .init(color: .red, location: 0.85),
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, min(displayLevel * width, width)))

                    // Clip dot
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
                        let x = mark.normalized * width
                        Rectangle()
                            .fill(palette.textSecondary.opacity(0.3))
                            .frame(width: 1)
                            .position(x: min(x, width - 1), y: geo.size.height / 2)
                    }
                }
            }
            .frame(height: 4)
            .clipShape(Capsule())

            // dB labels
            GeometryReader { geo in
                let width = geo.size.width
                ForEach(scaleMarks, id: \.db) { mark in
                    let x = mark.normalized * width
                    Text(mark.db)
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.textSecondary.opacity(0.6))
                        .position(x: min(x, width - 8), y: 5)
                }
            }
            .frame(height: 10)
        }
        .animation(.easeOut(duration: 0.08), value: displayLevel)
        .onChange(of: level) { _, newLevel in
            let newDisplay = isPaused ? CGFloat(0) : levelToPosition(newLevel)
            displayLevel = newDisplay

            // Hold clip indicator for 500ms after clipping
            if newLevel >= clipThreshold && !isPaused {
                isClipping = true
                clipTimer?.invalidate()
                clipTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { _ in
                    Task { @MainActor in isClipping = false }
                }
            }
        }
        .onChange(of: isPaused) { _, paused in
            if paused {
                displayLevel = 0
                isClipping = false
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

    @State private var searchMode: SearchMode = .default
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

                switch searchMode {
                case .default:
                    defaultSearchContent
                case .calendar:
                    calendarSearchContent
                case .timeline:
                    timelineSearchContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 4) {
                        // Calendar mode button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchMode = searchMode == .calendar ? .default : .calendar
                            }
                        } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(searchMode == .calendar ? palette.accent : palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(searchMode == .calendar ? palette.accent.opacity(0.15) : Color.clear)
                                .clipShape(Circle())
                        }

                        // Timeline mode button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchMode = searchMode == .timeline ? .default : .timeline
                            }
                        } label: {
                            Image(systemName: "clock")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(searchMode == .timeline ? palette.accent : palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(searchMode == .timeline ? palette.accent.opacity(0.15) : Color.clear)
                                .clipShape(Circle())
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    // Title - tapping it returns to default search
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchMode = .default
                        }
                    } label: {
                        Text("Search")
                            .font(.headline)
                            .foregroundStyle(searchMode == .default ? palette.accent : palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
            .iPadSheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(item: $selectedAlbum) { album in
                if album.isShared {
                    SharedAlbumDetailView(album: album)
                } else {
                    AlbumDetailSheet(album: album)
                }
            }
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(project: project)
            }
            .onChange(of: searchScope) { _, _ in
                if searchScope != .recordings { selectedTagIDs.removeAll() }
            }
        }
    }

    // MARK: - Default Search Content

    private var defaultSearchContent: some View {
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

    // MARK: - Calendar Search Content

    private var calendarSearchContent: some View {
        SearchCalendarView(searchQuery: searchQuery, selectedRecording: $selectedRecording)
    }

    // MARK: - Timeline Search Content

    private var timelineSearchContent: some View {
        SearchTimelineView(searchQuery: searchQuery, selectedRecording: $selectedRecording)
    }

    // MARK: - Recordings Results

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

    // MARK: - Albums Results

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

    // MARK: - Projects Results

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

// MARK: - Search Calendar View (Embedded)

struct SearchCalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    let searchQuery: String
    @Binding var selectedRecording: RecordingItem?

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    private var recordingsByDay: [Date: [RecordingItem]] {
        let filtered: [RecordingItem]
        if searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            filtered = appState.activeRecordings
        } else {
            let query = searchQuery.lowercased()
            filtered = appState.activeRecordings.filter { recording in
                recording.title.lowercased().contains(query) ||
                recording.transcript.lowercased().contains(query)
            }
        }
        return Dictionary(grouping: filtered) { recording in
            calendar.startOfDay(for: recording.createdAt)
        }
    }

    private var daysWithRecordings: Set<Date> {
        Set(recordingsByDay.keys)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation
            monthNavigationHeader

            // Days of week header
            daysOfWeekHeader

            // Calendar grid
            calendarGrid

            Divider()
                .padding(.top, 8)

            // Selected day recordings
            if let date = selectedDate {
                dayRecordingsList(for: date)
            } else {
                selectDayPrompt
            }
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthYearString)
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            Spacer()

            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var monthYearString: String {
        CachedDateFormatter.monthYear.string(from: currentMonth)
    }

    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(daysOfWeek, id: \.self) { day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var calendarGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    calendarDayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func calendarDayCell(for date: Date) -> some View {
        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
        let isToday = calendar.isDateInToday(date)
        let hasRecordings = daysWithRecordings.contains(calendar.startOfDay(for: date))
        let recordingCount = recordingsByDay[calendar.startOfDay(for: date)]?.count ?? 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.white :
                        isToday ? palette.accent :
                        palette.textPrimary
                    )

                if hasRecordings {
                    if recordingCount > 1 {
                        Text("\(recordingCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : palette.accent)
                    } else {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.9) : palette.accent)
                            .frame(width: 5, height: 5)
                    }
                } else {
                    Color.clear
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                Group {
                    if isSelected {
                        Circle()
                            .fill(palette.accent)
                    } else if isToday {
                        Circle()
                            .strokeBorder(palette.accent, lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func dayRecordingsList(for date: Date) -> some View {
        let recordings = recordingsByDay[calendar.startOfDay(for: date)] ?? []

        return VStack(spacing: 0) {
            HStack {
                Text(dayHeaderString(for: date))
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                if !recordings.isEmpty {
                    Text("\(recordings.count) recording\(recordings.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title)
                        .foregroundStyle(palette.textTertiary)

                    Text("No recordings")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recordings.sorted(by: { $0.createdAt > $1.createdAt })) { recording in
                            SearchCalendarRecordingRow(recording: recording)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRecording = recording
                                }

                            if recording.id != recordings.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func dayHeaderString(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return CachedDateFormatter.weekdayMonthDay.string(from: date)
        }
    }

    private var selectDayPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title)
                .foregroundStyle(palette.textTertiary)

            Text("Select a day to view recordings")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        var days: [Date?] = []

        let startOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: startOfMonth)
        for _ in 1..<weekdayOfFirst {
            days.append(nil)
        }

        var date = startOfMonth
        while date < monthInterval.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return days
    }
}

// MARK: - Search Calendar Recording Row

struct SearchCalendarRecordingRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem

    private var formattedTime: String {
        CachedDateFormatter.timeOnly.string(from: recording.createdAt)
    }

    private var formattedDuration: String {
        let minutes = Int(recording.duration) / 60
        let seconds = Int(recording.duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(formattedTime)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(recording.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }

                Label(formattedDuration, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.background)
    }
}

// MARK: - Search Timeline View (Embedded)

struct SearchTimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    let searchQuery: String
    @Binding var selectedRecording: RecordingItem?

    private var timelineGroups: [TimelineGroup] {
        // Filter out trashed recordings, then apply search query
        var activeRecordings = appState.recordings.filter { !$0.isTrashed }
        if !searchQuery.trimmingCharacters(in: .whitespaces).isEmpty {
            let query = searchQuery.lowercased()
            activeRecordings = activeRecordings.filter { recording in
                recording.title.lowercased().contains(query) ||
                recording.transcript.lowercased().contains(query)
            }
        }
        let items = TimelineBuilder.buildTimeline(
            recordings: activeRecordings,
            projects: appState.projects
        )
        return TimelineBuilder.groupByDay(items)
    }

    var body: some View {
        if timelineGroups.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.textTertiary)

                Text("No Recordings Yet")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Text("Your recording timeline will appear here")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(timelineGroups) { group in
                        Section {
                            ForEach(group.items) { item in
                                SearchTimelineRowView(item: item, tags: tagsForItem(item))
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        handleItemTap(item)
                                    }

                                if item.id != group.items.last?.id {
                                    Divider()
                                        .padding(.leading, 60)
                                }
                            }
                        } header: {
                            sectionHeader(for: group)
                        }
                    }
                }
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
    }

    private func sectionHeader(for group: TimelineGroup) -> some View {
        HStack {
            Text(group.displayTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            Spacer()

            Text("\(group.items.count)")
                .font(.footnote)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(palette.background)
    }

    private func tagsForItem(_ item: TimelineItem) -> [Tag] {
        item.tagIDs.compactMap { appState.tag(for: $0) }
    }

    private func handleItemTap(_ item: TimelineItem) {
        if let recording = appState.recording(for: item.recordingID) {
            selectedRecording = recording
        }
    }
}

// MARK: - Search Timeline Row View

struct SearchTimelineRowView: View {
    @Environment(\.themePalette) private var palette

    let item: TimelineItem
    let tags: [Tag]

    private var formattedTime: String {
        CachedDateFormatter.timeOnly.string(from: item.timestamp)
    }

    private var formattedDuration: String {
        let minutes = Int(item.duration) / 60
        let seconds = Int(item.duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .trailing) {
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 50, alignment: .trailing)

            VStack(spacing: 4) {
                Circle()
                    .fill(item.isBestTake ? Color.yellow : palette.accent)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    if item.isBestTake {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                            Text("Best")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }

                HStack(spacing: 8) {
                    Label(formattedDuration, systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                    if case .projectTake(let projectTitle, let takeLabel) = item.type {
                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)

                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text("\(projectTitle) \u{00B7} \(takeLabel)")
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()
                }

                if !tags.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(tags.prefix(3)) { tag in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(palette.chipBackground)
                            .clipShape(Capsule())
                        }

                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette.background)
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
            ZStack {
                Image(systemName: album.isShared ? "person.2.fill" : "square.stack.fill")
                    .font(.system(size: 20))
                    .foregroundColor(album.isShared ? .sharedAlbumGold : .primary)
                    .frame(width: 36, height: 36)
                    .background(album.isShared ? Color.sharedAlbumGold.opacity(0.15) : Color(.systemGray4))
                    .cornerRadius(6)

                // Glow effect for shared albums
                if album.isShared {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.sharedAlbumGold.opacity(0.5), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .shadow(color: .sharedAlbumGold.opacity(0.3), radius: 4, x: 0, y: 0)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    AlbumTitleView(album: album, font: .body.weight(.medium), showBadge: true)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if album.isShared {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(album.participantCount) participant\(album.participantCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.sharedAlbumGold)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(album.isShared ? .sharedAlbumGold.opacity(0.7) : .secondary)
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
    @State private var showLeaveSheet = false
    @State private var showManageSheet = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private var albumRecordings: [RecordingItem] {
        let recordings = appState.recordings(in: album)
        if selectedTagIDs.isEmpty { return recordings }
        return recordings.filter { !selectedTagIDs.isDisjoint(with: Set($0.tagIDs)) }
    }

    /// Reactive lookup so the navigation title updates after rename
    private var currentAlbum: Album {
        appState.albums.first(where: { $0.id == album.id }) ?? album
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Shared album banner at top
                    if album.isShared {
                        SharedAlbumBanner(album: album)
                    }

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
                                Image(systemName: album.isShared ? "person.2.wave.2" : "waveform.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text(selectedTagIDs.isEmpty ? (album.isShared ? "No recordings in this shared album" : "No recordings in this album") : "No recordings match selected tags")
                                    .font(.headline)
                                if album.isShared && selectedTagIDs.isEmpty {
                                    Text("Add recordings to share with collaborators")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
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
            }
            .navigationTitle(currentAlbum.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        if album.isShared {
                            Menu {
                                if album.isOwner {
                                    Button {
                                        showManageSheet = true
                                    } label: {
                                        Label("Manage Sharing", systemImage: "person.badge.plus")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        showLeaveSheet = true
                                    } label: {
                                        Label("Leave Album", systemImage: "person.badge.minus")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }

                        if album.canRename {
                            Button {
                                renameText = currentAlbum.name
                                showRenameAlert = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Album", isPresented: $showRenameAlert) {
                TextField("Album name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, trimmed != currentAlbum.name else { return }
                    if appState.renameAlbum(currentAlbum, to: trimmed) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } message: {
                Text("Enter a new name for this album.")
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(isPresented: $showLeaveSheet) {
                LeaveSharedAlbumSheet(album: album)
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
                HStack(spacing: 4) {
                    Text(recording.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let album = album {
                        Text("•").font(.caption).foregroundColor(.secondary)
                        if album.isShared {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 8))
                                Text(album.name)
                            }
                            .font(.caption)
                            .foregroundColor(.sharedAlbumGold)
                            .lineLimit(1)
                        } else {
                            Text(album.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
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

// MARK: - Help Topic (Single Source of Truth for Guide and Settings Info)

enum HelpTopic: String, Identifiable, CaseIterable {
    case iCloud
    case collaboration
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return "iCloud Sync"
        case .collaboration: return "Shared Albums"
        case .tags: return "Tags"
        }
    }

    var icon: String {
        switch self {
        case .iCloud: return "icloud"
        case .collaboration: return "person.2.fill"
        case .tags: return "tag"
        }
    }

    /// Content used by both Guide view and Settings info sheets
    var content: [(heading: String?, bullets: [String])] {
        switch self {
        case .iCloud:
            return [
                (nil, [
                    "Sync recordings, tags, albums, and projects across all your devices.",
                    "Changes made on one device appear automatically on others.",
                    "Ensure iCloud is enabled in your device Settings for Sonidea."
                ]),
                ("Troubleshooting", [
                    "If sync seems stuck, try toggling iCloud off and on.",
                    "Large recordings may take time to upload on slow connections.",
                    "Check iCloud storage isn't full."
                ])
            ]
        case .collaboration:
            return [
                (nil, [
                    "Share albums with specific people via iCloud.",
                    "Shared albums sync audio recordings only (no photos/videos).",
                    "You cannot convert an existing album—create a new Shared Album first."
                ]),
                ("Roles", [
                    "Admin: Full control—invite/remove people, change settings, delete any recording.",
                    "Member: Add recordings, edit own recordings; delete permission depends on settings.",
                    "Viewer: Listen only, cannot add or delete."
                ]),
                ("Safety", [
                    "Deletions move to Shared Album Trash for 7–30 days before permanent removal.",
                    "Activity tab shows who added, deleted, or modified recordings.",
                    "Only share with people you trust."
                ])
            ]
        case .tags:
            return [
                (nil, [
                    "Tags help you organize and find recordings quickly.",
                    "Add multiple tags to any recording.",
                    "Filter your library by tag to focus on specific topics."
                ]),
                ("Tips", [
                    "Use consistent naming for easy filtering.",
                    "Create tags for projects, moods, or categories.",
                    "Tags sync across all your devices via iCloud."
                ])
            ]
        }
    }
}

// MARK: - Settings Section Header with Info Icon

struct SettingsSectionHeader: View {
    let title: String
    let topic: HelpTopic?
    let onInfoTap: (() -> Void)?
    var isGold: Bool = false
    var showProBadge: Bool = false

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundColor(isGold ? Color.sharedAlbumGold : palette.textSecondary)

            if showProBadge {
                ProBadge()
            }

            if let _ = topic, let onTap = onInfoTap {
                Button {
                    onTap()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(isGold ? Color.sharedAlbumGold.opacity(0.8) : palette.textTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }

            Spacer()

            // Optional sparkles for Collaboration
            if isGold {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
            }
        }
    }
}

// MARK: - Help Sheet View

struct HelpSheetView: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: topic.icon)
                            .font(.title2)
                            .foregroundColor(topic == .collaboration ? Color.sharedAlbumGold : palette.accent)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(topic == .collaboration ? Color.sharedAlbumGold.opacity(0.15) : palette.accent.opacity(0.15))
                            )

                        Text(topic.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                    }
                    .padding(.bottom, 8)

                    // Content sections
                    ForEach(Array(topic.content.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 12) {
                            if let heading = section.heading {
                                Text(heading)
                                    .font(.headline)
                                    .foregroundColor(palette.textPrimary)
                            }

                            ForEach(section.bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(palette.textSecondary)
                                    Text(bullet)
                                        .font(.subheadline)
                                        .foregroundColor(palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
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
    @State private var showMicrophoneSheet = false
    @State private var showStorageEstimateSheet = false
    @State private var showSiriShortcutsHelp = false
    @State private var showGuide = false
    @State private var showCreateSharedAlbumSheet = false
    @State private var isResetButtonAnimating = false
    @State private var activeHelpTopic: HelpTopic?
    @State private var showAutoIconInfo = false
    @State private var showResetStep1 = false
    @State private var showResetStep2 = false
    @State private var resetConfirmText = ""
    @State private var resetConfirmationChecked = false
    @State private var showResetLoading = false
    @State private var proUpgradeContext: ProFeatureContext? = nil
    @State private var showTipJar = false

    private func requirePro(_ context: ProFeatureContext) -> Bool {
        if appState.supportManager.canUseProFeatures { return true }
        proUpgradeContext = context
        return false
    }

    // Sync status color based on state
    private var syncStatusColor: Color {
        switch appState.syncManager.status {
        case .disabled:
            return palette.textSecondary
        case .initializing, .syncing:
            return palette.accent
        case .synced:
            return .green
        case .error:
            return .red
        case .networkUnavailable:
            return .orange
        case .accountUnavailable:
            return .yellow
        }
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            List {
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
                        // Perform reset
                        appState.resetRecordButtonPosition()
                        // Trigger animation after reset
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isResetButtonAnimating = true
                        }
                        // Success haptic
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        // Reset animation state after completion
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isResetButtonAnimating = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                                .rotationEffect(.degrees(isResetButtonAnimating ? -360 : 0))
                                .animation(.easeInOut(duration: 0.4), value: isResetButtonAnimating)
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

                // MARK: Recording Section
                Section {
                    // Recording Quality
                    Picker("Quality", selection: $appState.appSettings.recordingQuality) {
                        ForEach(RecordingQualityPreset.allCases) { preset in
                            Text(preset.displayName)
                                .tag(preset)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    // Recording Mode
                    Picker("Mode", selection: $appState.appSettings.recordingMode) {
                        ForEach(RecordingMode.allCases) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    // Microphone
                    Button {
                        showMicrophoneSheet = true
                    } label: {
                        HStack {
                            Text("Microphone")
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(microphoneDisplayName)
                                .foregroundStyle(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    // Prevent Sleep
                    Toggle("Prevent Sleep", isOn: $appState.appSettings.preventSleepWhileRecording)
                        .tint(palette.accent)
                        .listRowBackground(palette.cardBackground)
                } header: {
                    HStack {
                        Text("Recording")
                        Spacer()
                        Button {
                            showStorageEstimateSheet = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .textCase(nil)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.appSettings.recordingQuality.description)
                        Text(appState.appSettings.recordingMode.description)
                        if appState.appSettings.preventSleepWhileRecording {
                            Text("Screen will stay on while recording.")
                        }
                    }
                    .foregroundColor(palette.textSecondary)
                }

                Section {
                    Picker("Skip Interval", selection: $appState.appSettings.skipInterval) {
                        ForEach(SkipInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Picker("Playback Speed", selection: $appState.appSettings.playbackSpeed) {
                        Text("0.5x").tag(Float(0.5))
                        Text("0.75x").tag(Float(0.75))
                        Text("1.0x").tag(Float(1.0))
                        Text("1.25x").tag(Float(1.25))
                        Text("1.5x").tag(Float(1.5))
                        Text("1.75x").tag(Float(1.75))
                        Text("2.0x").tag(Float(2.0))
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

                Section {
                    HStack {
                        Toggle("Auto-Select Icon", isOn: $appState.appSettings.autoSelectIcon)
                            .tint(palette.toggleOnTint)
                            .onChange(of: appState.appSettings.autoSelectIcon) { _, enabled in
                                if enabled && !appState.supportManager.canUseProFeatures {
                                    appState.appSettings.autoSelectIcon = false
                                    proUpgradeContext = .autoIcons
                                }
                            }

                        Button {
                            showAutoIconInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 18))
                                .foregroundColor(palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    HStack(spacing: 6) {
                        Text("Smart Detection")
                        if !appState.supportManager.canUseProFeatures { ProBadge() }
                    }
                    .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Automatically detect audio type (voice, guitar, drums, keys) and set the recording icon.")
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
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
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
                        .onChange(of: appState.appSettings.iCloudSyncEnabled) { oldValue, enabled in
                            if enabled && !appState.supportManager.canUseProFeatures {
                                appState.appSettings.iCloudSyncEnabled = false
                                proUpgradeContext = .icloudSync
                                return
                            }
                            // Avoid acting on programmatic revert (false -> false)
                            guard oldValue != enabled else { return }
                            Task {
                                if enabled {
                                    await appState.syncManager.enableSync()
                                } else {
                                    appState.syncManager.disableSync()
                                }
                            }
                        }

                    // Sync status row (only when enabled)
                    if appState.appSettings.iCloudSyncEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: appState.syncManager.status.iconName)
                                    .foregroundColor(syncStatusColor)
                                    .font(.system(size: 14))

                                Text(appState.syncManager.status.displayText)
                                    .font(.subheadline)
                                    .foregroundColor(palette.textSecondary)

                                Spacer()

                                if appState.syncManager.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(palette.accent)
                                }
                            }

                            // Progress bar when syncing
                            if let progress = appState.syncManager.status.progress, progress > 0 {
                                ProgressView(value: progress)
                                    .tint(palette.accent)
                            }

                            // Show current upload if any
                            if let currentUpload = appState.syncManager.uploadProgress.first(where: { $0.status == .uploading }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.caption2)
                                        .foregroundColor(palette.textTertiary)
                                    Text(currentUpload.fileName)
                                        .font(.caption2)
                                        .foregroundColor(palette.textTertiary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(currentUpload.progress * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(palette.textTertiary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    SettingsSectionHeader(
                        title: "iCloud",
                        topic: .iCloud,
                        onInfoTap: { activeHelpTopic = .iCloud },
                        showProBadge: !appState.supportManager.canUseProFeatures
                    )
                } footer: {
                    Text("Sync recordings, tags, albums, and projects across all your devices.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Watch Sync Section
                Section {
                    Toggle(isOn: $appState.appSettings.watchSyncEnabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "applewatch")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                            Text("Auto Sync Watch Recordings")
                        }
                    }
                    .tint(palette.toggleOnTint)
                    .listRowBackground(palette.cardBackground)
                    .onChange(of: appState.appSettings.watchSyncEnabled) { oldValue, enabled in
                        if enabled && !appState.supportManager.canUseProFeatures {
                            appState.appSettings.watchSyncEnabled = false
                            proUpgradeContext = .watchSync
                            return
                        }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Apple Watch")
                            .foregroundStyle(palette.textSecondary)
                        if !appState.supportManager.canUseProFeatures {
                            ProBadge()
                        }
                    }
                } footer: {
                    Text("Automatically import recordings from the Sonidea Apple Watch app into the ⌚️ Recordings album. Requires the Sonidea watch app and a Pro plan.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Shared Albums Section
                Section {
                    Button {
                        if requirePro(.sharedAlbums) {
                            showCreateSharedAlbumSheet = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            // Gold gradient icon
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.65, blue: 0.13)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Shared Album")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                                Text("Collaborate with others")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }

                            Spacer()

                            // Premium badge
                            Text("NEW")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.65, blue: 0.13)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(4)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(palette.cardBackground)

                    // Show existing shared albums count
                    if !appState.sharedAlbums.isEmpty {
                        HStack {
                            Image(systemName: "square.stack.fill")
                                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                                .frame(width: 24)
                            Text("Your Shared Albums")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(appState.sharedAlbums.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.85, green: 0.65, blue: 0.13))
                                .cornerRadius(10)
                        }
                        .listRowBackground(palette.cardBackground)
                    }

                    // Debug mode toggle
                    #if DEBUG
                    Toggle(isOn: Binding(
                        get: { appState.isSharedAlbumsDebugMode },
                        set: { newValue in
                            if newValue {
                                appState.enableSharedAlbumsDebugMode()
                            } else {
                                appState.disableSharedAlbumsDebugMode()
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: "ant.fill")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Demo Mode")
                                    .foregroundColor(palette.textPrimary)
                                Text("Test UI without iCloud")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }
                    .tint(.purple)
                    .listRowBackground(palette.cardBackground)
                    #endif
                } header: {
                    SettingsSectionHeader(
                        title: "Collaboration",
                        topic: .collaboration,
                        onInfoTap: { activeHelpTopic = .collaboration },
                        isGold: true,
                        showProBadge: !appState.supportManager.canUseProFeatures
                    )
                } footer: {
                    #if DEBUG
                    if appState.isSharedAlbumsDebugMode {
                        Text("Demo mode active - showing sample shared album data. Disable to remove demo content.")
                            .foregroundColor(.purple)
                    } else {
                        Text("Collaborate on albums with up to 5 people. Share audio recordings in real-time with role-based permissions.")
                            .foregroundColor(palette.textSecondary)
                    }
                    #else
                    Text("Collaborate on albums with up to 5 people. Share audio recordings in real-time with role-based permissions.")
                        .foregroundColor(palette.textSecondary)
                    #endif
                }

                Section {
                    Button {
                        if requirePro(.tags) {
                            showTagManager = true
                        }
                    } label: {
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
                    SettingsSectionHeader(
                        title: "Tags",
                        topic: .tags,
                        onInfoTap: { activeHelpTopic = .tags },
                        showProBadge: !appState.supportManager.canUseProFeatures
                    )
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
                        Text("2.0")
                            .foregroundColor(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://www.notion.so/sonidea/Sonidea-Privacy-Policy-2f72934c965380a3bafaf7967e2295df")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Privacy Policy")
                                    .foregroundColor(palette.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://forms.gle/rmEQg3nXDaoHCGj5A")!) {
                        HStack {
                            Image(systemName: "ladybug")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Report a Bug")
                                    .foregroundColor(palette.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://forms.gle/4Hf5DMDJBCD9gdir6")!) {
                        HStack {
                            Image(systemName: "lightbulb")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Suggestions")
                                    .foregroundColor(palette.textPrimary)
                                Text("Tell us what you'd like to see in our app.")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
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

                #if DEBUG
                // MARK: - Debug Tier Testing
                Section {
                    let mgr = appState.supportManager
                    Picker("Tier Override", selection: Binding<Int>(
                        get: {
                            if mgr.debugProOverride == nil { return 0 }
                            return mgr.debugProOverride == true ? 1 : 2
                        },
                        set: { val in
                            switch val {
                            case 1: mgr.debugProOverride = true
                            case 2: mgr.debugProOverride = false
                            default: mgr.debugProOverride = nil
                            }
                        }
                    )) {
                        Text("Normal").tag(0)
                        Text("Force Pro").tag(1)
                        Text("Force Free").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("DEBUG")
                        .foregroundColor(.red)
                }
                #endif

                // MARK: - Factory Reset
                Section {
                    Button(role: .destructive) {
                        showResetStep1 = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.red)
                            Text("Reset App")
                                .foregroundColor(.red)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } footer: {
                    Text("Erase all recordings, albums, tags, projects, and settings. The app will return to its initial state.")
                        .foregroundColor(palette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Guide") {
                        showGuide = true
                    }
                    .foregroundColor(palette.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
            .alert("Reset App?", isPresented: $showResetStep1) {
                Button("Cancel", role: .cancel) {}
                Button("I Understand, Continue", role: .destructive) {
                    resetConfirmText = ""
                    showResetLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showResetLoading = false
                        showResetStep2 = true
                    }
                }
            } message: {
                Text("This will permanently delete ALL your recordings, albums, tags, projects, overdubs, and settings.\n\nPlease back up any recordings you want to keep before proceeding.")
            }
            .fullScreenCover(isPresented: $showResetLoading) {
                ZStack {
                    palette.background.ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.red)
                        Text("Preparing reset...")
                            .font(.headline)
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showResetStep2) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer().frame(height: 40)

                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.red)

                            Text("This Cannot Be Undone")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(palette.textPrimary)

                            Text("Type RESET below to confirm you want to erase all app data and return to factory settings.")
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal)

                            TextField("Type RESET", text: $resetConfirmText)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .padding(.horizontal, 40)

                            Button(role: .destructive) {
                                appState.factoryReset()
                                showResetStep2 = false
                                dismiss()
                            } label: {
                                Text("Erase Everything")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(resetConfirmText == "RESET" ? Color.red : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(resetConfirmText != "RESET")
                            .padding(.horizontal, 40)

                            Spacer().frame(height: 40)
                        }
                    }
                    .background(palette.background)
                    .navigationTitle("Confirm Reset")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showResetStep2 = false
                            }
                            .foregroundColor(palette.accent)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .tint(palette.accent)
            .sheet(isPresented: $showGuide) {
                GuideView()
            }
            .sheet(item: $activeHelpTopic) { topic in
                HelpSheetView(topic: topic)
            }
            .sheet(isPresented: $showMicrophoneSheet) {
                MicrophoneSelectorSheet()
            }
            .sheet(isPresented: $showStorageEstimateSheet) {
                StorageEstimateSheet()
            }
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
            .sheet(item: $proUpgradeContext) { context in
                ProUpgradeSheet(
                    context: context,
                    onViewPlans: {
                        proUpgradeContext = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTipJar = true
                        }
                    },
                    onDismiss: {
                        proUpgradeContext = nil
                    }
                )
                .environment(\.themePalette, palette)
            }
            .iPadSheet(isPresented: $showTipJar) {
                TipJarView()
                    .environment(appState)
                    .environment(\.themePalette, palette)
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
            .sheet(isPresented: $showCreateSharedAlbumSheet) {
                CreateSharedAlbumSheet()
            }
            .sheet(isPresented: $showAutoIconInfo) {
                AutoIconInfoSheet()
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
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

    /// Display name for the currently selected microphone
    private var microphoneDisplayName: String {
        // If no preferred UID, show "Automatic"
        guard let preferredUID = appState.appSettings.preferredInputUID else {
            return "Automatic"
        }

        // Check if the preferred input is currently available
        if let input = AudioSessionManager.shared.input(for: preferredUID) {
            return input.portName
        }

        // Preferred input not available
        return "Not connected"
    }
}

// MARK: - Microphone Selector Sheet

struct MicrophoneSelectorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                // Automatic option
                Button {
                    selectInput(uid: nil)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.body)
                            .foregroundStyle(palette.accent)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic")
                                .font(.body)
                                .foregroundStyle(palette.textPrimary)
                            Text("System chooses best available")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }

                        Spacer()

                        if appState.appSettings.preferredInputUID == nil {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowBackground(palette.cardBackground)

                // Available inputs section
                Section {
                    ForEach(AudioSessionManager.shared.availableInputs, id: \.uid) { input in
                        Button {
                            selectInput(uid: input.uid)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: AudioSessionManager.icon(for: input.portType))
                                    .font(.body)
                                    .foregroundStyle(palette.accent)
                                    .frame(width: 28)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(input.portName)
                                        .font(.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(AudioSessionManager.portTypeName(for: input.portType))
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }

                                Spacer()

                                if appState.appSettings.preferredInputUID == input.uid {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Available Inputs")
                        .foregroundStyle(palette.textSecondary)
                }

                // Show previously selected but unavailable input
                if let preferredUID = appState.appSettings.preferredInputUID,
                   !AudioSessionManager.shared.isInputAvailable(uid: preferredUID) {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.body)
                                .foregroundStyle(.orange)
                                .frame(width: 28)

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Selected microphone")
                                    .font(.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text("Not connected")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }

                            Spacer()

                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(palette.accent)
                        }
                        .listRowBackground(palette.cardBackground)
                    } header: {
                        Text("Previously Selected")
                            .foregroundStyle(palette.textSecondary)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Microphone Input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            // Refresh available inputs when sheet appears
            AudioSessionManager.shared.refreshAvailableInputs()
        }
    }

    private func selectInput(uid: String?) {
        appState.appSettings.preferredInputUID = uid

        // Apply the preference immediately if possible
        do {
            try AudioSessionManager.shared.setPreferredInput(uid: uid)
        } catch {
            print("Failed to set preferred input: \(error)")
        }

        dismiss()
    }
}

// MARK: - Guide View

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Learn how to get the most out of Sonidea's features.")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .listRowBackground(palette.cardBackground)
                }

                Section {
                    NavigationLink {
                        RecordingPlaybackInfoView()
                    } label: {
                        GuideRow(
                            icon: "mic.fill",
                            title: "Recording & Playback",
                            subtitle: "Quality, EQ, speed, gain, and more"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        EditingInfoView()
                    } label: {
                        GuideRow(
                            icon: "waveform.and.scissors",
                            title: "Editing",
                            subtitle: "Trim, cut, and remove silence"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        TagsInfoView()
                    } label: {
                        GuideRow(
                            icon: "tag",
                            title: "Tags",
                            subtitle: "Organize recordings with custom labels"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        AlbumsInfoView()
                    } label: {
                        GuideRow(
                            icon: "folder",
                            title: "Albums",
                            subtitle: "Group related recordings together"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        SharedAlbumsInfoView()
                    } label: {
                        SharedAlbumsGuideRow()
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ProjectsInfoView()
                    } label: {
                        GuideRow(
                            icon: "folder.badge.plus",
                            title: "Projects",
                            subtitle: "Track multiple takes and versions"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        OverdubInfoView()
                    } label: {
                        GuideRow(
                            icon: "waveform.badge.plus",
                            title: "Overdub",
                            subtitle: "Layer recordings over existing tracks"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ExportInfoView()
                    } label: {
                        GuideRow(
                            icon: "square.and.arrow.up",
                            title: "Export",
                            subtitle: "Share recordings as WAV or ZIP"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        MapsInfoView()
                    } label: {
                        GuideRow(
                            icon: "map",
                            title: "Maps",
                            subtitle: "View recordings by location"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        RecordButtonInfoView()
                    } label: {
                        GuideRow(
                            icon: "hand.draw",
                            title: "Movable Record Button",
                            subtitle: "Position the button anywhere on screen"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        SearchInfoView()
                    } label: {
                        GuideRow(
                            icon: "magnifyingglass",
                            title: "Search & Browse",
                            subtitle: "Find recordings by title, calendar, or timeline"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        AppearanceInfoView()
                    } label: {
                        GuideRow(
                            icon: "paintpalette",
                            title: "Themes",
                            subtitle: "7 studio-inspired visual themes"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        iCloudSyncInfoView()
                    } label: {
                        GuideRow(
                            icon: "icloud",
                            title: "iCloud Sync",
                            subtitle: "Keep recordings synced across devices"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ProofReceiptsInfoView()
                    } label: {
                        GuideRow(
                            icon: "checkmark.seal",
                            title: "Proof Receipts",
                            subtitle: "Tamper-evident timestamps for your recordings"
                        )
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Features")
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
    }
}

// MARK: - Guide Row

struct GuideRow: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Storage Estimate Sheet

struct StorageEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                // Explanation section
                Section {
                    Text("Estimates are approximate and vary based on audio content, silence, and complexity.")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .listRowBackground(palette.cardBackground)
                }

                // Quality estimates
                Section {
                    ForEach(RecordingQualityPreset.allCases) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .font(.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }

                            Spacer()

                            Text(storageEstimate(for: preset))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(palette.textSecondary)
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Estimated Storage per Minute")
                        .foregroundStyle(palette.textSecondary)
                }

                // Technical notes
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("AAC formats use variable bitrate encoding")
                        } icon: {
                            Image(systemName: "waveform")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                        Label {
                            Text("Lossless (ALAC) size depends on audio complexity")
                        } icon: {
                            Image(systemName: "music.note")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                        Label {
                            Text("WAV is uncompressed with fixed, predictable size")
                        } icon: {
                            Image(systemName: "doc.badge.gearshape")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Storage Estimate")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Calculate storage estimate string for a given quality preset
    private func storageEstimate(for preset: RecordingQualityPreset) -> String {
        switch preset {
        case .standard:
            // AAC ~128kbps = ~0.96 MB/min, but VBR so varies
            return "~1 MB/min"

        case .high:
            // AAC ~256kbps = ~1.9 MB/min, but VBR so varies
            return "~2 MB/min"

        case .lossless:
            // ALAC varies greatly based on content
            // Typical speech: 2-4 MB/min, complex audio: 4-6 MB/min
            return "~3–5 MB/min"

        case .wav:
            // PCM is deterministic: sample_rate × bit_depth × channels / 8 / 1024 / 1024 × 60
            // 48000 Hz × 16-bit × 1 channel = 5.49 MB/min (mono)
            // Formula: 48000 * 16 * 1 / 8 / 1024 / 1024 * 60 = 5.49
            let sampleRate: Double = 48000
            let bitDepth: Double = 16
            let channels: Double = 1 // Mono recording
            let bytesPerSecond = sampleRate * (bitDepth / 8) * channels
            let mbPerMinute = bytesPerSecond * 60 / 1024 / 1024

            return String(format: "~%.1f MB/min", mbPerMinute)
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
    @Environment(\.themePalette) private var palette

    let urls: [URL]
    let onImport: (UUID) -> Void

    @State private var selectedAlbumID: UUID = Album.importsID
    @State private var showNewAlbumSheet = false
    @State private var newAlbumName = ""

    /// System albums (Imports and Drafts)
    private var systemAlbums: [Album] {
        // Include Imports even if it doesn't exist yet (we'll create it on import)
        var result: [Album] = []

        // Always show Imports option (will be created on import if needed)
        if let imports = appState.albums.first(where: { $0.id == Album.importsID }) {
            result.append(imports)
        } else {
            result.append(Album.imports)
        }

        // Show Drafts
        if let drafts = appState.albums.first(where: { $0.id == Album.draftsID }) {
            result.append(drafts)
        }

        return result
    }

    /// User-created albums (non-system)
    private var userAlbums: [Album] {
        appState.albums.filter { !$0.isSystem }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Files Info Section
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(palette.accent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(palette.accent)
                                .font(.title3)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(urls.count) file\(urls.count == 1 ? "" : "s") to import")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                            Text(urls.map { $0.lastPathComponent }.prefix(3).joined(separator: ", ") + (urls.count > 3 ? "..." : ""))
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(palette.cardBackground)
                }

                // MARK: - System Albums Section
                Section {
                    ForEach(systemAlbums) { album in
                        albumRow(album, isSystem: true)
                    }
                } header: {
                    Text("Default")
                } footer: {
                    if selectedAlbumID == Album.importsID {
                        Text("External files are saved to Imports by default.")
                    }
                }

                // MARK: - User Albums Section
                if !userAlbums.isEmpty {
                    Section {
                        ForEach(userAlbums) { album in
                            albumRow(album, isSystem: false)
                        }
                    } header: {
                        Text("Albums")
                    }
                }

                // MARK: - Create New Album
                Section {
                    Button {
                        showNewAlbumSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("New Album")
                                .foregroundColor(palette.textPrimary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        // Ensure Imports album exists if that's the destination
                        if selectedAlbumID == Album.importsID {
                            appState.ensureImportsAlbum()
                        }
                        dismiss()
                        onImport(selectedAlbumID)
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("New Album", isPresented: $showNewAlbumSheet) {
                TextField("Album name", text: $newAlbumName)
                Button("Cancel", role: .cancel) {
                    newAlbumName = ""
                }
                Button("Create") {
                    if !newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty {
                        let album = appState.createAlbum(name: newAlbumName.trimmingCharacters(in: .whitespaces))
                        selectedAlbumID = album.id
                    }
                    newAlbumName = ""
                }
            } message: {
                Text("Enter a name for the new album.")
            }
        }
    }

    @ViewBuilder
    private func albumRow(_ album: Album, isSystem: Bool) -> some View {
        Button {
            selectedAlbumID = album.id
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(albumIconColor(album).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: albumIconName(album))
                        .foregroundColor(albumIconColor(album))
                        .font(.system(size: 14, weight: .medium))
                }

                // Name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        AlbumTitleView(album: album, showBadge: true)
                        if isSystem {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    if album.isImportsAlbum {
                        Text("Recommended for external files")
                            .font(.caption2)
                            .foregroundColor(palette.textTertiary)
                    }
                }

                Spacer()

                // Checkmark
                if selectedAlbumID == album.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.accent)
                        .font(.title3)
                }
            }
        }
        .listRowBackground(palette.cardBackground)
    }

    private func albumIconName(_ album: Album) -> String {
        if album.isShared {
            return "person.2.fill"
        } else if album.isImportsAlbum {
            return "square.and.arrow.down"
        } else if album.isDraftsAlbum {
            return "doc.text"
        } else if album.isWatchRecordingsAlbum {
            return "applewatch"
        } else {
            return "folder"
        }
    }

    private func albumIconColor(_ album: Album) -> Color {
        if album.isShared {
            return .sharedAlbumGold
        } else if album.isImportsAlbum {
            return .blue
        } else if album.isDraftsAlbum {
            return .orange
        } else if album.isWatchRecordingsAlbum {
            return .green
        } else {
            return palette.accent
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
                        AlbumRowView(album: album)
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

// MARK: - Recording & Playback Info View

struct RecordingPlaybackInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sonidea captures ideas the moment they happen and gives you studio-level playback controls.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                InfoCard {
                    Text("Recording")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Tap the floating record button to start. Tap again to stop and save.")
                        InfoBulletRow(text: "Pause and resume mid-recording — your audio is stitched seamlessly.")
                        InfoBulletRow(text: "Adjust input gain (-6 to +6 dB) and enable a limiter to prevent clipping.")
                        InfoBulletRow(text: "Recordings are auto-tagged with your GPS location when available.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Recording quality")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Standard — AAC 128 kbps at 44.1 kHz (free tier).")
                        InfoBulletRow(text: "High — AAC 256 kbps at 48 kHz (Pro).")
                        InfoBulletRow(text: "Lossless — Apple Lossless (ALAC) at 48 kHz (Pro).")
                        InfoBulletRow(text: "WAV — Uncompressed PCM 16-bit at 48 kHz (Pro).")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Playback")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Adjust playback speed from 0.5x to 2x with pitch preserved.")
                        InfoBulletRow(text: "Use the 4-band parametric EQ to shape the sound — drag the band points on the graph.")
                        InfoBulletRow(text: "Skip Silence automatically jumps past quiet sections during playback.")
                        InfoBulletRow(text: "Add markers at any point and tap them to jump back instantly.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Live Activity")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "While recording, a Live Activity appears on the Lock Screen and Dynamic Island.")
                        InfoBulletRow(text: "Pause, resume, or stop your recording without unlocking the phone.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    InfoTipRow(text: "Enable the limiter when recording loud sources — it catches peaks that would otherwise clip.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Recording & Playback")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Editing Info View

struct EditingInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Clean up recordings with trim, cut, and silence removal — all from the waveform editor.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                InfoCard {
                    Text("How editing works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Open a recording and tap Edit to enter the waveform editor.")
                        InfoBulletRow(text: "Pinch to zoom into the waveform for precise selection.")
                        InfoBulletRow(text: "Drag the selection handles to highlight a region.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Edit actions")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Trim — keep only the selected region, remove everything else.")
                        InfoBulletRow(text: "Cut — remove the selected region and join the remaining audio.")
                        InfoBulletRow(text: "Remove Silence — automatically detect and strip all silent sections at once.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Skip Silence settings")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Adjust the silence threshold (-60 to -20 dB) and minimum duration (100–1000 ms).")
                        InfoBulletRow(text: "Toggle fade transitions on cut boundaries to avoid audio clicks.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    InfoTipRow(text: "Editing is a Pro feature. Edits create new files — your original is safe until you confirm.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Editing")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Tags Info View

struct TagsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Tags let you label ideas fast so you can find them later.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                InfoCard {
                    Text("How Tags work")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Add tags to any recording (Hook, Verse, Beat, Lyrics, To Finish).")
                        InfoBulletRow(text: "Tap tags to filter your library instantly.")
                        InfoBulletRow(text: "Use multiple tags on the same recording (e.g., Hook + Melody).")
                        InfoBulletRow(text: "The Favorite tag is built-in and cannot be deleted — use it to mark your best ideas.")
                        InfoBulletRow(text: "Create, rename, recolor, or delete tags in Settings → Manage Tags.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    InfoTipRow(text: "Tags are a Pro feature. Keep names short (1–2 words) so your filters stay clean.")
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
                Text("Albums are folders that keep your recordings organized by project, session, or vibe.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                InfoCard {
                    Text("How Albums work")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Use Albums to separate drafts, sessions, clients, or song ideas.")
                        InfoBulletRow(text: "Move a recording into an Album from its Details screen, or use swipe actions in the list.")
                        InfoBulletRow(text: "Albums work with Search and Tags — filter by Album first, then refine with tags.")
                        InfoBulletRow(text: "Rename an album by tapping the pencil icon in its detail view.")
                        InfoBulletRow(text: "Create, rename, or delete albums anytime. System albums (like Drafts) cannot be renamed or deleted.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    InfoTipRow(text: "Keep a \"Drafts\" album for quick capture, then move ideas into project-specific albums later.")
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

// MARK: - Shared Albums Guide Row (Gold-styled)

struct SharedAlbumsGuideRow: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.body)
                .foregroundStyle(Color.sharedAlbumGold)
                .shadow(color: .sharedAlbumGold.opacity(0.5), radius: 4, x: 0, y: 0)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Shared Albums")
                    .font(.body)
                    .foregroundStyle(Color.sharedAlbumGold)
                    .shadow(color: .sharedAlbumGold.opacity(0.4), radius: 3, x: 0, y: 0)
                Text("Collaborate on recordings with others")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Shared Albums Info View

struct SharedAlbumsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Shared Albums let you collaborate on recordings with trusted people via iCloud.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // What Shared Albums Are
                InfoCard {
                    Text("What is a Shared Album?")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "A collaborative album that syncs via iCloud with specific invited people.")
                        InfoBulletRow(text: "Only audio recordings are supported (no photos, videos, or other files).")
                        InfoBulletRow(text: "Shared albums appear with a gold glow, a badge, and participant count to distinguish them.")
                    }
                }
                .padding(.horizontal)

                // How to Create
                InfoCard {
                    Text("How to Create a Shared Album")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SharedAlbumInfoBullet(
                            prefix: "You cannot convert an existing album into a Shared Album.",
                            suffix: " You must create one fresh before adding recordings."
                        )
                        SharedAlbumInfoBullet(
                            prefix: "This prevents accidentally sharing a full private library or enabling mass deletion.",
                            suffix: ""
                        )
                    }

                    Text("Steps:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        SharedAlbumStepRow(number: 1, action: "Tap", highlight: "Create Shared Album", suffix: " in Settings.")
                        SharedAlbumStepRow(number: 2, action: "Name the album and choose initial settings.", highlight: nil, suffix: nil)
                        SharedAlbumStepRow(number: 3, action: "Tap", highlight: "Invite People", suffix: " to share the link.")
                        SharedAlbumStepRow(number: 4, action: "Add recordings (you'll see a confirmation before sharing).", highlight: nil, suffix: nil)
                    }
                }
                .padding(.horizontal)

                // Roles & Permissions
                InfoCard {
                    Text("Roles & Permissions")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        SharedAlbumRoleRow(
                            role: "Admin",
                            roleColor: .sharedAlbumGold,
                            description: "Invite/remove people, change settings, delete any recording."
                        )
                        SharedAlbumRoleRow(
                            role: "Member",
                            roleColor: .blue,
                            description: "Add recordings, edit their own metadata. Delete permission depends on album settings."
                        )
                        SharedAlbumRoleRow(
                            role: "Viewer",
                            roleColor: .secondary,
                            description: "Listen only. Cannot add or delete recordings."
                        )
                    }
                }
                .padding(.horizontal)

                // Confirmation & Privacy
                InfoCard {
                    Text("Privacy & Confirmation")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "When adding a recording to a shared album, you'll see a confirmation showing how many people will receive it.")
                        SharedAlbumInfoBullet(
                            prefix: "Location sharing is ",
                            highlight: "opt-in per album",
                            suffix: " and defaults to OFF."
                        )
                        InfoBulletRow(text: "If enabled, locations appear on a map with attribution (who recorded and when).")
                    }
                }
                .padding(.horizontal)

                // Trash & Restore
                InfoCard {
                    HStack(spacing: 8) {
                        Text("Shared Album Trash")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("(Anti-disaster)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Deletions in Shared Albums do not permanently delete immediately.")
                        SharedAlbumInfoBullet(
                            prefix: "Deleted recordings move to ",
                            highlight: "Shared Album Trash",
                            suffix: " for 7–30 days (configurable by admin)."
                        )
                        InfoBulletRow(text: "Restore permissions depend on album settings: either any participant can restore, or admins only.")
                        InfoBulletRow(text: "After the retention period, items are permanently removed.")
                    }
                }
                .padding(.horizontal)

                // Album Management
                InfoCard {
                    Text("Managing the Album")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "The album owner can rename the album from the toolbar menu or Settings. The new name syncs to all participants.")
                        InfoBulletRow(text: "Add comments to any recording — great for feedback or notes to collaborators.")
                        InfoBulletRow(text: "The recording creator controls whether others can download the audio file. Downloads default to off.")
                        InfoBulletRow(text: "Recordings can be flagged as sensitive. If the album requires approval, an admin must approve before the recording is visible.")
                    }
                }
                .padding(.horizontal)

                // Activity Feed
                InfoCard {
                    Text("Activity Feed")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SharedAlbumInfoBullet(
                            prefix: "Each shared album has an ",
                            highlight: "Activity",
                            suffix: " tab showing all actions: recordings added, deleted, or renamed, participant changes, settings updates, comments, and more."
                        )
                        InfoBulletRow(text: "This provides full transparency so everyone knows what happened and when.")
                    }
                }
                .padding(.horizontal)

                // Offline
                InfoCard {
                    Text("Offline support")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "If you lose connectivity, changes are queued and automatically synced when you're back online.")
                        InfoBulletRow(text: "Downloaded recordings are cached locally so you can listen without a connection.")
                    }
                }
                .padding(.horizontal)

                // Safety Warning
                InfoCard {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Safety Warning")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Only share albums with people you trust.")
                        InfoBulletRow(text: "Participants with permission can add or delete audio based on their role and album settings.")
                        InfoBulletRow(text: "Be aware of inappropriate content risks (spam, unwanted audio). Members can leave anytime.")
                    }
                }
                .padding(.horizontal)

                // Leaving a Shared Album
                InfoCard {
                    Text("Leaving a Shared Album")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SharedAlbumInfoBullet(
                            prefix: "Tap ",
                            highlight: "Leave Shared Album",
                            suffix: " in the album settings to remove yourself."
                        )
                        InfoBulletRow(text: "Your device will stop syncing that album.")
                        InfoBulletRow(text: "Recordings you added remain in the album for other participants unless they delete them.")
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Shared Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared Album Info Helpers (Gold Highlighted Text)

/// A bullet row with optional gold-highlighted inline text
struct SharedAlbumInfoBullet: View {
    let prefix: String
    var highlight: String? = nil
    var suffix: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 12, alignment: .leading)

            if let highlight = highlight {
                (Text(prefix)
                    .foregroundColor(.secondary) +
                 Text(highlight)
                    .foregroundColor(.sharedAlbumGold)
                    .fontWeight(.medium) +
                 Text(suffix)
                    .foregroundColor(.secondary))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(prefix + suffix)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A numbered step with optional gold-highlighted button/label text
struct SharedAlbumStepRow: View {
    let number: Int
    let action: String
    let highlight: String?
    let suffix: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.sharedAlbumGold)
                .frame(width: 20, alignment: .leading)

            if let highlight = highlight {
                (Text(action + " ")
                    .foregroundColor(.secondary) +
                 Text(highlight)
                    .foregroundColor(.sharedAlbumGold)
                    .fontWeight(.semibold) +
                 Text(suffix ?? "")
                    .foregroundColor(.secondary))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(action)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A role description row with colored role name
struct SharedAlbumRoleRow: View {
    let role: String
    let roleColor: Color
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 12, alignment: .leading)

            (Text(role)
                .foregroundColor(roleColor)
                .fontWeight(.semibold) +
             Text(": " + description)
                .foregroundColor(.secondary))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Projects Info View

struct ProjectsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Keep versions organized without clutter.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                InfoCard {
                    Text("How Projects work")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "A Project groups related takes for the same idea (Hook v1, Chorus v2, Verse idea).")
                        InfoBulletRow(text: "Record New Version creates a linked take (V2, V3...) inside the same Project instead of making scattered files.")
                        InfoBulletRow(text: "Mark a Best Take to highlight the version you want to keep. Press and hold a take to set it.")
                        InfoBulletRow(text: "Pin important projects so they always appear at the top of your list.")
                        InfoBulletRow(text: "Albums vs. Projects: Albums organize your library. Projects organize versions of the same idea.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    InfoTipRow(text: "Use Record New Version in a recording's Details to quickly capture another take without leaving the project.")
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

// MARK: - Overdub Info View

struct OverdubInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Record new layers over an existing track — like a one-person band.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                InfoCard {
                    Text("How Overdub works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Open any recording's Details and tap Overdub to start a session.")
                        InfoBulletRow(text: "Headphones are required — this prevents audio feedback from the speaker into the mic.")
                        InfoBulletRow(text: "You'll hear the original track (and any existing layers) while recording a new layer.")
                        InfoBulletRow(text: "Each base track supports up to 3 layers. All layers stay linked in an Overdub Group.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Mix controls")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Adjust the base track volume and layer volume independently while recording.")
                        InfoBulletRow(text: "Toggle \"Hear Previous Layers\" off if you only want to hear the base track during recording.")
                        InfoBulletRow(text: "Auto-headroom reduces the mixer gain when multiple sources play to prevent clipping.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Sync adjustment & preview")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "After recording a layer, expand Sync Adjustment to shift it ±500 ms in 10 ms steps.")
                        InfoBulletRow(text: "Tap Preview Mix to hear the base, existing layers, and the new layer together before saving.")
                        InfoBulletRow(text: "Drag the slider while previewing — playback restarts instantly with the new offset so you can dial it in by ear.")
                        InfoBulletRow(text: "Positive values delay the layer; negative values make it play earlier.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    Text("Finding overdubs in your library")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Base tracks show an orange OVERDUB badge with layer count.")
                        InfoBulletRow(text: "Layers show a purple LAYER 1/2/3 badge.")
                        InfoBulletRow(text: "In any overdub recording's Details, the Overdub Group section shows all linked tracks.")
                    }
                }
                .padding(.horizontal)

                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "headphones")
                            .font(.system(size: 14))
                            .foregroundColor(.orange)
                        Text("Tip: Wired headphones have the lowest latency. Bluetooth works but may need more sync adjustment.")
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
        .navigationTitle("Overdub")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Maps Info View

struct MapsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Maps lets you see your creative footprint—where your ideas were captured over time.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How Maps work")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Each recording can save an optional location when it's created.")
                        InfoBulletRow(text: "Open Maps to see your recording spots over time—sessions, trips, and favorite places.")
                        InfoBulletRow(text: "Tap a pin to jump straight to that recording's details.")
                        InfoBulletRow(text: "You control it anytime: enable or disable Location in iOS Settings.")
                    }
                }
                .padding(.horizontal)

                // Note
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Location is optional. Sonidea works fully without it, and you can turn it off anytime.")
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
                Text("Move the record button anywhere so it's always where your thumb expects it.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How it works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Drag the record button anywhere on screen (below the top bar).")
                        InfoBulletRow(text: "Your placement is saved automatically.")
                        InfoBulletRow(text: "Long-press the button to reveal quick options, including Reset.")
                        InfoBulletRow(text: "You can also reset it anytime in Settings → Reset Record Button Position.")
                    }
                }
                .padding(.horizontal)

                // Note
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 14))
                            .foregroundColor(.blue)
                        Text("Reset returns the button to the default bottom position.")
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
                Text("Find any recording instantly using search, or browse your library by calendar or timeline.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // Search
                InfoCard {
                    Text("Search")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Tap the magnifying glass in the top bar")
                        InfoBulletRow(text: "Search by recording name or tag (e.g., \"melody\")")
                        InfoBulletRow(text: "Filter results by tapping tag chips below the search bar")
                        InfoBulletRow(text: "Results update as you type")
                    }
                }
                .padding(.horizontal)

                // Browse modes
                InfoCard {
                    Text("Browse modes")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "List — classic scrollable list of all recordings")
                        InfoBulletRow(text: "Grid — visual card layout with color thumbnails")
                        InfoBulletRow(text: "Calendar — monthly view with dots on days you recorded; tap a day to see that day's recordings")
                        InfoBulletRow(text: "Timeline — chronological journal grouped by day, showing time, tags, location, and project context")
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "Switch browse modes using the view picker at the top of the recordings list.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Search & Browse")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Appearance Info View

struct AppearanceInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Choose from 7 studio-inspired themes to make Sonidea feel like your favorite DAW.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // Themes
                InfoCard {
                    Text("Available themes")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "System — clean default look, follows Light or Dark mode")
                        InfoBulletRow(text: "Angst Robot — purple-tinted dark theme inspired by Ableton Live")
                        InfoBulletRow(text: "Cream — warm amber tones on a light background")
                        InfoBulletRow(text: "Logic — periwinkle accents on dark, inspired by Logic Pro")
                        InfoBulletRow(text: "Fruity — orange accents on dark, inspired by FL Studio")
                        InfoBulletRow(text: "AVID — teal and mint on dark, inspired by Pro Tools")
                        InfoBulletRow(text: "Dynamite — bold red and blue on charcoal")
                    }
                }
                .padding(.horizontal)

                // How to change
                InfoCard {
                    Text("How to change your theme")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Go to Settings → Theme")
                        InfoBulletRow(text: "Tap any theme to preview it instantly")
                        InfoBulletRow(text: "Your choice applies across the entire app")
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "You can also customize tag colors in Settings → Manage Tags to match your workflow.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Themes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - iCloud Sync Info View

struct iCloudSyncInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Keep your recordings, tags, albums, and projects synced across all your Apple devices.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How iCloud Sync works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Enable iCloud Sync in Settings to start syncing automatically.")
                        InfoBulletRow(text: "Recordings, audio files, tags, albums, and projects all sync in real-time.")
                        InfoBulletRow(text: "Changes on one device appear on your other devices within seconds.")
                        InfoBulletRow(text: "Works in the background — no manual syncing needed.")
                    }
                }
                .padding(.horizontal)

                // What syncs
                InfoCard {
                    Text("What gets synced")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Audio files — your actual recordings")
                        InfoBulletRow(text: "Metadata — titles, notes, transcripts, locations")
                        InfoBulletRow(text: "Tags — all your custom tags and assignments")
                        InfoBulletRow(text: "Albums — including the Drafts and Imports system albums")
                        InfoBulletRow(text: "Projects — versions, best takes, and project notes")
                        InfoBulletRow(text: "Deletions — trashed items sync across devices too")
                    }
                }
                .padding(.horizontal)

                // Status indicators
                InfoCard {
                    Text("Sync status indicators")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundColor(.green)
                            Text("Synced — Everything is up to date")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                .foregroundColor(.blue)
                            Text("Syncing — Upload or download in progress")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundColor(.red)
                            Text("Error — Check your connection and try again")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "person.icloud")
                                .foregroundColor(.yellow)
                            Text("Sign in required — Log in to iCloud")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal)

                // Requirements
                InfoCard {
                    Text("Requirements")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Signed in to iCloud on all devices")
                        InfoBulletRow(text: "Sonidea installed on each device")
                        InfoBulletRow(text: "Sufficient iCloud storage for audio files")
                        InfoBulletRow(text: "Internet connection for syncing")
                    }
                }
                .padding(.horizontal)

                // Tips
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tips for best results:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("• Use \"Sync Now\" after making many changes offline\n• Large recordings may take longer to upload\n• Edits and deletions sync immediately when online")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Export Info View

struct ExportInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Export your recordings as high-quality WAV files, or bulk-export an entire album as a ZIP archive.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // Single export
                InfoCard {
                    Text("Exporting a single recording")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Open a recording and tap the share icon")
                        InfoBulletRow(text: "The recording is converted to 16-bit PCM WAV at its original sample rate")
                        InfoBulletRow(text: "Share via AirDrop, Files, Messages, or any app that accepts audio")
                    }
                }
                .padding(.horizontal)

                // Bulk export
                InfoCard {
                    Text("Bulk export (ZIP)")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Export all recordings or a single album at once")
                        InfoBulletRow(text: "Creates a ZIP file with WAV audio organized into album folders")
                        InfoBulletRow(text: "Includes a manifest.json with metadata: titles, dates, durations, tags, and locations")
                        InfoBulletRow(text: "Recordings without an album are placed in an \"Unsorted\" folder")
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "The manifest file makes it easy to catalog or import your recordings into a DAW or project manager.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Export")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Proof Receipts Info View

struct ProofReceiptsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Proof receipts create a tamper-evident record of your recordings, proving when and where they were captured.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How it works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "A SHA-256 hash (digital fingerprint) of your audio file is computed")
                        InfoBulletRow(text: "The hash is uploaded to Apple's CloudKit servers, which stamp it with a server-side timestamp")
                        InfoBulletRow(text: "If location was captured, a separate hash of the GPS coordinates is stored as well")
                        InfoBulletRow(text: "The result is a verifiable receipt that the recording existed at that time and place")
                    }
                }
                .padding(.horizontal)

                // Verification
                InfoCard {
                    Text("Verification")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Sonidea re-computes the hash and compares it to the stored receipt")
                        InfoBulletRow(text: "If the file has been altered, the hashes won't match and the status shows a mismatch warning")
                        InfoBulletRow(text: "An unmodified recording shows a green \"Proven\" status")
                    }
                }
                .padding(.horizontal)

                // Status indicators
                InfoCard {
                    Text("Status indicators")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Proven — receipt verified, file unmodified")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            Text("Pending — waiting to upload (e.g., offline)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Mismatch — file was modified after proof was created")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "Proof receipts work offline too. Pending proofs are automatically uploaded when you reconnect.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Proof Receipts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(AppState())
}
