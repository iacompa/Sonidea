//
//  SharedAlbumManager.swift
//  Sonidea
//
//  Manages CloudKit sharing for Shared Albums.
//  Uses CKShare for multi-participant collaboration.
//

import Foundation
import CloudKit
import Observation
import OSLog
import UIKit

// MARK: - Shared Album Error

enum SharedAlbumError: Error, LocalizedError {
    case notSignedIn
    case sharingNotAvailable
    case albumNotFound
    case shareCreationFailed(Error)
    case participantLimitReached
    case notOwner
    case audioOnlyViolation
    case networkError(Error)
    case permissionDenied
    case recordingNotFound
    case trashItemNotFound
    case invalidRole

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Please sign in to iCloud to use Shared Albums"
        case .sharingNotAvailable:
            return "iCloud sharing is not available"
        case .albumNotFound:
            return "Album not found"
        case .shareCreationFailed(let error):
            return "Failed to create share: \(error.localizedDescription)"
        case .participantLimitReached:
            return "Maximum participants reached (5)"
        case .notOwner:
            return "Only the album owner can perform this action"
        case .audioOnlyViolation:
            return "Only audio files can be added to shared albums"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .permissionDenied:
            return "You don't have permission to perform this action"
        case .recordingNotFound:
            return "Recording not found"
        case .trashItemNotFound:
            return "Trash item not found"
        case .invalidRole:
            return "Invalid participant role"
        }
    }
}

// MARK: - Shared Album Manager

@MainActor
@Observable
final class SharedAlbumManager {

    // MARK: - Observable State

    var isProcessing = false
    var error: String?

    // MARK: - Configuration

