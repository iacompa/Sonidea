//
//  RecordingDetailView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Inline Recorder State

private enum InlineRecorderState: Equatable {
    case idle       // Not recording - shows "Record New Version" button
    case recording  // Actively recording
    case paused     // Recording paused
}

// MARK: - Original State Snapshot (for Done/Save logic)

private struct RecordingSnapshot: Equatable {
    let title: String
    let notes: String
    let albumID: UUID?
    let projectId: UUID?
    let tagIDs: [UUID]
    let locationLabel: String
    let latitude: Double?
    let longitude: Double?
    let iconColorHex: String?
    let fileURL: URL
    let duration: TimeInterval
    let markers: [Marker]

    init(from recording: RecordingItem) {
        self.title = recording.title
        self.notes = recording.notes
        self.albumID = recording.albumID
        self.projectId = recording.projectId
        self.tagIDs = recording.tagIDs
        self.locationLabel = recording.locationLabel
        self.latitude = recording.latitude
        self.longitude = recording.longitude
        self.iconColorHex = recording.iconColorHex
        self.fileURL = recording.fileURL
        self.duration = recording.duration
        self.markers = recording.markers
    }
}

struct RecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    @State private var playback = PlaybackEngine()

    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var editedLocationLabel: String
    @State private var currentRecording: RecordingItem

    @State private var showManageTags = false
    @State private var showChooseAlbum = false
    @State private var showShareSheet = false
    @State private var showSpeedPicker = false
    @State private var showProjectSheet = false
    @State private var showChooseProject = false
    @State private var showCreateProject = false
    @State private var showVersionSavedToast = false
    @State private var savedVersionLabel: String = ""

    // Inline version recorder state
    @State private var isInlineRecorderExpanded = false
    @State private var inlineRecorderState: InlineRecorderState = .idle

    @State private var waveformSamples: [Float] = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var isLoadingWaveform = true

    // MARK: - Waveform Editing State
    @State private var isEditingWaveform = false
    @State private var selectionStart: TimeInterval = 0
    @State private var selectionEnd: TimeInterval = 0
    @State private var editPlayheadPosition: TimeInterval = 0  // Tap-to-set playhead for marker placement
    @State private var isPrecisionMode = false  // "Hold for Precision" button state
    @State private var editedMarkers: [Marker] = []
    @State private var isProcessingEdit = false
    @State private var pendingAudioEdit: URL?  // Pending edited file URL before save
    @State private var pendingDuration: TimeInterval?  // Pending duration after edit
    @State private var hasAudioEdits = false  // Track if audio was modified
    @State private var editHistory = EditHistory()  // Undo/redo support

    // Waveform height constants
    private let compactWaveformHeight: CGFloat = 100
    private let expandedWaveformHeight: CGFloat = 200

    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var exportedWAVURL: URL?
    @State private var isExporting = false

    @State private var editedIconColor: Color
    // Track if icon color was explicitly modified by user (to avoid lossy round-trip conversion)
    @State private var iconColorWasModified = false
    private let originalIconColorHex: String?

    // EQ panel state
    @State private var showEQPanel = false
    @State private var localEQSettings: EQSettings

    // Location search state
    @State private var locationSearchQuery = ""
    @State private var isSearchingLocation = false
    @State private var locationSearchResults: [MKLocalSearchCompletion] = []
    @State private var reverseGeocodedName: String?
    @State private var isLoadingReverseGeocode = false

    // Location editing state
    @State private var showLocationEditor = false

    // Verification info sheet state
    @State private var showVerificationInfo = false

    // Icon color picker state
    @State private var showIconColorPicker = false

    // Verification timeout state
    @State private var verificationTimedOut = false
    @State private var verificationTimeoutTask: Task<Void, Never>?

    // Playback error state
    @State private var showPlaybackError = false

    // Original state snapshot for Done/Save logic
    private let originalSnapshot: RecordingSnapshot

    // Navigation context flag - when true, tapping project just dismisses back to parent
    private let isOpenedFromProject: Bool

    init(recording: RecordingItem, isOpenedFromProject: Bool = false) {
        _editedTitle = State(initialValue: recording.title)
        _editedNotes = State(initialValue: recording.notes)
        _editedLocationLabel = State(initialValue: recording.locationLabel)
        _currentRecording = State(initialValue: recording)
        _editedIconColor = State(initialValue: recording.iconColor)
        _localEQSettings = State(initialValue: recording.eqSettings ?? .flat)
        _editedMarkers = State(initialValue: recording.markers)
        _selectionEnd = State(initialValue: recording.duration)
        // Store original hex to avoid overwriting with lossy Color -> hex conversion
        self.originalIconColorHex = recording.iconColorHex
        self.isOpenedFromProject = isOpenedFromProject
        // Store original snapshot for Done/Save comparison
        self.originalSnapshot = RecordingSnapshot(from: recording)
    }

    // MARK: - Computed Properties for Done/Save Logic

    private var currentSnapshot: RecordingSnapshot {
        var snapshotRecording = currentRecording
        snapshotRecording.title = editedTitle.isEmpty ? currentRecording.title : editedTitle
        snapshotRecording.notes = editedNotes
        snapshotRecording.locationLabel = editedLocationLabel
        if iconColorWasModified {
            snapshotRecording.iconColorHex = editedIconColor.toHex()
        }
        snapshotRecording.markers = editedMarkers
        if let pendingURL = pendingAudioEdit {
            snapshotRecording = RecordingItem(
                id: snapshotRecording.id,
                fileURL: pendingURL,
                createdAt: snapshotRecording.createdAt,
                duration: pendingDuration ?? snapshotRecording.duration,
                title: snapshotRecording.title,
                notes: snapshotRecording.notes,
                tagIDs: snapshotRecording.tagIDs,
                albumID: snapshotRecording.albumID,
                locationLabel: snapshotRecording.locationLabel,
                transcript: snapshotRecording.transcript,
                latitude: snapshotRecording.latitude,
                longitude: snapshotRecording.longitude,
                trashedAt: snapshotRecording.trashedAt,
                lastPlaybackPosition: 0,
                iconColorHex: snapshotRecording.iconColorHex,
                eqSettings: snapshotRecording.eqSettings,
                projectId: snapshotRecording.projectId,
                parentRecordingId: snapshotRecording.parentRecordingId,
                versionIndex: snapshotRecording.versionIndex,
                proofStatusRaw: snapshotRecording.proofStatusRaw,
                proofSHA256: nil,
                proofCloudCreatedAt: nil,
                proofCloudRecordName: nil,
                locationModeRaw: snapshotRecording.locationModeRaw,
                locationProofHash: snapshotRecording.locationProofHash,
                locationProofStatusRaw: snapshotRecording.locationProofStatusRaw,
                markers: editedMarkers
            )
        }
        return RecordingSnapshot(from: snapshotRecording)
    }

    private var hasEdits: Bool {
        currentSnapshot != originalSnapshot || hasAudioEdits
    }

    private var actionButtonTitle: String {
        hasEdits ? "Save" : "Done"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        playbackSection
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 1)
                        metadataSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        // Share button
                        Button {
                            shareRecording()
                        } label: {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 17))
                                    .foregroundColor(palette.textPrimary)
                            }
                        }
                        .disabled(isExporting)

                        // Icon color indicator
                        Button {
                            showIconColorPicker = true
                        } label: {
                            Circle()
                                .fill(editedIconColor)
                                .frame(width: 20, height: 20)
                                .overlay(
                                    Circle()
                                        .strokeBorder(palette.textPrimary.opacity(0.2), lineWidth: 1.5)
                                )
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(actionButtonTitle) {
                        if hasEdits {
                            saveChanges()
                        }
                        savePlaybackPosition()
                        playback.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupPlayback()
                // Check for playback load errors
                if playback.loadError != nil {
                    showPlaybackError = true
                }
                loadReverseGeocodedName()
                createProofSilently()
                startVerificationTimeout()
            }
            .onDisappear {
                savePlaybackPosition()
                playback.stop()
                verificationTimeoutTask?.cancel()
                editHistory.clear()  // Clean up undo history
            }
            .alert("Cannot Play Recording", isPresented: $showPlaybackError) {
                Button("OK") {
                    playback.clearError()
                    dismiss()
                }
            } message: {
                Text(playback.loadError?.errorDescription ?? "The recording file could not be opened.")
            }
            .sheet(isPresented: $showManageTags) {
                ManageTagsSheet()
            }
            .sheet(isPresented: $showChooseAlbum) {
                ChooseAlbumSheet(recording: $currentRecording)
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedWAVURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showProjectSheet) {
                if let projectId = currentRecording.projectId,
                   let project = appState.project(for: projectId) {
                    ProjectDetailView(project: project)
                        .environment(appState)
                }
            }
            .sheet(isPresented: $showChooseProject) {
                ChooseProjectSheet(recording: $currentRecording)
            }
            .sheet(isPresented: $showCreateProject) {
                CreateProjectSheet(recording: currentRecording)
            }
            .sheet(isPresented: $showVerificationInfo) {
                VerificationInfoSheet(
                    recording: currentRecording,
                    timedOut: verificationTimedOut
                )
                .presentationDetents([.height(220)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showIconColorPicker) {
                IconColorPickerSheet(selectedColor: $editedIconColor, onColorChanged: {
                    iconColorWasModified = true
                })
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showLocationEditor) {
                LocationEditorSheet(
                    recording: $currentRecording,
                    editedLocationLabel: $editedLocationLabel,
                    reverseGeocodedName: $reverseGeocodedName,
                    onLocationChanged: {
                        // Mark location as edited - this ONLY affects location verification, NOT date
                        currentRecording.locationProofStatusRaw = LocationProofStatus.edited.rawValue
                        appState.updateRecording(currentRecording)
                    }
                )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
            .overlay(alignment: .bottom) {
                if showVersionSavedToast {
                    versionSavedToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: showVersionSavedToast)
                }
            }
        }
    }

    // MARK: - Verification Timeout

    private func startVerificationTimeout() {
        // Only start timeout if status is pending
        guard currentRecording.proofStatus == .pending else { return }

        verificationTimeoutTask = Task {
            try? await Task.sleep(nanoseconds: 12_000_000_000) // 12 seconds
            if !Task.isCancelled {
                await MainActor.run {
                    // If still pending after timeout, mark as timed out
                    if currentRecording.proofStatus == .pending {
                        verificationTimedOut = true
                    }
                }
            }
        }
    }

    // MARK: - Version Saved Toast

    private var versionSavedToast: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
            Text("Saved as \(savedVersionLabel)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(25)
        .padding(.bottom, 20)
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Edit/Done button row (ABOVE waveform, not overlapping)
            if !isLoadingWaveform && !waveformSamples.isEmpty {
                HStack {
                    Spacer()
                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if isEditingWaveform {
                                // Exit edit mode - reset precision mode
                                isPrecisionMode = false
                                isEditingWaveform = false
                            } else {
                                // Enter edit mode - pause playback and set selection to full duration
                                if playback.isPlaying {
                                    playback.pause()
                                }
                                selectionStart = 0
                                selectionEnd = pendingDuration ?? playback.duration
                                editPlayheadPosition = 0
                                isEditingWaveform = true
                            }
                        }
                    } label: {
                        Text(isEditingWaveform ? "Done" : "Edit")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(palette.accent)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(palette.accent.opacity(0.15))
                            .cornerRadius(6)
                    }
                }
            }

            // Waveform with animated height expansion
            ZStack {
                if isLoadingWaveform {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: palette.textPrimary))
                        .frame(height: isEditingWaveform ? expandedWaveformHeight : compactWaveformHeight)
                } else if waveformSamples.isEmpty {
                    Image(systemName: "waveform")
                        .font(.system(size: 60))
                        .foregroundColor(palette.textSecondary)
                        .frame(height: isEditingWaveform ? expandedWaveformHeight : compactWaveformHeight)
                } else if isEditingWaveform {
                    // Editable waveform with selection (0.01s precision)
                    EditableWaveformView(
                        samples: waveformSamples,
                        duration: pendingDuration ?? playback.duration,
                        selectionStart: $selectionStart,
                        selectionEnd: $selectionEnd,
                        playheadPosition: $editPlayheadPosition,
                        currentTime: playback.currentTime,
                        isEditing: true,
                        isPrecisionMode: isPrecisionMode,
                        markers: $editedMarkers,
                        onScrub: { time in
                            playback.seek(to: time)
                        },
                        onMarkerTap: { marker in
                            // Tap marker to set playhead to marker position
                            editPlayheadPosition = marker.time
                            playback.seek(to: marker.time)
                        },
                        onMarkerMoved: { marker, newTime in
                            // Marker was dragged - this is already handled by binding
                        }
                    )
                    .frame(height: expandedWaveformHeight)
                } else {
                    // Normal playback waveform
                    WaveformView(
                        samples: waveformSamples,
                        progress: playbackProgress,
                        zoomScale: $zoomScale
                    )
                    .frame(height: compactWaveformHeight)
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.8), value: isEditingWaveform)
            .padding(.vertical, 10)

            // Edit mode: Selection info and actions
            if isEditingWaveform {
                VStack(spacing: 12) {
                    // Selection time display with nudge controls (0.01s precision)
                    SelectionTimeDisplay(
                        selectionStart: $selectionStart,
                        selectionEnd: $selectionEnd,
                        duration: pendingDuration ?? playback.duration
                    )

                    // Edit actions with undo/redo and Hold for Precision
                    WaveformEditActionsView(
                        canUndo: editHistory.canUndo,
                        canRedo: editHistory.canRedo,
                        canTrim: canPerformTrim,
                        canCut: canPerformCut,
                        isProcessing: isProcessingEdit,
                        isPrecisionMode: $isPrecisionMode,
                        onUndo: performUndo,
                        onRedo: performRedo,
                        onTrim: performTrim,
                        onCut: performCut,
                        onAddMarker: addMarkerAtPlayhead
                    )

                    // Processing indicator
                    if isProcessingEdit {
                        HStack(spacing: 8) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: palette.accent))
                                .scaleEffect(0.8)
                            Text("Processing...")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Zoom indicator (only when not editing)
            if !isEditingWaveform && zoomScale > 1.01 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                    Spacer()
                    Button {
                        withAnimation {
                            zoomScale = 1.0
                        }
                    } label: {
                        Text("Reset")
                            .font(.caption)
                            .foregroundColor(palette.accent)
                    }
                }
            }

            // Time display
            HStack {
                Text(formatTime(playback.currentTime))
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(pendingDuration ?? playback.duration))
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .monospacedDigit()
            }

            // Progress bar (only when not editing)
            if !isEditingWaveform {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(palette.stroke)
                            .frame(height: 4)
                            .cornerRadius(2)
                        Rectangle()
                            .fill(palette.accent)
                            .frame(width: progressWidth(in: geometry.size.width), height: 4)
                            .cornerRadius(2)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let progress = max(0, min(1, value.location.x / geometry.size.width))
                                let newTime = progress * playback.duration
                                playback.seek(to: newTime)
                            }
                    )
                }
                .frame(height: 20)
            }

            // Playback controls
            HStack(spacing: 32) {
                // Skip backward
                Button {
                    playback.skip(seconds: -Double(appState.appSettings.skipInterval.rawValue))
                } label: {
                    Image(systemName: "gobackward.\(appState.appSettings.skipInterval.rawValue)")
                        .font(.system(size: 28))
                        .foregroundColor(palette.textPrimary)
                }

                // Play/Pause
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(palette.accent)
                }

                // Skip forward
                Button {
                    playback.skip(seconds: Double(appState.appSettings.skipInterval.rawValue))
                } label: {
                    Image(systemName: "goforward.\(appState.appSettings.skipInterval.rawValue)")
                        .font(.system(size: 28))
                        .foregroundColor(palette.textPrimary)
                }
            }

            // Speed and EQ controls
            HStack(spacing: 12) {
                Spacer()

                // Speed button
                Button {
                    cycleSpeed()
                } label: {
                    Text(String(format: "%.1fx", playback.playbackSpeed))
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }

                // EQ button
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showEQPanel.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: 12))
                        Text("EQ")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(showEQPanel ? .white : .purple)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showEQPanel ? Color.purple : Color.purple.opacity(0.15))
                    .cornerRadius(8)
                }

                Spacer()
            }

            Text(currentRecording.formattedDate)
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            // Inline Version Recorder
            inlineVersionRecorder

            // Collapsible EQ Panel
            if showEQPanel {
                eqPanel
            }
        }
    }

    // MARK: - Waveform Edit Helpers

    private var canPerformTrim: Bool {
        // Can trim if selection is not the entire duration
        let duration = pendingDuration ?? playback.duration
        return selectionStart > 0.1 || selectionEnd < (duration - 0.1)
    }

    private var canPerformCut: Bool {
        // Can cut if selection is not the entire duration and has some content
        let duration = pendingDuration ?? playback.duration
        let selectionDuration = selectionEnd - selectionStart
        return selectionDuration > 0.1 && selectionDuration < (duration - 0.1)
    }

    /// Create a snapshot of current state for undo
    private func createUndoSnapshot(description: String) -> EditSnapshot {
        EditSnapshot(
            audioFileURL: pendingAudioEdit ?? currentRecording.fileURL,
            duration: pendingDuration ?? playback.duration,
            markers: editedMarkers,
            selectionStart: selectionStart,
            selectionEnd: selectionEnd,
            description: description
        )
    }

    /// Restore state from a snapshot
    private func restoreFromSnapshot(_ snapshot: EditSnapshot) {
        pendingAudioEdit = snapshot.audioFileURL == currentRecording.fileURL ? nil : snapshot.audioFileURL
        pendingDuration = snapshot.audioFileURL == currentRecording.fileURL ? nil : snapshot.duration
        editedMarkers = snapshot.markers
        selectionStart = snapshot.selectionStart
        selectionEnd = snapshot.selectionEnd

        // Reload waveform and playback
        isLoadingWaveform = true
        Task {
            let samples = await WaveformSampler.shared.samples(
                for: snapshot.audioFileURL,
                targetSampleCount: 150
            )
            await MainActor.run {
                waveformSamples = samples
                isLoadingWaveform = false
                playback.load(url: snapshot.audioFileURL)
            }
        }
    }

    private func performUndo() {
        guard let snapshot = editHistory.popUndo() else { return }

        // Push current state to redo stack
        let currentSnapshot = createUndoSnapshot(description: "Redo")
        editHistory.pushRedo(currentSnapshot)

        // Restore previous state
        restoreFromSnapshot(snapshot)
        hasAudioEdits = snapshot.audioFileURL != currentRecording.fileURL
    }

    private func performRedo() {
        guard let snapshot = editHistory.popRedo() else { return }

        // Push current state to undo stack
        let currentSnapshot = createUndoSnapshot(description: snapshot.description)
        editHistory.pushUndo(currentSnapshot)

        // Restore redo state
        restoreFromSnapshot(snapshot)
        hasAudioEdits = snapshot.audioFileURL != currentRecording.fileURL
    }

    private func performTrim() {
        guard canPerformTrim else { return }

        // Push current state to undo stack before making changes
        let undoSnapshot = createUndoSnapshot(description: "Trim")
        editHistory.pushUndo(undoSnapshot)

        isProcessingEdit = true
        let sourceURL = pendingAudioEdit ?? currentRecording.fileURL

        Task {
            let result = await AudioEditor.shared.trim(
                sourceURL: sourceURL,
                startTime: selectionStart,
                endTime: selectionEnd
            )

            await MainActor.run {
                if result.success {
                    // Update markers to match new timeline
                    editedMarkers = editedMarkers.afterTrim(
                        keepingStart: selectionStart,
                        keepingEnd: selectionEnd
                    )

                    // Store pending edit
                    pendingAudioEdit = result.outputURL
                    pendingDuration = result.newDuration
                    hasAudioEdits = true

                    // Reload waveform for new file
                    reloadWaveformForPendingEdit()

                    // Reset selection to full new duration
                    selectionStart = 0
                    selectionEnd = result.newDuration

                    // Reload playback
                    playback.load(url: result.outputURL)
                }
                isProcessingEdit = false
            }
        }
    }

    private func performCut() {
        guard canPerformCut else { return }

        // Push current state to undo stack before making changes
        let undoSnapshot = createUndoSnapshot(description: "Cut")
        editHistory.pushUndo(undoSnapshot)

        isProcessingEdit = true
        let sourceURL = pendingAudioEdit ?? currentRecording.fileURL

        Task {
            let result = await AudioEditor.shared.cut(
                sourceURL: sourceURL,
                startTime: selectionStart,
                endTime: selectionEnd
            )

            await MainActor.run {
                if result.success {
                    // Update markers to match new timeline (remove cut region, shift after)
                    editedMarkers = editedMarkers.afterCut(
                        removingStart: selectionStart,
                        removingEnd: selectionEnd
                    )

                    // Store pending edit
                    pendingAudioEdit = result.outputURL
                    pendingDuration = result.newDuration
                    hasAudioEdits = true

                    // Reload waveform for new file
                    reloadWaveformForPendingEdit()

                    // Reset selection
                    selectionStart = 0
                    selectionEnd = result.newDuration

                    // Reload playback
                    playback.load(url: result.outputURL)
                }
                isProcessingEdit = false
            }
        }
    }

    private func addMarkerAtPlayhead() {
        // Marker placement uses the edit playhead position (tap-to-set cursor)
        // The editPlayheadPosition is controlled by:
        // - Tapping anywhere on the waveform
        // - Tapping a marker (sets playhead to marker time)
        // - Dragging the playhead cursor
        //
        // This ensures deterministic, user-controlled marker placement.

        // Quantize to 0.01s precision
        let editStep: TimeInterval = 0.01
        let quantizedTime = (editPlayheadPosition / editStep).rounded() * editStep
        let duration = pendingDuration ?? playback.duration
        let markerTime = Swift.max(0, Swift.min(quantizedTime, duration))

        let newMarker = Marker(time: markerTime)
        editedMarkers.append(newMarker)
        editedMarkers = editedMarkers.sortedByTime

        // Haptic feedback
        let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
        impactGenerator.impactOccurred()
    }

    private func reloadWaveformForPendingEdit() {
        guard let pendingURL = pendingAudioEdit else { return }

        isLoadingWaveform = true
        Task {
            // Clear cache for old URL
            await WaveformSampler.shared.clearCache(for: currentRecording.fileURL)

            let samples = await WaveformSampler.shared.samples(
                for: pendingURL,
                targetSampleCount: 150
            )
            await MainActor.run {
                waveformSamples = samples
                isLoadingWaveform = false
            }
        }
    }

    // MARK: - Inline Version Recorder

    private var inlineVersionRecorder: some View {
        VStack(spacing: 0) {
            if inlineRecorderState == .idle {
                // Idle state: Compact "Record New Version" button
                inlineRecorderIdleButton
            } else {
                // Recording/Paused state: Expanded card
                inlineRecorderExpandedCard
            }
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: inlineRecorderState)
    }

    private var inlineRecorderIdleButton: some View {
        Button {
            startInlineRecording()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "mic.circle.fill")
                    .font(.system(size: 20))
                Text("Record New Version")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .foregroundColor(palette.accent)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity)
            .background(palette.accent.opacity(0.12))
            .cornerRadius(12)
        }
    }

    private var inlineRecorderExpandedCard: some View {
        VStack(spacing: 16) {
            // Header: Version badge + Timer
            HStack {
                // Version badge
                let nextVersion = computeNextVersionLabel()
                Text(nextVersion)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundColor(palette.accent)

                Spacer()

                // Duration timer
                Text(formatInlineRecorderDuration(appState.recorder.currentDuration))
                    .font(.system(size: 28, weight: .light, design: .monospaced))
                    .foregroundColor(palette.textPrimary)
            }

            // Compact waveform
            LiveWaveformView(
                samples: appState.recorder.liveMeterSamples,
                accentColor: inlineRecorderState == .paused ? palette.textSecondary : palette.accent
            )
            .frame(height: 50)
            .opacity(inlineRecorderState == .paused ? 0.5 : 1.0)

            // Control buttons
            HStack(spacing: 16) {
                // Cancel button
                Button {
                    cancelInlineRecording()
                } label: {
                    Text("Cancel")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(palette.inputBackground)
                        .cornerRadius(20)
                }

                Spacer()

                // Pause/Resume button
                Button {
                    toggleInlineRecordingPause()
                } label: {
                    Image(systemName: inlineRecorderState == .paused ? "play.fill" : "pause.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(palette.textSecondary)
                        .clipShape(Circle())
                }

                // Stop & Save button
                Button {
                    stopAndSaveInlineRecording()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 12))
                        Text("Save")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(palette.accent)
                    .cornerRadius(20)
                }
            }
        }
        .padding(16)
        .background(palette.inputBackground)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(palette.accent.opacity(0.3), lineWidth: 1)
        )
    }

    // MARK: - Inline Recorder Actions

    private func startInlineRecording() {
        // Stop playback before recording
        playback.stop()
        // Start recording
        appState.recorder.startRecording()
        // Update state
        withAnimation {
            inlineRecorderState = .recording
        }
    }

    private func toggleInlineRecordingPause() {
        if inlineRecorderState == .recording {
            appState.recorder.pauseRecording()
            withAnimation {
                inlineRecorderState = .paused
            }
        } else if inlineRecorderState == .paused {
            appState.recorder.resumeRecording()
            withAnimation {
                inlineRecorderState = .recording
            }
        }
    }

    private func cancelInlineRecording() {
        // Stop and discard the recording
        _ = appState.recorder.stopRecording()
        withAnimation {
            inlineRecorderState = .idle
        }
    }

    private func stopAndSaveInlineRecording() {
        guard let rawData = appState.recorder.stopRecording() else {
            withAnimation {
                inlineRecorderState = .idle
            }
            return
        }

        // Determine the target project
        var targetProject: Project

        if let projectId = currentRecording.projectId,
           let existingProject = appState.project(for: projectId) {
            // Already in a project - use it
            targetProject = existingProject
        } else {
            // No project - create one with the source recording as V1
            targetProject = appState.createProject(from: currentRecording, title: nil)
        }

        // Add the new recording using the standard method
        appState.addRecording(from: rawData)

        // The newly added recording is at index 0
        guard let newRecording = appState.recordings.first else {
            withAnimation {
                inlineRecorderState = .idle
            }
            return
        }

        // Link to project as new version
        appState.addVersion(recording: newRecording, to: targetProject)

        // Get the version label for the toast
        let versionLabel = "V\(appState.nextVersionIndex(for: targetProject) - 1)"

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        // Reset state and show toast
        withAnimation {
            inlineRecorderState = .idle
        }

        savedVersionLabel = versionLabel
        refreshRecording()

        // Show toast briefly
        showVersionSavedToast = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showVersionSavedToast = false
        }
    }

    private func computeNextVersionLabel() -> String {
        if let projectId = currentRecording.projectId,
           let project = appState.project(for: projectId) {
            let nextIndex = appState.nextVersionIndex(for: project)
            return "V\(nextIndex)"
        } else {
            // No project yet - this will become V2 (current becomes V1)
            return "V2"
        }
    }

    private func formatInlineRecorderDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let centiseconds = Int((duration.truncatingRemainder(dividingBy: 1)) * 100)
        return String(format: "%d:%02d.%02d", minutes, seconds, centiseconds)
    }

    // MARK: - EQ Panel

    @ViewBuilder
    private var eqPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            ParametricEQView(
                settings: $localEQSettings,
                onSettingsChanged: {
                    // Apply EQ changes in real-time to playback
                    playback.setEQ(localEQSettings)
                    // Save to recording
                    saveEQSettings()
                }
            )
        }
        .padding(16)
        .background(palette.inputBackground)
        .cornerRadius(12)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)
                TextField("Recording title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .foregroundColor(palette.textPrimary)
                    .padding(12)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
            }

            // Album
            VStack(alignment: .leading, spacing: 8) {
                Text("Album")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)

                Button {
                    showChooseAlbum = true
                } label: {
                    HStack {
                        if let album = appState.album(for: currentRecording.albumID) {
                            Text(album.name)
                                .foregroundColor(palette.textPrimary)
                        } else {
                            Text("None")
                                .foregroundColor(palette.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                    .padding(12)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
                }
            }

            // Project & Version
            projectSection

            // Tags
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button("Manage") {
                        showManageTags = true
                    }
                    .font(.caption)
                    .foregroundColor(palette.accent)
                }

                FlowLayout(spacing: 8) {
                    ForEach(appState.tags) { tag in
                        TagChipSelectable(
                            tag: tag,
                            isSelected: currentRecording.tagIDs.contains(tag.id)
                        ) {
                            currentRecording = appState.toggleTag(tag, for: currentRecording)
                        }
                    }
                }
            }

            // Location Section (simplified)
            locationSection

            // Transcription
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .textCase(.uppercase)
                    Spacer()
                    if !currentRecording.transcript.isEmpty {
                        Button("Clear") {
                            currentRecording.transcript = ""
                            appState.updateTranscript("", for: currentRecording.id)
                        }
                        .font(.caption)
                        .foregroundColor(.red)
                    }
                }

                if isTranscribing {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
                } else if let error = transcriptionError {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.red)
                        Button("Try Again") {
                            transcribeRecording()
                        }
                        .font(.subheadline)
                        .foregroundColor(palette.accent)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
                } else if currentRecording.transcript.isEmpty {
                    Button {
                        transcribeRecording()
                    } label: {
                        HStack {
                            Image(systemName: "waveform.badge.mic")
                            Text("Transcribe Recording")
                        }
                        .font(.subheadline)
                        .foregroundColor(palette.accent)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(palette.inputBackground)
                        .cornerRadius(8)
                    }
                } else {
                    Text(currentRecording.transcript)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(palette.inputBackground)
                        .cornerRadius(8)
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)
                TextEditor(text: $editedNotes)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(palette.textPrimary)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
            }

            // Footer: File size + Verification status
            footerSection
        }
    }

    // MARK: - Footer Section (File size + Verification)

    private var footerSection: some View {
        VStack(spacing: 12) {
            // File size (subtle, at bottom)
            HStack {
                Spacer()
                Text(currentRecording.fileSizeFormatted)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            // Verification status row
            HStack {
                Spacer()

                Text(verificationStatusText)
                    .font(.caption)
                    .foregroundColor(verificationStatusColor)

                Button {
                    showVerificationInfo = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 16))
                        .foregroundColor(palette.textTertiary)
                }
            }
        }
        .padding(.top, 8)
    }

    // MARK: - Verification Status (Date-only, independent from location)

    private var verificationStatusText: String {
        if verificationTimedOut && currentRecording.proofStatus == .pending {
            return "Not verified"
        }
        switch currentRecording.proofStatus {
        case .proven: return "Verified"
        case .pending: return "Pending"
        case .none, .error, .mismatch: return "Not verified"
        }
    }

    private var verificationStatusColor: Color {
        if verificationTimedOut && currentRecording.proofStatus == .pending {
            return palette.textTertiary
        }
        switch currentRecording.proofStatus {
        case .proven: return .green
        case .pending: return .orange
        case .none, .error, .mismatch: return palette.textTertiary
        }
    }

    // MARK: - Project Section

    @ViewBuilder
    private var projectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Project")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
                .textCase(.uppercase)

            if currentRecording.belongsToProject {
                // Recording is part of a project
                if let project = appState.project(for: currentRecording.projectId) {
                    Button {
                        if isOpenedFromProject {
                            // Already came from project - just go back (dismiss)
                            if hasEdits {
                                saveChanges()
                            }
                            dismiss()
                        } else {
                            // Open project sheet
                            showProjectSheet = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "folder.fill")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(project.title)
                                        .font(.subheadline)
                                        .foregroundColor(palette.textPrimary)
                                        .lineLimit(1)

                                    Text(currentRecording.versionLabel)
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(palette.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(palette.accent.opacity(0.15))
                                        .cornerRadius(4)

                                    if project.bestTakeRecordingId == currentRecording.id {
                                        Image(systemName: "star.fill")
                                            .font(.caption)
                                            .foregroundColor(.yellow)
                                    }
                                }

                                Text("\(appState.recordingCount(in: project)) versions")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }

                            Spacer()

                            if isOpenedFromProject {
                                // Show "Back" indicator when opened from project
                                Text("Back")
                                    .font(.caption)
                                    .foregroundColor(palette.accent)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                        .padding(12)
                        .background(palette.inputBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    // Remove from project button (only show if not opened from project context)
                    if !isOpenedFromProject {
                        Button(role: .destructive) {
                            appState.removeFromProject(recording: currentRecording)
                            refreshRecording()
                        } label: {
                            HStack {
                                Image(systemName: "folder.badge.minus")
                                Text("Remove from Project")
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                        .padding(.top, 4)
                    }
                }
            } else {
                // Standalone recording - show options to add to project
                HStack(spacing: 12) {
                    Button {
                        showCreateProject = true
                    } label: {
                        HStack {
                            Image(systemName: "folder.badge.plus")
                            Text("Create Project")
                        }
                        .font(.subheadline)
                        .foregroundColor(palette.accent)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(palette.inputBackground)
                        .cornerRadius(8)
                    }

                    if !appState.projects.isEmpty {
                        Button {
                            showChooseProject = true
                        } label: {
                            HStack {
                                Image(systemName: "folder")
                                Text("Add to Project")
                            }
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                            .padding(12)
                            .frame(maxWidth: .infinity)
                            .background(palette.inputBackground)
                            .cornerRadius(8)
                        }
                    }
                }
            }
        }
    }

    private func refreshRecording() {
        if let updated = appState.recording(for: currentRecording.id) {
            currentRecording = updated
        }
    }

    // MARK: - Location Section (Simplified)

    @ViewBuilder
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
                .textCase(.uppercase)

            Button {
                showLocationEditor = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "mappin.circle.fill")
                        .foregroundColor(currentRecording.hasCoordinates ? .red : palette.textTertiary)
                        .font(.system(size: 20))

                    VStack(alignment: .leading, spacing: 2) {
                        if currentRecording.hasCoordinates {
                            Text("Pinned Location")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)

                            if isLoadingReverseGeocode {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                    Text("Loading...")
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                            } else if let name = reverseGeocodedName, !name.isEmpty {
                                Text(name)
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                                    .lineLimit(1)
                            } else if !editedLocationLabel.isEmpty {
                                Text(editedLocationLabel)
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                                    .lineLimit(1)
                            }
                        } else {
                            Text("No location")
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)

                            Text("Tap to add")
                                .font(.caption)
                                .foregroundColor(palette.textTertiary)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .padding(12)
                .background(palette.inputBackground)
                .cornerRadius(8)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Location Actions

    private func loadReverseGeocodedName() {
        guard currentRecording.hasCoordinates,
              let lat = currentRecording.latitude,
              let lon = currentRecording.longitude else {
            return
        }

        isLoadingReverseGeocode = true
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)

        Task {
            let name = await appState.locationManager.reverseGeocode(coordinate)
            await MainActor.run {
                reverseGeocodedName = name
                isLoadingReverseGeocode = false
            }
        }
    }

    // MARK: - Proof Silent Creation

    private func createProofSilently() {
        // Only create if not already proven or pending
        guard currentRecording.proofStatus == .none || currentRecording.proofStatus == .error else { return }

        Task {
            var locationPayload: LocationPayload? = nil
            var locationMode: LocationMode = .off

            if currentRecording.hasCoordinates,
               let lat = currentRecording.latitude,
               let lon = currentRecording.longitude {
                let accuracy = appState.locationManager.lastKnownLocation?.horizontalAccuracy ?? 100
                locationMode = accuracy < 50 ? .precise : .approx

                locationPayload = LocationPayload(
                    latitude: lat,
                    longitude: lon,
                    horizontalAccuracy: accuracy,
                    altitude: nil,
                    timestamp: currentRecording.createdAt,
                    manualAddress: nil
                )
            }

            let updatedRecording = await appState.proofManager.createProof(
                for: currentRecording,
                locationPayload: locationPayload,
                locationMode: locationMode
            )

            await MainActor.run {
                currentRecording = updatedRecording
                appState.updateRecording(updatedRecording)
            }
        }
    }

    // MARK: - Helpers

    private var playbackProgress: Double {
        guard playback.duration > 0 else { return 0 }
        return min(1, max(0, playback.currentTime / playback.duration))
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return totalWidth * (playback.currentTime / playback.duration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func setupPlayback() {
        playback.load(url: currentRecording.fileURL)
        playback.setSpeed(appState.appSettings.playbackSpeed)
        // Apply per-recording EQ settings
        playback.setEQ(localEQSettings)

        // Smart resume - seek to last position
        if currentRecording.lastPlaybackPosition > 0 && currentRecording.lastPlaybackPosition < playback.duration {
            playback.seek(to: currentRecording.lastPlaybackPosition)
        }

        loadWaveform()
    }

    private func saveChanges() {
        var updated = currentRecording
        updated.title = editedTitle.isEmpty ? currentRecording.title : editedTitle
        updated.notes = editedNotes
        updated.locationLabel = editedLocationLabel
        // IMPORTANT: Only update iconColorHex if user explicitly changed it via ColorPicker
        // This prevents lossy Color -> hex round-trip conversion from changing the color
        // when user edits other fields (title, notes, tags, album, EQ, etc.)
        if iconColorWasModified {
            updated.iconColorHex = editedIconColor.toHex()
        }
        // Otherwise preserve the original iconColorHex (already in currentRecording)
        updated.eqSettings = localEQSettings
        updated.markers = editedMarkers

        // Handle audio edits - update file URL and duration
        if let pendingURL = pendingAudioEdit, let newDuration = pendingDuration {
            // Clean up old file if different
            let oldURL = currentRecording.fileURL
            if oldURL != pendingURL {
                AudioEditor.shared.cleanupOldFile(at: oldURL)
            }

            // Create updated recording with new audio file
            updated = RecordingItem(
                id: updated.id,
                fileURL: pendingURL,
                createdAt: updated.createdAt,
                duration: newDuration,
                title: updated.title,
                notes: updated.notes,
                tagIDs: updated.tagIDs,
                albumID: updated.albumID,
                locationLabel: updated.locationLabel,
                transcript: updated.transcript,
                latitude: updated.latitude,
                longitude: updated.longitude,
                trashedAt: updated.trashedAt,
                lastPlaybackPosition: 0,  // Reset playback position after edit
                iconColorHex: updated.iconColorHex,
                eqSettings: updated.eqSettings,
                projectId: updated.projectId,
                parentRecordingId: updated.parentRecordingId,
                versionIndex: updated.versionIndex,
                proofStatusRaw: nil,  // Clear proof - file has changed
                proofSHA256: nil,
                proofCloudCreatedAt: nil,
                proofCloudRecordName: nil,
                locationModeRaw: updated.locationModeRaw,
                locationProofHash: updated.locationProofHash,
                locationProofStatusRaw: updated.locationProofStatusRaw,
                markers: editedMarkers
            )

            // Clear waveform cache for old URL
            Task {
                await WaveformSampler.shared.clearCache(for: oldURL)
            }
        }

        // Clear edit history after saving
        editHistory.clear()

        appState.updateRecording(updated)
    }

    private func saveEQSettings() {
        var updated = currentRecording
        updated.eqSettings = localEQSettings
        currentRecording = updated
        appState.updateRecording(updated)
    }

    private func savePlaybackPosition() {
        appState.updatePlaybackPosition(playback.currentTime, for: currentRecording.id)
    }

    private func cycleSpeed() {
        let speeds: [Float] = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0]
        let currentIndex = speeds.firstIndex(of: playback.playbackSpeed) ?? 2
        let nextIndex = (currentIndex + 1) % speeds.count
        let newSpeed = speeds[nextIndex]
        playback.setSpeed(newSpeed)

        // Save to settings
        var settings = appState.appSettings
        settings.playbackSpeed = newSpeed
        appState.appSettings = settings
    }

    private func loadWaveform() {
        isLoadingWaveform = true
        Task {
            let samples = await WaveformSampler.shared.samples(
                for: currentRecording.fileURL,
                targetSampleCount: 150
            )
            await MainActor.run {
                waveformSamples = samples
                isLoadingWaveform = false
            }
        }
    }

    private func transcribeRecording() {
        isTranscribing = true
        transcriptionError = nil
        Task {
            do {
                let transcript = try await TranscriptionManager.shared.transcribe(
                    audioURL: currentRecording.fileURL,
                    language: appState.appSettings.transcriptionLanguage
                )
                currentRecording.transcript = transcript
                appState.updateTranscript(transcript, for: currentRecording.id)
                isTranscribing = false
                appState.onTranscriptionSuccess()
            } catch {
                transcriptionError = error.localizedDescription
                isTranscribing = false
            }
        }
    }

    private func shareRecording() {
        isExporting = true
        Task {
            do {
                let wavURL = try await AudioExporter.shared.exportToWAV(recording: currentRecording)
                exportedWAVURL = wavURL
                isExporting = false
                showShareSheet = true
            } catch {
                isExporting = false
            }
        }
    }
}

// MARK: - Verification Info Sheet

struct VerificationInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let timedOut: Bool

    // Date verification is independent - based only on proofStatus (CloudKit + SHA-256)
    private var dateVerificationStatus: (text: String, verified: Bool) {
        if timedOut && recording.proofStatus == .pending {
            return ("Not verified", false)
        }
        switch recording.proofStatus {
        case .proven:
            return ("Verified", true)
        case .pending:
            return ("Pending", false)
        case .none, .error, .mismatch:
            return ("Not verified", false)
        }
    }

    // Location verification is independent - based on locationProofStatus
    private var locationVerificationStatus: (text: String, verified: Bool) {
        // Use the independent location proof status
        switch recording.locationProofStatus {
        case .verified:
            return ("Verified", true)
        case .edited:
            return ("Edited", false)
        case .pending:
            return ("Pending", false)
        case .none, .error:
            return ("Not verified", false)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 20) {
                    VStack(spacing: 12) {
                        // Date verification row
                        HStack {
                            Text("Date")
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Text(dateVerificationStatus.text)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(dateVerificationStatus.verified ? palette.textPrimary : palette.textSecondary)
                                if dateVerificationStatus.verified {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(palette.inputBackground)
                        .cornerRadius(10)

                        // Location verification row
                        HStack {
                            Text("Location")
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                            Spacer()
                            HStack(spacing: 6) {
                                Text(locationVerificationStatus.text)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(locationVerificationStatus.verified ? palette.textPrimary : palette.textSecondary)
                                if locationVerificationStatus.verified {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(palette.inputBackground)
                        .cornerRadius(10)
                    }
                    .padding(.horizontal)

                    // Footnote
                    Text("Verified using iCloud server timestamp + file fingerprint.")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

// MARK: - Location Editor Sheet

struct LocationEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @Binding var recording: RecordingItem
    @Binding var editedLocationLabel: String
    @Binding var reverseGeocodedName: String?
    let onLocationChanged: () -> Void

    @State private var locationSearchQuery = ""
    @State private var isSearchingLocation = false

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 16) {
                    if recording.hasCoordinates {
                        // Current location display
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Current Location")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .textCase(.uppercase)

                            HStack(spacing: 10) {
                                Image(systemName: "mappin.circle.fill")
                                    .foregroundColor(.red)
                                    .font(.system(size: 24))

                                VStack(alignment: .leading, spacing: 2) {
                                    if let name = reverseGeocodedName, !name.isEmpty {
                                        Text(name)
                                            .font(.subheadline)
                                            .foregroundColor(palette.textPrimary)
                                    } else if !editedLocationLabel.isEmpty {
                                        Text(editedLocationLabel)
                                            .font(.subheadline)
                                            .foregroundColor(palette.textPrimary)
                                    } else if let lat = recording.latitude, let lon = recording.longitude {
                                        Text(String(format: "%.4f, %.4f", lat, lon))
                                            .font(.subheadline)
                                            .foregroundColor(palette.textPrimary)
                                    }
                                }

                                Spacer()

                                Button {
                                    clearLocation()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(palette.textSecondary)
                                        .font(.system(size: 22))
                                }
                            }
                            .padding(12)
                            .background(palette.inputBackground)
                            .cornerRadius(10)
                        }
                        .padding(.horizontal)

                        // Label field
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Label (optional)")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .textCase(.uppercase)

                            TextField("e.g. Home, Office", text: $editedLocationLabel)
                                .textFieldStyle(.plain)
                                .foregroundColor(palette.textPrimary)
                                .padding(12)
                                .background(palette.inputBackground)
                                .cornerRadius(10)
                        }
                        .padding(.horizontal)

                        Divider()
                            .padding(.vertical, 8)
                    }

                    // Search section
                    VStack(alignment: .leading, spacing: 8) {
                        Text(recording.hasCoordinates ? "Change Location" : "Add Location")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                            .textCase(.uppercase)

                        HStack {
                            Image(systemName: "magnifyingglass")
                                .foregroundColor(palette.textSecondary)
                            TextField("Search for a place or address", text: $locationSearchQuery)
                                .textFieldStyle(.plain)
                                .foregroundColor(palette.textPrimary)
                                .onChange(of: locationSearchQuery) { _, newValue in
                                    appState.locationManager.searchQuery = newValue
                                }

                            if !locationSearchQuery.isEmpty {
                                Button {
                                    locationSearchQuery = ""
                                    appState.locationManager.clearSearch()
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                        }
                        .padding(12)
                        .background(palette.inputBackground)
                        .cornerRadius(10)

                        // Search results
                        if !appState.locationManager.searchResults.isEmpty && !locationSearchQuery.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(appState.locationManager.searchResults.prefix(5), id: \.self) { result in
                                    Button {
                                        selectSearchResult(result)
                                    } label: {
                                        HStack {
                                            Image(systemName: "mappin")
                                                .foregroundColor(.red)
                                                .frame(width: 24)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text(result.title)
                                                    .font(.subheadline)
                                                    .foregroundColor(palette.textPrimary)
                                                    .lineLimit(1)
                                                if !result.subtitle.isEmpty {
                                                    Text(result.subtitle)
                                                        .font(.caption)
                                                        .foregroundColor(palette.textSecondary)
                                                        .lineLimit(1)
                                                }
                                            }

                                            Spacer()
                                        }
                                        .padding(.vertical, 10)
                                        .padding(.horizontal, 12)
                                    }
                                    .buttonStyle(.plain)

                                    if result != appState.locationManager.searchResults.prefix(5).last {
                                        Divider()
                                            .padding(.leading, 48)
                                    }
                                }
                            }
                            .background(palette.inputBackground)
                            .cornerRadius(10)
                        }

                        // Geocode button
                        if !locationSearchQuery.isEmpty && appState.locationManager.searchResults.isEmpty {
                            Button {
                                geocodeManualAddress()
                            } label: {
                                HStack {
                                    if isSearchingLocation {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "location.fill")
                                    }
                                    Text("Save as Location")
                                }
                                .font(.subheadline)
                                .foregroundColor(palette.accent)
                                .padding(12)
                                .frame(maxWidth: .infinity)
                                .background(palette.inputBackground)
                                .cornerRadius(10)
                            }
                            .disabled(isSearchingLocation)
                        }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }

    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        isSearchingLocation = true

        Task {
            if let geocoded = await appState.locationManager.geocodeCompletion(result) {
                await MainActor.run {
                    // Update recording with coordinates
                    appState.updateRecordingLocation(
                        recordingID: recording.id,
                        latitude: geocoded.coordinate.latitude,
                        longitude: geocoded.coordinate.longitude,
                        label: geocoded.label
                    )

                    // Update local state
                    recording.latitude = geocoded.coordinate.latitude
                    recording.longitude = geocoded.coordinate.longitude
                    recording.locationLabel = geocoded.label
                    editedLocationLabel = geocoded.label
                    reverseGeocodedName = geocoded.label

                    // Mark location as edited (this only affects location proof, not date proof)
                    onLocationChanged()

                    // Clear search
                    locationSearchQuery = ""
                    appState.locationManager.clearSearch()
                    isSearchingLocation = false
                }
            } else {
                await MainActor.run {
                    isSearchingLocation = false
                }
            }
        }
    }

    private func geocodeManualAddress() {
        guard !locationSearchQuery.isEmpty else { return }
        isSearchingLocation = true

        Task {
            if let geocoded = await appState.locationManager.geocodeAddress(locationSearchQuery) {
                await MainActor.run {
                    // Update recording with coordinates
                    appState.updateRecordingLocation(
                        recordingID: recording.id,
                        latitude: geocoded.coordinate.latitude,
                        longitude: geocoded.coordinate.longitude,
                        label: geocoded.label
                    )

                    // Update local state
                    recording.latitude = geocoded.coordinate.latitude
                    recording.longitude = geocoded.coordinate.longitude
                    recording.locationLabel = geocoded.label
                    editedLocationLabel = geocoded.label
                    reverseGeocodedName = geocoded.label

                    // Mark location as edited (this only affects location proof, not date proof)
                    onLocationChanged()

                    // Clear search
                    locationSearchQuery = ""
                    appState.locationManager.clearSearch()
                    isSearchingLocation = false
                }
            } else {
                await MainActor.run {
                    isSearchingLocation = false
                }
            }
        }
    }

    private func clearLocation() {
        // Clear coordinates from recording
        appState.updateRecordingLocation(
            recordingID: recording.id,
            latitude: 0,
            longitude: 0,
            label: ""
        )

        // Update local state
        recording.latitude = nil
        recording.longitude = nil
        recording.locationLabel = ""
        editedLocationLabel = ""
        reverseGeocodedName = nil

        // Mark location as edited (location removed)
        onLocationChanged()
    }
}

// MARK: - Icon Color Picker Sheet

struct IconColorPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var selectedColor: Color
    let onColorChanged: () -> Void

    private let presetColors: [Color] = [
        .red, .orange, .yellow, .green, .mint, .teal,
        .cyan, .blue, .indigo, .purple, .pink, .brown
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    // Current color preview
                    HStack {
                        Text("Selected Color")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 32, height: 32)
                            .overlay(
                                Circle()
                                    .strokeBorder(palette.textPrimary.opacity(0.15), lineWidth: 1)
                            )
                    }
                    .padding(.horizontal)

                    // Preset colors grid
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 6), spacing: 12) {
                        ForEach(presetColors, id: \.self) { color in
                            Button {
                                selectedColor = color
                                onColorChanged()
                            } label: {
                                Circle()
                                    .fill(color)
                                    .frame(width: 44, height: 44)
                                    .overlay(
                                        Circle()
                                            .strokeBorder(selectedColor == color ? palette.textPrimary : Color.clear, lineWidth: 2)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Custom color picker
                    HStack {
                        Text("Custom Color")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        ColorPicker("", selection: $selectedColor, supportsOpacity: false)
                            .labelsHidden()
                            .onChange(of: selectedColor) { _, _ in
                                onColorChanged()
                            }
                    }
                    .padding(.horizontal)

                    Spacer()
                }
                .padding(.top, 24)
            }
            .navigationTitle("Icon Color")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

// MARK: - Tag Chip Selectable

struct TagChipSelectable: View {
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
                .background(isSelected ? tag.color : tag.color.opacity(0.2))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tag.color, lineWidth: isSelected ? 0 : 1)
                )
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

// MARK: - Manage Tags Sheet

struct ManageTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var newTagName = ""
    @State private var newTagColor = Color.blue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.tags) { tag in
                        HStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 24, height: 24)
                            Text(tag.name)
                            if tag.isProtected {
                                Spacer()
                                Text("SYSTEM")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(4)
                            }
                            Spacer()
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            _ = appState.deleteTag(appState.tags[index])
                        }
                    }
                } header: {
                    Text("Existing Tags")
                }

                Section {
                    HStack {
                        TextField("Tag name", text: $newTagName)
                        ColorPicker("", selection: $newTagColor, supportsOpacity: false)
                            .labelsHidden()
                    }

                    Button("Create Tag") {
                        guard !newTagName.isEmpty else { return }
                        _ = appState.createTag(name: newTagName, colorHex: newTagColor.toHex())
                        newTagName = ""
                        newTagColor = .blue
                    }
                    .disabled(newTagName.isEmpty)
                } header: {
                    Text("New Tag")
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Choose Album Sheet

struct ChooseAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Binding var recording: RecordingItem

    @State private var newAlbumName = ""
    @State private var showCannotDeleteAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.albums) { album in
                        Button {
                            recording = appState.setAlbum(album, for: recording)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(album.name)
                                        if album.isSystem {
                                            Text("SYSTEM")
                                                .font(.caption2)
                                                .fontWeight(.bold)
                                                .foregroundColor(.orange)
                                                .padding(.horizontal, 6)
                                                .padding(.vertical, 2)
                                                .background(Color.orange.opacity(0.2))
                                                .cornerRadius(4)
                                        }
                                    }
                                    Text("\(appState.recordingCount(in: album)) recordings \u{2022} \(appState.albumTotalSizeFormatted(album))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if recording.albumID == album.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let album = appState.albums[index]
                            if album.canDelete {
                                appState.deleteAlbum(album)
                            } else {
                                showCannotDeleteAlert = true
                            }
                        }
                    }
                } header: {
                    Text("Albums")
                } footer: {
                    Text("Tip: Swipe left on an album to delete it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    HStack {
                        TextField("Album name", text: $newAlbumName)
                    }

                    Button("Create Album") {
                        guard !newAlbumName.isEmpty else { return }
                        let album = appState.createAlbum(name: newAlbumName)
                        recording = appState.setAlbum(album, for: recording)
                        newAlbumName = ""
                        dismiss()
                    }
                    .disabled(newAlbumName.isEmpty)
                } header: {
                    Text("New Album")
                }
            }
            .navigationTitle("Choose Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Cannot Delete", isPresented: $showCannotDeleteAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("The Drafts album is protected and cannot be deleted.")
            }
        }
    }
}

