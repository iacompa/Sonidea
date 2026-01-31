//
//  OverdubSessionView.swift
//  Sonidea
//
//  Created by Claude on 1/25/26.
//

import SwiftUI
import AVFoundation

/// Full-screen view for overdub (Record Over Track) sessions
struct OverdubSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @Environment(AppState.self) private var appState

    /// The base recording to overdub on
    let baseRecording: RecordingItem

    /// Callback when a new layer is saved
    var onLayerSaved: ((RecordingItem) -> Void)?

    // MARK: - State

    @State private var engine = OverdubEngine()
    @State private var overdubGroup: OverdubGroup?
    @State private var existingLayers: [RecordingItem] = []

    @State private var isRecording = false
    @State private var isPrepared = false
    @State private var showMixer = false
    @State private var isBouncing = false
    @State private var recordedLayerURL: URL?
    
    @State private var recordedLayerDuration: TimeInterval = 0

    @State private var showHeadphonesAlert = false
    @State private var showMaxLayersAlert = false
    @State private var showDiscardConfirmation = false
    @State private var showRecordingCloseConfirmation = false
    @State private var showSaveConfirmation = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    @State private var isStartingRecording = false  // Brief wait during Bluetooth route setup
    @State private var offsetSliderValue: Double = 0 // For sync adjustment
    @State private var showOffsetSlider = false
    @State private var isPreviewing = false
    @State private var bounceErrorMessage: String?
    @State private var showBounceError = false
    @State private var showTrackAlignment = false
    @State private var expandedLayerSync: UUID? // which layer has its sync slider open
    @State private var layerToDelete: RecordingItem?
    @State private var showDeleteLayerConfirmation = false
    @State private var bounceToastMessage: String?
    @State private var showBounceConfirmation = false
    @State private var proUpgradeContext: ProFeatureContext?
    @State private var showTipJar = false

    var body: some View {
        NavigationStack {
            overdubNavContent
        }
    }

    private var overdubNavContent: some View {
        mainContent
            .navigationTitle("Record Over Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { overdubToolbar }
            .sheet(isPresented: $showMixer) { mixerSheet }
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
            .sheet(isPresented: $showTipJar) {
                TipJarView()
            }
            .sheet(isPresented: $showTrackAlignment) {
                TrackAlignmentView(
                    baseRecording: baseRecording,
                    layers: existingLayers,
                    unsavedLayerURL: recordedLayerURL,
                    unsavedLayerOffset: $offsetSliderValue,
                    mixSettings: overdubGroup?.mixSettings ?? MixSettings(),
                    onOffsetsChanged: { changes in
                        for (id, offset) in changes {
                            appState.updateLayerOffset(recordingId: id, offsetSeconds: offset)
                        }
                        // Reload layers and re-prepare engine
                        if let groupId = baseRecording.overdubGroupId,
                           let group = appState.overdubGroup(for: groupId) {
                            self.overdubGroup = group
                            self.existingLayers = appState.layerRecordings(for: group)
                        }
                        prepareEngine()
                    }
                )
            }
            .modifier(OverdubAlertsModifier(
                showHeadphonesAlert: $showHeadphonesAlert,
                showMaxLayersAlert: $showMaxLayersAlert,
                showDiscardConfirmation: $showDiscardConfirmation,
                showErrorAlert: $showErrorAlert,
                showBounceError: $showBounceError,
                showRecordingCloseConfirmation: $showRecordingCloseConfirmation,
                errorMessage: $errorMessage,
                bounceErrorMessage: $bounceErrorMessage,
                maxLayers: OverdubGroup.maxLayers,
                onDiscard: {
                    discardRecording()
                    engine.cleanup()
                    dismiss()
                },
                onStopAndClose: {
                    stopRecording()
                    if let url = recordedLayerURL {
                        try? FileManager.default.removeItem(at: url)
                    }
                    recordedLayerURL = nil
                    recordedLayerDuration = 0
                    engine.cleanup()
                    dismiss()
                }
            ))
            .alert("Delete Layer?", isPresented: $showDeleteLayerConfirmation) {
                Button("Delete", role: .destructive) {
                    if let layer = layerToDelete {
                        deleteLayer(layer)
                    }
                }
                Button("Cancel", role: .cancel) {
                    layerToDelete = nil
                }
            } message: {
                Text("This will permanently remove this layer from the overdub group.")
            }
            .alert("Overwrite Existing Mix?", isPresented: $showBounceConfirmation) {
                Button("Overwrite", role: .destructive) {
                    bounceMix()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("A bounced mix already exists for this recording. This will replace it.")
            }
            .onAppear {
                setupSession()
            }
            .onDisappear {
                cleanup()
            }
            .onReceive(NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)) { notification in
                handleRouteChange(notification)
            }
            .onChange(of: engine.state) { oldValue, newValue in
                // Detect when engine auto-stops (e.g. from write failure)
                if oldValue == .recording && newValue == .idle && isRecording {
                    isRecording = false
                    if let writeError = engine.recordingError {
                        errorMessage = writeError
                        showErrorAlert = true
                        // Discard corrupt file
                        if let url = recordedLayerURL {
                            try? FileManager.default.removeItem(at: url)
                        }
                        recordedLayerURL = nil
                        recordedLayerDuration = 0
                    }
                }
                // Reset preview state when playback ends naturally
                if oldValue == .playing && newValue == .idle && isPreviewing {
                    isPreviewing = false
                    prepareEngine()
                }
            }
    }

    // MARK: - Extracted Body Parts

    private var mainContent: some View {
        ZStack(alignment: .bottom) {
            palette.background.ignoresSafeArea()

            VStack(spacing: 0) {
                statusBar
                Divider()
                ScrollView {
                    VStack(spacing: 24) {
                        baseTrackSection
                        layersSection
                        if !isRecording && recordedLayerURL == nil {
                            recordingControlsSection
                        }
                        if isRecording {
                            activeRecordingSection
                        }
                        if recordedLayerURL != nil && !isRecording {
                            postRecordingSection
                        }
                        mixControlsSection
                    }
                    .padding()
                }
            }

            // Bounce success toast
            if let toast = bounceToastMessage {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(toast)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.85))
                )
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .animation(.easeInOut(duration: 0.3), value: bounceToastMessage)
            }
        }
    }

    @ToolbarContentBuilder
    private var overdubToolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Close") {
                handleClose()
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                if appState.supportManager.canUseProFeatures || ProFeatureContext.recordOverTrack.isFree {
                    showMixer = true
                } else {
                    proUpgradeContext = .mixer
                }
            } label: {
                Image(systemName: "slider.vertical.3")
            }
            .disabled(isRecording)
        }
    }

    @ViewBuilder
    private var mixerSheet: some View {
        if overdubGroup != nil {
            MixerView(
                mixSettings: Binding(
                    get: {
                        overdubGroup?.mixSettings ?? MixSettings()
                    },
                    set: { newValue in
                        overdubGroup?.mixSettings = newValue
                        engine.applyMixSettings(newValue)
                        if let groupId = overdubGroup?.id,
                           let gIdx = appState.overdubGroups.firstIndex(where: { $0.id == groupId }) {
                            appState.overdubGroups[gIdx].mixSettings = newValue
                        }
                    }
                ),
                layerCount: existingLayers.count,
                bounceTitle: "\(baseRecording.title) - Mix",
                onBounce: {
                    requestBounce()
                },
                isBouncing: isBouncing
            )
            .presentationDetents([.medium, .large])
            .onAppear {
                overdubGroup?.mixSettings.syncLayerCount(existingLayers.count)
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        VStack(spacing: 4) {
            HStack {
                // Headphones indicator
                HStack(spacing: 6) {
                    Image(systemName: AudioSessionManager.shared.isHeadphoneMonitoringActive() ? "headphones" : "headphones.slash")
                        .font(.system(size: 14))
                        .foregroundColor(AudioSessionManager.shared.isHeadphoneMonitoringActive() ? .green : palette.recordButton)
                        .accessibilityLabel(AudioSessionManager.shared.isHeadphoneMonitoringActive() ? "Headphones connected" : "Headphones not connected")

                    Text(AudioSessionManager.shared.isHeadphoneMonitoringActive() ? "Connected" : "No Headphones")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                // Current output
                Text(AudioSessionManager.shared.currentOutputName())
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            // Bluetooth latency warning
            if AudioSessionManager.shared.isBluetoothOutput() {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("Bluetooth detected — expect audio delay. Wired headphones are strongly recommended for overdub recording.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(palette.surface.opacity(0.5))
    }

    // MARK: - Base Track Section

    private var baseTrackSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("BASE TRACK")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(palette.textSecondary)

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    // Icon
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(palette.surface)
                            .frame(width: 50, height: 50)

                        Image(systemName: "waveform")
                            .font(.system(size: 20))
                            .foregroundColor(palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text(baseRecording.title)
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)

                        Text(formatDuration(baseRecording.duration))
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()

                    // Loop toggle for base track
                    Button {
                        toggleLoopForBase()
                    } label: {
                        Image(systemName: (overdubGroup?.mixSettings.baseChannel.isLooped ?? false) ? "repeat.1" : "repeat")
                            .font(.system(size: 16))
                            .foregroundColor((overdubGroup?.mixSettings.baseChannel.isLooped ?? false) ? .white : palette.textTertiary)
                            .frame(width: 34, height: 34)
                            .background((overdubGroup?.mixSettings.baseChannel.isLooped ?? false) ? Color.blue : palette.inputBackground)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRecording)
                    .accessibilityLabel("Toggle loop for base track")

                    // Play/Pause base
                    Button {
                        toggleBasePlayback()
                    } label: {
                        Image(systemName: engine.state == .playing ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 36))
                            .foregroundColor(palette.accent)
                    }
                    .buttonStyle(.plain)
                    .disabled(isRecording)
                    .accessibilityLabel(engine.state == .playing ? "Pause base track" : "Play base track")
                }
                .padding()

                // Playback position bar
                if engine.state == .playing || engine.state == .recording {
                    TrackPlaybackIndicator(
                        currentTime: engine.currentPlaybackTime,
                        trackDuration: baseRecording.duration,
                        trackOffset: 0,
                        isLooped: overdubGroup?.mixSettings.baseChannel.isLooped ?? false,
                        tintColor: palette.accent
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 8)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.surface)
            )
        }
    }

    // MARK: - Layers Section

    private var layersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("LAYERS")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textSecondary)

                Spacer()

                Text("\(existingLayers.count)/\(OverdubGroup.maxLayers)")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            VStack(spacing: 8) {
                ForEach(0..<OverdubGroup.maxLayers, id: \.self) { index in
                    layerRow(at: index)
                }
            }

            // Align Tracks (always visible when layers exist)
            if !existingLayers.isEmpty {
                Button {
                    showTrackAlignment = true
                } label: {
                    HStack {
                        Image(systemName: "timeline.selection")
                        Text("Align Tracks")
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                    }
                    .foregroundColor(palette.accent)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(palette.surface)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private func layerRow(at index: Int) -> some View {
        let layerNumber = index + 1

        if index < existingLayers.count {
            // Existing layer
            let layer = existingLayers[index]

            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(palette.accent.opacity(0.2))
                            .frame(width: 36, height: 36)

                        Text("\(layerNumber)")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(palette.accent)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.title)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)

                        Text(formatDuration(layer.duration))
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()

                    // Offset indicator
                    Text(formatOffset(layer.overdubOffsetSeconds))
                        .font(.caption2)
                        .foregroundColor(layer.overdubOffsetSeconds == 0 ? palette.textTertiary : palette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.inputBackground))

                    // Loop toggle for layer
                    Button {
                        toggleLoopForLayer(at: index)
                    } label: {
                        let isLooped = layerIsLooped(at: index)
                        Image(systemName: isLooped ? "repeat.1" : "repeat")
                            .font(.system(size: 12))
                            .foregroundColor(isLooped ? .white : palette.textTertiary)
                            .frame(width: 28, height: 28)
                            .background(isLooped ? Color.blue : palette.inputBackground)
                            .cornerRadius(6)
                    }
                    .buttonStyle(.plain)

                    // Sync adjust toggle
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            expandedLayerSync = expandedLayerSync == layer.id ? nil : layer.id
                        }
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 14))
                            .foregroundColor(expandedLayerSync == layer.id ? palette.accent : palette.textSecondary)
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)

                    // Delete layer
                    Button {
                        layerToDelete = layer
                        showDeleteLayerConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .foregroundColor(.red.opacity(0.7))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.plain)
                }
                .padding()

                // Playback position bar for layer
                if engine.state == .playing || engine.state == .recording {
                    TrackPlaybackIndicator(
                        currentTime: engine.currentPlaybackTime,
                        trackDuration: layer.duration,
                        trackOffset: layer.overdubOffsetSeconds,
                        isLooped: layerIsLooped(at: index),
                        tintColor: palette.accent
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                }

                // Per-layer sync adjustment (expandable)
                if expandedLayerSync == layer.id {
                    VStack(spacing: 6) {
                        Slider(
                            value: Binding(
                                get: { layer.overdubOffsetSeconds },
                                set: { newVal in
                                    appState.updateLayerOffset(recordingId: layer.id, offsetSeconds: newVal)
                                    // Update local copy
                                    if let idx = existingLayers.firstIndex(where: { $0.id == layer.id }) {
                                        existingLayers[idx].overdubOffsetSeconds = newVal
                                    }
                                    if isPreviewing {
                                        if let layerIdx = existingLayers.firstIndex(where: { $0.id == layer.id }) {
                                            engine.updateLayerOffset(at: layerIdx, offset: newVal)
                                        }
                                    }
                                }
                            ),
                            in: -1.5...1.5,
                            step: 0.001
                        )
                        .tint(palette.accent)

                        HStack {
                            Text("-1500ms")
                                .font(.caption2)
                            Spacer()
                            Text(formatOffset(layer.overdubOffsetSeconds))
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                                .foregroundColor(palette.accent)
                            Spacer()
                            Text("+1500ms")
                                .font(.caption2)
                        }
                        .foregroundColor(palette.textTertiary)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(palette.surface)
            )
        } else {
            // Empty slot
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(palette.textTertiary.opacity(0.3), lineWidth: 1.5)
                        .frame(width: 36, height: 36)

                    Text("\(layerNumber)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(palette.textTertiary)
                }

                Text("Empty")
                    .font(.subheadline)
                    .foregroundColor(palette.textTertiary)

                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.textTertiary.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Recording Controls Section

    private var recordingControlsSection: some View {
        VStack(spacing: 16) {
            if existingLayers.count < OverdubGroup.maxLayers {
                Button {
                    startRecording()
                } label: {
                    HStack {
                        if isStartingRecording {
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.8)
                            Text("Starting…")
                                .fontWeight(.semibold)
                        } else {
                            Image(systemName: "record.circle")
                                .font(.system(size: 20))
                            Text("Record Layer \(existingLayers.count + 1)")
                                .fontWeight(.semibold)
                        }
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isPrepared && !isStartingRecording ? palette.recordButton : palette.recordButton.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isPrepared || isStartingRecording)
                .opacity(isPrepared ? 1.0 : 0.6)
                .accessibilityLabel("Record new layer")

                if !isPrepared {
                    HStack(spacing: 6) {
                        if errorMessage != nil {
                            Button {
                                errorMessage = nil
                                prepareEngine()
                            } label: {
                                Label("Retry Preparation", systemImage: "arrow.clockwise")
                                    .font(.caption)
                                    .foregroundColor(palette.accent)
                            }
                        } else {
                            ProgressView()
                                .scaleEffect(0.8)
                            Text("Preparing audio engine...")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                } else {
                    Text("The base track will play while you record")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
            } else {
                Text("Maximum layers reached")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(palette.surface)
                    )
            }
        }
    }

    // MARK: - Active Recording Section

    private var activeRecordingSection: some View {
        VStack(spacing: 16) {
            // Recording indicator
            HStack(spacing: 10) {
                Circle()
                    .fill(palette.liveRecordingAccent)
                    .frame(width: 12, height: 12)

                Text("Recording Layer \(existingLayers.count + 1)")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)

                Spacer()

                RecordingTimerDisplay(duration: engine.recordingDuration)
                    .foregroundColor(palette.liveRecordingAccent)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.recordButton.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(palette.recordButton.opacity(0.3), lineWidth: 1)
                    )
            )

            // Level meter
            ProgressView(value: Double(engine.meterLevel))
                .progressViewStyle(.linear)
                .tint(engine.meterLevel > 0.9 ? palette.recordButton : .green)

            // Stop button
            Button {
                stopRecording()
            } label: {
                HStack {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 16))
                    Text("Stop Recording")
                        .fontWeight(.semibold)
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(palette.recordButton)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
        }
    }

    // MARK: - Post Recording Section

    private var postRecordingSection: some View {
        VStack(spacing: 16) {
            // Preview info
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)

                Text("Layer \(existingLayers.count + 1) Recorded")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)

                Spacer()

                Text(formatDuration(recordedLayerDuration))
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.green.opacity(0.1))
            )

            // Offset adjustment
            VStack(alignment: .leading, spacing: 8) {
                Button {
                    showOffsetSlider.toggle()
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                        Text("Sync Adjustment")
                        Spacer()
                        Text(formatOffset(offsetSliderValue))
                            .foregroundColor(palette.textSecondary)
                        Image(systemName: showOffsetSlider ? "chevron.up" : "chevron.down")
                            .font(.caption)
                    }
                    .foregroundColor(palette.textPrimary)
                }
                .buttonStyle(.plain)

                if showOffsetSlider {
                    VStack(spacing: 8) {
                        Slider(value: $offsetSliderValue, in: -1.5...1.5, step: 0.001)
                            .tint(palette.accent)
                            .onChange(of: offsetSliderValue) {
                                if isPreviewing {
                                    engine.updatePreviewOffset(offsetSliderValue)
                                }
                            }

                        HStack {
                            Text("-1500ms")
                                .font(.caption2)
                            Spacer()
                            Text("+1500ms")
                                .font(.caption2)
                        }
                        .foregroundColor(palette.textTertiary)

                        // Preview playback button
                        Button {
                            if isPreviewing {
                                stopPreview()
                            } else {
                                startPreview()
                            }
                        } label: {
                            HStack {
                                Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                                Text(isPreviewing ? "Stop Preview" : "Preview Mix")
                            }
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(isPreviewing ? palette.textPrimary : .white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isPreviewing ? palette.surface : palette.accent)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(isPreviewing ? palette.stroke : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.surface)
            )

            // Save/Discard buttons
            HStack(spacing: 12) {
                Button {
                    showDiscardConfirmation = true
                } label: {
                    Text("Discard")
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(palette.surface)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Discard recorded layer")

                Button {
                    saveRecording()
                } label: {
                    Text("Save Layer")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(palette.accent)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save recorded layer")
            }
        }
    }

    // MARK: - Mix Controls Section

    private var mixControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MONITORING")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(palette.textSecondary)

            VStack(spacing: 16) {
                // Base volume
                HStack {
                    Text("Base Volume")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Slider(value: Binding(
                        get: { Double(engine.baseVolume) },
                        set: { engine.baseVolume = Float($0) }
                    ), in: 0...1)
                    .frame(width: 150)
                    .tint(palette.accent)
                }

                // Layer monitoring toggle
                Toggle(isOn: $engine.monitorLayers) {
                    Text("Hear Previous Layers")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                }
                .tint(palette.accent)

                // Layer volume (if monitoring enabled)
                if engine.monitorLayers && !existingLayers.isEmpty {
                    HStack {
                        Text("Layer Volume")
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        Slider(value: Binding(
                            get: { Double(engine.layerVolume) },
                            set: { engine.layerVolume = Float($0) }
                        ), in: 0...1)
                        .frame(width: 150)
                        .tint(palette.accent)
                    }
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.surface)
            )
        }
    }

    // MARK: - Actions

    private func deleteLayer(_ layer: RecordingItem) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        // Stop preview if running
        if isPreviewing { stopPreview() }

        // Close any expanded sync slider for this layer
        if expandedLayerSync == layer.id { expandedLayerSync = nil }

        // Remove from overdub group and move to trash
        appState.removeOverdubLayer(layer)

        // Reload layers from appState
        if let groupId = baseRecording.overdubGroupId,
           let group = appState.overdubGroup(for: groupId) {
            self.overdubGroup = group
            self.existingLayers = appState.layerRecordings(for: group)
        } else {
            existingLayers = []
        }

        // Re-prepare engine with updated layers
        prepareEngine()
        layerToDelete = nil
    }

    private func setupSession() {
        // Guard against concurrent recording
        if appState.recorder.isRecording {
            errorMessage = "Cannot start overdub while a recording is in progress. Please stop the current recording first."
            showErrorAlert = true
            return
        }

        #if DEBUG
        print("🎙️ [OverdubSessionView] setupSession() called")
        print("🎙️ [OverdubSessionView] Base recording: \(baseRecording.title)")
        print("🎙️ [OverdubSessionView] Base URL: \(baseRecording.fileURL)")
        #endif

        // Check for existing overdub group
        if let groupId = baseRecording.overdubGroupId,
           let group = appState.overdubGroup(for: groupId) {
            self.overdubGroup = group
            self.existingLayers = appState.layerRecordings(for: group)
            #if DEBUG
            print("🎙️ [OverdubSessionView] Found existing overdub group with \(existingLayers.count) layers")
            #endif
        }

        // Check headphones
        let hasHeadphones = AudioSessionManager.shared.isHeadphoneMonitoringActive()
        #if DEBUG
        print("🎙️ [OverdubSessionView] Headphones connected: \(hasHeadphones)")
        #endif
        if !hasHeadphones {
            showHeadphonesAlert = true
        }

        // Prepare engine
        prepareEngine()
    }

    private func prepareEngine() {
        let layerURLs = existingLayers.map { $0.fileURL }
        let layerOffsets = existingLayers.map { $0.overdubOffsetSeconds }

        // Build loop flags from mix settings: [base, layer0, layer1, ...]
        var settings = overdubGroup?.mixSettings ?? MixSettings()
        settings.syncLayerCount(existingLayers.count)
        var flags = [settings.baseChannel.isLooped]
        for ch in settings.layerChannels {
            flags.append(ch.isLooped)
        }

        #if DEBUG
        print("🎙️ [OverdubSessionView] Preparing engine with base: \(baseRecording.fileURL.lastPathComponent)")
        print("🎙️ [OverdubSessionView] Base file exists: \(FileManager.default.fileExists(atPath: baseRecording.fileURL.path))")
        #endif

        do {
            try engine.prepare(
                baseFileURL: baseRecording.fileURL,
                baseDuration: baseRecording.duration,
                layerFileURLs: layerURLs,
                layerOffsets: layerOffsets,
                loopFlags: flags,
                quality: appState.appSettings.recordingQuality,
                settings: appState.appSettings
            )
            isPrepared = true
            #if DEBUG
            print("✅ [OverdubSessionView] Engine prepared successfully, isPrepared=\(isPrepared)")
            #endif

            // Warn about any layers that couldn't be loaded
            if !engine.failedLayerIndices.isEmpty {
                let layerNames = engine.failedLayerIndices.map { "Layer \($0)" }.joined(separator: ", ")
                errorMessage = "\(layerNames) could not be loaded and won't play during monitoring. The audio file may be missing or corrupted."
                showErrorAlert = true
            }
        } catch {
            isPrepared = false
            errorMessage = "Failed to prepare overdub: \(error.localizedDescription)"
            showErrorAlert = true
            #if DEBUG
            print("❌ [OverdubSessionView] Engine preparation failed: \(error)")
            #endif
        }
    }

    // MARK: - Loop Toggle Actions

    private func toggleLoopForBase() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Create overdub group if it doesn't exist yet
        if overdubGroup == nil {
            overdubGroup = appState.createOverdubGroup(baseRecording: baseRecording)
        }
        guard var group = overdubGroup else { return }
        group.mixSettings.baseChannel.isLooped.toggle()
        overdubGroup = group
        persistMixSettings()
        prepareEngine()
    }

    private func toggleLoopForLayer(at index: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Create overdub group if it doesn't exist yet
        if overdubGroup == nil {
            overdubGroup = appState.createOverdubGroup(baseRecording: baseRecording)
        }
        guard var group = overdubGroup else { return }
        var settings = group.mixSettings
        settings.syncLayerCount(existingLayers.count)
        guard index < settings.layerChannels.count else { return }
        settings.layerChannels[index].isLooped.toggle()
        group.mixSettings = settings
        overdubGroup = group
        persistMixSettings()
        prepareEngine()
    }

    private func layerIsLooped(at index: Int) -> Bool {
        guard let group = overdubGroup else { return false }
        guard index < group.mixSettings.layerChannels.count else { return false }
        return group.mixSettings.layerChannels[index].isLooped
    }

    private func persistMixSettings() {
        guard let groupId = overdubGroup?.id,
              let newSettings = overdubGroup?.mixSettings,
              let gIdx = appState.overdubGroups.firstIndex(where: { $0.id == groupId }) else { return }
        appState.overdubGroups[gIdx].mixSettings = newSettings
    }

    private func toggleBasePlayback() {
        if engine.state == .playing {
            engine.pause()
        } else {
            engine.play()
        }
    }

    private func startRecording() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        guard !isStartingRecording && !isRecording else { return }

        // Check max layers
        guard existingLayers.count < OverdubGroup.maxLayers else {
            showMaxLayersAlert = true
            return
        }

        // Check headphones
        guard AudioSessionManager.shared.isHeadphoneMonitoringActive() else {
            showHeadphonesAlert = true
            return
        }

        // Generate file URL for new layer
        let layerURL = generateLayerFileURL()
        isStartingRecording = true

        Task {
            do {
                try await engine.startRecording(
                    outputURL: layerURL,
                    quality: appState.appSettings.recordingQuality
                )
                recordedLayerURL = layerURL
                isRecording = true
                isStartingRecording = false
            } catch {
                errorMessage = error.localizedDescription
                showErrorAlert = true
                // Clean up the file if it was partially created
                try? FileManager.default.removeItem(at: layerURL)
                recordedLayerURL = nil
                isStartingRecording = false
                // Engine is in a broken state after failed startRecording — re-prepare needed
                isPrepared = false
                prepareEngine()
            }
        }
    }

    private func stopRecording() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Set isRecording = false BEFORE engine state changes,
        // so the onChange(of: engine.state) handler knows this was a manual stop.
        isRecording = false
        recordedLayerDuration = engine.stopRecording()

        // Check if engine encountered a write error during recording
        if let writeError = engine.recordingError {
            errorMessage = writeError
            showErrorAlert = true
            // Discard the corrupt file
            if let url = recordedLayerURL {
                try? FileManager.default.removeItem(at: url)
            }
            recordedLayerURL = nil
            recordedLayerDuration = 0
        }
    }

    private func startPreview() {
        guard let layerURL = recordedLayerURL else { return }

        // Build loop flags for preview
        var settings = overdubGroup?.mixSettings ?? MixSettings()
        settings.syncLayerCount(existingLayers.count)
        var flags = [settings.baseChannel.isLooped]
        for ch in settings.layerChannels {
            flags.append(ch.isLooped)
        }

        do {
            try engine.prepareForPreview(
                baseFileURL: baseRecording.fileURL,
                baseDuration: baseRecording.duration,
                existingLayerURLs: existingLayers.map { $0.fileURL },
                existingLayerOffsets: existingLayers.map { $0.overdubOffsetSeconds },
                previewLayerURL: layerURL,
                previewLayerOffset: offsetSliderValue,
                loopFlags: flags,
                quality: appState.appSettings.recordingQuality,
                settings: appState.appSettings
            )
            engine.play()
            isPreviewing = true
        } catch {
            errorMessage = "Failed to preview: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    private func stopPreview() {
        engine.stop()
        isPreviewing = false
        prepareEngine()
    }

    private func saveRecording() {
        if isPreviewing { stopPreview() }

        guard let layerURL = recordedLayerURL,
              FileManager.default.fileExists(atPath: layerURL.path) else {
            errorMessage = "Recording file not found. The recording may have been interrupted."
            showErrorAlert = true
            recordedLayerURL = nil
            recordedLayerDuration = 0
            return
        }

        guard recordedLayerDuration >= 0.1 else {
            errorMessage = "Recording is too short. Please record for at least a moment before saving."
            showErrorAlert = true
            try? FileManager.default.removeItem(at: layerURL)
            recordedLayerURL = nil
            recordedLayerDuration = 0
            return
        }

        // Create or get overdub group
        let group: OverdubGroup
        if let existingGroup = overdubGroup {
            group = existingGroup
        } else {
            group = appState.createOverdubGroup(baseRecording: baseRecording)
            overdubGroup = group
        }

        // Create layer recording item
        let layerNumber = existingLayers.count + 1
        let layerTitle = "\(baseRecording.title) - Layer \(layerNumber)"

        let layerRecording = RecordingItem(
            fileURL: layerURL,
            createdAt: Date(),
            duration: recordedLayerDuration,
            title: layerTitle,
            albumID: baseRecording.albumID,
            projectId: baseRecording.projectId,
            overdubGroupId: group.id,
            overdubRoleRaw: OverdubRole.layer.rawValue,
            overdubIndex: layerNumber,
            overdubOffsetSeconds: offsetSliderValue,
            overdubSourceBaseId: baseRecording.id
        )

        // Add to app state
        appState.recordings.append(layerRecording)
        appState.addLayerToOverdubGroup(
            groupId: group.id,
            layerRecording: layerRecording,
            offsetSeconds: offsetSliderValue
        )

        // Update local state
        existingLayers.append(layerRecording)

        // Reset recording state
        recordedLayerURL = nil
        recordedLayerDuration = 0
        offsetSliderValue = 0
        showOffsetSlider = false

        // Re-prepare engine with new layer
        prepareEngine()

        // Notify
        onLayerSaved?(layerRecording)
    }

    private func discardRecording() {
        if isPreviewing { stopPreview() }

        if let url = recordedLayerURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedLayerURL = nil
        recordedLayerDuration = 0
        offsetSliderValue = 0
        showOffsetSlider = false
    }

    private func requestBounce() {
        let bounceTitle = "\(baseRecording.title) - Mix"
        let exists = appState.recordings.contains { $0.title == bounceTitle }
        if exists {
            showBounceConfirmation = true
        } else {
            bounceMix()
        }
    }

    private func bounceMix() {
        guard let group = overdubGroup else { return }
        isBouncing = true

        let baseURL = baseRecording.fileURL
        let layerURLs = existingLayers.map { $0.fileURL }
        let offsets = existingLayers.map { $0.overdubOffsetSeconds }
        var settings = group.mixSettings
        settings.syncLayerCount(existingLayers.count)

        let bounceTitle = "\(baseRecording.title) - Mix"
        let outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("SonideaBounce", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("\(bounceTitle).wav")

        Task {
            let mixEngine = MixdownEngine()
            let result = await mixEngine.bounce(
                baseFileURL: baseURL,
                layerFileURLs: layerURLs,
                layerOffsets: offsets,
                mixSettings: settings,
                outputURL: outputURL
            )
            await MainActor.run {
                isBouncing = false
                if result.success {
                    do {
                        try appState.importRecording(
                            from: result.outputURL,
                            duration: result.duration,
                            title: bounceTitle,
                            albumID: baseRecording.albumID ?? Album.draftsID
                        )
                        showMixer = false
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        bounceToastMessage = "Bounced: \(bounceTitle)"
                        // Auto-dismiss toast after 3 seconds
                        Task {
                            try? await Task.sleep(for: .seconds(3))
                            await MainActor.run { bounceToastMessage = nil }
                        }
                    } catch {
                        bounceErrorMessage = "Import failed: \(error.localizedDescription)"
                        showBounceError = true
                    }
                } else {
                    bounceErrorMessage = result.error?.localizedDescription ?? "Bounce failed"
                    showBounceError = true
                }
            }
        }
    }

    private func handleClose() {
        if isRecording {
            showRecordingCloseConfirmation = true
            return
        }

        if recordedLayerURL != nil {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        if !AudioSessionManager.shared.isHeadphoneMonitoringActive() {
            // Headphones disconnected — stop everything
            if isRecording {
                stopRecording()
                // The partial recording may be incomplete — auto-discard it
                if let url = recordedLayerURL {
                    try? FileManager.default.removeItem(at: url)
                }
                recordedLayerURL = nil
                recordedLayerDuration = 0
                errorMessage = "Headphones disconnected during recording. The partial recording was discarded."
                showErrorAlert = true
            }
            engine.stop()
            isPrepared = false
            if !showErrorAlert {
                showHeadphonesAlert = true
            }
        } else if !isPrepared && !isRecording {
            // Headphones reconnected — re-prepare engine
            prepareEngine()
        }
    }

    private func cleanup() {
        engine.cleanup()
    }

    // MARK: - Helpers

    private func generateLayerFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let ext = appState.appSettings.recordingQuality.fileExtension
        let filename = "overdub_layer_\(CachedDateFormatter.fileTimestamp.string(from: Date()))_\(UUID().uuidString.prefix(6)).\(ext)"
        return documentsPath.appendingPathComponent(filename)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let clamped = max(0, duration)
        let totalSeconds = Int(clamped)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let tenths = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }

    private func formatOffset(_ offset: Double) -> String {
        let ms = Int(offset * 1000)
        if ms >= 0 {
            return "+\(ms)ms"
        } else {
            return "\(ms)ms"
        }
    }
}

// MARK: - Track Playback Position Indicator

/// Shows a thin progress bar with a playhead dot indicating current playback position within a track.
/// For looped tracks, the position wraps around (currentTime % trackDuration).
private struct TrackPlaybackIndicator: View {
    let currentTime: TimeInterval
    let trackDuration: TimeInterval
    let trackOffset: TimeInterval
    let isLooped: Bool
    let tintColor: Color

    @Environment(\.themePalette) private var palette

    var body: some View {
        GeometryReader { geo in
            let progress = clampedProgress
            let dotX = progress * geo.size.width

            ZStack(alignment: .leading) {
                // Track bar background
                Capsule()
                    .fill(palette.inputBackground)
                    .frame(height: 3)

                // Filled portion
                Capsule()
                    .fill(tintColor.opacity(0.5))
                    .frame(width: max(0, dotX), height: 3)

                // Playhead dot
                Circle()
                    .fill(tintColor)
                    .frame(width: 8, height: 8)
                    .offset(x: dotX - 4)

                // Loop icon at the end for looped tracks
                if isLooped {
                    Image(systemName: "repeat")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(tintColor.opacity(0.6))
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .frame(height: 8)
    }

    private var clampedProgress: CGFloat {
        guard trackDuration > 0 else { return 0 }

        // Effective time within this track (accounting for offset)
        let effectiveTime = currentTime - trackOffset

        guard effectiveTime >= 0 else { return 0 }

        if isLooped {
            // Wrap around for looped tracks
            let posInLoop = effectiveTime.truncatingRemainder(dividingBy: trackDuration)
            return CGFloat(posInLoop / trackDuration)
        } else {
            return CGFloat(min(effectiveTime / trackDuration, 1.0))
        }
    }
}

// MARK: - Alerts Modifier (extracted to reduce body complexity)

private struct OverdubAlertsModifier: ViewModifier {
    @Binding var showHeadphonesAlert: Bool
    @Binding var showMaxLayersAlert: Bool
    @Binding var showDiscardConfirmation: Bool
    @Binding var showErrorAlert: Bool
    @Binding var showBounceError: Bool
    @Binding var showRecordingCloseConfirmation: Bool
    @Binding var errorMessage: String?
    @Binding var bounceErrorMessage: String?
    let maxLayers: Int
    let onDiscard: () -> Void
    let onStopAndClose: () -> Void

    func body(content: Content) -> some View {
        content
            .alert("Headphones Required", isPresented: $showHeadphonesAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Recording over a track requires headphones to prevent feedback.\n\nWired headphones are strongly recommended for the best overdub experience — they typically provide lower latency and more consistent timing. Bluetooth headphones will work but may introduce noticeable audio delay.")
            }
            .alert("Maximum Layers Reached", isPresented: $showMaxLayersAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can record up to \(maxLayers) layers per overdub group.")
            }
            .confirmationDialog("Discard Recording?", isPresented: $showDiscardConfirmation) {
                Button("Discard", role: .destructive) { onDiscard() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the layer you just recorded.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .alert("Bounce Error", isPresented: $showBounceError) {
                Button("OK", role: .cancel) { bounceErrorMessage = nil }
            } message: {
                Text(bounceErrorMessage ?? "Bounce failed")
            }
            .alert("Stop Recording?", isPresented: $showRecordingCloseConfirmation) {
                Button("Stop & Close", role: .destructive) { onStopAndClose() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Recording in progress. Stopping will discard the current layer.")
            }
    }
}

// MARK: - Recording Timer Display (Isolated for high-frequency updates)

/// Isolated subview for the recording timer so that high-frequency duration updates
/// (~20Hz during recording) only recompute this minimal view, not the entire OverdubSessionView body.
private struct RecordingTimerDisplay: View {
    let duration: TimeInterval

    var body: some View {
        Text(formatted)
            .font(.system(size: 24, weight: .medium, design: .monospaced))
    }

    private var formatted: String {
        let clamped = max(0, duration)
        let totalSeconds = Int(clamped)
        let mins = totalSeconds / 60
        let secs = totalSeconds % 60
        let tenths = Int((clamped.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", mins, secs, tenths)
    }
}
