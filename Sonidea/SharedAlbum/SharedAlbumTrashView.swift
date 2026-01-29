//
//  SharedAlbumTrashView.swift
//  Sonidea
//
//  Trash view for shared albums.
//  Shows deleted items with restore/permanent delete options.
//

import SwiftUI

struct SharedAlbumTrashView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album

    @State private var trashItems: [SharedAlbumTrashItem] = []
    @State private var isLoading = true
    @State private var selectedItem: SharedAlbumTrashItem?
    @State private var showRestoreConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var showEmptyTrashConfirmation = false
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var retentionDays: Int {
        album.sharedSettings?.trashRetentionDays ?? 14
    }

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading trash...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if trashItems.isEmpty {
                    emptyStateView
                } else {
                    trashList
                }
            }
            .background(palette.background)
            .navigationTitle("Trash")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                if album.canDeleteAnyRecording && !trashItems.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Empty") {
                            showEmptyTrashConfirmation = true
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .alert("Restore Recording?", isPresented: $showRestoreConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Restore") {
                    if let item = selectedItem {
                        restoreItem(item)
                    }
                }
            } message: {
                if let item = selectedItem {
                    Text("\"\(item.title)\" will be restored to the album.")
                }
            }
            .alert("Delete Permanently?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    if let item = selectedItem {
                        permanentlyDeleteItem(item)
                    }
                }
            } message: {
                if let item = selectedItem {
                    Text("\"\(item.title)\" will be permanently deleted and cannot be recovered.")
                }
            }
            .alert("Empty Trash?", isPresented: $showEmptyTrashConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) {
                    emptyTrash()
                }
            } message: {
                Text("All \(trashItems.count) items will be permanently deleted and cannot be recovered.")
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .overlay {
                if isProcessing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .onAppear {
                loadTrashItems()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "trash")
                .font(.system(size: 48))
                .foregroundColor(palette.textTertiary)

            Text("Trash is Empty")
                .font(.headline)
                .foregroundColor(palette.textSecondary)

            Text("Deleted recordings will appear here for \(retentionDays) days before being permanently removed")
                .font(.subheadline)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }

    private var trashList: some View {
        List {
            // Stats header
            Section {
                TrashStatsRow(stats: trashItems.stats(retentionDays: retentionDays))
            }

            // Trash items
            Section {
                ForEach(trashItems.sortedByDeletionDate()) { item in
                    SharedAlbumTrashItemRow(
                        item: item,
                        retentionDays: retentionDays,
                        canRestore: album.canRestoreFromTrash,
                        canDelete: album.canDeleteAnyRecording,
                        onRestore: {
                            selectedItem = item
                            showRestoreConfirmation = true
                        },
                        onDelete: {
                            selectedItem = item
                            showDeleteConfirmation = true
                        }
                    )
                }
            } header: {
                Text("\(trashItems.count) Item\(trashItems.count == 1 ? "" : "s")")
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadTrashItems() {
        isLoading = true
        Task {
            #if DEBUG
            let useDebugMode = appState.isSharedAlbumsDebugMode
            #else
            let useDebugMode = false
            #endif

            if useDebugMode {
                #if DEBUG
                await MainActor.run {
                    trashItems = appState.debugMockTrashItems()
                    isLoading = false
                }
                #endif
            } else {
                let items = await appState.sharedAlbumManager.fetchTrashItems(for: album)
                await MainActor.run {
                    trashItems = items
                    isLoading = false
                }
            }
        }
    }

    private func restoreItem(_ item: SharedAlbumTrashItem) {
        isProcessing = true
        Task {
            do {
                try await appState.sharedAlbumManager.restoreFromTrash(trashItem: item, album: album)
                await MainActor.run {
                    trashItems.removeAll { $0.id == item.id }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func permanentlyDeleteItem(_ item: SharedAlbumTrashItem) {
        isProcessing = true
        Task {
            do {
                try await appState.sharedAlbumManager.permanentlyDelete(trashItem: item, album: album)
                await MainActor.run {
                    trashItems.removeAll { $0.id == item.id }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func emptyTrash() {
        isProcessing = true
        Task {
            var deletedIds: Set<UUID> = []
            var failCount = 0
            for item in trashItems {
                do {
                    try await appState.sharedAlbumManager.permanentlyDelete(trashItem: item, album: album)
                    deletedIds.insert(item.id)
                } catch {
                    failCount += 1
                }
            }
            await MainActor.run {
                trashItems.removeAll { deletedIds.contains($0.id) }
                if failCount > 0 {
                    errorMessage = "Failed to delete \(failCount) item\(failCount == 1 ? "" : "s"). Please try again."
                }
                isProcessing = false
            }
        }
    }
}

// MARK: - Trash Stats Row

struct TrashStatsRow: View {
    @Environment(\.themePalette) private var palette

    let stats: SharedAlbumTrashStats

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 24) {
                StatItem(value: "\(stats.totalItems)", label: "Total")

                if stats.expiringToday > 0 {
                    StatItem(value: "\(stats.expiringToday)", label: "Expiring Today", color: .red)
                }

                if stats.expiringSoon > 0 {
                    StatItem(value: "\(stats.expiringSoon)", label: "Expiring Soon", color: .orange)
                }
            }

            if stats.hasExpiringItems {
                Text("Items expire automatically after the retention period")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding(.vertical, 8)
    }
}

struct StatItem: View {
    @Environment(\.themePalette) private var palette

    let value: String
    let label: String
    var color: Color?

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color ?? palette.textPrimary)

            Text(label)
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
    }
}

// MARK: - Trash Item Row

struct SharedAlbumTrashItemRow: View {
    @Environment(\.themePalette) private var palette

    let item: SharedAlbumTrashItem
    let retentionDays: Int
    let canRestore: Bool
    let canDelete: Bool
    let onRestore: () -> Void
    let onDelete: () -> Void

    private var daysRemaining: Int {
        item.daysUntilExpiration(retentionDays: retentionDays)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Recording info
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)

                    HStack(spacing: 8) {
                        Text(item.formattedDuration)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

                        Text("by \(item.creatorDisplayName)")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                }

                Spacer()

                // Expiration badge
                ExpirationBadge(daysRemaining: daysRemaining)
            }

            // Deletion info
            HStack(spacing: 4) {
                Image(systemName: "trash")
                    .font(.caption2)

                if item.deletedByCreator {
                    Text("Deleted \(item.relativeDeletedTime)")
                } else {
                    Text("Deleted by \(item.deletedByDisplayName) \(item.relativeDeletedTime)")
                }
            }
            .font(.caption)
            .foregroundColor(palette.textTertiary)

            // Actions
            HStack(spacing: 12) {
                if canRestore {
                    Button {
                        onRestore()
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                    .tint(.blue)
                }

                if canDelete {
                    Button(role: .destructive) {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "trash")
                            .font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.top, 4)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Expiration Badge

struct ExpirationBadge: View {
    let daysRemaining: Int

    var backgroundColor: Color {
        if daysRemaining <= 1 {
            return .red
        } else if daysRemaining <= 3 {
            return .orange
        } else {
            return .gray
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.caption2)

            Text(daysRemaining == 0 ? "Today" : "\(daysRemaining)d")
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(backgroundColor)
        .cornerRadius(6)
    }
}

// MARK: - Compact Trash Preview (for album detail)

struct SharedAlbumTrashPreview: View {
    @Environment(\.themePalette) private var palette

    let trashCount: Int
    let expiringCount: Int
    let onViewAll: () -> Void

    var body: some View {
        Button(action: onViewAll) {
            HStack {
                Image(systemName: "trash")
                    .foregroundColor(expiringCount > 0 ? .orange : palette.textSecondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Trash")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)

                    if trashCount == 0 {
                        Text("Empty")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    } else {
                        Text("\(trashCount) item\(trashCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                }

                Spacer()

                if expiringCount > 0 {
                    Text("\(expiringCount) expiring")
                        .font(.caption)
                        .foregroundColor(.orange)
                }

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
