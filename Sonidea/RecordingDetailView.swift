//
//  RecordingDetailView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import MapKit
import UIKit

// MARK: - Identifiable UUID Wrapper for sheet(item:)

/// Wrapper to make UUID Identifiable for use with sheet(item:) pattern
private struct IdentifiableUUID: Identifiable {
    let id: UUID
}

// NOTE: Inline recorder now uses appState.recorder.recordingState directly
// to ensure UI always reflects actual recorder state (no sync issues)

// MARK: - Silence Mode (2-step flow)

private enum SilenceMode: Equatable {
    case idle                                      // No silence highlighted
    case highlighted([SelectableSilenceRange])    // Silence ranges detected, each can be toggled
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
    let iconName: String?
    let secondaryIcons: [String]?
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
        self.iconName = recording.iconName
        self.secondaryIcons = recording.secondaryIcons
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
    @State private var showProjectActionSheet = false
    @State private var showVersionSavedToast = false
    @State private var savedVersionLabel: String = ""

    // Inline version recorder uses appState.recorder.recordingState directly (no local state)
    @State private var isInlineRecorderExpanded = false

    // Overdub (Record Over Track)
    @State private var showOverdubSession = false
    @State private var showHeadphonesRequiredAlert = false

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
    @State private var showSkipSilenceResult = false  // Toast for skip silence result
    @State private var skipSilenceResultMessage = ""  // Message for skip silence toast
    @State private var silenceMode: SilenceMode = .idle  // 2-step silence removal state

    // Pro waveform editor state
    @State private var highResWaveformData: WaveformData?
    @State private var skipSilenceManager = SkipSilenceManager()
    @State private var isLoadingHighResWaveform = false
    @State private var silenceRMSMeter = SilenceRMSMeter()

    // Waveform height constants
    private let compactWaveformHeight: CGFloat = 100
    private let expandedWaveformHeight: CGFloat = 240  // Increased ~20% for more editing space

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

    // Verification info sheet state - using Identifiable wrapper for safe sheet(item:) pattern
    @State private var verificationSheetItem: IdentifiableUUID?

    // Icon color picker state
    @State private var showIconColorPicker = false

    // Icon picker state
    @State private var showIconPicker = false
    @State private var editedIconSymbol: String  // SF Symbol name (main icon)
    @State private var iconWasModified = false
    @State private var editedSecondaryIcons: [String]  // Secondary icons for top bar (max 2)
    @State private var secondaryIconsWasModified = false

    // Playback error state
    @State private var showPlaybackError = false

