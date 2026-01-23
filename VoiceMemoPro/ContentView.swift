//
//  ContentView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
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
    case albums

    var displayName: String {
        switch self {
        case .recordings: return "Recordings"
        case .albums: return "Albums"
        }
    }
}

// MARK: - Main Content View
struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var currentRoute: AppRoute = .recordings
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showTipJar = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                // Top Navigation Bar
                topNavigationBar
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                // Recording Status (when recording)
                if appState.recorder.isRecording {
                    RecordingStatusView(
                        duration: appState.recorder.currentDuration,
                        liveSamples: appState.recorder.liveMeterSamples
                    )
                    .padding(.top, 8)
                    .padding(.horizontal, 16)
                }

                // Main Content
                Group {
                    switch currentRoute {
                    case .recordings:
                        RecordingsListView()
                    case .map:
                        GPSInsightsMapView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .safeAreaInset(edge: .bottom) {
            // Bottom Record Button
            VStack(spacing: 0) {
                VoiceMemosRecordButton {
                    handleRecordTap()
                }
                .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(
                    colors: [Color(.systemBackground).opacity(0), Color(.systemBackground)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 60)
                .allowsHitTesting(false),
                alignment: .top
            )
        }
        .sheet(isPresented: $showSearch) {
            SearchSheetView()
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheetView()
        }
        .sheet(isPresented: $showTipJar) {
            TipJarSheetView()
        }
    }

    // MARK: - Top Navigation Bar

    private var topNavigationBar: some View {
        HStack(spacing: 8) {
            // Left cluster: Settings, Map, Recordings
            HStack(spacing: 8) {
                // Settings
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }

                // Map
                Button {
                    currentRoute = .map
                } label: {
                    Image(systemName: "map.fill")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(currentRoute == .map ? .accentColor : .primary)
                        .frame(width: 44, height: 44)
                }

                // Recordings/Home
                Button {
                    currentRoute = .recordings
                } label: {
                    Image(systemName: "waveform")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(currentRoute == .recordings ? .accentColor : .primary)
                        .frame(width: 44, height: 44)
                }
            }

            Spacer()

            // Right cluster: Search, Tip Jar
            HStack(spacing: 8) {
                // Search
                Button {
                    showSearch = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }

                // Tip Jar
                Button {
                    showTipJar = true
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 25, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 44, height: 44)
                }
            }
        }
    }

    // MARK: - Record Button Handler

    private func handleRecordTap() {
        if appState.recorder.isRecording {
            if let rawData = appState.recorder.stopRecording() {
                appState.addRecording(from: rawData)
                currentRoute = .recordings
            }
        } else {
            appState.recorder.startRecording()
        }
    }
}

// MARK: - Voice Memos Style Record Button

struct VoiceMemosRecordButton: View {
    @Environment(AppState.self) var appState
    let action: () -> Void

    @State private var isPulsing = false

    private var isRecording: Bool {
        appState.recorder.isRecording
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Outer ring
                Circle()
                    .stroke(isRecording ? Color.red : Color.red.opacity(0.3), lineWidth: 4)
                    .frame(width: 80, height: 80)
                    .scaleEffect(isRecording && isPulsing ? 1.08 : 1.0)
                    .animation(
                        isRecording ? Animation.easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default,
                        value: isPulsing
                    )

                // Inner fill
                Circle()
                    .fill(isRecording ? Color.red : Color.red)
                    .frame(width: 68, height: 68)

                // Mic icon
                Image(systemName: isRecording ? "mic.fill" : "mic.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundColor(.white)
            }
        }
        .buttonStyle(.plain)
        .onChange(of: isRecording) { _, newValue in
            isPulsing = newValue
        }
        .onAppear {
            isPulsing = isRecording
        }
    }
}

// MARK: - Recording Status View
struct RecordingStatusView: View {
    let duration: TimeInterval
    let liveSamples: [Float]

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Circle()
                    .fill(Color.red)
                    .frame(width: 10, height: 10)

