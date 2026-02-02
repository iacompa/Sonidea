//
//  WatchContentView.swift
//  SonideaWatch Watch App
//
//  Single root view: recordings list with floating movable record button.
//  Record button hides when navigated into playback detail.
//

import AVFoundation
import SwiftUI
import WatchKit

struct WatchContentView: View {
    @Environment(WatchAppState.self) private var appState
    @Environment(\.watchPalette) private var palette

    @State private var recorder = WatchRecorderManager()
    @State private var isDragging = false
    @State private var dragStartPosition: CGPoint = .zero
    @State private var showResetPill = false
    @State private var isPulsing = false
    @State private var navigationPath = NavigationPath()
    @State private var showSyncInfo = false
    @State private var showMicDeniedAlert = false

    private let buttonDiameter: CGFloat = 56
    private let buttonPadding: CGFloat = 10

    /// Hide record button when navigated into a detail screen
    private var isOnRootList: Bool {
        navigationPath.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size
            let radius = buttonDiameter / 2

            let minX = buttonPadding + radius
            let maxX = containerSize.width - buttonPadding - radius
            let minY = buttonPadding + radius
            let maxY = containerSize.height - buttonPadding - radius

            let defaultPosition = CGPoint(
                x: containerSize.width / 2,
                y: containerSize.height - radius - 12
            )
            let buttonPosition = appState.recordButtonPosition ?? defaultPosition

            ZStack {
                // Layer 1: Main content
                if recorder.isRecording {
                    recordingHUD
                } else {
                    recordingsList
                }

                // Layer 2: Reset pill (only on root, not recording)
                if showResetPill && isOnRootList && !recorder.isRecording {
                    resetPillView(buttonPosition: buttonPosition, containerSize: containerSize)
                }

                // Layer 3: Floating record button (stays in place during recording)
                if isOnRootList {
                    floatingRecordButton
                        .frame(width: buttonDiameter, height: buttonDiameter)
                        .shadow(color: .black.opacity(isDragging ? 0.5 : 0.3), radius: isDragging ? 8 : 5, y: isDragging ? 4 : 2)
                        .scaleEffect(isDragging ? 1.08 : 1.0)
                        .position(buttonPosition)
                        .highPriorityGesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    // Disable dragging while recording
                                    guard !recorder.isRecording else { return }
                                    let distance = sqrt(
                                        value.translation.width * value.translation.width +
                                        value.translation.height * value.translation.height
                                    )
                                    if distance > 5 {
                                        if !isDragging {
                                            isDragging = true
                                            dragStartPosition = buttonPosition
                                            if showResetPill { showResetPill = false }
                                        }
                                        let newX = dragStartPosition.x + value.translation.width
                                        let newY = dragStartPosition.y + value.translation.height
                                        appState.recordButtonPosition = CGPoint(
                                            x: min(max(newX, minX), maxX),
                                            y: min(max(newY, minY), maxY)
                                        )
                                    }
                                }
                                .onEnded { value in
                                    if isDragging {
                                        let newX = dragStartPosition.x + value.translation.width
                                        let newY = dragStartPosition.y + value.translation.height
                                        appState.recordButtonPosition = CGPoint(
                                            x: min(max(newX, minX), maxX),
                                            y: min(max(newY, minY), maxY)
                                        )
                                        appState.persistRecordButtonPosition()
                                        isDragging = false
                                    } else if !showResetPill {
                                        handleRecordTap()
                                    }
                                }
                        )
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.5)
                                .onEnded { _ in
                                    // Disable long press while recording
                                    guard !recorder.isRecording else { return }
                                    if !isDragging {
                                        WKInterfaceDevice.current().play(.click)
                                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                            showResetPill = true
                                        }
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                            withAnimation(.easeOut(duration: 0.2)) {
                                                showResetPill = false
                                            }
                                        }
                                    }
                                }
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.85)))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isOnRootList)
        }
        .ignoresSafeArea(edges: .bottom)
        .background(palette.background.ignoresSafeArea())
        .onChange(of: recorder.isRecording) { _, newValue in
            isPulsing = newValue
        }
        .alert("Microphone Access", isPresented: $showMicDeniedAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Sonidea needs microphone access to record. Please enable it in Settings > Privacy & Security > Microphone on your iPhone.")
        }
        .onAppear {
            // Handle pending start recording from complication intent
            if UserDefaults.standard.bool(forKey: "pendingStartRecording") {
                UserDefaults.standard.set(false, forKey: "pendingStartRecording")
                if !recorder.isRecording {
                    handleRecordTap()
                }
            }
        }
    }

    // MARK: - Recording HUD with live waveform animation

    private var recordingHUD: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Duration timer
                Text(formatDurationWithTenths(recorder.currentDuration))
                    .font(.system(size: 38, weight: .light, design: .monospaced))
                    .foregroundColor(palette.liveRecordingAccent)
                    .contentTransition(.numericText())
                    .padding(.top, 6)

                // Waveform — right below timer
                LiveWaveformBars(palette: palette, isActive: recorder.isRecording, audioLevel: recorder.currentLevel)
                    .frame(height: 28)
                    .padding(.horizontal, 4)
                    .padding(.top, 10)

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(palette.recordButton)
                            .frame(width: 7, height: 7)
                            .scaleEffect(isPulsing ? 1.5 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: isPulsing)

                        Text("Recording")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(palette.textSecondary)
                            .textCase(.uppercase)
                            .tracking(0.6)
                    }
                }
            }
        }
    }

    // MARK: - Recordings List

    private var recordingsList: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if appState.recordings.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(appState.recordings) { recording in
                            NavigationLink(value: recording) {
                                recordingRow(recording)
                            }
                            .listRowBackground(
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(palette.surface)
                                    .padding(.vertical, 2)
                            )
                            .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        }
                        .onDelete { offsets in
                            appState.deleteRecording(at: offsets)
                        }

                        // Spacer for floating button
                        Color.clear
                            .frame(height: 70)
                            .listRowBackground(Color.clear)
                    }
                    .listStyle(.plain)
                }
            }
            .navigationDestination(for: WatchRecordingItem.self) { recording in
                WatchPlaybackView(recording: recording)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSyncInfo = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 14))
                                .foregroundColor(palette.textSecondary)
                            if appState.pendingTransferCount > 0 {
                                Text("\(appState.pendingTransferCount)")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(2)
                                    .background(Color.orange)
                                    .clipShape(Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .onAppear {
                appState.retryPendingTransfers()
            }
            .alert("Sync to iPhone", isPresented: $showSyncInfo) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("With a Pro plan, recordings automatically sync to the ⌚️ Recordings album on your iPhone.\n\nEnable \"Auto Sync Watch Recordings\" in Sonidea settings on your iPhone.\n\nWithout Pro, use the Share button to send recordings manually.")
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 36, weight: .light))
                .foregroundColor(palette.textSecondary.opacity(0.4))
            Text("No recordings")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(palette.textSecondary)
            Text("Tap to record")
                .font(.system(size: 13))
                .foregroundColor(palette.textSecondary.opacity(0.6))
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    // MARK: - Recording Row

    private func recordingRow(_ recording: WatchRecordingItem) -> some View {
        HStack(spacing: 12) {
            // Icon tile
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.accent.opacity(0.15))
                    .frame(width: 38, height: 38)
                Image(systemName: "waveform")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Text(recording.title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    if recording.isTransferred {
                        Image(systemName: "iphone")
                            .font(.system(size: 10))
                            .foregroundColor(palette.accent.opacity(0.7))
                    }
                }

                HStack(spacing: 5) {
                    Text(recording.formattedDuration)
                        .font(.system(size: 12, design: .monospaced))
                    Text("·")
                    Text(recording.shortDate)
                        .font(.system(size: 12))
                }
                .foregroundColor(palette.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Floating Record Button

    private var floatingRecordButton: some View {
        ZStack {
            Circle()
                .stroke(palette.recordButton.opacity(0.3), lineWidth: 3)

            Circle()
                .fill(palette.recordButton)
                .padding(4)

            if recorder.isRecording {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "mic.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: recorder.isRecording)
    }

    // MARK: - Reset Pill

    private func resetPillView(buttonPosition: CGPoint, containerSize: CGSize) -> some View {
        let aboveSpace = buttonPosition.y - buttonDiameter / 2
        let pillY = aboveSpace > 40
            ? buttonPosition.y - buttonDiameter / 2 - 22
            : buttonPosition.y + buttonDiameter / 2 + 22

        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                appState.resetRecordButtonPosition()
                showResetPill = false
            }
        } label: {
            Text("Reset")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 5)
                .background(Capsule().fill(palette.surface))
        }
        .buttonStyle(.plain)
        .position(x: buttonPosition.x, y: pillY)
        .transition(.opacity.combined(with: .scale(scale: 0.8)))
    }

    // MARK: - Actions

    private func handleRecordTap() {
        if recorder.isRecording {
            guard let (url, duration) = recorder.stopRecording() else { return }
            let title = appState.generateTitle()
            let item = WatchRecordingItem(fileURL: url, duration: duration, title: title)
            appState.addRecording(item)
            WatchConnectivityService.shared.transferRecording(item)
        } else {
            if !recorder.startRecording() {
                WKInterfaceDevice.current().play(.failure)
                // Check if failure is due to microphone permission denial
                if AVAudioSession.sharedInstance().recordPermission == .denied {
                    showMicDeniedAlert = true
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatDurationWithTenths(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Live Waveform Bars (Apple Voice Memos style)

struct LiveWaveformBars: View {
    let palette: WatchThemePalette
    let isActive: Bool
    /// Normalized audio level 0.0–1.0 from the recorder
    var audioLevel: Float = 0

    private let barCount = 28
    @State private var barHeights: [CGFloat] = Array(repeating: 0.08, count: 28)

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(0..<barCount, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1)
                    .fill(palette.liveRecordingAccent.opacity(barOpacity(for: index)))
                    .frame(width: 3, height: max(2, barHeights[index] * 28))
                    .animation(
                        .easeInOut(duration: 0.08),
                        value: barHeights[index]
                    )
            }
        }
        .onChange(of: audioLevel) { _, newLevel in
            updateBars(level: CGFloat(newLevel))
        }
        .onDisappear { barHeights = Array(repeating: 0.08, count: barCount) }
    }

    /// Fade bars at edges for a polished look
    private func barOpacity(for index: Int) -> Double {
        let edgeFade = 3
        if index < edgeFade {
            return 0.4 + 0.6 * Double(index) / Double(edgeFade)
        } else if index >= barCount - edgeFade {
            return 0.4 + 0.6 * Double(barCount - 1 - index) / Double(edgeFade)
        }
        return 1.0
    }

    private func updateBars(level: CGFloat) {
        withAnimation {
            for i in 0..<barCount {
                // Center bars taller, edges shorter
                let centerWeight = 1.0 - abs(CGFloat(i - barCount / 2)) / CGFloat(barCount / 2) * 0.4
                // Mix audio level with a small random variance for organic movement
                let variance = CGFloat.random(in: -0.12...0.12)
                let height = (level + variance) * centerWeight
                barHeights[i] = max(0.06, min(1.0, height))
            }
        }
    }
}
