//
//  ContentView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

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
                HStack {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.primary)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if appState.recorder.isRecording {
                    RecordingStatusView(
                        duration: appState.recorder.currentDuration,
                        liveSamples: appState.recorder.liveMeterSamples
                    )
                    .padding(.top, 8)
                }

                Group {
                    switch currentRoute {
                    case .recordings:
                        RecordingsListView()
                    case .map:
                        MapPlaceholderView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Spacer(minLength: 100)
            }

            VStack {
                Spacer()
                BottomDockView(
                    currentRoute: $currentRoute,
                    showTipJar: $showTipJar
                )
            }
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
        .background(Color.red.opacity(0.2))
        .cornerRadius(20)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        let tenths = Int((duration.truncatingRemainder(dividingBy: 1)) * 10)
        return String(format: "%d:%02d.%d", minutes, seconds, tenths)
    }
}

// MARK: - Bottom Dock
struct BottomDockView: View {
    @Environment(AppState.self) var appState
    @Binding var currentRoute: AppRoute
    @Binding var showTipJar: Bool

    var body: some View {
        HStack(spacing: 0) {
            DockButton(
                icon: "map.fill",
                label: "Map",
                isSelected: currentRoute == .map
            ) {
                currentRoute = .map
            }

            DockButton(
                icon: "waveform",
                label: "Recordings",
                isSelected: currentRoute == .recordings
            ) {
                currentRoute = .recordings
            }

            Button {
                handleRecordTap()
            } label: {
                ZStack {
                    Circle()
                        .fill(appState.recorder.isRecording ? Color.gray : Color.red)
                        .frame(width: 64, height: 64)

                    if appState.recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
            }
            .padding(.horizontal, 16)

            DockButton(
                icon: "heart.fill",
                label: "Tip Jar",
                isSelected: false
            ) {
                showTipJar = true
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemGray5).opacity(0.95))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

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

// MARK: - Dock Button
struct DockButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                Text(label)
                    .font(.system(size: 10, weight: .medium))
            }
            .foregroundColor(isSelected ? .primary : .secondary)
            .frame(maxWidth: .infinity)
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
                .background(Color(.systemGray4))
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

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            List {
                Section {
                    Picker("Appearance", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Choose how the app appears. System follows your device settings.")
                }

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
                    .disabled(isExporting || appState.recordings.isEmpty)

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
                } header: {
                    Text("Export")
                } footer: {
                    Text("Export recordings as WAV files in a ZIP archive with metadata.")
                }

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
        }
    }

    private func exportAllRecordings() {
        isExporting = true
        exportProgress = "all"
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    appState.recordings,
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
