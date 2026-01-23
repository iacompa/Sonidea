//
//  RecordingDetailView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import MapKit

struct RecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var playback = PlaybackEngine()

    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var editedLocationLabel: String
    @State private var currentRecording: RecordingItem

    @State private var showManageTags = false
    @State private var showChooseAlbum = false
    @State private var showShareSheet = false
    @State private var showSpeedPicker = false

    @State private var waveformSamples: [Float] = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var isLoadingWaveform = true

    @State private var isTranscribing = false
    @State private var transcriptionError: String?
    @State private var exportedWAVURL: URL?
    @State private var isExporting = false

    @State private var editedIconColor: Color

    // Location search state
    @State private var locationSearchQuery = ""
    @State private var isSearchingLocation = false
    @State private var locationSearchResults: [MKLocalSearchCompletion] = []
    @State private var reverseGeocodedName: String?
    @State private var isLoadingReverseGeocode = false

    init(recording: RecordingItem) {
        _editedTitle = State(initialValue: recording.title)
        _editedNotes = State(initialValue: recording.notes)
        _editedLocationLabel = State(initialValue: recording.locationLabel)
        _currentRecording = State(initialValue: recording)
        _editedIconColor = State(initialValue: recording.iconColor)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        playbackSection
                        Divider()
                        metadataSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        shareRecording()
                    } label: {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveChanges()
                        savePlaybackPosition()
                        playback.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                setupPlayback()
                loadReverseGeocodedName()
            }
            .onDisappear {
                savePlaybackPosition()
                playback.stop()
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
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Waveform
            ZStack {
                if isLoadingWaveform {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .frame(height: 100)
                } else if waveformSamples.isEmpty {
                    Image(systemName: "waveform")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                        .frame(height: 100)
                } else {
                    WaveformView(
                        samples: waveformSamples,
                        progress: playbackProgress,
                        zoomScale: $zoomScale
                    )
                    .frame(height: 100)
                }
            }
            .padding(.vertical, 10)

            // Zoom indicator
            if zoomScale > 1.01 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation {
                            zoomScale = 1.0
                        }
                    } label: {
                        Text("Reset")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            // Time display
            HStack {
                Text(formatTime(playback.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(playback.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 4)
                        .cornerRadius(2)
                    Rectangle()
                        .fill(Color.accentColor)
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

            // Playback controls
            HStack(spacing: 32) {
                // Skip backward
                Button {
                    playback.skip(seconds: -Double(appState.appSettings.skipInterval.rawValue))
                } label: {
                    Image(systemName: "gobackward.\(appState.appSettings.skipInterval.rawValue)")
                        .font(.system(size: 28))
                        .foregroundColor(.primary)
                }

                // Play/Pause
                Button {
                    playback.togglePlayPause()
                } label: {
                    Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 56))
                        .foregroundColor(.accentColor)
                }

                // Skip forward
                Button {
                    playback.skip(seconds: Double(appState.appSettings.skipInterval.rawValue))
                } label: {
                    Image(systemName: "goforward.\(appState.appSettings.skipInterval.rawValue)")
                        .font(.system(size: 28))
                        .foregroundColor(.primary)
                }
            }

            // Speed control
            HStack {
                Spacer()
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
                Spacer()
            }

            Text(currentRecording.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextField("Recording title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            // Album
            VStack(alignment: .leading, spacing: 8) {
                Text("Album")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Button {
                    showChooseAlbum = true
                } label: {
                    HStack {
                        if let album = appState.album(for: currentRecording.albumID) {
                            Text(album.name)
                                .foregroundColor(.primary)
                        } else {
                            Text("None")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // Tags
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button("Manage") {
                        showManageTags = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
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

            // Location Section
            locationSection

            // Icon Color
            VStack(alignment: .leading, spacing: 8) {
                Text("Icon Color")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                HStack {
                    Text("Choose a color for this recording's icon")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    ColorPicker("", selection: $editedIconColor, supportsOpacity: false)
                        .labelsHidden()
                }
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Transcription
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Transcription")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
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
                        .foregroundColor(.blue)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.systemGray6))
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
                        .foregroundColor(.blue)
                        .padding(12)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                    }
                } else {
                    Text(currentRecording.transcript)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemGray6))
                        .cornerRadius(8)
                }
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextEditor(text: $editedNotes)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Location Section

    @ViewBuilder
    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Location")
                .font(.caption)
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            if currentRecording.hasCoordinates {
                // Has GPS coordinates - show pinned location
                pinnedLocationView
            } else {
                // No coordinates - show address search
                addressSearchView
            }
        }
    }

    private var pinnedLocationView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Pinned location indicator
            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundColor(.red)
                    .font(.system(size: 20))

                VStack(alignment: .leading, spacing: 2) {
                    Text("Pinned Location")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)

                    if isLoadingReverseGeocode {
                        HStack(spacing: 4) {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Loading...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else if let name = reverseGeocodedName, !name.isEmpty {
                        Text(name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else if !editedLocationLabel.isEmpty {
                        Text(editedLocationLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    } else if let lat = currentRecording.latitude, let lon = currentRecording.longitude {
                        Text(String(format: "%.4f, %.4f", lat, lon))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Clear location button
                Button {
                    clearLocation()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 20))
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)

            // Editable label
            TextField("Location label (optional)", text: $editedLocationLabel)
                .textFieldStyle(.plain)
                .padding(12)
                .background(Color(.systemGray6))
                .cornerRadius(8)
        }
    }

    private var addressSearchView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Search field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search for a place or address", text: $locationSearchQuery)
                    .textFieldStyle(.plain)
                    .onChange(of: locationSearchQuery) { _, newValue in
                        appState.locationManager.searchQuery = newValue
                    }

                if !locationSearchQuery.isEmpty {
                    Button {
                        locationSearchQuery = ""
                        appState.locationManager.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(12)
            .background(Color(.systemGray6))
            .cornerRadius(8)

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
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
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
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }

            // Manual save button (geocode typed address)
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
                    .foregroundColor(.blue)
                    .padding(12)
                    .frame(maxWidth: .infinity)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
                .disabled(isSearchingLocation)
            }

            // Request location permission hint
            if appState.locationManager.authorizationStatus == .notDetermined {
                Button {
                    appState.locationManager.requestPermission()
                } label: {
                    HStack {
                        Image(systemName: "location")
                        Text("Enable GPS for automatic location")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                .padding(.top, 4)
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

    private func selectSearchResult(_ result: MKLocalSearchCompletion) {
        isSearchingLocation = true

        Task {
            if let geocoded = await appState.locationManager.geocodeCompletion(result) {
                await MainActor.run {
                    // Update recording with coordinates
                    appState.updateRecordingLocation(
                        recordingID: currentRecording.id,
                        latitude: geocoded.coordinate.latitude,
                        longitude: geocoded.coordinate.longitude,
                        label: geocoded.label
                    )

                    // Update local state
                    currentRecording.latitude = geocoded.coordinate.latitude
                    currentRecording.longitude = geocoded.coordinate.longitude
                    currentRecording.locationLabel = geocoded.label
                    editedLocationLabel = geocoded.label
                    reverseGeocodedName = geocoded.label

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
                        recordingID: currentRecording.id,
                        latitude: geocoded.coordinate.latitude,
                        longitude: geocoded.coordinate.longitude,
                        label: geocoded.label
                    )

                    // Update local state
                    currentRecording.latitude = geocoded.coordinate.latitude
                    currentRecording.longitude = geocoded.coordinate.longitude
                    currentRecording.locationLabel = geocoded.label
                    editedLocationLabel = geocoded.label
                    reverseGeocodedName = geocoded.label

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
            recordingID: currentRecording.id,
            latitude: 0,
            longitude: 0,
            label: ""
        )

        // Update local state
        currentRecording.latitude = nil
        currentRecording.longitude = nil
        currentRecording.locationLabel = ""
        editedLocationLabel = ""
        reverseGeocodedName = nil
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
        playback.setEQ(appState.appSettings.eqSettings)

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
        updated.iconColorHex = editedIconColor.toHex()
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
                            }
                        }
                    }
                } header: {
                    Text("Albums")
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
        }
    }
}
