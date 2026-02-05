//
//  RecordingGridView.swift
//  Sonidea
//
//  2-column card grid layout for recordings.
//  Apple-native style with gradient thumbnails, rounded cards, and soft shadows.
//

import SwiftUI

// MARK: - Recording Grid View

struct RecordingGridView: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var selectedRecording: RecordingItem?
    @State private var isSelectionMode = false
    @State private var selectedRecordingIDs: Set<UUID> = []

    // Sheet states
    @State private var showBatchAlbumPicker = false
    @State private var showBatchTagPicker = false
    @State private var showShareSheet = false
    @State private var exportedURL: URL?
    @State private var showDeleteConfirmation = false

    // Single recording action sheets
    @State private var recordingForMenu: RecordingItem?
    @State private var showMoveToAlbumSheet = false
    @State private var showSingleTagSheet = false

    // Export format selection for single share
    @State private var recordingToShare: RecordingItem?
    @State private var showExportFormatPicker = false

    // Bulk export format picker
    @State private var showBulkFormatPicker = false

    // Pro feature gating
    @State private var proUpgradeContext: ProFeatureContext?
    @State private var showTipJar = false

    // Grid configuration — adaptive for iPad
    private var columns: [GridItem] {
        let columnCount = sizeClass == .regular ? 3 : 2
        return Array(repeating: GridItem(.flexible(), spacing: CardGridStyle.cardSpacing), count: columnCount)
    }

    private var hasSelection: Bool {
        !selectedRecordingIDs.isEmpty
    }

    var body: some View {
        ZStack {
            palette.background
                .ignoresSafeArea()

            Group {
                if appState.activeRecordings.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        gridHeader

                        if isSelectionMode {
                            selectionHeader
                            selectionActionBar
                        }

                        recordingsGrid
                    }
                }
            }
        }
        .iPadSheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
        .iPadSheet(isPresented: $showBatchAlbumPicker) {
            BatchAlbumPickerSheet(selectedRecordingIDs: selectedRecordingIDs) {
                clearSelection()
            }
        }
        .iPadSheet(isPresented: $showBatchTagPicker) {
            BatchTagPickerSheet(selectedRecordingIDs: selectedRecordingIDs) {
                clearSelection()
            }
        }
        .sheet(isPresented: $showExportFormatPicker) {
            ExportFormatPicker { format in
                if let recording = recordingToShare {
                    exportAndShare(recording, format: format)
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showBulkFormatPicker) {
            BulkExportFormatPicker { formats in
                exportSelectedRecordings(formats: formats)
            }
        }
        .iPadSheet(isPresented: $showMoveToAlbumSheet) {
            if let recording = recordingForMenu {
                MoveToAlbumSheet(recording: recording)
            }
        }
        .iPadSheet(isPresented: $showSingleTagSheet) {
            if let recording = recordingForMenu {
                SingleRecordingTagSheet(recording: recording)
            }
        }
        .alert("Delete Recordings", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                appState.moveRecordingsToTrash(recordingIDs: selectedRecordingIDs)
                clearSelection()
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
                .environment(\.themePalette, palette)
        }
    }

    // MARK: - Empty State

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

    // MARK: - Grid Header

    private var gridHeader: some View {
        HStack {
            Text("Recordings")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(palette.textPrimary)

            Spacer()

            if !isSelectionMode {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isSelectionMode = true
                    }
                } label: {
                    Text("Select")
                        .font(.subheadline)
                        .foregroundColor(palette.accent)
                }
            }
        }
        .padding(.horizontal, CardGridStyle.horizontalPadding)
        .padding(.vertical, 8)
        .background(palette.background)
    }

    // MARK: - Selection Header

    private var selectionHeader: some View {
        HStack {
            Button("Cancel") {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
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
                withAnimation(.easeInOut(duration: 0.15)) {
                    if selectedRecordingIDs.count == appState.activeRecordings.count {
                        selectedRecordingIDs.removeAll()
                    } else {
                        selectedRecordingIDs = Set(appState.activeRecordings.map { $0.id })
                    }
                }
            }
            .foregroundColor(palette.accent)
        }
        .padding(.horizontal, CardGridStyle.horizontalPadding)
        .frame(height: 44)
        .background(palette.surface)
    }

    // MARK: - Selection Action Bar

    private var selectionActionBar: some View {
        HStack(spacing: 0) {
            SelectionActionButton(icon: "folder", label: "Album", isEnabled: hasSelection, isDestructive: false) {
                showBatchAlbumPicker = true
            }

            Divider().frame(height: 40).background(palette.separator)

            SelectionActionButton(icon: "tag", label: "Tags", isEnabled: hasSelection, isDestructive: false) {
                guard appState.supportManager.canUseProFeatures else {
                    proUpgradeContext = .tags
                    return
                }
                showBatchTagPicker = true
            }

            Divider().frame(height: 40).background(palette.separator)

            SelectionActionButton(icon: "square.and.arrow.up", label: "Export", isEnabled: hasSelection, isDestructive: false) {
                showBulkFormatPicker = true
            }

            Divider().frame(height: 40).background(palette.separator)

            SelectionActionButton(icon: "trash", label: "Delete", isEnabled: hasSelection, isDestructive: true) {
                showDeleteConfirmation = true
            }
        }
        .frame(height: 64)
        .background(palette.inputBackground)
        .cornerRadius(12)
        .padding(.horizontal, CardGridStyle.horizontalPadding)
        .padding(.vertical, 8)
    }

    // Pre-computed album lookup for O(1) resolution in card rendering
    private var albumLookup: [UUID: Album] {
        Dictionary(uniqueKeysWithValues: appState.albums.map { ($0.id, $0) })
    }

    // MARK: - Recordings Grid

    private var recordingsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: CardGridStyle.cardSpacing) {
                ForEach(appState.activeRecordings) { recording in
                    RecordingCardView(
                        recording: recording,
                        isSelectionMode: isSelectionMode,
                        isSelected: selectedRecordingIDs.contains(recording.id),
                        onTap: {
                            if isSelectionMode {
                                toggleSelection(recording)
                            } else {
                                selectedRecording = recording
                            }
                        },
                        onLongPress: {
                            if !isSelectionMode {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                    isSelectionMode = true
                                    selectedRecordingIDs.insert(recording.id)
                                }
                            }
                        },
                        onMenuAction: { action in
                            handleMenuAction(action, for: recording)
                        },
                        preResolvedAlbum: .some(recording.albumID.flatMap { albumLookup[$0] })
                    )
                }
            }
            .padding(.horizontal, CardGridStyle.horizontalPadding)
            .padding(.top, 8)
            .padding(.bottom, 120) // Space for floating record button
        }
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

    private func handleMenuAction(_ action: RecordingCardMenuAction, for recording: RecordingItem) {
        recordingForMenu = recording
        switch action {
        case .favorite:
            _ = appState.toggleFavorite(for: recording)
        case .album:
            showMoveToAlbumSheet = true
        case .tags:
            guard appState.supportManager.canUseProFeatures else {
                proUpgradeContext = .tags
                return
            }
            showSingleTagSheet = true
        case .share:
            shareRecording(recording)
        case .delete:
            appState.moveToTrash(recording)
        }
    }

    private func shareRecording(_ recording: RecordingItem) {
        recordingToShare = recording
        showExportFormatPicker = true
    }

    private func exportAndShare(_ recording: RecordingItem, format: ExportFormat) {
        Task {
            do {
                let url = try await AudioExporter.shared.export(recording: recording, format: format)
                exportedURL = url
                showShareSheet = true
            } catch {
                #if DEBUG
                print("Export failed: \(error)")
                #endif
            }
        }
    }

    private func exportSelectedRecordings(formats: Set<ExportFormat>) {
        let selectedRecordings = appState.activeRecordings.filter { selectedRecordingIDs.contains($0.id) }
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    selectedRecordings,
                    scope: .all,
                    formats: formats,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedURL = zipURL
                showShareSheet = true
                await MainActor.run {
                    clearSelection()
                }
            } catch {
                #if DEBUG
                print("Export failed: \(error)")
                #endif
            }
        }
    }
}

