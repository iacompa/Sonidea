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

// MARK: - Main Content View
struct ContentView: View {
    @Environment(AppState.self) var appState
    @State private var currentRoute: AppRoute = .recordings
    @State private var showSearch = false
    @State private var showSettings = false
    @State private var showTipJar = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }

                    Spacer()

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)

                if appState.recorder.isRecording {
                    RecordingStatusView(duration: appState.recorder.currentDuration)
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

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)

            Text("Recording...")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white)

            Text(formatDuration(duration))
                .font(.subheadline)
                .monospacedDigit()
                .foregroundColor(.red)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
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
                .fill(Color(.systemGray6).opacity(0.95))
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
            .foregroundColor(isSelected ? .white : .gray)
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
                .foregroundColor(.gray)
            Text("Map")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text("Recording locations will appear here")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Search Sheet View
struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var searchQuery = ""
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?

    private var searchResults: [RecordingItem] {
        appState.searchRecordings(query: searchQuery, filterTagIDs: selectedTagIDs)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    // Search field
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.gray)
                        TextField("Search recordings...", text: $searchQuery)
                            .foregroundColor(.white)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)

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

                    // Results
                    if searchResults.isEmpty {
                        Spacer()
                        if searchQuery.isEmpty && selectedTagIDs.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("Search your recordings")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("Search by title, notes, location, tags, or album")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                    .multilineTextAlignment(.center)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundColor(.gray)
                                Text("No results found")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                        }
                        Spacer()
                    } else {
                        List {
                            ForEach(searchResults) { recording in
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
        }
        .preferredColorScheme(.dark)
    }
}

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
                .foregroundColor(.white)
                .frame(width: 36, height: 36)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(6)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.gray)

                    if let album = album {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(album.name)
                            .font(.caption)
                            .foregroundColor(.gray)
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
                .foregroundColor(.gray)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Settings Sheet
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.gray)
                    Text("Settings")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Settings coming soon")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tip Jar Sheet
struct TipJarSheetView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.pink)
                    Text("Tip Jar")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                    Text("Support the developer")
                        .font(.subheadline)
                        .foregroundColor(.gray)
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
        .preferredColorScheme(.dark)
    }
}

// MARK: - Preview
#Preview {
    ContentView()
        .environment(AppState())
}
