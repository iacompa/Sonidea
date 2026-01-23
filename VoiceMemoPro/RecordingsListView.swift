//
//  RecordingsListView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct RecordingsListView: View {
    @Environment(AppState.self) var appState
    @State private var selectedRecording: RecordingItem?
    @State private var isSelectionMode = false
    @State private var selectedRecordingIDs: Set<UUID> = []
    @State private var showBatchAlbumPicker = false
    @State private var showBatchTagPicker = false
    @State private var showBatchExport = false
    @State private var showShareSheet = false
    @State private var exportedURL: URL?

    var body: some View {
        Group {
            if appState.activeRecordings.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    if isSelectionMode {
                        selectionHeader
                    }
                    recordingsList
                    if isSelectionMode && !selectedRecordingIDs.isEmpty {
                        batchActionBar
                    }
                }
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
        .sheet(isPresented: $showBatchAlbumPicker) {
            BatchAlbumPickerSheet(selectedRecordingIDs: selectedRecordingIDs) {
                clearSelection()
            }
        }
        .sheet(isPresented: $showBatchTagPicker) {
            BatchTagPickerSheet(selectedRecordingIDs: selectedRecordingIDs) {
                clearSelection()
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No Recordings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text("Tap the red button to start recording")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private var selectionHeader: some View {
        HStack {
            Button("Cancel") {
                clearSelection()
            }

            Spacer()

            Text("\(selectedRecordingIDs.count) selected")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Button(selectedRecordingIDs.count == appState.activeRecordings.count ? "Deselect All" : "Select All") {
                if selectedRecordingIDs.count == appState.activeRecordings.count {
                    selectedRecordingIDs.removeAll()
                } else {
                    selectedRecordingIDs = Set(appState.activeRecordings.map { $0.id })
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }

    private var recordingsList: some View {
        List {
            ForEach(appState.activeRecordings) { recording in
                RecordingRow(
                    recording: recording,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedRecordingIDs.contains(recording.id)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSelectionMode {
                        toggleSelection(recording)
                    } else {
                        selectedRecording = recording
                    }
                }
                .onLongPressGesture {
                    if !isSelectionMode {
                        isSelectionMode = true
                        selectedRecordingIDs.insert(recording.id)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button(role: .destructive) {
                        appState.moveToTrash(recording)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    Button {
                        _ = appState.toggleFavorite(for: recording)
                    } label: {
                        Label(
                            appState.isFavorite(recording) ? "Unfavorite" : "Favorite",
                            systemImage: appState.isFavorite(recording) ? "heart.slash" : "heart.fill"
                        )
                    }
                    .tint(.pink)

                    Button {
                        shareRecording(recording)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private var batchActionBar: some View {
        HStack(spacing: 20) {
            Button {
                showBatchAlbumPicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.stack")
                    Text("Album")
                        .font(.caption)
                }
            }

            Button {
                showBatchTagPicker = true
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "tag")
                    Text("Tags")
                        .font(.caption)
                }
            }

            Button {
                exportSelectedRecordings()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                        .font(.caption)
                }
            }

            Button(role: .destructive) {
                appState.moveRecordingsToTrash(recordingIDs: selectedRecordingIDs)
                clearSelection()
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "trash")
                    Text("Delete")
                        .font(.caption)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
    }

    private func toggleSelection(_ recording: RecordingItem) {
        if selectedRecordingIDs.contains(recording.id) {
            selectedRecordingIDs.remove(recording.id)
        } else {
            selectedRecordingIDs.insert(recording.id)
        }
    }

    private func clearSelection() {
        isSelectionMode = false
        selectedRecordingIDs.removeAll()
    }

    private func shareRecording(_ recording: RecordingItem) {
        Task {
            do {
                let wavURL = try await AudioExporter.shared.exportToWAV(recording: recording)
                exportedURL = wavURL
                showShareSheet = true
            } catch {
                print("Export failed: \(error)")
            }
        }
    }

    private func exportSelectedRecordings() {
        let selectedRecordings = appState.activeRecordings.filter { selectedRecordingIDs.contains($0.id) }
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    selectedRecordings,
                    scope: .all,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedURL = zipURL
                showShareSheet = true
                clearSelection()
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

struct RecordingRow: View {
    @Environment(AppState.self) var appState
    let recording: RecordingItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false

    private var recordingTags: [Tag] {
        appState.tags(for: recording.tagIDs)
    }

    private var album: Album? {
        appState.album(for: recording.albumID)
    }

    var body: some View {
        HStack(spacing: 12) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? .blue : .secondary)
            }

            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundColor(.primary)
                .frame(width: 44, height: 44)
                .background(Color(.systemGray4))
                .cornerRadius(8)

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

                // Tag chips (show up to 2)
                if !recordingTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recordingTags.prefix(2)) { tag in
                            TagChipSmall(tag: tag)
                        }
                        if recordingTags.count > 2 {
                            Text("+\(recordingTags.count - 2)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Spacer()

            if !isSelectionMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct TagChipSmall: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tag.color.opacity(0.8))
            .cornerRadius(4)
    }
}

// MARK: - Batch Album Picker

struct BatchAlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let selectedRecordingIDs: Set<UUID>
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.albums) { album in
                    Button {
                        appState.setAlbumForRecordings(album, recordingIDs: selectedRecordingIDs)
                        dismiss()
                        onComplete()
                    } label: {
                        HStack {
                            Text(album.name)
                                .foregroundColor(.primary)
                            if album.isSystem {
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
                }
            }
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Batch Tag Picker

struct BatchTagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let selectedRecordingIDs: Set<UUID>
    let onComplete: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.tags) { tag in
                        Button {
                            appState.addTagToRecordings(tag, recordingIDs: selectedRecordingIDs)
                            dismiss()
                            onComplete()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 20, height: 20)
                                Text(tag.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                } header: {
                    Text("Add Tag")
                }

                Section {
                    ForEach(appState.tags) { tag in
                        Button {
                            appState.removeTagFromRecordings(tag, recordingIDs: selectedRecordingIDs)
                            dismiss()
                            onComplete()
                        } label: {
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 20, height: 20)
                                Text(tag.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                Image(systemName: "minus")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                } header: {
                    Text("Remove Tag")
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
