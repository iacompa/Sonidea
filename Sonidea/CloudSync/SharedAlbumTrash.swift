//
//  SharedAlbumTrash.swift
//  Sonidea
//
//  Model for trash items in shared albums.
//  Supports configurable retention and permission-based restore.
//

import Foundation

/// A trashed recording in a shared album
struct SharedAlbumTrashItem: Identifiable, Codable, Equatable {
    let id: UUID
    let recordingId: UUID
    let albumId: UUID
    let title: String
    let duration: TimeInterval
    let creatorId: String
    let creatorDisplayName: String
    let deletedBy: String
    let deletedByDisplayName: String
    let deletedAt: Date
    let originalCreatedAt: Date

    /// CloudKit asset reference for potential restore
    var audioAssetReference: String?

    /// Original shared recording metadata (for full restore)
    var originalMetadata: SharedRecordingItem?

    // MARK: - Computed Properties

    /// Calculate when this item expires based on retention days
    func expiresAt(retentionDays: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: retentionDays, to: deletedAt) ?? deletedAt
    }

    /// Days remaining until permanent deletion
    func daysUntilExpiration(retentionDays: Int) -> Int {
        let expirationDate = expiresAt(retentionDays: retentionDays)
        let days = Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day ?? 0
        return max(0, days)
    }

    /// Whether this item should be permanently deleted
    func shouldPurge(retentionDays: Int) -> Bool {
        daysUntilExpiration(retentionDays: retentionDays) <= 0
    }

    /// Formatted duration string
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Formatted deleted date
    var formattedDeletedAt: String {
        CachedDateFormatter.mediumDateTime.string(from: deletedAt)
    }

    /// Relative time since deletion
    var relativeDeletedTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: deletedAt, relativeTo: Date())
    }

    /// Creator initials for avatar
    var creatorInitials: String {
        SharedAlbumParticipant.generateInitials(from: creatorDisplayName)
    }

    /// Deleter initials for avatar
    var deleterInitials: String {
        SharedAlbumParticipant.generateInitials(from: deletedByDisplayName)
    }

    /// Whether the creator and deleter are the same person
    var deletedByCreator: Bool {
        creatorId == deletedBy
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        albumId: UUID,
        title: String,
        duration: TimeInterval,
        creatorId: String,
        creatorDisplayName: String,
        deletedBy: String,
        deletedByDisplayName: String,
        deletedAt: Date = Date(),
        originalCreatedAt: Date,
        audioAssetReference: String? = nil,
        originalMetadata: SharedRecordingItem? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.albumId = albumId
        self.title = title
        self.duration = duration
        self.creatorId = creatorId
        self.creatorDisplayName = creatorDisplayName
        self.deletedBy = deletedBy
        self.deletedByDisplayName = deletedByDisplayName
        self.deletedAt = deletedAt
        self.originalCreatedAt = originalCreatedAt
        self.audioAssetReference = audioAssetReference
        self.originalMetadata = originalMetadata
    }

    /// Create a trash item from a shared recording
    static func from(
        sharedRecording: SharedRecordingItem,
        recording: RecordingItem,
        deletedBy: String,
        deletedByDisplayName: String
    ) -> SharedAlbumTrashItem {
        SharedAlbumTrashItem(
            recordingId: recording.id,
            albumId: sharedRecording.albumId,
            title: recording.title,
            duration: recording.duration,
            creatorId: sharedRecording.creatorId,
            creatorDisplayName: sharedRecording.creatorDisplayName,
            deletedBy: deletedBy,
            deletedByDisplayName: deletedByDisplayName,
            originalCreatedAt: recording.createdAt,
            originalMetadata: sharedRecording
        )
    }
}

// MARK: - Trash Statistics

struct SharedAlbumTrashStats {
    let totalItems: Int
    let expiringToday: Int
    let expiringSoon: Int  // Within 3 days
    let oldestItem: SharedAlbumTrashItem?
    let newestItem: SharedAlbumTrashItem?

    var isEmpty: Bool {
        totalItems == 0
    }

    var hasExpiringItems: Bool {
        expiringToday > 0 || expiringSoon > 0
    }
}

extension Array where Element == SharedAlbumTrashItem {
    /// Calculate trash statistics for a given retention period
    func stats(retentionDays: Int) -> SharedAlbumTrashStats {
        let expiringToday = filter { $0.daysUntilExpiration(retentionDays: retentionDays) == 0 }.count
        let expiringSoon = filter { $0.daysUntilExpiration(retentionDays: retentionDays) <= 3 && $0.daysUntilExpiration(retentionDays: retentionDays) > 0 }.count
        let sorted = sorted { $0.deletedAt < $1.deletedAt }

        return SharedAlbumTrashStats(
            totalItems: count,
            expiringToday: expiringToday,
            expiringSoon: expiringSoon,
            oldestItem: sorted.first,
            newestItem: sorted.last
        )
    }

    /// Filter to items that should be purged
    func itemsToPurge(retentionDays: Int) -> [SharedAlbumTrashItem] {
        filter { $0.shouldPurge(retentionDays: retentionDays) }
    }

    /// Sort by deletion date (newest first)
    func sortedByDeletionDate() -> [SharedAlbumTrashItem] {
        sorted { $0.deletedAt > $1.deletedAt }
    }

    /// Group by deleter
    func groupedByDeleter() -> [String: [SharedAlbumTrashItem]] {
        Dictionary(grouping: self) { $0.deletedBy }
    }
}
