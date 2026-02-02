//
//  UtilitySheets.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct StorageEstimateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                // Explanation section
                Section {
                    Text("Estimates are approximate and vary based on audio content, silence, and complexity.")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .listRowBackground(palette.cardBackground)
                }

                // Quality estimates
                Section {
                    ForEach(RecordingQualityPreset.allCases) { preset in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(preset.displayName)
                                    .font(.body)
                                    .foregroundStyle(palette.textPrimary)
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }

                            Spacer()

                            Text(storageEstimate(for: preset))
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(palette.textSecondary)
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Estimated Storage per Minute")
                        .foregroundStyle(palette.textSecondary)
                }

                // Technical notes
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("AAC formats use variable bitrate encoding")
                        } icon: {
                            Image(systemName: "waveform")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                        Label {
                            Text("Lossless (ALAC) size depends on audio complexity")
                        } icon: {
                            Image(systemName: "music.note")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                        Label {
                            Text("WAV is uncompressed with fixed, predictable size")
                        } icon: {
                            Image(systemName: "doc.badge.gearshape")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)
                }

                // Background recording info
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Label {
                            Text("Recording continues when you lock the screen or switch to another app. A red indicator appears in the status bar while recording.")
                        } icon: {
                            Image(systemName: "record.circle")
                                .foregroundStyle(.red)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                        Label {
                            Text("To test: Start recording, then lock the screen or switch apps. Unlock to see the recording continued.")
                        } icon: {
                            Image(systemName: "info.circle")
                                .foregroundStyle(palette.accent)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textTertiary)
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Background Recording")
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Recording Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    /// Calculate storage estimate string for a given quality preset
    private func storageEstimate(for preset: RecordingQualityPreset) -> String {
        switch preset {
        case .standard:
            // AAC ~128kbps = ~0.96 MB/min, but VBR so varies
            return "~1 MB/min"

        case .high:
            // AAC ~256kbps = ~1.9 MB/min, but VBR so varies
            return "~2 MB/min"

        case .lossless:
            // ALAC varies greatly based on content
            // Typical speech: 2-4 MB/min, complex audio: 4-6 MB/min
            return "~3–5 MB/min"

        case .wav:
            // PCM is deterministic: sample_rate × bit_depth × channels / 8 / 1024 / 1024 × 60
            // 48000 Hz × 16-bit × 1 channel = 5.49 MB/min (mono)
            // Formula: 48000 * 16 * 1 / 8 / 1024 / 1024 * 60 = 5.49
            let sampleRate: Double = 48000
            let bitDepth: Double = 16
            let channels: Double = 1 // Mono recording
            let bytesPerSecond = sampleRate * (bitDepth / 8) * channels
            let mbPerMinute = bytesPerSecond * 60 / 1024 / 1024

            return String(format: "~%.1f MB/min", mbPerMinute)
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

    @State private var showDeleteConfirmation = false

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

            Button { appState.restoreFromTrash(recording) } label: {
                Text("Restore")
                    .font(.subheadline)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)

            Button { showDeleteConfirmation = true } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
        .alert("Permanently Delete?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) { appState.permanentlyDelete(recording) }
        } message: {
            Text("\"\(recording.title)\" will be permanently deleted. This cannot be undone.")
        }
    }
}

// MARK: - Import Destination Sheet
struct ImportDestinationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let urls: [URL]
    let onImport: (UUID) -> Void

    @State private var selectedAlbumID: UUID = Album.importsID
    @State private var showNewAlbumSheet = false
    @State private var newAlbumName = ""

    /// System albums (Imports and Drafts)
    private var systemAlbums: [Album] {
        // Include Imports even if it doesn't exist yet (we'll create it on import)
        var result: [Album] = []

        // Always show Imports option (will be created on import if needed)
        if let imports = appState.albums.first(where: { $0.id == Album.importsID }) {
            result.append(imports)
        } else {
            result.append(Album.imports)
        }

        // Show Drafts
        if let drafts = appState.albums.first(where: { $0.id == Album.draftsID }) {
            result.append(drafts)
        }

        return result
    }

    /// User-created albums (non-system)
    private var userAlbums: [Album] {
        appState.albums.filter { !$0.isSystem }
    }

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Files Info Section
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(palette.accent.opacity(0.15))
                                .frame(width: 44, height: 44)
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(palette.accent)
                                .font(.title3)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(urls.count) file\(urls.count == 1 ? "" : "s") to import")
                                .font(.headline)
                                .foregroundColor(palette.textPrimary)
                            Text(urls.map { $0.lastPathComponent }.prefix(3).joined(separator: ", ") + (urls.count > 3 ? "..." : ""))
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 4)
                    .listRowBackground(palette.cardBackground)
                }

                // MARK: - System Albums Section
                Section {
                    ForEach(systemAlbums) { album in
                        albumRow(album, isSystem: true)
                    }
                } header: {
                    Text("Default")
                } footer: {
                    if selectedAlbumID == Album.importsID {
                        Text("External files are saved to Imports by default.")
                    }
                }

                // MARK: - User Albums Section
                if !userAlbums.isEmpty {
                    Section {
                        ForEach(userAlbums) { album in
                            albumRow(album, isSystem: false)
                        }
                    } header: {
                        Text("Albums")
                    }
                }

                // MARK: - Create New Album
                Section {
                    Button {
                        showNewAlbumSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.green)
                            Text("New Album")
                                .foregroundColor(palette.textPrimary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Import") {
                        // Ensure Imports album exists if that's the destination
                        if selectedAlbumID == Album.importsID {
                            appState.ensureImportsAlbum()
                        }
                        dismiss()
                        onImport(selectedAlbumID)
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("New Album", isPresented: $showNewAlbumSheet) {
                TextField("Album name", text: $newAlbumName)
                Button("Cancel", role: .cancel) {
                    newAlbumName = ""
                }
                Button("Create") {
                    if !newAlbumName.trimmingCharacters(in: .whitespaces).isEmpty {
                        let album = appState.createAlbum(name: newAlbumName.trimmingCharacters(in: .whitespaces))
                        selectedAlbumID = album.id
                    }
                    newAlbumName = ""
                }
            } message: {
                Text("Enter a name for the new album.")
            }
        }
    }

    @ViewBuilder
    private func albumRow(_ album: Album, isSystem: Bool) -> some View {
        Button {
            selectedAlbumID = album.id
        } label: {
            HStack(spacing: 12) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(albumIconColor(album).opacity(0.15))
                        .frame(width: 32, height: 32)
                    Image(systemName: albumIconName(album))
                        .foregroundColor(albumIconColor(album))
                        .font(.system(size: 14, weight: .medium))
                }

                // Name
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        AlbumTitleView(album: album, showBadge: true)
                        if isSystem {
                            Image(systemName: "lock.fill")
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                    if album.isImportsAlbum {
                        Text("Recommended for external files")
                            .font(.caption2)
                            .foregroundColor(palette.textTertiary)
                    }
                }

                Spacer()

                // Checkmark
                if selectedAlbumID == album.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(palette.accent)
                        .font(.title3)
                }
            }
        }
        .listRowBackground(palette.cardBackground)
    }

    private func albumIconName(_ album: Album) -> String {
        if album.isShared {
            return "person.2.fill"
        } else if album.isImportsAlbum {
            return "square.and.arrow.down"
        } else if album.isDraftsAlbum {
            return "doc.text"
        } else if album.isWatchRecordingsAlbum {
            return "applewatch"
        } else {
            return "folder"
        }
    }

    private func albumIconColor(_ album: Album) -> Color {
        if album.isShared {
            return .sharedAlbumGold
        } else if album.isImportsAlbum {
            return .blue
        } else if album.isDraftsAlbum {
            return .orange
        } else if album.isWatchRecordingsAlbum {
            return .green
        } else {
            return palette.accent
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
                        AlbumRowView(album: album)
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