// MARK: - Card Grid Style Constants

enum CardGridStyle {
    static let horizontalPadding: CGFloat = 16
    static let cardSpacing: CGFloat = 12
    static let cardCornerRadius: CGFloat = 16
    static let thumbnailHeightRatio: CGFloat = 0.58 // 58% for thumbnail
    static let cardAspectRatio: CGFloat = 0.85 // width / height
    static let shadowRadius: CGFloat = 8
    static let shadowOpacity: Double = 0.15
}

// MARK: - Card Menu Actions

enum RecordingCardMenuAction {
    case favorite
    case album
    case tags
    case share
    case delete
}

// MARK: - Recording Card View

struct RecordingCardView: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let recording: RecordingItem
    let isSelectionMode: Bool
    let isSelected: Bool
    let onTap: () -> Void
    let onLongPress: () -> Void
    let onMenuAction: (RecordingCardMenuAction) -> Void

    // Pre-resolved album to avoid O(n) scan per card during render passes
    var preResolvedAlbum: Album??

    // Computed properties
    private var markerCount: Int {
        recording.markers.count
    }

    private var isFavorite: Bool {
        appState.isFavorite(recording)
    }

    private var gradientColors: [Color] {
        CardGradientGenerator.gradient(for: recording.id)
    }

    private var album: Album? {
        if let resolved = preResolvedAlbum { return resolved }
        return appState.album(for: recording.albumID)
    }

    private var isInSharedAlbum: Bool {
        album?.isShared == true
    }

    var body: some View {
        GeometryReader { geometry in
            let cardHeight = geometry.size.width / CardGridStyle.cardAspectRatio
            let thumbnailHeight = cardHeight * CardGridStyle.thumbnailHeightRatio

            VStack(spacing: 0) {
                // Top thumbnail region
                thumbnailRegion(width: geometry.size.width, height: thumbnailHeight)

                // Bottom text region
                textRegion(width: geometry.size.width, height: cardHeight - thumbnailHeight)
            }
            .frame(width: geometry.size.width, height: cardHeight)
            .clipShape(RoundedRectangle(cornerRadius: CardGridStyle.cardCornerRadius))
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.4 : CardGridStyle.shadowOpacity),
                radius: CardGridStyle.shadowRadius,
                x: 0,
                y: 4
            )
            .overlay(selectionOverlay)
            .contentShape(RoundedRectangle(cornerRadius: CardGridStyle.cardCornerRadius))
            .onTapGesture(perform: onTap)
            .onLongPressGesture(perform: onLongPress)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(recording.title), \(formattedDuration), \(formattedCardDate)")
            .accessibilityHint(isSelectionMode ? (isSelected ? "Selected" : "Not selected") : "Double tap to open")
        }
        .aspectRatio(CardGridStyle.cardAspectRatio, contentMode: .fit)
    }

    // MARK: - Thumbnail Region

    private func thumbnailRegion(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            // Gradient background
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            // Top-left: Mic badge
            VStack {
                HStack {
                    micBadge
                    if isInSharedAlbum {
                        SharedAlbumBadge()
                    }
                    Spacer()
                    menuButton
                }
                .padding(12)

                Spacer()

                // Bottom-left: Marker count + Duration
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        if markerCount > 0 {
                            markerCountBadge
                        }
                        durationLabel
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .frame(width: width, height: height)
    }

    private var micBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "mic.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white)

            if isFavorite {
                Image(systemName: "heart.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.pink)
            }

            if recording.hasProof {
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.green)
            }

        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial.opacity(0.8))
        .clipShape(Capsule())
    }

    private var menuButton: some View {
        Menu {
            Button {
                onMenuAction(.favorite)
            } label: {
                Label(isFavorite ? "Unfavorite" : "Favorite", systemImage: isFavorite ? "heart.slash" : "heart.fill")
            }

            Button {
                onMenuAction(.album)
            } label: {
                Label("Move to Album", systemImage: "folder")
            }

            Button {
                onMenuAction(.tags)
            } label: {
                Label("Tags", systemImage: "tag")
            }

            Button {
                onMenuAction(.share)
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                onMenuAction(.delete)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(.ultraThinMaterial.opacity(0.6))
                .clipShape(Circle())
        }
        .accessibilityLabel("More options")
    }

    private var markerCountBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color.white)
                .frame(width: 6, height: 6)
            Text("\(markerCount)")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private var durationLabel: some View {
        Text(formattedDuration)
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
            .foregroundColor(.white)
            .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }

    // MARK: - Text Region

    private func textRegion(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(recording.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(formattedCardDate)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(12)
        .background(Color(white: 0.12)) // Dark gray background
    }

    // MARK: - Selection Overlay

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelectionMode {
            ZStack {
                RoundedRectangle(cornerRadius: CardGridStyle.cardCornerRadius)
                    .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 3)

                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(isSelected ? palette.accent : .white.opacity(0.7))
                            .background(
                                Circle()
                                    .fill(isSelected ? Color.white : Color.black.opacity(0.3))
                                    .frame(width: 20, height: 20)
                            )
                            .padding(8)
                    }
                    Spacer()
                }
            }
        }
    }

    // MARK: - Formatters

    private var formattedDuration: String {
        CardDurationFormatter.format(recording.duration)
    }

    private var formattedCardDate: String {
        CardDateFormatter.format(recording.createdAt)
    }
}

