//
//  RecordingsListView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

// MARK: - Anchor Preference Key for Options Button

struct OptionsButtonAnchorKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? = nil
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

struct RecordingsListView: View {
    @Environment(AppState.self) var appState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedRecording: RecordingItem?
    @State private var isSelectionMode = false
    @State private var selectedRecordingIDs: Set<UUID> = []
    @State private var showActionsMenu = false
    @State private var showBatchAlbumPicker = false
    @State private var showBatchTagPicker = false
    @State private var showBatchExport = false
    @State private var showShareSheet = false
    @State private var exportedURL: URL?

    // Single recording actions
    @State private var recordingToMove: RecordingItem?
    @State private var showMoveToAlbumSheet = false

    // Menu dimensions
    private let menuWidth: CGFloat = 250
    private let menuRowHeight: CGFloat = 44
    private var menuHeight: CGFloat { menuRowHeight * 4 + 3 } // 4 rows + 3 dividers

    // Animation configuration
    private var menuAnimation: Animation {
        reduceMotion
            ? .easeInOut(duration: 0.15)
            : .spring(response: 0.3, dampingFraction: 0.8)
    }

    var body: some View {
        Group {
            if appState.activeRecordings.isEmpty {
                emptyState
            } else {
                GeometryReader { outerGeo in
                    ZStack(alignment: .topTrailing) {
                        // Layer 1: Main content (header + list)
                        VStack(spacing: 0) {
                            listHeader

                            if isSelectionMode {
                                selectionHeader
                            }

                            recordingsList
                        }

                        // Layer 2: Floating dropdown overlay
                        if isSelectionMode && showActionsMenu {
                            // Invisible tap catcher to dismiss menu
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(menuAnimation) {
                                        showActionsMenu = false
                                    }
                                }
                                .zIndex(1)
                        }
                    }
                    .overlayPreferenceValue(OptionsButtonAnchorKey.self) { anchor in
                        if isSelectionMode && showActionsMenu, let anchor = anchor {
                            GeometryReader { geo in
                                let rect = geo[anchor]
                                let screenWidth = geo.size.width

                                // Calculate X position: center menu under the Options button
                                let idealX = rect.midX
                                let minX = menuWidth / 2 + 16 // 16pt from left edge
                                let maxX = screenWidth - menuWidth / 2 - 16 // 16pt from right edge
                                let clampedX = min(max(idealX, minX), maxX)

                                // Y position: directly below the button with 8pt gap
                                let menuY = rect.maxY + menuHeight / 2 + 8

                                compactFloatingMenu
                                    .position(x: clampedX, y: menuY)
                                    .transition(.asymmetric(
                                        insertion: .move(edge: .top).combined(with: .opacity),
                                        removal: .move(edge: .top).combined(with: .opacity)
                                    ))
                            }
                            .zIndex(2)
                        }
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
        .onChange(of: isSelectionMode) { _, newValue in
            if newValue {
                withAnimation(menuAnimation) {
                    showActionsMenu = true
                }
            } else {
                showActionsMenu = false
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

    // MARK: - List Header

    private var listHeader: some View {
        HStack {
            Text("Recordings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Spacer()

            if !isSelectionMode {
                Button {
                    withAnimation(menuAnimation) {
                        isSelectionMode = true
                    }
                } label: {
                    Text("Select")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Selection Header

    private var selectionHeader: some View {
        HStack {
            Button("Cancel") {
                withAnimation(menuAnimation) {
                    clearSelection()
                }
            }

            Spacer()

            // Options button with liquid glass style
            SelectOptionsButton(
                selectedCount: selectedRecordingIDs.count,
                isExpanded: $showActionsMenu,
                animation: menuAnimation
            )
            .anchorPreference(key: OptionsButtonAnchorKey.self, value: .bounds) { $0 }

            Spacer()

            // Select All button
            Button(selectedRecordingIDs.count == appState.activeRecordings.count ? "Deselect All" : "Select All") {
                withAnimation(menuAnimation) {
                    if selectedRecordingIDs.count == appState.activeRecordings.count {
                        selectedRecordingIDs.removeAll()
                    } else {
                        selectedRecordingIDs = Set(appState.activeRecordings.map { $0.id })
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Compact Floating Actions Menu

    private var compactFloatingMenu: some View {
        VStack(spacing: 0) {
            CompactMenuRow(
                icon: "folder",
                label: "Move to Album",
                isDestructive: false
            ) {
                showBatchAlbumPicker = true
                withAnimation(menuAnimation) {
                    showActionsMenu = false
                }
            }

            Divider()
                .padding(.leading, 44)

            CompactMenuRow(
                icon: "tag",
                label: "Manage Tags",
                isDestructive: false
            ) {
                showBatchTagPicker = true
                withAnimation(menuAnimation) {
                    showActionsMenu = false
                }
            }

            Divider()
                .padding(.leading, 44)

            CompactMenuRow(
                icon: "square.and.arrow.up",
                label: "Export",
                isDestructive: false
            ) {
                exportSelectedRecordings()
                withAnimation(menuAnimation) {
                    showActionsMenu = false
                }
            }

            Divider()
                .padding(.leading, 44)

            CompactMenuRow(
                icon: "trash",
                label: "Delete",
                isDestructive: true
            ) {
                appState.moveRecordingsToTrash(recordingIDs: selectedRecordingIDs)
                withAnimation(menuAnimation) {
                    clearSelection()
                }
            }
        }
        .frame(width: menuWidth)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.2), radius: 20, x: 0, y: 10)
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
                        if showActionsMenu {
                            withAnimation(menuAnimation) {
                                showActionsMenu = false
                            }
                        }
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
                        recordingToMove = recording
                        showMoveToAlbumSheet = true
                    } label: {
                        Label("Album", systemImage: "square.stack")
                    }
                    .tint(.purple)

                    Button {
                        shareRecording(recording)
                    } label: {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                    .tint(.blue)
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
        showActionsMenu = false
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

// MARK: - Select Options Button (Liquid Glass Style)

struct SelectOptionsButton: View {
    let selectedCount: Int
    @Binding var isExpanded: Bool
    let animation: Animation

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button {
            withAnimation(animation) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Options")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.primary)

                    Text("\(selectedCount) selected")
                        .font(.system(size: 12))
                        .foregroundColor(.primary.opacity(0.65))
                }

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.primary.opacity(0.65))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .shadow(
                        color: isExpanded ? .black.opacity(0.15) : .clear,
                        radius: isExpanded ? 8 : 0,
                        x: 0,
                        y: isExpanded ? 4 : 0
                    )
            )
            .overlay(
                Capsule()
                    .strokeBorder(
                        colorScheme == .dark
                            ? Color.white.opacity(0.12)
                            : Color.black.opacity(0.08),
                        lineWidth: 1
                    )
            )
            .contentShape(Capsule())
        }
        .buttonStyle(OptionsButtonStyle())
    }
}

// MARK: - Options Button Style

struct OptionsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Compact Menu Row

struct CompactMenuRow: View {
    let icon: String
    let label: String
    let isDestructive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(isDestructive ? .red : .primary)
                    .frame(width: 20, alignment: .center)

                Text(label)
                    .font(.system(size: 16))
                    .foregroundColor(isDestructive ? .red : .primary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Color(.tertiaryLabel))
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(CompactMenuButtonStyle())
    }
}

// MARK: - Compact Menu Button Style

struct CompactMenuButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                configuration.isPressed
                    ? Color.primary.opacity(0.08)
                    : Color.clear
            )
    }
}

// MARK: - Recording Row

struct RecordingRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme
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
                .foregroundColor(recording.iconSymbolColor(for: colorScheme))
                .frame(width: 44, height: 44)
                .background(recording.iconTileBackground(for: colorScheme))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(recording.iconTileBorder(for: colorScheme), lineWidth: 1)
                )

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

// MARK: - Move to Album Sheet (Single Recording, Searchable)

struct MoveToAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

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
                            Image(systemName: "square.stack")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            Text(album.name)
                                .foregroundColor(.primary)
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
            }
            .searchable(text: $searchQuery, prompt: "Search albums")
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

// MARK: - Batch Album Picker

struct BatchAlbumPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

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
                            Image(systemName: "square.stack")
                                .foregroundColor(.purple)
                                .frame(width: 24)
                            Text(album.name)
                                .foregroundColor(.primary)
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
                        }
                    }
                }
            }
            .searchable(text: $searchQuery, prompt: "Search albums")
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