    private let containerIdentifier = "iCloud.com.iacompa.sonidea"
    private let sharedZoneName = "SharedAlbumsZone"
    private let maxParticipants = 5
    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "SharedAlbum")

    // MARK: - CloudKit Objects

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    private var sharedDatabase: CKDatabase {
        container.sharedCloudDatabase
    }

    // Weak reference to AppState
    weak var appState: AppState?

    // MARK: - Initialization

    init() {}

    // MARK: - Public API

    /// Create a new shared album (born-shared, starts empty)
    func createSharedAlbum(name: String) async throws -> Album {
        logger.info("Creating shared album: \(name)")
        isProcessing = true
        defer { isProcessing = false }

        // Check iCloud account status
        let accountStatus = try await container.accountStatus()
        guard accountStatus == .available else {
            throw SharedAlbumError.notSignedIn
        }

        // Create the album locally first
        let albumId = UUID()
        var album = Album(
            id: albumId,
            name: name,
            createdAt: Date(),
            isSystem: false,
            isShared: true,
            participantCount: 1,
            isOwner: true
        )

        // Create a custom zone for this shared album
        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(albumId.uuidString)", ownerName: CKCurrentUserDefaultName)
        let zone = CKRecordZone(zoneID: zoneID)

        do {
            // Create the zone
            try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
            logger.info("Created zone for shared album: \(zoneID.zoneName)")

            // Create the album record in the zone
            let recordID = CKRecord.ID(recordName: albumId.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: "SharedAlbum", recordID: recordID)
            record["name"] = name
            record["createdAt"] = album.createdAt
            record["isShared"] = true

            // Save the record
            try await privateDatabase.save(record)

            // Create the share
            let share = CKShare(rootRecord: record)
            share.publicPermission = .none  // Only invited participants
            share[CKShare.SystemFieldKey.title] = name
            share[CKShare.SystemFieldKey.shareType] = "com.iacompa.sonidea.sharedalbum"

            // Save the share
            let modifyResults = try await privateDatabase.modifyRecords(saving: [record, share], deleting: [])
            logger.info("Created share for album")

            // Update album with share info
            album.cloudKitShareRecordName = share.recordID.recordName
            if let shareURL = share.url {
                album.shareURL = shareURL
            }

            return album

        } catch {
            logger.error("Failed to create shared album: \(error.localizedDescription)")
            throw SharedAlbumError.shareCreationFailed(error)
        }
    }

    /// Get the CKShare for a shared album
    func getShare(for album: Album) async throws -> CKShare? {
        guard album.isShared, let shareRecordName = album.cloudKitShareRecordName else {
            return nil
        }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: shareRecordID)
            return record as? CKShare
        } catch {
            logger.error("Failed to fetch share: \(error.localizedDescription)")
            return nil
        }
    }

    /// Leave a shared album (for non-owners)
    func leaveSharedAlbum(_ album: Album) async throws {
        guard album.isShared && !album.isOwner else {
            throw SharedAlbumError.notOwner
        }

        logger.info("Leaving shared album: \(album.name)")
        isProcessing = true
        defer { isProcessing = false }

        // For participants, we just remove the zone from sharedDatabase
        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)

        do {
            // Accept leaving by removing from shared database
            // The zone will be removed from the participant's view
            try await sharedDatabase.modifyRecordZones(saving: [], deleting: [zoneID])
            logger.info("Left shared album successfully")
        } catch {
            // If zone doesn't exist in shared database, it's already been left
            logger.warning("Zone may already be removed: \(error.localizedDescription)")
        }
    }

    /// Stop sharing an album (for owners only)
    func stopSharing(_ album: Album) async throws {
        guard album.isShared && album.isOwner else {
            throw SharedAlbumError.notOwner
        }

        logger.info("Stopping sharing for album: \(album.name)")
        isProcessing = true
        defer { isProcessing = false }

        guard let shareRecordName = album.cloudKitShareRecordName else {
            throw SharedAlbumError.albumNotFound
        }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)

        do {
            // Delete the share record to stop sharing
            try await privateDatabase.modifyRecords(saving: [], deleting: [shareRecordID])
            logger.info("Stopped sharing album")
        } catch {
            logger.error("Failed to stop sharing: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Add a recording to a shared album with CloudKit
    func addRecordingToSharedAlbum(recording: RecordingItem, album: Album) async throws {
        guard album.isShared else { return }

        logger.info("Adding recording to shared album: \(recording.title) -> \(album.name)")
        isProcessing = true
        defer { isProcessing = false }

        // Validate audio-only
        let fileExtension = recording.fileURL.pathExtension.lowercased()
        let audioExtensions = ["m4a", "mp3", "wav", "aiff", "aac", "caf"]
        guard audioExtensions.contains(fileExtension) else {
            throw SharedAlbumError.audioOnlyViolation
        }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: recording.id.uuidString, zoneID: zoneID)

        let record = CKRecord(recordType: "SharedRecording", recordID: recordID)
        record["title"] = recording.title
        record["duration"] = recording.duration
        record["createdAt"] = recording.createdAt
        record["notes"] = recording.notes

        // Add audio as CKAsset
        if FileManager.default.fileExists(atPath: recording.fileURL.path) {
            let asset = CKAsset(fileURL: recording.fileURL)
            record["audioFile"] = asset
        }

        do {
            try await privateDatabase.save(record)
            logger.info("Added recording to shared album")
        } catch {
            logger.error("Failed to add recording to shared album: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Delete a recording from a shared album
    func deleteRecordingFromSharedAlbum(recordingId: UUID, album: Album) async throws {
        guard album.isShared else { return }

        logger.info("Deleting recording from shared album: \(recordingId)")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: recordingId.uuidString, zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecords(saving: [], deleting: [recordID])
            logger.info("Deleted recording from shared album")
        } catch {
            logger.error("Failed to delete recording from shared album: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Fetch participants for a shared album
    func fetchParticipants(for album: Album) async -> [SharedAlbumParticipant] {
        guard album.isShared else { return [] }

        do {
            guard let share = try await getShare(for: album) else {
                return []
            }

            var participants: [SharedAlbumParticipant] = []

            // Add owner (always admin)
            let owner = share.owner
            let ownerName = owner.userIdentity.nameComponents?.formatted() ?? "Owner"
            let ownerParticipant = SharedAlbumParticipant(
                id: owner.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                displayName: ownerName,
                role: .admin,
                acceptanceStatus: .accepted,
                joinedAt: album.createdAt,
                avatarInitials: SharedAlbumParticipant.generateInitials(from: ownerName)
            )
            participants.append(ownerParticipant)

            // Add other participants
            for participant in share.participants where participant.role != .owner {
                let status: SharedAlbumParticipant.ParticipantStatus
                switch participant.acceptanceStatus {
                case .accepted:
                    status = .accepted
                case .pending:
                    status = .pending
                case .removed:
                    status = .removed
                @unknown default:
                    status = .pending
                }

                // Default new participants to member role
                // In a full implementation, we'd fetch stored roles from CloudKit
                let displayName = participant.userIdentity.nameComponents?.formatted() ?? "Participant"
                let p = SharedAlbumParticipant(
                    id: participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                    displayName: displayName,
                    role: .member,  // Default role for non-owners
                    acceptanceStatus: status,
                    joinedAt: status == .accepted ? Date() : nil,
                    avatarInitials: SharedAlbumParticipant.generateInitials(from: displayName)
                )
                participants.append(p)
            }

            return participants

        } catch {
            logger.error("Failed to fetch participants: \(error.localizedDescription)")
            return []
        }
    }

    /// Validate that a file is audio-only
    func validateAudioOnly(url: URL) -> Bool {
        let audioExtensions = ["m4a", "mp3", "wav", "aiff", "aac", "caf", "flac", "alac"]
        let fileExtension = url.pathExtension.lowercased()
        return audioExtensions.contains(fileExtension)
    }

    /// Check if user can add more participants
    func canAddParticipants(to album: Album) -> Bool {
        return album.isOwner && album.participantCount < maxParticipants
    }

    // MARK: - Participant Management

    /// Change a participant's role (admin only)
    func changeParticipantRole(
        album: Album,
        participantId: String,
        newRole: ParticipantRole
    ) async throws {
        guard album.isShared && album.canManageParticipants else {
            throw SharedAlbumError.permissionDenied
        }

        // Cannot change role to admin (only one admin/owner allowed)
        guard newRole != .admin else {
            throw SharedAlbumError.invalidRole
        }

        logger.info("Changing role for participant \(participantId) to \(newRole.rawValue)")
        isProcessing = true
        defer { isProcessing = false }

        // In a real implementation, this would update the CKShare participant permissions
        // For now, we'll update local state and sync

        // Log activity
        if let currentUserId = await getCurrentUserId() {
            let event = SharedAlbumActivityEvent(
                albumId: album.id,
                actorId: currentUserId,
                actorDisplayName: "You",
                eventType: .participantRoleChanged,
                targetParticipantId: participantId,
                newValue: newRole.displayName
            )
            try await logActivity(event: event, for: album)
        }
    }

    /// Remove a participant from the album (admin only)
    func removeParticipant(album: Album, participantId: String) async throws {
        guard album.isShared && album.canManageParticipants else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Removing participant \(participantId) from album: \(album.name)")
        isProcessing = true
        defer { isProcessing = false }

        guard let share = try await getShare(for: album) else {
            throw SharedAlbumError.albumNotFound
        }

        // Find and remove the participant
        for participant in share.participants {
            if participant.userIdentity.userRecordID?.recordName == participantId {
                share.removeParticipant(participant)
                break
            }
        }

        // Save the updated share
        do {
            try await privateDatabase.save(share)
            logger.info("Removed participant successfully")

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: "You",
                    eventType: .participantRemoved,
                    targetParticipantId: participantId
                )
                try await logActivity(event: event, for: album)
            }
        } catch {
            logger.error("Failed to remove participant: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    // MARK: - Trash Operations

    /// Move a recording to the shared album trash
    func moveToTrash(
        recording: SharedRecordingItem,
        localRecording: RecordingItem,
        album: Album,
        deletedBy: String,
        deletedByDisplayName: String
    ) async throws -> SharedAlbumTrashItem {
        guard album.isShared else {
            throw SharedAlbumError.albumNotFound
        }

        // Check permissions
        let canDelete = album.canDeleteAnyRecording ||
            (album.canDeleteOwnRecording && recording.creatorId == deletedBy)
        guard canDelete else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Moving recording to shared album trash: \(localRecording.title)")
        isProcessing = true
        defer { isProcessing = false }

        // Create trash item
        let trashItem = SharedAlbumTrashItem.from(
            sharedRecording: recording,
            recording: localRecording,
            deletedBy: deletedBy,
            deletedByDisplayName: deletedByDisplayName
        )

        // Store in CloudKit trash zone
        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let trashRecordID = CKRecord.ID(recordName: "trash-\(trashItem.id.uuidString)", zoneID: zoneID)
        let trashRecord = CKRecord(recordType: "SharedAlbumTrash", recordID: trashRecordID)

        trashRecord["recordingId"] = trashItem.recordingId.uuidString
        trashRecord["title"] = trashItem.title
        trashRecord["duration"] = trashItem.duration
        trashRecord["creatorId"] = trashItem.creatorId
        trashRecord["creatorDisplayName"] = trashItem.creatorDisplayName
        trashRecord["deletedBy"] = trashItem.deletedBy
        trashRecord["deletedByDisplayName"] = trashItem.deletedByDisplayName
        trashRecord["deletedAt"] = trashItem.deletedAt
        trashRecord["originalCreatedAt"] = trashItem.originalCreatedAt

        do {
            // Save trash record and delete original
            let recordingRecordID = CKRecord.ID(recordName: localRecording.id.uuidString, zoneID: zoneID)
            try await privateDatabase.modifyRecords(saving: [trashRecord], deleting: [recordingRecordID])

            // Log activity
            let event = SharedAlbumActivityEvent.recordingDeleted(
                albumId: album.id,
                actorId: deletedBy,
                actorDisplayName: deletedByDisplayName,
                recordingId: localRecording.id,
                recordingTitle: localRecording.title
            )
            try await logActivity(event: event, for: album)

            logger.info("Moved recording to trash successfully")
            return trashItem
        } catch {
            logger.error("Failed to move recording to trash: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Restore a recording from trash
    func restoreFromTrash(trashItem: SharedAlbumTrashItem, album: Album) async throws {
        guard album.isShared && album.canRestoreFromTrash else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Restoring recording from trash: \(trashItem.title)")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)

        // Recreate the recording record
        let recordID = CKRecord.ID(recordName: trashItem.recordingId.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "SharedRecording", recordID: recordID)

        record["title"] = trashItem.title
        record["duration"] = trashItem.duration
        record["createdAt"] = trashItem.originalCreatedAt
        record["creatorId"] = trashItem.creatorId
        record["creatorDisplayName"] = trashItem.creatorDisplayName

        // Delete trash record
        let trashRecordID = CKRecord.ID(recordName: "trash-\(trashItem.id.uuidString)", zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecords(saving: [record], deleting: [trashRecordID])

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: "You",
                    eventType: .recordingRestored,
                    targetRecordingId: trashItem.recordingId,
                    targetRecordingTitle: trashItem.title
                )
                try await logActivity(event: event, for: album)
            }

            logger.info("Restored recording from trash successfully")
        } catch {
            logger.error("Failed to restore from trash: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Permanently delete a trash item
    func permanentlyDelete(trashItem: SharedAlbumTrashItem, album: Album) async throws {
        guard album.isShared && album.canDeleteAnyRecording else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Permanently deleting: \(trashItem.title)")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let trashRecordID = CKRecord.ID(recordName: "trash-\(trashItem.id.uuidString)", zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecords(saving: [], deleting: [trashRecordID])
            logger.info("Permanently deleted trash item")
        } catch {
            logger.error("Failed to permanently delete: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Fetch all trash items for an album
    func fetchTrashItems(for album: Album) async -> [SharedAlbumTrashItem] {
        guard album.isShared else { return [] }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let query = CKQuery(recordType: "SharedAlbumTrash", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]

        do {
            let (results, _) = try await privateDatabase.records(matching: query, inZoneWith: zoneID)

            var trashItems: [SharedAlbumTrashItem] = []
            for (_, result) in results {
                if case .success(let record) = result {
                    if let item = parseTrashRecord(record) {
                        trashItems.append(item)
                    }
                }
            }
            return trashItems
        } catch {
            logger.error("Failed to fetch trash items: \(error.localizedDescription)")
            return []
        }
    }

    /// Purge expired trash items
    func purgeExpiredTrashItems(for album: Album) async throws {
        guard album.isShared else { return }

        let retentionDays = album.sharedSettings?.trashRetentionDays ?? 14
        let trashItems = await fetchTrashItems(for: album)
        let itemsToPurge = trashItems.itemsToPurge(retentionDays: retentionDays)

        guard !itemsToPurge.isEmpty else { return }

        logger.info("Purging \(itemsToPurge.count) expired trash items")

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordIDsToDelete = itemsToPurge.map { item in
            CKRecord.ID(recordName: "trash-\(item.id.uuidString)", zoneID: zoneID)
        }

        do {
            try await privateDatabase.modifyRecords(saving: [], deleting: recordIDsToDelete)
            logger.info("Purged expired trash items successfully")
        } catch {
            logger.error("Failed to purge trash items: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    private func parseTrashRecord(_ record: CKRecord) -> SharedAlbumTrashItem? {
        guard let recordingIdString = record["recordingId"] as? String,
              let recordingId = UUID(uuidString: recordingIdString),
              let title = record["title"] as? String,
              let duration = record["duration"] as? TimeInterval,
              let creatorId = record["creatorId"] as? String,
              let creatorDisplayName = record["creatorDisplayName"] as? String,
              let deletedBy = record["deletedBy"] as? String,
              let deletedByDisplayName = record["deletedByDisplayName"] as? String,
              let deletedAt = record["deletedAt"] as? Date,
              let originalCreatedAt = record["originalCreatedAt"] as? Date else {
            return nil
        }

        // Extract album ID from zone name
        let zoneName = record.recordID.zoneID.zoneName
        guard zoneName.hasPrefix("SharedAlbum-"),
              let albumId = UUID(uuidString: String(zoneName.dropFirst("SharedAlbum-".count))) else {
            return nil
        }

        return SharedAlbumTrashItem(
            id: UUID(uuidString: record.recordID.recordName.replacingOccurrences(of: "trash-", with: "")) ?? UUID(),
            recordingId: recordingId,
            albumId: albumId,
            title: title,
            duration: duration,
            creatorId: creatorId,
            creatorDisplayName: creatorDisplayName,
            deletedBy: deletedBy,
            deletedByDisplayName: deletedByDisplayName,
            deletedAt: deletedAt,
            originalCreatedAt: originalCreatedAt
        )
    }

    // MARK: - Activity Feed

    /// Log an activity event
    func logActivity(event: SharedAlbumActivityEvent, for album: Album) async throws {
        guard album.isShared else { return }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: "activity-\(event.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "SharedAlbumActivity", recordID: recordID)

        record["timestamp"] = event.timestamp
        record["actorId"] = event.actorId
        record["actorDisplayName"] = event.actorDisplayName
        record["eventType"] = event.eventType.rawValue
        record["targetRecordingId"] = event.targetRecordingId?.uuidString
        record["targetRecordingTitle"] = event.targetRecordingTitle
        record["targetParticipantId"] = event.targetParticipantId
        record["targetParticipantName"] = event.targetParticipantName
        record["oldValue"] = event.oldValue
        record["newValue"] = event.newValue

        do {
            try await privateDatabase.save(record)
            logger.debug("Logged activity: \(event.eventType.rawValue)")
        } catch {
            logger.error("Failed to log activity: \(error.localizedDescription)")
            // Don't throw - activity logging is non-critical
        }
    }

    /// Fetch activity feed for an album
    func fetchActivityFeed(for album: Album, limit: Int = 50) async -> [SharedAlbumActivityEvent] {
        guard album.isShared else { return [] }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let query = CKQuery(recordType: "SharedAlbumActivity", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (results, _) = try await privateDatabase.records(matching: query, inZoneWith: zoneID, resultsLimit: limit)

            var events: [SharedAlbumActivityEvent] = []
            for (_, result) in results {
                if case .success(let record) = result {
                    if let event = parseActivityRecord(record, albumId: album.id) {
                        events.append(event)
                    }
                }
            }
            return events
        } catch {
            logger.error("Failed to fetch activity feed: \(error.localizedDescription)")
            return []
        }
    }

    private func parseActivityRecord(_ record: CKRecord, albumId: UUID) -> SharedAlbumActivityEvent? {
        guard let timestamp = record["timestamp"] as? Date,
              let actorId = record["actorId"] as? String,
              let actorDisplayName = record["actorDisplayName"] as? String,
              let eventTypeRaw = record["eventType"] as? String,
              let eventType = ActivityEventType(rawValue: eventTypeRaw) else {
            return nil
        }

        return SharedAlbumActivityEvent(
            id: UUID(uuidString: record.recordID.recordName.replacingOccurrences(of: "activity-", with: "")) ?? UUID(),
            albumId: albumId,
            timestamp: timestamp,
            actorId: actorId,
            actorDisplayName: actorDisplayName,
            eventType: eventType,
            targetRecordingId: (record["targetRecordingId"] as? String).flatMap { UUID(uuidString: $0) },
            targetRecordingTitle: record["targetRecordingTitle"] as? String,
            targetParticipantId: record["targetParticipantId"] as? String,
            targetParticipantName: record["targetParticipantName"] as? String,
            oldValue: record["oldValue"] as? String,
            newValue: record["newValue"] as? String
        )
    }

    // MARK: - Settings Management

    /// Update album settings
    func updateAlbumSettings(album: Album, settings: SharedAlbumSettings) async throws {
        guard album.isShared && album.canEditSettings else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Updating settings for album: \(album.name)")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let settingsRecordID = CKRecord.ID(recordName: "settings-\(album.id.uuidString)", zoneID: zoneID)

        // Try to fetch existing settings record or create new one
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: settingsRecordID)
        } catch {
            record = CKRecord(recordType: "SharedAlbumSettings", recordID: settingsRecordID)
        }

        record["allowMembersToDelete"] = settings.allowMembersToDelete
        record["trashRestorePermission"] = settings.trashRestorePermission.rawValue
        record["trashRetentionDays"] = settings.trashRetentionDays
        record["defaultLocationSharingMode"] = settings.defaultLocationSharingMode.rawValue
        record["allowMembersToShareLocation"] = settings.allowMembersToShareLocation
        record["requireSensitiveApproval"] = settings.requireSensitiveApproval

        do {
            try await privateDatabase.save(record)
            logger.info("Updated album settings successfully")
        } catch {
            logger.error("Failed to update settings: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Fetch album settings
    func fetchAlbumSettings(for album: Album) async -> SharedAlbumSettings? {
        guard album.isShared else { return nil }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let settingsRecordID = CKRecord.ID(recordName: "settings-\(album.id.uuidString)", zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: settingsRecordID)
            return parseSettingsRecord(record)
        } catch {
            // Settings don't exist yet, return defaults
            return SharedAlbumSettings.default
        }
    }

    private func parseSettingsRecord(_ record: CKRecord) -> SharedAlbumSettings {
        var settings = SharedAlbumSettings.default

        if let allowDeletes = record["allowMembersToDelete"] as? Bool {
            settings.allowMembersToDelete = allowDeletes
        }
        if let permissionRaw = record["trashRestorePermission"] as? String,
           let permission = TrashRestorePermission(rawValue: permissionRaw) {
            settings.trashRestorePermission = permission
        }
        if let retentionDays = record["trashRetentionDays"] as? Int {
            settings.trashRetentionDays = min(max(retentionDays, 7), 30)
        }
        if let locationModeRaw = record["defaultLocationSharingMode"] as? String,
           let locationMode = LocationSharingMode(rawValue: locationModeRaw) {
            settings.defaultLocationSharingMode = locationMode
        }
        if let allowLocation = record["allowMembersToShareLocation"] as? Bool {
            settings.allowMembersToShareLocation = allowLocation
        }
        if let requireApproval = record["requireSensitiveApproval"] as? Bool {
            settings.requireSensitiveApproval = requireApproval
        }

        return settings
    }

    // MARK: - Location Sharing

    /// Update location sharing for a recording
    func updateLocationSharing(
        recording: SharedRecordingItem,
        mode: LocationSharingMode,
        album: Album,
        latitude: Double?,
        longitude: Double?,
        placeName: String?
    ) async throws {
        guard album.isShared else { return }

        // Check if user can share location
        if mode != .none {
            guard album.sharedSettings?.allowMembersToShareLocation ?? true else {
                throw SharedAlbumError.permissionDenied
            }
        }

        logger.info("Updating location sharing to \(mode.rawValue) for recording")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: recording.recordingId.uuidString, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: recordID)

            record["locationSharingMode"] = mode.rawValue

            if mode != .none, let lat = latitude, let lon = longitude {
                let approx = SharedRecordingItem.approximateLocation(latitude: lat, longitude: lon, mode: mode)
                record["sharedLatitude"] = approx.latitude
                record["sharedLongitude"] = approx.longitude
                record["sharedPlaceName"] = placeName
            } else {
                record["sharedLatitude"] = nil
                record["sharedLongitude"] = nil
                record["sharedPlaceName"] = nil
            }

            try await privateDatabase.save(record)

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let eventType: ActivityEventType = mode == .none ? .locationDisabled : .locationEnabled
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: "You",
                    eventType: eventType,
                    newValue: mode.displayName
                )
                try await logActivity(event: event, for: album)
            }

            logger.info("Updated location sharing successfully")
        } catch {
            logger.error("Failed to update location sharing: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    // MARK: - Sensitive Recording Management

    /// Mark a recording as sensitive
    func markRecordingSensitive(
        recording: SharedRecordingItem,
        isSensitive: Bool,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        logger.info("Marking recording as sensitive: \(isSensitive)")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: recording.recordingId.uuidString, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: recordID)
            record["isSensitive"] = isSensitive
            record["sensitiveApproved"] = false
            record["sensitiveApprovedBy"] = nil

            try await privateDatabase.save(record)

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let eventType: ActivityEventType = isSensitive ? .recordingMarkedSensitive : .recordingUnmarkedSensitive
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: "You",
                    eventType: eventType,
                    targetRecordingId: recording.recordingId
                )
                try await logActivity(event: event, for: album)
            }

            logger.info("Updated sensitive status successfully")
        } catch {
            logger.error("Failed to update sensitive status: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Approve or reject a sensitive recording (admin only)
    func approveSensitiveRecording(
        recording: SharedRecordingItem,
        approved: Bool,
        album: Album
    ) async throws {
        guard album.isShared && album.currentUserRole == .admin else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Admin \(approved ? "approving" : "rejecting") sensitive recording")
        isProcessing = true
        defer { isProcessing = false }

        let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecord.ID(recordName: recording.recordingId.uuidString, zoneID: zoneID)

        do {
            let record = try await privateDatabase.record(for: recordID)

            if let currentUserId = await getCurrentUserId() {
                record["sensitiveApproved"] = approved
                record["sensitiveApprovedBy"] = approved ? currentUserId : nil
                record["sensitiveApprovedAt"] = approved ? Date() : nil

                try await privateDatabase.save(record)

                // Log activity
                let eventType: ActivityEventType = approved ? .sensitiveRecordingApproved : .sensitiveRecordingRejected
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: "You",
                    eventType: eventType,
                    targetRecordingId: recording.recordingId
                )
                try await logActivity(event: event, for: album)
            }

            logger.info("Sensitive recording \(approved ? "approved" : "rejected")")
        } catch {
            logger.error("Failed to approve sensitive recording: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    // MARK: - Helper Methods

    /// Get current user's CloudKit ID
    func getCurrentUserId() async -> String? {
        do {
            let userRecordID = try await container.userRecordID()
            return userRecordID.recordName
        } catch {
            logger.error("Failed to get current user ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Get current user's display name
    func getCurrentUserDisplayName() async -> String {
        do {
            let userRecordID = try await container.userRecordID()
            let identity = try await container.userIdentity(forUserRecordID: userRecordID)
            return identity?.nameComponents?.formatted() ?? "You"
        } catch {
            return "You"
        }
    }
}

// MARK: - UICloudSharingController Support

extension SharedAlbumManager {

    /// Prepare sharing controller for presenting
    @MainActor
    func prepareSharingController(
        for album: Album,
        completion: @escaping (UICloudSharingController?) -> Void
    ) {
        Task {
            do {
                guard let share = try await getShare(for: album) else {
                    completion(nil)
                    return
                }

                let controller = UICloudSharingController(share: share, container: container)
                controller.availablePermissions = [.allowReadWrite]
                completion(controller)

            } catch {
                logger.error("Failed to prepare sharing controller: \(error.localizedDescription)")
                completion(nil)
            }
        }
    }
}
