//
//  RecordingsListView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct RecordingsListView: View {
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.themePalette) private var palette

    @State private var selectedRecording: RecordingItem?
    @State private var isSelectionMode = false
    @State private var selectedRecordingIDs: Set<UUID> = []
    @State private var showBatchAlbumPicker = false
    @State private var showBatchTagPicker = false
    @State private var showShareSheet = false
    @State private var exportedURL: URL?
    @State private var showDeleteConfirmation = false

    // Single recording actions
    @State private var recordingToMove: RecordingItem?
    @State private var showMoveToAlbumSheet = false
    @State private var recordingToTag: RecordingItem?
    @State private var showSingleTagSheet = false

    // Pro feature gating
    @State private var proUpgradeContext: ProFeatureContext? = nil
    @State private var showTipJar = false

    // Animation configuration
    private var menuAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.3, dampingFraction: 0.8)
    }

    private var hasSelection: Bool {
        !selectedRecordingIDs.isEmpty
    }

    var body: some View {
        ZStack {
            // Full background - ensures no dead zones
            palette.background
                .ignoresSafeArea()

            // Content
            Group {
                if appState.activeRecordings.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        listHeader

                        if isSelectionMode {
                            selectionHeader
                            selectionActionBar
                        }

                        recordingsList
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
        .sheet(isPresented: $showMoveToAlbumSheet) {
            if let recording = recordingToMove {
                MoveToAlbumSheet(recording: recording)
            }
        }
        .sheet(isPresented: $showSingleTagSheet) {
            if let recording = recordingToTag {
                SingleRecordingTagSheet(recording: recording)
            }
        }
        .alert("Delete Recordings", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                appState.moveRecordingsToTrash(recordingIDs: selectedRecordingIDs)
                withAnimation(menuAnimation) {
                    clearSelection()
                }
            }
        } message: {
            Text("Are you sure you want to delete \(selectedRecordingIDs.count) recording\(selectedRecordingIDs.count == 1 ? "" : "s")? They will be moved to Recently Deleted.")
        }
        .sheet(item: $proUpgradeContext) { context in
            ProUpgradeSheet(
                context: context,
                onViewPlans: {
                    proUpgradeContext = nil
                    showTipJar = true
                },
                onDismiss: {
                    proUpgradeContext = nil
                }
            )
            .environment(\.themePalette, palette)
        }
        .sheet(isPresented: $showTipJar) {
            TipJarView()
                .environment(appState)
                .environment(\.themePalette, palette)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(palette.textSecondary)
            Text("No Recordings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(palette.textPrimary)
            Text("Tap the red button to start recording")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - List Header

    private var listHeader: some View {
        HStack {
            Text("Recordings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(palette.textPrimary)

            Spacer()

            if !isSelectionMode {
                Button {
                    withAnimation(menuAnimation) {
                        isSelectionMode = true
                    }
                } label: {
                    Text("Select")
                        .font(.subheadline)
                        .foregroundColor(palette.accent)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
        .background(palette.background)
    }

    // MARK: - Selection Header

    private var selectionHeader: some View {
        HStack {
            Button("Cancel") {
                withAnimation(menuAnimation) {
                    clearSelection()
                }
            }
            .foregroundColor(palette.accent)

            Spacer()

            Text("\(selectedRecordingIDs.count) selected")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)

            Spacer()

            Button(selectedRecordingIDs.count == appState.activeRecordings.count ? "Deselect All" : "Select All") {
                withAnimation(menuAnimation) {
                    if selectedRecordingIDs.count == appState.activeRecordings.count {
                        selectedRecordingIDs.removeAll()
                    } else {
                        selectedRecordingIDs = Set(appState.activeRecordings.map { $0.id })
                    }
                }
            }
            .foregroundColor(palette.accent)
        }
        .padding(.horizontal, 16)
        .frame(height: 44)
        .background(palette.surface)
    }

    // MARK: - Selection Action Bar (Horizontal, Apple-like)

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            // Album
            SelectionActionButton(
                icon: "folder",
                label: "Album",
                isEnabled: hasSelection,
                isDestructive: false
            ) {
                showBatchAlbumPicker = true
            }

            Divider()
                .frame(height: 40)
                .background(palette.separator)

            // Tags
            SelectionActionButton(
                icon: "tag",
                label: "Tags",
                isEnabled: hasSelection,
                isDestructive: false
            ) {
                guard appState.supportManager.canUseProFeatures else {
                    proUpgradeContext = .tags
                    return
                }
                showBatchTagPicker = true
            }

            Divider()
                .frame(height: 40)
                .background(palette.separator)

            // Export
            SelectionActionButton(
                icon: "square.and.arrow.up",
                label: "Export",
                isEnabled: hasSelection,
                isDestructive: false
            ) {
                exportSelectedRecordings()
            }

            Divider()
                .frame(height: 40)
                .background(palette.separator)

            // Delete
            SelectionActionButton(
                icon: "trash",
                label: "Delete",
                isEnabled: hasSelection,
                isDestructive: true
            ) {
                showDeleteConfirmation = true
            }
        }
        .frame(height: 64)
        .background(palette.inputBackground)
        .cornerRadius(12)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Recordings List

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
                        withAnimation(menuAnimation) {
                            isSelectionMode = true
                            selectedRecordingIDs.insert(recording.id)
                        }
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button(role: .destructive) {
                        appState.moveToTrash(recording)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        shareRecording(recording)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(palette.accent)

                    Button {
                        guard appState.supportManager.canUseProFeatures else {
                            proUpgradeContext = .tags
                            return
                        }
                        recordingToTag = recording
                        showSingleTagSheet = true
                    } label: {
                        Label("Tags", systemImage: "tag")
                    }
                    .tint(.orange)

                    Button {
                        recordingToMove = recording
                        showMoveToAlbumSheet = true
                    } label: {
                        Label("Album", systemImage: "square.stack")
                    }
                    .tint(.purple)
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
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowSeparatorTint(palette.separator)
            }

            // Bottom spacer for floating record button
            Color.clear
                .frame(height: 100)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Actions

    private func toggleSelection(_ recording: RecordingItem) {
        withAnimation(.easeInOut(duration: 0.15)) {
            if selectedRecordingIDs.contains(recording.id) {
                selectedRecordingIDs.remove(recording.id)
            } else {
                selectedRecordingIDs.insert(recording.id)
            }
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
                await MainActor.run {
                    withAnimation(menuAnimation) {
                        clearSelection()
                    }
                }
            } catch {
                print("Export failed: \(error)")
            }
        }
    }
}

// MARK: - Selection Action Button

struct SelectionActionButton: View {
    @Environment(\.themePalette) private var palette
    let icon: String
    let label: String
    let isEnabled: Bool
    let isDestructive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundColor(buttonColor)

                Text(label)
                    .font(.caption)
                    .foregroundColor(buttonColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 64)
            .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .buttonStyle(SelectionActionButtonStyle())
    }

    private var buttonColor: Color {
        if !isEnabled {
            return palette.textSecondary.opacity(0.4)
        }
        return isDestructive ? .red : palette.textPrimary
    }
}

// MARK: - Selection Action Button Style

struct SelectionActionButtonStyle: ButtonStyle {
    @Environment(\.themePalette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? palette.textPrimary.opacity(0.08)
                    : Color.clear
            )
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.themePalette) var palette
    let recording: RecordingItem
    var isSelectionMode: Bool = false
    var isSelected: Bool = false

    private var recordingTags: [Tag] {
        appState.tags(for: recording.tagIDs)
    }

    private var album: Album? {
        appState.album(for: recording.albumID)
    }

    private var project: Project? {
        appState.project(for: recording.projectId)
    }

    private var isBestTake: Bool {
        guard let project = project else { return false }
        return project.bestTakeRecordingId == recording.id
    }

    var body: some View {
        HStack(spacing: 14) {
            if isSelectionMode {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isSelected ? palette.accent : palette.textSecondary)
                    .font(.system(size: 22))
            }

            // Icon tile - isolated from row highlight states
            RecordingIconTile(recording: recording, colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(recording.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    // Version badge for project recordings
                    if recording.belongsToProject {
                        Text(recording.versionLabel)
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(palette.accent)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(palette.accent.opacity(0.15))
                            .cornerRadius(4)

                        if isBestTake {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }

                    // Overdub badge
                    if recording.isPartOfOverdub {
                        overdubBadge
                    }
                }

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)

                    // Show project name if in project
                    if let project = project {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        HStack(spacing: 3) {
                            Image(systemName: "folder.fill")
                                .font(.caption2)
                            Text(project.title)
                                .lineLimit(1)
                        }
                        .font(.subheadline)
                        .foregroundColor(palette.accent.opacity(0.9))
                    } else if let album = album {
                        Text("•")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                        if album.isShared {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 10))
                                Text(album.name)
                            }
                            .font(.subheadline)
                            .foregroundColor(.sharedAlbumGold)
                            .lineLimit(1)
                        } else {
                            Text(album.name)
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)
                        }
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
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                }
            }

            Spacer()

            if !isSelectionMode {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding(.vertical, 12)
    }

    /// Badge for overdub recordings
    @ViewBuilder
    private var overdubBadge: some View {
        if recording.isOverdubBase {
            // Base track badge with layer count
            let layerCount = appState.overdubLayerCount(for: recording)
            HStack(spacing: 3) {
                Image(systemName: "waveform.circle.fill")
                    .font(.system(size: 10))
                Text("OVERDUB")
                    .font(.system(size: 9, weight: .bold))
                if layerCount > 0 {
                    Text("•\(layerCount)")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(4)
        } else if recording.isOverdubLayer {
            // Layer badge
            let layerNum = recording.overdubIndex ?? 1
            HStack(spacing: 3) {
                Image(systemName: "waveform.badge.plus")
                    .font(.system(size: 10))
                Text("LAYER \(layerNum)")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundColor(.purple)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.purple.opacity(0.15))
            .cornerRadius(4)
        }
    }
}

// MARK: - Recording Icon Tile (Isolated, Stable Colors)

/// A dedicated view for the recording icon tile that maintains stable colors
/// regardless of row selection, highlight, or edit state.
struct RecordingIconTile: View {
    let recording: RecordingItem
    let colorScheme: ColorScheme

    var body: some View {
        Image(systemName: recording.displayIconSymbol)
            .font(.system(size: 24))
            .foregroundColor(recording.iconSymbolColor(for: colorScheme))
            .frame(width: 44, height: 44)
            .background(recording.iconTileBackground(for: colorScheme))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(recording.iconTileBorder(for: colorScheme), lineWidth: 1)
            )
            // Prevent any inherited opacity/highlight from affecting this view
            .compositingGroup()
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

// MARK: - Move to Album Sheet (Single Recording, Searchable)

struct MoveToAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    @State private var searchQuery = ""

    private var filteredAlbums: [Album] {
        if searchQuery.isEmpty {
            return appState.albums
        }
        return appState.albums.filter {
            $0.name.lowercased().contains(searchQuery.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredAlbums) { album in
                    Button {
                        _ = appState.setAlbum(album, for: recording)
                        dismiss()
                    } label: {
                        HStack {
                            Image(systemName: album.isShared ? "person.2.fill" : "square.stack")
                                .foregroundColor(album.isShared ? .sharedAlbumGold : .purple)
                                .frame(width: 24)
                            AlbumTitleView(album: album)
                            Spacer()
                            if recording.albumID == album.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(album.isShared ? .sharedAlbumGold : palette.accent)
                            }
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .searchable(text: $searchQuery, prompt: "Search albums")
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

// MARK: - Batch Album Picker

struct BatchAlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let selectedRecordingIDs: Set<UUID>
    let onComplete: () -> Void

    @State private var searchQuery = ""

    private var filteredAlbums: [Album] {
        if searchQuery.isEmpty {
            return appState.albums
        }
        return appState.albums.filter {
            $0.name.lowercased().contains(searchQuery.lowercased())
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filteredAlbums) { album in
                    Button {
                        appState.setAlbumForRecordings(album, recordingIDs: selectedRecordingIDs)
                        dismiss()
                        onComplete()
                    } label: {
                        HStack {
                            Image(systemName: album.isShared ? "person.2.fill" : "square.stack")
                                .foregroundColor(album.isShared ? .sharedAlbumGold : .purple)
                                .frame(width: 24)
                            AlbumTitleView(album: album)
                            Spacer()
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .searchable(text: $searchQuery, prompt: "Search albums")
            .navigationTitle("Move to Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

// MARK: - Batch Tag Picker

struct BatchTagPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

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
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                Image(systemName: "plus")
                                    .foregroundColor(palette.accent)
                            }
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Add Tag")
                        .foregroundColor(palette.textSecondary)
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
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                Image(systemName: "minus")
                                    .foregroundColor(.red)
                            }
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Remove Tag")
                        .foregroundColor(palette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
        }
    }
}

// MARK: - Single Recording Tag Sheet

struct SingleRecordingTagSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem

    // Fetch live recording from AppState to reflect tag changes
    private var liveRecording: RecordingItem {
        appState.recordings.first { $0.id == recording.id } ?? recording
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(appState.tags) { tag in
                    let isSelected = liveRecording.tagIDs.contains(tag.id)
                    Button {
                        _ = appState.toggleTag(tag, for: liveRecording)
                    } label: {
                        HStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 20, height: 20)
                            Text(tag.name)
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundColor(palette.accent)
                            }
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .navigationTitle("Tags")
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