// MARK: - Card Duration Formatter

enum CardDurationFormatter {
    static func format(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

// MARK: - Card Date Formatter

enum CardDateFormatter {
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func format(_ date: Date) -> String {
        formatter.string(from: date)
    }
}

// MARK: - Card Gradient Generator

enum CardGradientGenerator {
    /// Predefined gradient palettes that look good together
    private static let palettes: [[Color]] = [
        [Color(hex: "#667eea")!, Color(hex: "#764ba2")!],  // Purple-blue
        [Color(hex: "#f093fb")!, Color(hex: "#f5576c")!],  // Pink-red
        [Color(hex: "#4facfe")!, Color(hex: "#00f2fe")!],  // Blue-cyan
        [Color(hex: "#43e97b")!, Color(hex: "#38f9d7")!],  // Green-teal
        [Color(hex: "#fa709a")!, Color(hex: "#fee140")!],  // Pink-yellow
        [Color(hex: "#a18cd1")!, Color(hex: "#fbc2eb")!],  // Lavender-pink
        [Color(hex: "#ff9a9e")!, Color(hex: "#fecfef")!],  // Coral-pink
        [Color(hex: "#a1c4fd")!, Color(hex: "#c2e9fb")!],  // Sky blue
        [Color(hex: "#d299c2")!, Color(hex: "#fef9d7")!],  // Mauve-cream
        [Color(hex: "#89f7fe")!, Color(hex: "#66a6ff")!],  // Aqua-blue
        [Color(hex: "#fddb92")!, Color(hex: "#d1fdff")!],  // Yellow-mint
        [Color(hex: "#9890e3")!, Color(hex: "#b1f4cf")!],  // Purple-mint
    ]

    /// Generate a deterministic gradient based on recording ID
    static func gradient(for id: UUID) -> [Color] {
        let hash = abs(id.hashValue)
        let index = hash % palettes.count
        return palettes[index]
    }
}

// MARK: - Preview

#Preview {
    RecordingGridView()
        .environment(AppState())
}