    // Focus state for keyboard dismissal
    @FocusState private var isNotesFocused: Bool

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
        _editedIconSymbol = State(initialValue: recording.iconName ?? recording.presetIcon.systemName)
        _editedSecondaryIcons = State(initialValue: recording.secondaryIcons ?? [])
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
        if iconWasModified {
            snapshotRecording.iconName = editedIconSymbol
        }
        if secondaryIconsWasModified {
            snapshotRecording.secondaryIcons = editedSecondaryIcons.isEmpty ? nil : editedSecondaryIcons
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
                iconName: snapshotRecording.iconName,
                iconSourceRaw: snapshotRecording.iconSourceRaw,
                secondaryIcons: snapshotRecording.secondaryIcons,
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

    /// Effective duration for Edit mode - uses pending, playback, or recording duration as fallback
    /// This prevents blank waveform when playback.duration is 0 (not yet loaded)
    private var effectiveEditDuration: TimeInterval {
        if let pending = pendingDuration, pending > 0 {
            return pending
        }
        if playback.duration > 0 {
            return playback.duration
        }
        return currentRecording.duration
    }

    /// Accessibility label for the suggested icons strip
    private var suggestedIconsAccessibilityLabel: String {
        // Priority 1: Pinned icons
        if !editedSecondaryIcons.isEmpty {
            let labels = editedSecondaryIcons.prefix(3).enumerated().map { index, symbol in
                let iconDef = IconCatalog.allIcons.first { $0.sfSymbol == symbol }
                let name = iconDef?.displayName ?? "Icon"
                let prefix = index == 0 ? "Pinned" : "Also pinned"
                return "\(prefix): \(name)"
            }
            return labels.joined(separator: "; ")
        }

        // Priority 2: Predictions
        let predictions = (currentRecording.iconPredictions ?? [])
            .filter { $0.confidence >= IconPrediction.suggestionThreshold }
            .prefix(3)

        if predictions.isEmpty {
            let iconDef = IconCatalog.allIcons.first { $0.sfSymbol == editedIconSymbol }
            return "Icon: \(iconDef?.displayName ?? "Recording")"
        }

        let labels = predictions.enumerated().map { index, pred in
            let iconDef = IconCatalog.allIcons.first { $0.sfSymbol == pred.iconSymbol }
            let name = iconDef?.displayName ?? "Icon"
            let pct = Int(pred.confidence * 100)
            let prefix = index == 0 ? "Primary" : "Suggested"
            return "\(prefix): \(name), \(pct)%"
        }
        return labels.joined(separator: "; ")
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
                .scrollDismissesKeyboard(.interactively)
                .simultaneousGesture(
                    TapGesture().onEnded {
                        // Tap outside to dismiss keyboard (uses simultaneousGesture to not block child buttons)
                        isNotesFocused = false
                    }
                )
            }
            .navigationTitle("")
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

                        // Main icon + up to 2 secondary icons strip
                        Button {
                            showIconPicker = true
                        } label: {
                            TopBarSuggestedIcons(
                                mainIcon: editedIconSymbol,
                                secondaryIcons: editedSecondaryIcons,
                                tintColor: editedIconColor
                            )
                        }
                        .accessibilityLabel(suggestedIconsAccessibilityLabel)

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
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        isNotesFocused = false
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
                // NOTE: Proof creation is now USER-DRIVEN via the Verification sheet
                // This prevents CloudKit crashes from blocking recording playback
            }
            .onDisappear {
                savePlaybackPosition()
                playback.stop()
                editHistory.clear()  // Clean up undo history
            }
            .onChange(of: isEditingWaveform) { _, editing in
                // Pause playback when switching modes (don't stop - keeps engine ready for edit mode playback)
                playback.pause()
                if editing {
                    // Load high-res waveform data when entering edit mode
                    // Force load if data is nil and not currently loading (handles failed pre-load)
                    let shouldForce = highResWaveformData == nil && !isLoadingHighResWaveform
                    loadHighResWaveform(force: shouldForce)

                    // Ensure playback engine is loaded with current audio file
                    // This handles case where engine was stopped/unloaded
                    if !playback.isLoaded {
                        let audioURL = pendingAudioEdit ?? currentRecording.fileURL
                        playback.load(url: audioURL)
                        // Seek to current playhead position after reload
                        playback.seek(to: editPlayheadPosition)
                    }
                }
            }
            .onChange(of: skipSilenceManager.isEnabled) { _, enabled in
                if enabled {
                    // Analyze audio for silence when skip silence is enabled
                    Task {
                        await skipSilenceManager.analyze(url: pendingAudioEdit ?? currentRecording.fileURL)
                    }
                }
            }
            .onChange(of: playback.currentTime) { _, currentTime in
                // Sync edit playhead with playback time when playing in edit mode
                if isEditingWaveform && playback.isPlaying {
                    editPlayheadPosition = currentTime
                }
                // Skip silence during playback
                if playback.isPlaying, let skipTo = skipSilenceManager.shouldSkip(at: currentTime) {
                    playback.seek(to: skipTo)
                }
                // Update silence debug strip RMS meter during playback/scrubbing
                if case .highlighted = silenceMode {
                    silenceRMSMeter.updateRMS(at: currentTime)
                }
            }
            .onChange(of: playback.isPlaying) { oldValue, newValue in
                // When playback stops, sync final position to edit playhead
                // This catches the case where playback finishes naturally
                if isEditingWaveform && oldValue == true && newValue == false {
                    editPlayheadPosition = playback.currentTime
                }
            }
            .onChange(of: silenceMode) { _, newMode in
                // Clear RMS meter when leaving highlight mode
                if case .idle = newMode {
                    silenceRMSMeter.clear()
                }
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
            .sheet(item: $verificationSheetItem) { item in
                VerificationInfoSheet(
                    recordingID: item.id,
                    onVerifyRequested: createProofUserInitiated
                )
                .presentationDetents([.height(260)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showIconColorPicker) {
                IconColorPickerSheet(selectedColor: $editedIconColor, onColorChanged: {
                    iconColorWasModified = true
                })
                .presentationDetents([.height(320)])
                .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showIconPicker) {
                IconPickerSheet(
                    selectedIconSymbol: $editedIconSymbol,
                    secondaryIcons: $editedSecondaryIcons,
                    tintColor: editedIconColor,
                    suggestions: currentRecording.iconPredictions ?? [],
                    onIconChanged: {
                        iconWasModified = true
                    },
                    onSecondaryIconsChanged: {
                        secondaryIconsWasModified = true
                    }
                )
                .presentationDetents([.large])
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
            .fullScreenCover(isPresented: $showOverdubSession) {
                OverdubSessionView(
                    baseRecording: currentRecording,
                    onLayerSaved: { layer in
                        // Refresh current recording to get updated overdub info
                        if let updated = appState.recording(for: currentRecording.id) {
                            currentRecording = updated
                        }
                    }
                )
            }
            .alert("Headphones Required", isPresented: $showHeadphonesRequiredAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Recording over a track requires headphones to prevent feedback. Plug in headphones or connect a supported headset, then try again.")
            }
            .overlay(alignment: .bottom) {
                if showVersionSavedToast {
                    versionSavedToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: showVersionSavedToast)
                }
                if showSkipSilenceResult {
                    skipSilenceResultToast
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .animation(.spring(response: 0.3), value: showSkipSilenceResult)
                        .onAppear {
                            // Auto-dismiss after 3 seconds
                            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                                withAnimation { showSkipSilenceResult = false }
                            }
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

    // MARK: - Skip Silence Result Toast

    private var skipSilenceResultToast: some View {
        HStack(spacing: 8) {
            Image(systemName: skipSilenceResultMessage.contains("Removed") ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundColor(skipSilenceResultMessage.contains("Removed") ? .green : .blue)
            Text(skipSilenceResultMessage)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.85))
        .cornerRadius(25)
        .padding(.bottom, 100)  // Higher position so it doesn't overlap playback controls
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 8) {  // Reduced from 16 for tighter layout
            // Edit/Done button row (ABOVE waveform, not overlapping)
            // When editing: Undo/Redo on left, Done on right
            if !isLoadingWaveform && !waveformSamples.isEmpty {
                HStack {
                    // Left side: Skip Silence toggle (non-edit) or Undo/Redo (edit mode)
                    if !isEditingWaveform {
                        // Skip Silence toggle for playback (non-destructive)
                        SkipSilenceToggle(skipSilenceManager: skipSilenceManager)
                    } else {
                        // Undo/Redo buttons (edit mode only)
                        HStack(spacing: 8) {
                            Button {
                                performUndo()
                            } label: {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(editHistory.canUndo ? palette.accent : palette.textTertiary)
                                    .frame(width: 32, height: 28)
                                    .background(editHistory.canUndo ? palette.accent.opacity(0.15) : palette.inputBackground)
                                    .cornerRadius(6)
                            }
                            .disabled(!editHistory.canUndo)

                            Button {
                                performRedo()
                            } label: {
                                Image(systemName: "arrow.uturn.forward")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundColor(editHistory.canRedo ? palette.accent : palette.textTertiary)
                                    .frame(width: 32, height: 28)
                                    .background(editHistory.canRedo ? palette.accent.opacity(0.15) : palette.inputBackground)
                                    .cornerRadius(6)
                            }
                            .disabled(!editHistory.canRedo)

                            // Divider
                            Rectangle()
                                .fill(palette.stroke.opacity(0.3))
                                .frame(width: 1, height: 20)

                            // Skip Silence button (2-step flow) with Cancel option
                            if case .highlighted = silenceMode {
                                // Two-button layout when highlighting is active
                                HStack(spacing: 4) {
                                    // Remove button (destructive)
                                    Button {
                                        removeSilentParts()
                                    } label: {
                                        HStack(spacing: 3) {
                                            Image(systemName: "scissors")
                                                .font(.system(size: 11, weight: .medium))
                                            Text("Remove")
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                        .foregroundColor(.white)
                                        .padding(.horizontal, 8)
                                        .frame(height: 28)
                                        .background(Color.red)
                                        .cornerRadius(6)
                                    }
                                    .disabled(isProcessingEdit)

                                    // Cancel button (neutral)
                                    Button {
                                        silenceMode = .idle
                                        silenceRMSMeter.clear()
                                    } label: {
                                        Text("Cancel")
                                            .font(.system(size: 11, weight: .medium))
                                            .foregroundColor(palette.textSecondary)
                                            .padding(.horizontal, 8)
                                            .frame(height: 28)
                                            .background(palette.inputBackground)
                                            .cornerRadius(6)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(palette.stroke.opacity(0.3), lineWidth: 1)
                                            )
                                    }
                                    .disabled(isProcessingEdit)
                                }
                            } else {
                                // Single button when idle
                                Button {
                                    highlightSilentParts()
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "waveform.path")
                                            .font(.system(size: 12, weight: .medium))
                                        Text("Highlight Silent Parts")
                                            .font(.system(size: 11, weight: .medium))
                                    }
                                    .foregroundColor(isProcessingEdit ? palette.textTertiary : palette.accent)
                                    .padding(.horizontal, 8)
                                    .frame(height: 28)
                                    .background(isProcessingEdit ? palette.inputBackground : palette.accent.opacity(0.15))
                                    .cornerRadius(6)
                                }
                                .disabled(isProcessingEdit)
                                .accessibilityLabel("Highlight Silent Parts")
                            }
                        }
                    }

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            if isEditingWaveform {
                                // Exit edit mode - pause playback and reset precision mode
                                playback.pause()
                                isPrecisionMode = false
                                silenceMode = .idle  // Clear any highlighted silence
                                isEditingWaveform = false
                            } else {
                                // Enter edit mode - ensure playback is loaded for accurate duration
                                // This prevents waveform timeline using stale currentRecording.duration
                                if !playback.isLoaded {
                                    let audioURL = pendingAudioEdit ?? currentRecording.fileURL
                                    playback.load(url: audioURL)
                                }

                                // Capture playhead position BEFORE pausing
                                let capturedTime = playback.currentTime
                                playback.pause()
                                selectionStart = 0
                                // Use actual playback duration for accurate timeline (not stored duration)
                                selectionEnd = playback.duration > 0 ? playback.duration : currentRecording.duration
                                // Set playhead to captured position (quantized to 0.01s)
                                editPlayheadPosition = (capturedTime / 0.01).rounded() * 0.01
                                isEditingWaveform = true
                            }
                        }
                    } label: {
                        Text(isEditingWaveform ? "Done" : "Edit")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.accent)
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
                    // Edit mode: Show loading indicator if high-res waveform not yet loaded
                    // OR if playback duration is not available (prevents duration mismatch)
                    if highResWaveformData == nil || playback.duration <= 0 {
                        VStack(spacing: 12) {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: palette.accent))
                            Text("Loading waveform...")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                        .frame(height: expandedWaveformHeight)
                        .task {
                            // Ensure waveform loading is triggered when this view appears
                            // This handles cases where the pre-load failed or was skipped
                            if highResWaveformData == nil && !isLoadingHighResWaveform {
                                print("🎨 [Waveform] Loading view appeared - triggering load")
                                loadHighResWaveform(force: true)
                            }
                            // Ensure playback is loaded to get accurate duration
                            if playback.duration <= 0 && !playback.isLoaded {
                                let audioURL = pendingAudioEdit ?? currentRecording.fileURL
                                playback.load(url: audioURL)
                            }
                        }
                    } else {
                        // Pro-level waveform editor with Voice Memos-style dense bars, timeline, pinch-to-zoom, and pan
                        // CRITICAL: Use playback.duration directly to ensure timeline matches actual audio
                        let editorDuration = playback.duration > 0 ? playback.duration : effectiveEditDuration
                        ProWaveformEditor(
                        waveformData: highResWaveformData,
                        duration: editorDuration,
                        selectionStart: $selectionStart,
                        selectionEnd: $selectionEnd,
                        playheadPosition: $editPlayheadPosition,
                        markers: $editedMarkers,
                        silenceRanges: highlightedSilenceRanges,
                        currentTime: playback.currentTime,
                        isPlaying: playback.isPlaying,
                        isPrecisionMode: $isPrecisionMode,
                        onSeek: { time in
                            playback.seek(to: time)
                        },
                        onMarkerTap: { marker in
                            // Tap marker to set playhead to marker position
                            editPlayheadPosition = marker.time
                            playback.seek(to: marker.time)
                        },
                        onSilenceRangeTap: { id in
                            toggleSilenceRange(id: id)
                        }
                    )
                    // Force fresh @State when duration changes to fix stale WaveformTimeline.duration
                    // WaveformTimeline.duration is a `let` constant, so @State must be recreated
                    // Use playback.duration directly in ID to ensure recreation when actual duration is known
                    .id("waveform-\(currentRecording.id)-\(Int(playback.duration * 1000))")
                    }
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
            .padding(.top, 8)  // Only top padding; bottom gap comes from VStack spacing

            // Edit mode: Selection info and actions
            if isEditingWaveform {
                VStack(spacing: 12) {
                    // Silence debug strip (only when highlighting silence)
                    if case .highlighted = silenceMode {
                        SilenceDebugStrip(
                            currentDBFS: silenceRMSMeter.currentDBFS,
                            thresholdDBFS: silenceRMSMeter.thresholdDBFS,
                            isBelowThreshold: silenceRMSMeter.isBelowThreshold
                        )
                        .padding(.horizontal, 8)
                    }

                    // Selection time display with nudge controls (0.01s precision)
                    // Center shows live playhead time during playback/scrubbing
                    SelectionTimeDisplay(
                        selectionStart: $selectionStart,
                        selectionEnd: $selectionEnd,
                        duration: effectiveEditDuration,
                        playheadPosition: editPlayheadPosition
                    )

                    // Edit actions: Trim, Cut, Skip Silence, Marker, Precision (Undo/Redo now in top bar)
                    WaveformEditActionsView(
                        canTrim: canPerformTrim,
                        canCut: canPerformCut,
                        isProcessing: isProcessingEdit,
                        isPrecisionMode: $isPrecisionMode,
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

            // Playback controls - Apple-like symmetric single row
            // [ Speed ]  [ -15 ]  [ Play ]  [ +15 ]  [ EQ ]
            HStack(spacing: 16) {
                // Speed button (left edge)
                Button {
                    cycleSpeed()
                } label: {
                    Text(String(format: "%.1fx", playback.playbackSpeed))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.blue)
                        .frame(width: 48, height: 36)
                        .background(Color.blue.opacity(0.15))
                        .cornerRadius(8)
                }

                Spacer()

                // Skip backward
                Button {
                    let skipAmount = -Double(appState.appSettings.skipInterval.rawValue)
                    if isEditingWaveform {
                        // In edit mode: update editor playhead and sync to playback
                        let newTime = max(0, min(effectiveEditDuration, editPlayheadPosition + skipAmount))
                        editPlayheadPosition = newTime
                        playback.seek(to: newTime)
                    } else {
                        playback.skip(seconds: skipAmount)
                    }
                } label: {
                    Image(systemName: "gobackward.\(appState.appSettings.skipInterval.rawValue)")
                        .font(.system(size: 28))
                        .foregroundColor(palette.textPrimary)
                        .frame(width: 44, height: 44)
                }

                // Play/Pause (centered)
                Button {
                    if isEditingWaveform {
                        if playback.isPlaying {
                            // Pause playback
                            playback.pause()
                        } else {
                            // In edit mode: ensure engine is loaded and seek to playhead before playing
                            if !playback.isLoaded {
                                let audioURL = pendingAudioEdit ?? currentRecording.fileURL
                                playback.load(url: audioURL)
                            }
                            // Seek to the editor playhead position, then play
                            playback.seek(to: editPlayheadPosition)
                            playback.play()
                        }
                    } else {
                        playback.togglePlayPause()
                    }
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(palette.accent)
                }

                // Skip forward
                Button {
                    let skipAmount = Double(appState.appSettings.skipInterval.rawValue)
                    if isEditingWaveform {
                        // In edit mode: update editor playhead and sync to playback
                        let newTime = max(0, min(effectiveEditDuration, editPlayheadPosition + skipAmount))
                        editPlayheadPosition = newTime
                        playback.seek(to: newTime)
                    } else {
                        playback.skip(seconds: skipAmount)
                    }
                } label: {
                    Image(systemName: "goforward.\(appState.appSettings.skipInterval.rawValue)")
                        .font(.system(size: 28))
                        .foregroundColor(palette.textPrimary)
                        .frame(width: 44, height: 44)
                }

                Spacer()

                // EQ button (right edge)
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showEQPanel.toggle()
                    }
                } label: {
                    Text("EQ")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(showEQPanel ? .white : .purple)
                        .frame(width: 48, height: 36)
                        .background(showEQPanel ? Color.purple : Color.purple.opacity(0.15))
                        .cornerRadius(8)
                }
            }
            .padding(.horizontal, 8)

            Text(currentRecording.formattedDate)
                .font(.caption)
                .foregroundColor(palette.textSecondary)

            // Collapsible EQ Panel (between date and New Version/Overdub buttons)
            if showEQPanel {
                eqPanel
                    .padding(.top, 4)
            }

            // Inline Version Recorder (New Version / Overdub buttons)
            inlineVersionRecorder
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

        // Reset silence highlight (ranges no longer valid after undo)
        silenceMode = .idle
    }

    private func performRedo() {
        guard let snapshot = editHistory.popRedo() else { return }

        // Push current state to undo stack
        let currentSnapshot = createUndoSnapshot(description: snapshot.description)
        editHistory.pushUndo(currentSnapshot)

        // Restore redo state
        restoreFromSnapshot(snapshot)
        hasAudioEdits = snapshot.audioFileURL != currentRecording.fileURL

        // Reset silence highlight (ranges no longer valid after redo)
        silenceMode = .idle
    }

    private func performTrim() {
        guard canPerformTrim else { return }

        // Reset silence highlight (ranges invalidated by edit)
        silenceMode = .idle

        // Push current state to undo stack before making changes
        let undoSnapshot = createUndoSnapshot(description: "Trim")
        editHistory.pushUndo(undoSnapshot)

        isProcessingEdit = true
        let sourceURL = pendingAudioEdit ?? currentRecording.fileURL

        // Capture original duration before trim for feedback notification
        let originalDuration = playback.duration > 0 ? playback.duration : (pendingDuration ?? currentRecording.duration)

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

                    // Show success feedback (same pattern as Cut)
                    let trimmedAmount = originalDuration - result.newDuration
                    skipSilenceResultMessage = String(format: "Trimmed %.1fs of audio", trimmedAmount)
                    showSkipSilenceResult = true
                }
                isProcessingEdit = false
            }
        }
    }

    private func performCut() {
        guard canPerformCut else { return }
        // Execute cut immediately (undo is available if needed)
        executeCut()
    }

    private func executeCut() {
        // Reset silence highlight (ranges invalidated by edit)
        silenceMode = .idle

        // Push current state to undo stack before making changes
        let undoSnapshot = createUndoSnapshot(description: "Cut")
        editHistory.pushUndo(undoSnapshot)

        isProcessingEdit = true
        let sourceURL = pendingAudioEdit ?? currentRecording.fileURL
        let cutStart = selectionStart
        let cutEnd = selectionEnd

        Task {
            let result = await AudioEditor.shared.cut(
                sourceURL: sourceURL,
                startTime: cutStart,
                endTime: cutEnd
            )

            await MainActor.run {
                if result.success {
                    // Update markers to match new timeline (remove cut region, shift after)
                    editedMarkers = editedMarkers.afterCut(
                        removingStart: cutStart,
                        removingEnd: cutEnd
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

                    // Show success feedback
                    let cutDuration = cutEnd - cutStart
                    skipSilenceResultMessage = String(format: "Cut %.1fs of audio", cutDuration)
                    showSkipSilenceResult = true
                }
                isProcessingEdit = false
            }
        }
    }

    // MARK: - 2-Step Silence Removal

    /// Step 1: Highlight silent parts (detect and show red overlay)
    private func highlightSilentParts() {
        isProcessingEdit = true
        let sourceURL = pendingAudioEdit ?? currentRecording.fileURL
        let detectionThreshold: Float = -45.0

        Task {
            // Clear silence cache to ensure fresh detection with current parameters
            AudioWaveformExtractor.shared.clearSilenceCache(for: sourceURL)

            // Detect silence ranges (minimum 0.5s, threshold -45dB)
            let silenceRanges = try? await AudioWaveformExtractor.shared.detectSilence(
                from: sourceURL,
                threshold: detectionThreshold,
                minDuration: 0.5
            )

            await MainActor.run {
                if let ranges = silenceRanges, !ranges.isEmpty {
                    // Wrap ranges in SelectableSilenceRange (all selected by default)
                    let selectableRanges = ranges.map { SelectableSilenceRange(range: $0, isSelected: true) }
                    silenceMode = .highlighted(selectableRanges)

                    // Load audio into RMS meter for debug strip
                    silenceRMSMeter.thresholdDBFS = detectionThreshold
                    silenceRMSMeter.loadAudio(from: sourceURL)

                    // Calculate total silence duration for feedback
                    let totalSilence = ranges.reduce(0) { $0 + $1.duration }
                    let totalSeconds = String(format: "%.1f", totalSilence)
                    skipSilenceResultMessage = "Found \(ranges.count) silent sections (\(totalSeconds)s) — tap to deselect"
                    showSkipSilenceResult = true
                } else {
                    skipSilenceResultMessage = "No silences ≥ 0.5s found"
                    showSkipSilenceResult = true
                }
                isProcessingEdit = false
            }
        }
    }

    /// Toggle selection of a specific silence range
    private func toggleSilenceRange(id: UUID) {
        guard case .highlighted(var ranges) = silenceMode else { return }
        if let index = ranges.firstIndex(where: { $0.id == id }) {
            ranges[index].isSelected.toggle()
            silenceMode = .highlighted(ranges)
        }
    }

    /// Step 2: Remove the highlighted silent parts
    private func removeSilentParts() {
        guard case .highlighted(let selectableRanges) = silenceMode else {
            silenceMode = .idle
            return
        }

        // Filter to only selected ranges
        let selectedRanges = selectableRanges.filter { $0.isSelected }.map { $0.range }

        guard !selectedRanges.isEmpty else {
            skipSilenceResultMessage = "No silent sections selected"
            showSkipSilenceResult = true
            silenceMode = .idle
            return
        }

        // Push current state to undo stack before making changes
        let undoSnapshot = createUndoSnapshot(description: "Remove Silent Parts")
        editHistory.pushUndo(undoSnapshot)

        isProcessingEdit = true
        let sourceURL = pendingAudioEdit ?? currentRecording.fileURL

        Task {
            // Remove only the selected silence ranges with padding
            let result = await AudioEditor.shared.removeMultipleSilenceRanges(
                sourceURL: sourceURL,
                silenceRanges: selectedRanges,
                padding: 0.05  // 50ms padding on each side
            )

            await MainActor.run {
                if result.success {
                    // Remap markers to new timeline (accounting for removed silence)
                    editedMarkers = editedMarkers.afterRemovingSilence(ranges: selectedRanges, padding: 0.05)

                    // Store pending edit
                    pendingAudioEdit = result.outputURL
                    pendingDuration = result.newDuration
                    hasAudioEdits = true

                    // Reload waveform for new file
                    reloadWaveformForPendingEdit()

                    // Reset selection to full duration
                    selectionStart = 0
                    selectionEnd = result.newDuration

                    // Clamp playhead
                    editPlayheadPosition = min(editPlayheadPosition, result.newDuration)

                    // Reload playback
                    playback.load(url: result.outputURL)

                    // Show success message
                    let removedSeconds = String(format: "%.1f", result.removedDuration)
                    skipSilenceResultMessage = "Removed \(result.removedRangesCount) silent sections (\(removedSeconds)s)"
                    showSkipSilenceResult = true
                } else {
                    skipSilenceResultMessage = "Failed to remove silence"
                    showSkipSilenceResult = true
                }

                // Reset silence mode back to idle
                silenceMode = .idle
                isProcessingEdit = false
            }
        }
    }

    /// Get currently highlighted silence ranges (for overlay rendering)
    private var highlightedSilenceRanges: [SelectableSilenceRange] {
        if case .highlighted(let ranges) = silenceMode {
            return ranges
        }
        return []
    }

    private func addMarkerAtPlayhead() {
        // Marker placement uses the edit playhead position (tap-to-set cursor)
        // The editPlayheadPosition is controlled by:
        // - Tapping anywhere on the waveform
        // - Tapping a marker (sets playhead to marker time)
        // - Dragging the playhead cursor
        //
        // This ensures deterministic, user-controlled marker placement.
        // The playhead position is already quantized to 0.01s in all input sources,
        // so we use it directly without re-quantization.

        // Push current state to undo stack before adding marker
        let undoSnapshot = createUndoSnapshot(description: "Add Marker")
        editHistory.pushUndo(undoSnapshot)

        let duration = pendingDuration ?? playback.duration
        let markerTime = Swift.max(0, Swift.min(editPlayheadPosition, duration))

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
        // Clear high-res waveform so it reloads with new audio
        highResWaveformData = nil
        // Reset skip silence manager for new audio
        skipSilenceManager.clear()

        Task {
            // Clear caches for old URL
            await WaveformSampler.shared.clearCache(for: currentRecording.fileURL)
            await AudioWaveformExtractor.shared.clearCache(for: currentRecording.fileURL)

            let samples = await WaveformSampler.shared.samples(
                for: pendingURL,
                targetSampleCount: 150
            )

            // Load high-res waveform for new file
            let waveformData = try? await AudioWaveformExtractor.shared.extractWaveform(from: pendingURL)

            await MainActor.run {
                waveformSamples = samples
                highResWaveformData = waveformData
                isLoadingWaveform = false
            }
        }
    }

    // MARK: - Inline Version Recorder

    private var inlineVersionRecorder: some View {
        VStack(spacing: 0) {
            if !appState.recorder.isActive {
                // Idle state: Compact "Record New Version" button
                inlineRecorderIdleButton
            } else {
                // Recording/Paused state: Expanded card
                inlineRecorderExpandedCard
            }
        }
        .padding(.top, 8)
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: appState.recorder.recordingState)
    }

    private var inlineRecorderIdleButton: some View {
        HStack(spacing: 12) {
            // Record New Version button
            Button {
                startInlineRecording()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic.circle.fill")
                        .font(.system(size: 18))
                    Text("New Version")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(palette.accent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(palette.accent.opacity(0.12))
                .cornerRadius(12)
            }

            // Record Over Track button
            Button {
                handleRecordOverTrack()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 16))
                    Text("Overdub")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(palette.surface)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.stroke.opacity(0.3), lineWidth: 1)
                )
            }
            .disabled(!canAddOverdubLayer)
            .opacity(canAddOverdubLayer ? 1.0 : 0.5)
        }
    }

    /// Whether we can add an overdub layer to this recording
    private var canAddOverdubLayer: Bool {
        appState.canAddOverdubLayer(to: currentRecording)
    }

    /// Handle Record Over Track button tap
    private func handleRecordOverTrack() {
        // Check headphones first
        guard AudioSessionManager.shared.isHeadphoneMonitoringActive() else {
            showHeadphonesRequiredAlert = true
            return
        }

        // Stop any current playback
        playback.stop()

        // Show overdub session
        showOverdubSession = true
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
                accentColor: appState.recorder.isPaused ? palette.textSecondary : palette.accent
            )
            .frame(height: 50)
            .opacity(appState.recorder.isPaused ? 0.5 : 1.0)

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
                    Image(systemName: appState.recorder.isPaused ? "play.fill" : "pause.fill")
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
        // Start recording - UI updates automatically via @Observable
        appState.recorder.startRecording()
    }

    private func toggleInlineRecordingPause() {
        // Toggle based on actual recorder state - UI updates automatically
        if appState.recorder.isRecording {
            appState.recorder.pauseRecording()
        } else if appState.recorder.isPaused {
            appState.recorder.resumeRecording()
        }
    }

    private func cancelInlineRecording() {
        // Stop and discard the recording - UI updates automatically via @Observable
        _ = appState.recorder.stopRecording()
    }

    private func stopAndSaveInlineRecording() {
        // Stop recording - UI updates automatically via @Observable
        guard let rawData = appState.recorder.stopRecording() else {
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
            return
        }

        // Link to project as new version
        appState.addVersion(recording: newRecording, to: targetProject)

        // Get the version label for the toast
        let versionLabel = "V\(appState.nextVersionIndex(for: targetProject) - 1)"

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

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
        VStack(alignment: .leading, spacing: 24) {

            // ═══════════════════════════════════════════════════════════════
            // DETAILS - Premium iOS Card Layout
            // ═══════════════════════════════════════════════════════════════

            // Section Header
            Text("DETAILS")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.textSecondary.opacity(0.7))
                .padding(.bottom, 4)

            // Card 1: Title, Album, Project
            MetadataCard {
                // Row 1: Title (editable inline - single render, no overlay)
                VStack(spacing: 0) {
                    HStack(alignment: .center, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("TITLE")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(palette.textTertiary)

                            TextField("Recording title", text: $editedTitle)
                                .textFieldStyle(.plain)
                                .font(.system(size: 16))
                                .foregroundColor(palette.textPrimary)
                        }

                        Spacer()

                        // No chevron for editable field
                    }
                    .padding(.horizontal, CardStyle.horizontalPadding)
                    .padding(.vertical, CardStyle.verticalPadding)

                    Rectangle()
                        .fill(palette.textSecondary.opacity(CardStyle.dividerOpacity))
                        .frame(height: 0.5)
                        .padding(.leading, CardStyle.horizontalPadding)
                }

                // Row 2: Album (with gold glow styling for shared albums)
                PickerRow(
                    label: "ALBUM",
                    value: appState.album(for: currentRecording.albumID)?.name ?? "None",
                    accessory: albumRowAccessory,
                    showDivider: true,
                    action: { showChooseAlbum = true }
                )

                // Row 3: Project - popover attached to ROW ITSELF with .rect(.bounds) anchor
                PickerRow(
                    label: "PROJECT",
                    value: projectDisplayValue,
                    valueColor: currentRecording.belongsToProject ? palette.textPrimary : palette.textSecondary,
                    accessory: projectAccessory,
                    showDivider: false,
                    action: { showProjectActionSheet = true }
                )
                .popover(
                    isPresented: $showProjectActionSheet,
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    // Popover content - menu options
                    ProjectActionMenu(
                        belongsToProject: currentRecording.belongsToProject,
                        hasProjects: !appState.projects.isEmpty,
                        onViewProject: {
                            showProjectActionSheet = false
                            showProjectSheet = true
                        },
                        onRemoveFromProject: {
                            showProjectActionSheet = false
                            appState.removeFromProject(recording: currentRecording)
                            refreshRecording()
                        },
                        onCreateProject: {
                            showProjectActionSheet = false
                            showCreateProject = true
                        },
                        onAddToExisting: {
                            showProjectActionSheet = false
                            showChooseProject = true
                        },
                        onCancel: {
                            showProjectActionSheet = false
                        }
                    )
                    .presentationCompactAdaptation(.popover)
                }
            }

            // Card 2: Tags with inline chips
            VStack(alignment: .leading, spacing: 8) {
                // Header row: TAGS label + Manage button
                HStack {
                    Text("TAGS")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(palette.textSecondary.opacity(0.7))

                    Spacer()

                    Button("Manage") {
                        showManageTags = true
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(palette.accent)
                }

                // Tag chips or "None"
                MetadataCard {
                    VStack(alignment: .leading, spacing: 0) {
                        if appState.tags.isEmpty {
                            // No tags exist at all
                            Text("None")
                                .font(.system(size: 15))
                                .foregroundColor(palette.textSecondary)
                                .padding(.horizontal, CardStyle.horizontalPadding)
                                .padding(.vertical, CardStyle.verticalPadding)
                        } else {
                            // Show tag chips (sorted by createdAt, limited to ~2 lines)
                            FlowLayout(spacing: 8) {
                                ForEach(tagsOrderedByCreation.prefix(12)) { tag in
                                    TagChipSelectable(
                                        tag: tag,
                                        isSelected: currentRecording.tagIDs.contains(tag.id)
                                    ) {
                                        currentRecording = appState.toggleTag(tag, for: currentRecording)
                                    }
                                }
                            }
                            .padding(.horizontal, CardStyle.horizontalPadding)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
            .padding(.top, 12)

            // Overdub Group Section (only shown if recording is part of an overdub)
            if currentRecording.isPartOfOverdub {
                overdubGroupSection
            }

            // Location Section
            locationSection

            // Transcription
            transcriptionSection

            // Notes
            notesSection

            // Footer: File size + Verification status
            footerSection
        }
    }

    // MARK: - Details Card Computed Properties

    /// Display value for Project row
    private var projectDisplayValue: String {
        if currentRecording.belongsToProject,
           let project = appState.project(for: currentRecording.projectId) {
            return project.title
        }
        return "None"
    }

    /// Custom accessory view for Album row (gold glow for shared albums)
    private var albumRowAccessory: AnyView? {
        guard let album = appState.album(for: currentRecording.albumID) else {
            // No album - show "None" in secondary color
            return AnyView(
                Text("None")
                    .font(.system(size: 16))
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
            )
        }

        if album.isShared {
            // Shared album - gold glow styling (matches AlbumTitleView)
            return AnyView(
                Text(album.name)
                    .font(.system(size: 16))
                    .foregroundColor(.sharedAlbumGold)
                    .shadow(color: Color.sharedAlbumGold.opacity(0.7), radius: 6, x: 0, y: 0)
                    .shadow(color: Color.sharedAlbumGold.opacity(0.35), radius: 12, x: 0, y: 0)
                    .lineLimit(1)
                    .accessibilityLabel("\(album.name), shared album")
            )
        } else {
            // Normal album - standard styling
            return AnyView(
                Text(album.name)
                    .font(.system(size: 16))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)
            )
        }
    }

    /// Custom accessory view for Project row (shows version badge if in project)
    private var projectAccessory: AnyView? {
        guard currentRecording.belongsToProject,
              let project = appState.project(for: currentRecording.projectId) else {
            return nil
        }

        return AnyView(
            HStack(spacing: 8) {
                Text(project.title)
                    .font(.system(size: 16))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)

                Text(currentRecording.versionLabel)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.accent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.accent.opacity(0.15))
                    .cornerRadius(4)

                if project.bestTakeRecordingId == currentRecording.id {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                }
            }
        )
    }

    /// Tags in creation order (array order - new tags are appended)
    private var tagsOrderedByCreation: [Tag] {
        appState.tags  // Array order reflects creation order
    }

    // MARK: - Overdub Group Section

    @ViewBuilder
    private var overdubGroupSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            Text("OVERDUB GROUP")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.textSecondary.opacity(0.7))

            // Card with all overdub members
            MetadataCard {
                VStack(spacing: 0) {
                    if let group = appState.overdubGroup(for: currentRecording) {
                        // Base recording row
                        if let baseRecording = appState.recordings.first(where: { $0.id == group.baseRecordingId }) {
                            OverdubMemberRow(
                                recording: baseRecording,
                                role: "Base",
                                isCurrent: baseRecording.id == currentRecording.id,
                                showDivider: !group.layerRecordingIds.isEmpty,
                                palette: palette
                            ) {
                                if baseRecording.id != currentRecording.id {
                                    navigateToRecording(baseRecording)
                                }
                            }
                        }

                        // Layer rows
                        ForEach(Array(group.layerRecordingIds.enumerated()), id: \.element) { index, layerId in
                            if let layerRecording = appState.recordings.first(where: { $0.id == layerId }) {
                                OverdubMemberRow(
                                    recording: layerRecording,
                                    role: "Layer \(index + 1)",
                                    isCurrent: layerRecording.id == currentRecording.id,
                                    showDivider: index < group.layerRecordingIds.count - 1,
                                    palette: palette
                                ) {
                                    if layerRecording.id != currentRecording.id {
                                        navigateToRecording(layerRecording)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        .padding(.top, 12)
    }

    /// Navigate to another recording in the overdub group
    private func navigateToRecording(_ recording: RecordingItem) {
        // Update the current recording to show the selected one
        currentRecording = recording
        editedTitle = recording.title
        // Reset playback state
        playback.stop()
        playback.load(url: recording.fileURL)
    }

    // MARK: - Transcription Section

    private var transcriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Transcription")
                    .font(.caption)
                    .fontWeight(.medium)
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

            MetadataCard {
                if isTranscribing {
                    CardRow(showDivider: false) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                        Text("Transcribing...")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                    }
                } else if let error = transcriptionError {
                    CardRow(showDivider: false) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.red)
                            Button("Try Again") {
                                transcribeRecording()
                            }
                            .font(.subheadline)
                            .foregroundColor(palette.accent)
                        }
                        Spacer()
                    }
                } else if currentRecording.transcript.isEmpty {
                    CardRow(showDivider: false, action: { transcribeRecording() }) {
                        Image(systemName: "waveform.badge.mic")
                            .foregroundColor(palette.accent)
                        Text("Transcribe Recording")
                            .font(.subheadline)
                            .foregroundColor(palette.accent)
                        Spacer()
                    }
                } else {
                    CardRow(showDivider: false) {
                        Text(currentRecording.transcript)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    // MARK: - Notes Section

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(palette.textSecondary)
                .textCase(.uppercase)

            TextEditor(text: $editedNotes)
                .scrollContentBackground(.hidden)
                .foregroundColor(palette.textPrimary)
                .padding(12)
                .frame(minHeight: 100)
                .background(palette.inputBackground)
                .cornerRadius(CardStyle.cornerRadius)
                .focused($isNotesFocused)
        }
    }

    // MARK: - Footer Section (File size + Verification)

    private var footerSection: some View {
        HStack(alignment: .center, spacing: 8) {
            // File size (LEFT)
            Text(currentRecording.fileSizeFormatted)
                .font(.footnote)
                .foregroundColor(palette.textTertiary)

            Spacer(minLength: 0)

            // Verification status (RIGHT)
            Button {
                verificationSheetItem = IdentifiableUUID(id: currentRecording.id)
            } label: {
                HStack(spacing: 5) {
                    Text(verificationStatusText)
                        .font(.footnote)
                        .foregroundColor(verificationStatusColor)

                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(palette.textTertiary)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 6)
    }

    // MARK: - Verification Status (Date-only, independent from location)

    private var verificationStatusText: String {
        switch currentRecording.proofStatus {
        case .proven: return "Verified"
        case .pending: return "Pending"
        case .none, .error, .mismatch: return "Not verified"
        }
    }

    private var verificationStatusColor: Color {
        switch currentRecording.proofStatus {
        case .proven: return .green
        case .pending: return .orange
        case .none, .error, .mismatch: return palette.textTertiary
        }
    }

    private func refreshRecording() {
        if let updated = appState.recording(for: currentRecording.id) {
            currentRecording = updated
        }
    }

    // MARK: - Location Section

    @ViewBuilder
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(palette.textSecondary)
                .textCase(.uppercase)

            MetadataCard {
                CardRow(showDivider: false, action: { showLocationEditor = true }) {
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
                        .fontWeight(.semibold)
                        .foregroundColor(palette.textTertiary)
                }
            }
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

    // MARK: - User-Initiated Proof Creation

    /// Create proof when user explicitly requests it (from Verification sheet)
    /// This is the ONLY way proofs are created - never automatic on view load
    private func createProofUserInitiated() {
        // Only create if not already proven
        guard currentRecording.proofStatus != .proven else { return }

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

        // Pre-load high-res waveform in background so Edit mode is instant
        // This prevents blank waveform when entering Edit mode
        loadHighResWaveform()
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
        // Only update iconName if user explicitly changed it via IconPicker
        if iconWasModified {
            updated.iconName = editedIconSymbol
            updated.iconSource = .user  // Mark as user-set to prevent auto-override
        }
        // Save secondary icons if modified
        if secondaryIconsWasModified {
            updated.secondaryIcons = editedSecondaryIcons.isEmpty ? nil : editedSecondaryIcons
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
                iconName: updated.iconName,
                iconSourceRaw: updated.iconSourceRaw,  // Preserve icon source
                secondaryIcons: updated.secondaryIcons,  // Preserve secondary icons
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

    private func loadHighResWaveform(force: Bool = false) {
        // Skip if already loaded (unless forced) or currently loading
        if !force {
            guard highResWaveformData == nil else {
                print("🎨 [Waveform] loadHighResWaveform skipped: already loaded")
                return
            }
        }

        // Don't start another load if one is in progress
        guard !isLoadingHighResWaveform else {
            print("🎨 [Waveform] loadHighResWaveform skipped: already loading")
            return
        }

        isLoadingHighResWaveform = true
        let audioURL = pendingAudioEdit ?? currentRecording.fileURL
        let recordingId = currentRecording.id

        print("🎨 [Waveform] Loading high-res waveform for: \(audioURL.lastPathComponent)")
        print("🎨 [Waveform] File exists: \(FileManager.default.fileExists(atPath: audioURL.path))")
        print("🎨 [Waveform] Recording duration: \(currentRecording.duration)s")

        Task {
            do {
                let waveformData = try await AudioWaveformExtractor.shared.extractWaveform(from: audioURL)

                await MainActor.run {
                    // Verify we're still showing the same recording
                    guard self.currentRecording.id == recordingId else {
                        print("⚠️ [Waveform] Recording changed during load, discarding result")
                        self.isLoadingHighResWaveform = false  // Reset flag even if discarding
                        return
                    }

                    self.highResWaveformData = waveformData
                    self.isLoadingHighResWaveform = false

                    // Log success with sample counts
                    let lodCount = waveformData.lodLevels.count
                    let lod0Count = waveformData.lodLevels.first?.count ?? 0
                    print("✅ [Waveform] High-res waveform loaded: \(lodCount) LOD levels, LOD0=\(lod0Count) samples, duration=\(waveformData.duration)s")
                }
            } catch {
                await MainActor.run {
                    self.isLoadingHighResWaveform = false
                    print("❌ [Waveform] Failed to load high-res waveform: \(error.localizedDescription)")
                }
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
    @Environment(AppState.self) private var appState

    /// Recording ID to look up - uses safe sheet(item:) pattern
    let recordingID: UUID
    let onVerifyRequested: () -> Void

    /// Safely fetch the recording from AppState - returns nil if not found
    private var recording: RecordingItem? {
        appState.recordings.first { $0.id == recordingID }
    }

    // Date verification status
    private func dateVerificationStatus(for recording: RecordingItem) -> (text: String, verified: Bool) {
        switch recording.proofStatus {
        case .proven:
            return ("Verified", true)
        case .pending:
            return ("Pending", false)
        case .none, .error, .mismatch:
            return ("Not verified", false)
        }
    }

    // Location verification status
    private func locationVerificationStatus(for recording: RecordingItem) -> (text: String, verified: Bool) {
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

    // Whether we can attempt verification
    private func canVerify(for recording: RecordingItem) -> Bool {
        recording.proofStatus != .proven && !appState.proofManager.isProcessing
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if let recording = recording {
                    // Recording found - show verification info
                    verificationContent(for: recording)
                } else {
                    // Recording not found - show fallback
                    unavailableContent
                }
            }
            .navigationTitle("Verification")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
            // NOTE: We intentionally do NOT check CloudKit availability on sheet open.
            // CloudKit is only initialized when user taps "Verify with iCloud" button.
            // This prevents crashes if entitlements/provisioning are misconfigured.
        }
    }

    // MARK: - Verification Content

    @ViewBuilder
    private func verificationContent(for recording: RecordingItem) -> some View {
        let dateStatus = dateVerificationStatus(for: recording)
        let locationStatus = locationVerificationStatus(for: recording)
        let canVerifyNow = canVerify(for: recording)

        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 12) {
                    // Date verification row
                    HStack {
                        Text("Date")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        Spacer()
                        HStack(spacing: 6) {
                            Text(dateStatus.text)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(dateStatus.verified ? palette.textPrimary : palette.textSecondary)
                            if dateStatus.verified {
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
                            Text(locationStatus.text)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(locationStatus.verified ? palette.textPrimary : palette.textSecondary)
                            if locationStatus.verified {
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

            // Verify button (only show if not already verified)
            if recording.proofStatus != .proven {
                VStack(spacing: 12) {
                    Button {
                        onVerifyRequested()
                    } label: {
                        HStack(spacing: 8) {
                            if appState.proofManager.isProcessing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "icloud.fill")
                            }
                            Text(appState.proofManager.isProcessing ? "Verifying..." : "Verify with iCloud")
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canVerifyNow ? Color.blue : Color.gray)
                        .cornerRadius(12)
                    }
                    .disabled(!canVerifyNow)
                    .padding(.horizontal)

                    // Error message if verification failed
                    if let error = appState.proofManager.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                }
            }

                // Footnote
                Text("Verified using iCloud server timestamp + file fingerprint.")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .padding(.top, 8)
            }
            .padding(.top, 20)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Unavailable Content (fallback if recording not found)

    private var unavailableContent: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(palette.textTertiary)

            Text("Verification Unavailable")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text("The recording information could not be loaded.")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
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

// MARK: - Icon Picker Sheet

/// Suggestion type for visual highlighting
enum IconSuggestionType {
    case none
    case primary    // Strong highlight (first suggestion)
    case secondary  // Subtle highlight (2nd/3rd suggestion)
}

// MARK: - Top Bar Suggested Icons

/// Compact icon strip for the navigation bar showing 1-3 icons
/// Shows: main icon (always first) + up to 2 secondary icons
struct TopBarSuggestedIcons: View {
    let mainIcon: String
    let secondaryIcons: [String]
    let tintColor: Color

    /// Icons to display: main icon first, then up to 2 secondary icons
    private var displayIcons: [(symbol: String, isMain: Bool)] {
        var icons: [(symbol: String, isMain: Bool)] = [(symbol: mainIcon, isMain: true)]

        // Add up to 2 secondary icons (that aren't the same as main)
        for secondary in secondaryIcons.prefix(2) where secondary != mainIcon {
            icons.append((symbol: secondary, isMain: false))
        }

        return icons
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(displayIcons.enumerated()), id: \.offset) { _, item in
                TopBarIconItem(
                    symbol: item.symbol,
                    isMain: item.isMain,
                    tintColor: tintColor
                )
            }
        }
    }
}

/// Individual icon item in the top bar strip - plain tintable SF Symbol
private struct TopBarIconItem: View {
    let symbol: String
    let isMain: Bool
    let tintColor: Color

    /// Icon size: main icon slightly larger
    private var iconSize: CGFloat {
        isMain ? 20 : 17
    }

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: iconSize, weight: isMain ? .semibold : .regular))
            .foregroundColor(tintColor)
    }
}

struct IconPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var selectedIconSymbol: String  // Main icon
    @Binding var secondaryIcons: [String]    // Up to 2 secondary icons
    let tintColor: Color
    let suggestions: [IconPrediction]
    let onIconChanged: () -> Void            // Called when main icon changes
    let onSecondaryIconsChanged: () -> Void  // Called when secondary icons change

    @State private var searchText = ""

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
    private let maxSecondaryIcons = 2

    /// Primary suggestion (highest confidence)
    private var primarySuggestion: IconPrediction? {
        suggestions.first
    }

    /// Secondary suggestions (2nd and 3rd highest confidence)
    private var secondarySuggestions: [IconPrediction] {
        Array(suggestions.dropFirst().prefix(2))
    }

    /// Check if an icon is a secondary icon
    private func isSecondary(_ symbol: String) -> Bool {
        secondaryIcons.contains(symbol)
    }

    /// Toggle secondary icon status
    private func toggleSecondary(_ symbol: String) {
        if let index = secondaryIcons.firstIndex(of: symbol) {
            secondaryIcons.remove(at: index)
            onSecondaryIconsChanged()
        } else if secondaryIcons.count < maxSecondaryIcons && symbol != selectedIconSymbol {
            secondaryIcons.append(symbol)
            onSecondaryIconsChanged()
        }
    }

    /// Set icon as main icon
    private func setAsMainIcon(_ symbol: String) {
        // Remove from secondary if it was there
        if let index = secondaryIcons.firstIndex(of: symbol) {
            secondaryIcons.remove(at: index)
            onSecondaryIconsChanged()
        }
        selectedIconSymbol = symbol
        onIconChanged()
    }

    /// Get the suggestion type for an icon symbol
    private func suggestionType(for symbol: String) -> IconSuggestionType {
        if symbol == primarySuggestion?.iconSymbol {
            return .primary
        } else if secondarySuggestions.contains(where: { $0.iconSymbol == symbol }) {
            return .secondary
        }
        return .none
    }

    /// Suggested icons as IconDefinitions (for display)
    private var suggestedIcons: [IconDefinition] {
        suggestions.compactMap { prediction in
            IconCatalog.allIcons.first { $0.sfSymbol == prediction.iconSymbol }
        }
    }

    /// Filtered icons based on search
    private var filteredCategories: [(category: IconCategory, icons: [IconDefinition])] {
        if searchText.isEmpty {
            return IconCatalog.iconsByCategory
        }
        let query = searchText.lowercased()
        return IconCatalog.iconsByCategory.compactMap { (category, icons) in
            let filtered = icons.filter { icon in
                icon.displayName.lowercased().contains(query) ||
                category.rawValue.lowercased().contains(query)
            }
            return filtered.isEmpty ? nil : (category: category, icons: filtered)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        // Suggested section (only show when not searching and has suggestions)
                        if !suggestedIcons.isEmpty && searchText.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                // Section header with sparkle
                                HStack(spacing: 6) {
                                    Image(systemName: "sparkles")
                                        .font(.system(size: 14))
                                        .foregroundColor(palette.accent)
                                    Text("Suggested")
                                        .font(.headline)
                                        .foregroundColor(palette.textPrimary)
                                }
                                .padding(.horizontal)

                                // Suggested icons grid
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(suggestedIcons) { icon in
                                        MainIconGridItem(
                                            icon: icon,
                                            isMainIcon: selectedIconSymbol == icon.sfSymbol,
                                            isSecondaryIcon: isSecondary(icon.sfSymbol),
                                            canAddSecondary: secondaryIcons.count < maxSecondaryIcons,
                                            suggestionType: suggestionType(for: icon.sfSymbol),
                                            tintColor: tintColor,
                                            palette: palette,
                                            onTap: {
                                                setAsMainIcon(icon.sfSymbol)
                                            },
                                            onSetAsMain: {
                                                setAsMainIcon(icon.sfSymbol)
                                            },
                                            onToggleSecondary: {
                                                toggleSecondary(icon.sfSymbol)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.top, 8)
                            .padding(.bottom, 8)
                        }

                        // Categories with icons
                        ForEach(filteredCategories, id: \.category) { category, icons in
                            VStack(alignment: .leading, spacing: 8) {
                                // Category header
                                Text(category.rawValue)
                                    .font(.headline)
                                    .foregroundColor(palette.textPrimary)
                                    .padding(.horizontal)

                                // Icon grid
                                LazyVGrid(columns: columns, spacing: 8) {
                                    ForEach(icons) { icon in
                                        MainIconGridItem(
                                            icon: icon,
                                            isMainIcon: selectedIconSymbol == icon.sfSymbol,
                                            isSecondaryIcon: isSecondary(icon.sfSymbol),
                                            canAddSecondary: secondaryIcons.count < maxSecondaryIcons,
                                            suggestionType: suggestionType(for: icon.sfSymbol),
                                            tintColor: tintColor,
                                            palette: palette,
                                            onTap: {
                                                setAsMainIcon(icon.sfSymbol)
                                            },
                                            onSetAsMain: {
                                                setAsMainIcon(icon.sfSymbol)
                                            },
                                            onToggleSecondary: {
                                                toggleSecondary(icon.sfSymbol)
                                            }
                                        )
                                    }
                                }
                                .padding(.horizontal)
                            }
                            .padding(.bottom, 8)
                        }
                    }
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle("Choose Icon")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search icons")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

/// Individual icon grid item
private struct IconGridItem: View {
    let icon: IconDefinition
    let isSelected: Bool
    let suggestionType: IconSuggestionType
    let tintColor: Color
    let palette: ThemePalette
    let onTap: () -> Void

    /// Glow color for suggestions
    private var suggestionGlowColor: Color {
        switch suggestionType {
        case .primary:
            return palette.accent
        case .secondary:
            return palette.accent.opacity(0.6)
        case .none:
            return .clear
        }
    }

    /// Glow intensity for suggestions
    private var suggestionGlowRadius: CGFloat {
        switch suggestionType {
        case .primary:
            return 8
        case .secondary:
            return 4
        case .none:
            return 0
        }
    }

    /// Border width for suggestions
    private var suggestionBorderWidth: CGFloat {
        switch suggestionType {
        case .primary:
            return 2.5
        case .secondary:
            return 1.5
        case .none:
            return 0
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    // Suggestion glow effect (behind the icon)
                    if suggestionType != .none {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(suggestionGlowColor.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .blur(radius: suggestionGlowRadius)
                    }

                    Image(systemName: icon.sfSymbol)
                        .font(.system(size: 22))
                        .foregroundColor(isSelected ? .white : tintColor)
                        .frame(width: 44, height: 44)
                        .background(isSelected ? tintColor : tintColor.opacity(0.12))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isSelected ? tintColor : (suggestionType != .none ? palette.accent : Color.clear),
                                    lineWidth: isSelected ? 2 : suggestionBorderWidth
                                )
                        )
                }

                Text(icon.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 50)
            }
        }
        .buttonStyle(.plain)
    }
}

/// Icon grid item with main icon highlighting and context menu
private struct MainIconGridItem: View {
    let icon: IconDefinition
    let isMainIcon: Bool
    let isSecondaryIcon: Bool
    let canAddSecondary: Bool
    let suggestionType: IconSuggestionType
    let tintColor: Color
    let palette: ThemePalette
    let onTap: () -> Void
    let onSetAsMain: () -> Void
    let onToggleSecondary: () -> Void

    /// Glow color for suggestions
    private var suggestionGlowColor: Color {
        switch suggestionType {
        case .primary:
            return palette.accent
        case .secondary:
            return palette.accent.opacity(0.6)
        case .none:
            return .clear
        }
    }

    /// Glow intensity for suggestions
    private var suggestionGlowRadius: CGFloat {
        switch suggestionType {
        case .primary:
            return 8
        case .secondary:
            return 4
        case .none:
            return 0
        }
    }

    /// Border width for suggestions
    private var suggestionBorderWidth: CGFloat {
        switch suggestionType {
        case .primary:
            return 2.5
        case .secondary:
            return 1.5
        case .none:
            return 0
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                ZStack {
                    // Suggestion glow effect (behind the icon)
                    if suggestionType != .none {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(suggestionGlowColor.opacity(0.3))
                            .frame(width: 44, height: 44)
                            .blur(radius: suggestionGlowRadius)
                    }

                    Image(systemName: icon.sfSymbol)
                        .font(.system(size: 22))
                        .foregroundColor(isMainIcon ? .white : tintColor)
                        .frame(width: 44, height: 44)
                        .background(isMainIcon ? tintColor : tintColor.opacity(0.12))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(
                                    isMainIcon ? tintColor : (suggestionType != .none ? palette.accent : Color.clear),
                                    lineWidth: isMainIcon ? 2 : suggestionBorderWidth
                                )
                        )
                        .overlay(alignment: .topTrailing) {
                            // Main icon indicator (star)
                            if isMainIcon {
                                Image(systemName: "star.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(3)
                                    .background(tintColor)
                                    .clipShape(Circle())
                                    .offset(x: 4, y: -4)
                            }
                            // Secondary icon indicator (number badge)
                            else if isSecondaryIcon {
                                Image(systemName: "2.circle.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundColor(palette.accent)
                                    .background(Circle().fill(palette.background).padding(-1))
                                    .offset(x: 4, y: -4)
                            }
                        }
                }

                Text(icon.displayName)
                    .font(.system(size: 9))
                    .foregroundColor(palette.textSecondary)
                    .lineLimit(1)
                    .frame(maxWidth: 50)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            // Set as main icon option (unless already main)
            if !isMainIcon {
                Button {
                    onSetAsMain()
                } label: {
                    Label("Set as Main Icon", systemImage: "star")
                }
            }

            // Secondary icon toggle
            if isSecondaryIcon {
                Button(role: .destructive) {
                    onToggleSecondary()
                } label: {
                    Label("Remove from Top Bar", systemImage: "minus.circle")
                }
            } else if !isMainIcon && canAddSecondary {
                Button {
                    onToggleSecondary()
                } label: {
                    Label("Add to Top Bar", systemImage: "plus.circle")
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

// MARK: - Metadata Card Components

/// Constants for consistent card styling
private enum CardStyle {
    static let cornerRadius: CGFloat = 14
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14
    static let rowSpacing: CGFloat = 0  // Rows use dividers, not spacing
    static let dividerOpacity: Double = 0.12
    static let headerBottomPadding: CGFloat = 8
}

/// A container card with rounded background - used for grouping related metadata rows
struct MetadataCard<Content: View>: View {
    @Environment(\.themePalette) private var palette
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: CardStyle.rowSpacing) {
            content()
        }
        .background(palette.inputBackground)
        .cornerRadius(CardStyle.cornerRadius)
    }
}

/// A tappable row inside a card - iOS Settings style
struct CardRow<Content: View>: View {
    @Environment(\.themePalette) private var palette
    let showDivider: Bool
    let action: (() -> Void)?
    let content: () -> Content

    init(showDivider: Bool = true, action: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.showDivider = showDivider
        self.action = action
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            if let action = action {
                Button(action: action) {
                    rowContent
                }
                .buttonStyle(.plain)
            } else {
                rowContent
            }

            if showDivider {
                Divider()
                    .background(palette.textSecondary.opacity(CardStyle.dividerOpacity))
                    .padding(.leading, CardStyle.horizontalPadding)
            }
        }
    }

    private var rowContent: some View {
        HStack {
            content()
        }
        .padding(.horizontal, CardStyle.horizontalPadding)
        .padding(.vertical, CardStyle.verticalPadding)
        .contentShape(Rectangle())
    }
}

/// Section header with optional right-side action - sits outside the card
struct CardSectionHeader: View {
    @Environment(\.themePalette) private var palette
    let title: String
    let actionLabel: String?
    let action: (() -> Void)?

    init(_ title: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.title = title
        self.actionLabel = actionLabel
        self.action = action
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(palette.textSecondary)
                .textCase(.uppercase)

            Spacer()

            if let label = actionLabel, let action = action {
                Button(action: action) {
                    Text(label)
                        .font(.caption)
                        .foregroundColor(palette.accent)
                }
            }
        }
        .padding(.bottom, CardStyle.headerBottomPadding)
    }
}

/// Premium iOS-style picker row - label above, value below, chevron on right
struct PickerRow: View {
    @Environment(\.themePalette) private var palette
    let label: String
    let value: String
    var valueColor: Color?
    var accessory: AnyView?
    let showDivider: Bool
    let action: (() -> Void)?

    init(
        label: String,
        value: String,
        valueColor: Color? = nil,
        accessory: AnyView? = nil,
        showDivider: Bool = true,
        action: (() -> Void)? = nil
    ) {
        self.label = label
        self.value = value
        self.valueColor = valueColor
        self.accessory = accessory
        self.showDivider = showDivider
        self.action = action
    }

    var body: some View {
        VStack(spacing: 0) {
            Button(action: { action?() }) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textTertiary)

                        if let accessory = accessory {
                            accessory
                        } else {
                            Text(value)
                                .font(.system(size: 16))
                                .foregroundColor(valueColor ?? palette.textPrimary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(palette.textTertiary.opacity(0.6))
                }
                .padding(.horizontal, CardStyle.horizontalPadding)
                .padding(.vertical, CardStyle.verticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showDivider {
                Rectangle()
                    .fill(palette.textSecondary.opacity(CardStyle.dividerOpacity))
                    .frame(height: 0.5)
                    .padding(.leading, CardStyle.horizontalPadding)
            }
        }
    }
}

/// Popover menu for Project row actions
struct ProjectActionMenu: View {
    @Environment(\.themePalette) private var palette

    let belongsToProject: Bool
    let hasProjects: Bool
    let onViewProject: () -> Void
    let onRemoveFromProject: () -> Void
    let onCreateProject: () -> Void
    let onAddToExisting: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if belongsToProject {
                // Recording is in a project - show view/remove options
                menuButton(title: "View Project", icon: "folder.fill") {
                    onViewProject()
                }

                Divider()

                menuButton(title: "Remove from Project", icon: "minus.circle", isDestructive: true) {
                    onRemoveFromProject()
                }
            } else {
                // Recording is not in a project - show add options
                menuButton(title: "Create New Project", icon: "folder.badge.plus") {
                    onCreateProject()
                }

                if hasProjects {
                    Divider()

                    menuButton(title: "Add to Existing Project", icon: "folder") {
                        onAddToExisting()
                    }
                }
            }

            Divider()

            menuButton(title: "Cancel", icon: nil) {
                onCancel()
            }
        }
        .frame(width: 220)
        .background(palette.cardBackground)
    }

    @ViewBuilder
    private func menuButton(title: String, icon: String?, isDestructive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if let icon = icon {
                    Image(systemName: icon)
                        .font(.system(size: 16))
                        .foregroundColor(isDestructive ? .red : palette.accent)
                        .frame(width: 24)
                }

                Text(title)
                    .font(.system(size: 15))
                    .foregroundColor(isDestructive ? .red : palette.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Row for displaying an overdub group member (base or layer)
struct OverdubMemberRow: View {
    let recording: RecordingItem
    let role: String
    let isCurrent: Bool
    let showDivider: Bool
    let palette: ThemePalette
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: action) {
                HStack(spacing: 12) {
                    // Role badge
                    Text(role.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(isCurrent ? .white : palette.accent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(isCurrent ? palette.accent : palette.accent.opacity(0.15))
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title.isEmpty ? "Untitled" : recording.title)
                            .font(.system(size: 15, weight: isCurrent ? .semibold : .regular))
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)

                        Text(recording.formattedDuration)
                            .font(.system(size: 12))
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()

                    if isCurrent {
                        Text("Current")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(palette.textSecondary)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(palette.textTertiary.opacity(0.6))
                    }
                }
                .padding(.horizontal, CardStyle.horizontalPadding)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isCurrent)

            if showDivider {
                Rectangle()
                    .fill(palette.textSecondary.opacity(CardStyle.dividerOpacity))
                    .frame(height: 0.5)
                    .padding(.leading, CardStyle.horizontalPadding)
            }
        }
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
    @State private var showSharedAlbumWarning = false
    @State private var pendingAlbumSelection: Album?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.albums) { album in
                        Button {
                            // Show warning for shared albums if needed
                            if album.isShared && !album.skipAddRecordingConsent {
                                pendingAlbumSelection = album
                                showSharedAlbumWarning = true
                            } else {
                                recording = appState.setAlbum(album, for: recording)
                                dismiss()
                            }
                        } label: {
                            AlbumRowView(
                                album: album,
                                isSelected: recording.albumID == album.id
                            )
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
            .alert("Move to Shared Album?", isPresented: $showSharedAlbumWarning) {
                Button("Cancel", role: .cancel) {
                    pendingAlbumSelection = nil
                }
                Button("Move to Shared Album") {
                    if let album = pendingAlbumSelection {
                        recording = appState.setAlbum(album, for: recording)
                        dismiss()
                    }
                }
            } message: {
                if let album = pendingAlbumSelection {
                    Text("This recording will be visible to all \(album.participantCount) participants in \"\(album.name)\". Are you sure?")
                }
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

