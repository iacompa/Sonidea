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
    @State private var recordedLayerURL: URL?
    @State private var recordedLayerDuration: TimeInterval = 0

    @State private var showHeadphonesAlert = false
    @State private var showMaxLayersAlert = false
    @State private var showDiscardConfirmation = false
    @State private var showSaveConfirmation = false
    @State private var errorMessage: String?
    @State private var showErrorAlert = false

    @State private var offsetSliderValue: Double = 0 // For sync adjustment
    @State private var showOffsetSlider = false

    // Route change monitoring
    @State private var routeChangeObserver: Any?

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Status bar
                    statusBar

                    Divider()

                    ScrollView {
                        VStack(spacing: 24) {
                            // Base track section
                            baseTrackSection

                            // Layers section
                            layersSection

                            // Recording controls
                            if !isRecording && recordedLayerURL == nil {
                                recordingControlsSection
                            }

                            // Active recording section
                            if isRecording {
                                activeRecordingSection
                            }

                            // Post-recording section (save/discard)
                            if recordedLayerURL != nil && !isRecording {
                                postRecordingSection
                            }

                            // Mix controls
                            mixControlsSection
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Record Over Track")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        handleClose()
                    }
                }
            }
            .alert("Headphones Required", isPresented: $showHeadphonesAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Recording over a track requires headphones to prevent feedback. Plug in headphones or connect a supported headset, then try again.")
            }
            .alert("Maximum Layers Reached", isPresented: $showMaxLayersAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can record up to \(OverdubGroup.maxLayers) layers per overdub group.")
            }
            .confirmationDialog("Discard Recording?", isPresented: $showDiscardConfirmation) {
                Button("Discard", role: .destructive) {
                    discardRecording()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will delete the layer you just recorded.")
            }
            .alert("Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) {
                    errorMessage = nil
                }
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
            .onAppear {
                setupSession()
            }
            .onDisappear {
                cleanup()
            }
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            // Headphones indicator
            HStack(spacing: 6) {
                Image(systemName: AudioSessionManager.shared.isHeadphoneMonitoringActive() ? "headphones" : "headphones.slash")
                    .font(.system(size: 14))
                    .foregroundColor(AudioSessionManager.shared.isHeadphoneMonitoringActive() ? .green : .red)

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
            }
            .padding()
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
        }
    }

    @ViewBuilder
    private func layerRow(at index: Int) -> some View {
        let layerNumber = index + 1

        if index < existingLayers.count {
            // Existing layer
            let layer = existingLayers[index]

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

                // Offset indicator if non-zero
                if layer.overdubOffsetSeconds != 0 {
                    Text(formatOffset(layer.overdubOffsetSeconds))
                        .font(.caption2)
                        .foregroundColor(palette.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(palette.surface))
                }
            }
            .padding()
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
                        Image(systemName: "record.circle")
                            .font(.system(size: 20))
                        Text("Record Layer \(existingLayers.count + 1)")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isPrepared ? Color.red : Color.red.opacity(0.4))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!isPrepared)
                .opacity(isPrepared ? 1.0 : 0.6)

                if !isPrepared {
                    HStack(spacing: 6) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Preparing audio engine...")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
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
                    .fill(Color.red)
                    .frame(width: 12, height: 12)

                Text("Recording Layer \(existingLayers.count + 1)")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)

                Spacer()

                Text(formatDuration(engine.recordingDuration))
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.red)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.red.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.red.opacity(0.3), lineWidth: 1)
                    )
            )

            // Level meter
            ProgressView(value: Double(engine.meterLevel))
                .progressViewStyle(.linear)
                .tint(engine.meterLevel > 0.9 ? .red : .green)

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
                        .fill(palette.textPrimary)
                )
            }
            .buttonStyle(.plain)
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
                    VStack(spacing: 4) {
                        Slider(value: $offsetSliderValue, in: -0.5...0.5, step: 0.01)
                            .tint(palette.accent)

                        HStack {
                            Text("-500ms")
                                .font(.caption2)
                            Spacer()
                            Text("+500ms")
                                .font(.caption2)
                        }
                        .foregroundColor(palette.textTertiary)
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

    private func setupSession() {
        print("🎙️ [OverdubSessionView] setupSession() called")
        print("🎙️ [OverdubSessionView] Base recording: \(baseRecording.title)")
        print("🎙️ [OverdubSessionView] Base URL: \(baseRecording.fileURL)")

        // Check for existing overdub group
        if let groupId = baseRecording.overdubGroupId,
           let group = appState.overdubGroup(for: groupId) {
            self.overdubGroup = group
            self.existingLayers = appState.layerRecordings(for: group)
            print("🎙️ [OverdubSessionView] Found existing overdub group with \(existingLayers.count) layers")
        }

        // Check headphones
        let hasHeadphones = AudioSessionManager.shared.isHeadphoneMonitoringActive()
        print("🎙️ [OverdubSessionView] Headphones connected: \(hasHeadphones)")
        if !hasHeadphones {
            showHeadphonesAlert = true
        }

        // Setup route change monitoring
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [self] notification in
            handleRouteChange(notification)
        }

        // Prepare engine
        prepareEngine()
    }

    private func prepareEngine() {
        let layerURLs = existingLayers.map { $0.fileURL }
        let layerOffsets = existingLayers.map { $0.overdubOffsetSeconds }

        print("🎙️ [OverdubSessionView] Preparing engine with base: \(baseRecording.fileURL.lastPathComponent)")
        print("🎙️ [OverdubSessionView] Base file exists: \(FileManager.default.fileExists(atPath: baseRecording.fileURL.path))")

        do {
            try engine.prepare(
                baseFileURL: baseRecording.fileURL,
                baseDuration: baseRecording.duration,
                layerFileURLs: layerURLs,
                layerOffsets: layerOffsets,
                quality: appState.appSettings.recordingQuality,
                settings: appState.appSettings
            )
            isPrepared = true
            print("✅ [OverdubSessionView] Engine prepared successfully, isPrepared=\(isPrepared)")
        } catch {
            isPrepared = false
            errorMessage = "Failed to prepare overdub: \(error.localizedDescription)"
            showErrorAlert = true
            print("❌ [OverdubSessionView] Engine preparation failed: \(error)")
        }
    }

    private func toggleBasePlayback() {
        if engine.state == .playing {
            engine.pause()
        } else {
            engine.play()
        }
    }

    private func startRecording() {
        print("🎙️ [OverdubSessionView] startRecording() called")

        // Check max layers
        guard existingLayers.count < OverdubGroup.maxLayers else {
            print("⚠️ [OverdubSessionView] Max layers reached")
            showMaxLayersAlert = true
            return
        }

        // Check headphones
        guard AudioSessionManager.shared.isHeadphoneMonitoringActive() else {
            print("⚠️ [OverdubSessionView] No headphones connected")
            showHeadphonesAlert = true
            return
        }

        // Generate file URL for new layer
        let layerURL = generateLayerFileURL()
        recordedLayerURL = layerURL
        print("🎙️ [OverdubSessionView] Recording to: \(layerURL.lastPathComponent)")

        do {
            try engine.startRecording(
                outputURL: layerURL,
                quality: appState.appSettings.recordingQuality
            )
            isRecording = true
            print("✅ [OverdubSessionView] Recording started successfully")
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
            showErrorAlert = true
            recordedLayerURL = nil
            print("❌ [OverdubSessionView] Failed to start recording: \(error)")
        }
    }

    private func stopRecording() {
        recordedLayerDuration = engine.stopRecording()
        isRecording = false
    }

    private func saveRecording() {
        guard let layerURL = recordedLayerURL else { return }

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
        if let url = recordedLayerURL {
            try? FileManager.default.removeItem(at: url)
        }
        recordedLayerURL = nil
        recordedLayerDuration = 0
        offsetSliderValue = 0
        showOffsetSlider = false
    }

    private func handleClose() {
        if isRecording {
            engine.stop()
        }

        if recordedLayerURL != nil {
            showDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        // Check if headphones were disconnected
        if !AudioSessionManager.shared.isHeadphoneMonitoringActive() {
            if isRecording {
                // Stop recording immediately
                stopRecording()
            }
            engine.stop()
            showHeadphonesAlert = true
        }
    }

    private func cleanup() {
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        engine.cleanup()
    }

    // MARK: - Helpers

    private func generateLayerFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let ext = appState.appSettings.recordingQuality.fileExtension
        let filename = "overdub_layer_\(formatter.string(from: Date())).\(ext)"
        return documentsPath.appendingPathComponent(filename)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
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