// MARK: - Choose Project Sheet

struct ChooseProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    @Binding var recording: RecordingItem

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                List {
                    ForEach(appState.sortedProjects) { project in
                        Button {
                            appState.addVersion(recording: recording, to: project)
                            if let updated = appState.recording(for: recording.id) {
                                recording = updated
                            }
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .foregroundColor(palette.accent)
                                    .frame(width: 24)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(project.title)
                                            .font(.subheadline)
                                            .foregroundColor(palette.textPrimary)
                                            .lineLimit(1)

                                        if project.pinned {
                                            Image(systemName: "pin.fill")
                                                .font(.caption2)
                                                .foregroundColor(palette.textSecondary)
                                        }
                                    }

                                    let versionCount = appState.recordingCount(in: project)
                                    Text("\(versionCount) version\(versionCount == 1 ? "" : "s") \u{2022} \(appState.projectTotalSizeFormatted(project))")
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }

                                Spacer()

                                Text("V\(appState.nextVersionIndex(for: project))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(palette.accent)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.accent.opacity(0.15))
                                    .cornerRadius(4)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add to Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Create Project Sheet

struct CreateProjectSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem

    @State private var projectTitle: String

    init(recording: RecordingItem) {
        self.recording = recording
        _projectTitle = State(initialValue: recording.title)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Project Title")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                            .textCase(.uppercase)

                        TextField("Enter project title", text: $projectTitle)
                            .textFieldStyle(.plain)
                            .foregroundColor(palette.textPrimary)
                            .padding(12)
                            .background(palette.inputBackground)
                            .cornerRadius(8)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("First Version")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                            .textCase(.uppercase)

                        HStack(spacing: 12) {
                            Image(systemName: "waveform")
                                .foregroundColor(palette.textSecondary)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(recording.title)
                                        .font(.subheadline)
                                        .foregroundColor(palette.textPrimary)
                                        .lineLimit(1)

                                    Text("V1")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(palette.accent)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(palette.accent.opacity(0.15))
                                        .cornerRadius(4)
                                }

                                Text("\(recording.formattedDuration) \u{2022} \(recording.formattedDate)")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(palette.inputBackground)
                        .cornerRadius(8)
                    }

                    Spacer()

                    Text("This recording will become V1 of the new project.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle("Create Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Create") {
                        appState.createProject(from: recording, title: projectTitle.isEmpty ? nil : projectTitle)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(projectTitle.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