                Text("Recording...")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)

                Text(formatDuration(duration))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(.red)
            }

            if !liveSamples.isEmpty {
                LiveWaveformView(samples: liveSamples)
                    .frame(height: 50)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.red.opacity(0.15))
        .cornerRadius(16)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
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
                .foregroundColor(.primary)
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

    @State private var searchScope: SearchScope = .recordings
    @State private var searchQuery = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?
    @State private var selectedAlbum: Album?

    private var recordingResults: [RecordingItem] {
        appState.searchRecordings(query: searchQuery, filterTagIDs: selectedTagIDs)
    }

    private var albumResults: [Album] {
        appState.searchAlbums(query: searchQuery)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    // Scope picker
                    Picker("Search Scope", selection: $searchScope) {
                        ForEach(SearchScope.allCases, id: \.self) { scope in
                            Text(scope.displayName).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)

                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField(searchScope == .recordings ? "Search recordings..." : "Search albums...", text: $searchQuery)
                            .foregroundColor(.primary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)

                    // Tag filter chips (only for Recordings scope)
                    if searchScope == .recordings && !appState.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    TagFilterChip(
                                        tag: tag,
                                        isSelected: selectedTagIDs.contains(tag.id)
                                    ) {
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

                    // Results
                    if searchScope == .recordings {
                        recordingsResultsView
                    } else {
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
            .onChange(of: searchScope) { _, _ in
                // Clear tag filters when switching to albums
                if searchScope == .albums {
                    selectedTagIDs.removeAll()
                }
            }
        }
    }

    // MARK: - Recordings Results View

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
                        .foregroundColor(.primary)
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
                        .foregroundColor(.primary)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(recordingResults) { recording in
                    SearchResultRow(recording: recording)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedRecording = recording
                        }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Albums Results View

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
                        .foregroundColor(.primary)
                    Text("Find albums by name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No albums found")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(albumResults) { album in
                    AlbumSearchRow(album: album)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedAlbum = album
                        }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
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
                    .foregroundColor(.primary)
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

        // Filter by tags if any selected
        if selectedTagIDs.isEmpty {
            return recordings
        }

        return recordings.filter { recording in
            !selectedTagIDs.isDisjoint(with: Set(recording.tagIDs))
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 16) {
                    // Tag filter chips
                    if !appState.tags.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(appState.tags) { tag in
                                    TagFilterChip(
                                        tag: tag,
                                        isSelected: selectedTagIDs.contains(tag.id)
                                    ) {
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

                    // Recordings list
                    if albumRecordings.isEmpty {
                        Spacer()
                        VStack(spacing: 12) {
                            Image(systemName: "waveform.circle")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            if selectedTagIDs.isEmpty {
                                Text("No recordings in this album")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            } else {
                                Text("No recordings match selected tags")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                            }
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(albumRecordings) { recording in
                                SearchResultRow(recording: recording)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedRecording = recording
                                    }
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
    let recording: RecordingItem

    private var recordingTags: [Tag] {
        appState.tags(for: recording.tagIDs)
    }

    private var album: Album? {
        appState.album(for: recording.albumID)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(recording.iconColor)
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let album = album {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
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

    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var showShareSheet = false
    @State private var exportedZIPURL: URL?
    @State private var showAlbumPicker = false
    @State private var showTagManager = false
    @State private var showTrashView = false
    @State private var showEmptyTrashAlert = false
    @State private var showFileImporter = false

    // Quick Access help sheets
    @State private var showLockScreenHelp = false
    @State private var showActionButtonHelp = false
    @State private var showSiriShortcutsHelp = false

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            List {
                // MARK: Quick Access
                Section {
                    Button {
                        showLockScreenHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "lock.rectangle.on.rectangle")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Lock Screen Widget")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showActionButtonHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "button.horizontal.top.press")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Action Button")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button {
                        showSiriShortcutsHelp = true
                    } label: {
                        HStack {
                            Image(systemName: "mic.badge.plus")
                                .foregroundColor(.blue)
                                .frame(width: 24)
                            Text("Siri & Shortcuts")
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Quick Access")
                } footer: {
                    Text("Set up fast ways to start recording from anywhere.")
                }

                // MARK: Recording Quality
                Section {
                    Picker("Quality", selection: $appState.appSettings.recordingQuality) {
                        ForEach(RecordingQualityPreset.allCases) { preset in
                            VStack(alignment: .leading) {
                                Text(preset.displayName)
                            }
                            .tag(preset)
                        }
                    }
                } header: {
                    Text("Recording Quality")
                } footer: {
                    Text(appState.appSettings.recordingQuality.description)
                }

                // MARK: Input Selection
                Section {
                    HStack {
                        Text("Current Input")
                        Spacer()
                        Text(AudioSessionManager.shared.currentInput?.portName ?? "Default")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Audio Input")
                }

                // MARK: Playback
                Section {
                    Picker("Skip Interval", selection: $appState.appSettings.skipInterval) {
                        ForEach(SkipInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }

                    HStack {
                        Text("Playback Speed")
                        Spacer()
                        Text(String(format: "%.1fx", appState.appSettings.playbackSpeed))
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Playback")
                }

                // MARK: Transcription
                Section {
                    Toggle("Auto-Transcribe", isOn: $appState.appSettings.autoTranscribe)

                    Picker("Language", selection: $appState.appSettings.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                } header: {
                    Text("Transcription")
                } footer: {
                    Text("Auto-transcribe new recordings when saved.")
                }

                // MARK: Appearance
                Section {
                    Picker("Appearance", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                }

                // MARK: Tags
                Section {
                    Button {
                        showTagManager = true
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(.blue)
                            Text("Manage Tags")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(appState.tags.count)")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Tags")
                }

                // MARK: Export & Import
                Section {
                    Button {
                        exportAllRecordings()
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.blue)
                            Text("Export All Recordings")
                                .foregroundColor(.primary)
                            Spacer()
                            if isExporting && exportProgress == "all" {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(isExporting || appState.activeRecordings.isEmpty)

                    Button {
                        showAlbumPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundColor(.blue)
                            Text("Export Album...")
                                .foregroundColor(.primary)
                            Spacer()
                            if isExporting && exportProgress == "album" {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle())
                            }
                        }
                    }
                    .disabled(isExporting || appState.albums.isEmpty)

                    Button {
                        showFileImporter = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(.blue)
                            Text("Import Recordings")
                                .foregroundColor(.primary)
                        }
                    }
                } header: {
                    Text("Export & Import")
                } footer: {
                    Text("Export as WAV files in ZIP. Import m4a, wav, mp3, or aiff files.")
                }

                // MARK: Trash
                Section {
                    Button {
                        showTrashView = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("View Trash")
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(appState.trashedCount) items")
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    Button(role: .destructive) {
                        showEmptyTrashAlert = true
                    } label: {
                        HStack {
                            Image(systemName: "trash.slash")
                            Text("Empty Trash Now")
                        }
                    }
                    .disabled(appState.trashedCount == 0)
                } header: {
                    Text("Trash")
                } footer: {
                    Text("Items in trash are automatically deleted after 30 days.")
                }

                // MARK: About
                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.secondary)
                        Text("VoiceMemoPro")
                        Spacer()
                        Text("1.0")
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("About")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedZIPURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showAlbumPicker) {
                ExportAlbumPickerSheet { album in
                    exportAlbum(album)
                }
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
                handleFileImport(result)
            }
            .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) {
                    appState.emptyTrash()
                }
            } message: {
                Text("This will permanently delete \(appState.trashedCount) items. This cannot be undone.")
            }
            // Quick Access help sheets
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
            } catch {
                isExporting = false
                exportProgress = ""
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                // Get duration
                let duration = getAudioDuration(url: url)
                appState.importRecording(from: url, duration: duration)
            }
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }

    private func getAudioDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
            return duration
        } catch {
            return 0
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

            Button {
                appState.restoreFromTrash(recording)
            } label: {
                Text("Restore")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button {
                appState.permanentlyDelete(recording)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
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
                            Text("\(appState.recordingCount(in: album)) recordings")
                                .font(.caption)
                                .foregroundColor(.secondary)
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

// MARK: - Tip Jar Sheet
struct TipJarSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.pink)
                    Text("Tip Jar")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text("Support the developer")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Tip Jar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(AppState())
}
