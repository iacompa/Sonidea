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
import Network

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
    case offline
    case shareNoLongerExists
    case downloadNotAllowed
    case commentTooLong
    case fileTooLarge
    case downloadFailed

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
        case .offline:
            return "You're offline. This action will be retried when connectivity returns."
        case .shareNoLongerExists:
            return "This shared album is no longer available. The owner may have stopped sharing."
        case .downloadNotAllowed:
            return "The creator has not enabled downloads for this recording."
        case .commentTooLong:
            return "Comment is too long (max 500 characters)."
        case .fileTooLarge:
            return "Recording file is too large to download (max 200MB)."
        case .downloadFailed:
            return "Failed to download the recording audio file. Please try again."
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
    var isOnline = true
    var shareStale = false  // Set true when owner has stopped sharing

    /// Cached current user ID for synchronous access (populated on first use)
    private(set) var cachedCurrentUserId: String?

    // MARK: - Configuration

    private let containerIdentifier = "iCloud.com.iacompa.sonidea"
    private let sharedZoneName = "SharedAlbumsZone"
    private let maxParticipants = 5
    private let maxCacheSizeBytes: Int64 = 500 * 1024 * 1024  // 500 MB
    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "SharedAlbum")

    // MARK: - CloudKit Objects

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private let sharedDatabase: CKDatabase

    // MARK: - Database Routing for Owner vs Non-Owner

    /// Returns the correct database and zone ID for a shared album.
    /// Owners use privateDatabase with their own zone.
    /// Non-owners use sharedDatabase and must find the zone from allRecordZones().
    private func databaseAndZone(for album: Album) async throws -> (database: CKDatabase, zoneID: CKRecordZone.ID) {
        if album.isOwner {
            let zoneID = CKRecordZone.ID(zoneName: "SharedAlbum-\(album.id.uuidString)", ownerName: CKCurrentUserDefaultName)
            return (privateDatabase, zoneID)
        } else {
            let allZones = try await sharedDatabase.allRecordZones()
            guard let sharedZone = allZones.first(where: { $0.zoneID.zoneName == "SharedAlbum-\(album.id.uuidString)" }) else {
                throw SharedAlbumError.shareNoLongerExists
            }
            return (sharedDatabase, sharedZone.zoneID)
        }
    }

    // Weak reference to AppState
    weak var appState: AppState?

    // MARK: - Network Monitor & Offline Queue

    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.iacompa.sonidea.networkMonitor")
    private var pendingOperations: [PendingOperation] = []
    private let pendingOpsKey = "sharedAlbum_pendingOperations"

    /// Represents a queued operation that failed due to being offline
    struct PendingOperation: Codable, Identifiable {
        let id: UUID
        let operationType: String
        let albumId: UUID
        let recordingId: UUID?
        let payload: [String: String]
        let createdAt: Date
        var retryCount: Int = 0
    }

    private let maxRetryCount = 5

    // MARK: - Initialization

    init() {
        let ckContainer = CKContainer(identifier: "iCloud.com.iacompa.sonidea")
        self.container = ckContainer
        self.privateDatabase = ckContainer.privateCloudDatabase
        self.sharedDatabase = ckContainer.sharedCloudDatabase
        loadPendingOperations()
        startNetworkMonitor()
    }

    deinit {
        networkMonitor.cancel()
    }

    // MARK: - Public API

    /// Create a new shared album (born-shared, starts empty)
    func createSharedAlbum(name: String) async throws -> Album {
        logger.info("Creating shared album: \(name, privacy: .private)")
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
            isOwner: true,
            currentUserRole: .admin
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

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let shareRecordID = CKRecord.ID(recordName: shareRecordName, zoneID: zoneID)
            let record = try await db.record(for: shareRecordID)
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

        logger.info("Leaving shared album: \(album.name, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        // Non-owners leave by fetching the share from the shared database
        // and using CKDatabase to remove the accepted share
        do {
            // Remove this user's recordings from the shared album before leaving
            if let currentUserId = await getCurrentUserId() {
                try? await removeUserRecordings(userId: currentUserId, album: album)
            }

            // First try to fetch all accepted shares and find the matching one
            let allZones = try await sharedDatabase.allRecordZones()
            let matchingZone = allZones.first { $0.zoneID.zoneName == "SharedAlbum-\(album.id.uuidString)" }

            if let zone = matchingZone {
                // Delete the zone from the shared database — this removes the participant's
                // accepted share and effectively leaves the album
                try await sharedDatabase.modifyRecordZones(saving: [], deleting: [zone.zoneID])
                logger.info("Left shared album successfully")
            } else {
                // Zone not found in shared database — may already be left
                logger.warning("Shared zone not found, album may already be left")
            }
        } catch {
            logger.error("Failed to leave shared album: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Stop sharing an album (for owners only)
    func stopSharing(_ album: Album) async throws {
        guard album.isShared && album.isOwner else {
            throw SharedAlbumError.notOwner
        }

        logger.info("Stopping sharing for album: \(album.name, privacy: .private)")
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
    func addRecordingToSharedAlbum(recording: RecordingItem, album: Album, locationMode: LocationSharingMode = .none) async throws {
        guard album.isShared else { return }

        // Check permission: only owner/admin/member can add recordings
        guard album.canAddRecordings else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Adding recording to shared album: \(recording.title, privacy: .private) -> \(album.name, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        // Validate audio-only
        let fileExtension = recording.fileURL.pathExtension.lowercased()
        let audioExtensions = ["m4a", "mp3", "wav", "aiff", "aac", "caf", "flac", "alac"]
        guard audioExtensions.contains(fileExtension) else {
            throw SharedAlbumError.audioOnlyViolation
        }

        // Get current user info
        let currentUserId = await getCurrentUserId() ?? "unknown"
        let currentUserName = await getCurrentUserDisplayName() ?? "Unknown User"

        let (db, zoneID) = try await databaseAndZone(for: album)
        let recordID = CKRecord.ID(recordName: recording.id.uuidString, zoneID: zoneID)

        let record = CKRecord(recordType: "SharedRecording", recordID: recordID)
        let sanitizedTitle = recording.title.trimmingCharacters(in: .controlCharacters)
        record["title"] = sanitizedTitle
        record["duration"] = recording.duration
        record["createdAt"] = recording.createdAt
        record["notes"] = recording.notes

        // Creator attribution
        record["creatorId"] = currentUserId
        record["creatorDisplayName"] = currentUserName

        // Location sharing (opt-in)
        record["locationSharingMode"] = locationMode.rawValue
        if locationMode != .none, let lat = recording.latitude, let lon = recording.longitude {
            if let approx = SharedRecordingItem.approximateLocation(latitude: lat, longitude: lon, mode: locationMode) {
                record["sharedLatitude"] = approx.latitude
                record["sharedLongitude"] = approx.longitude
                record["sharedPlaceName"] = recording.locationLabel
            }
        }

        // Download permission (default: off — creator must opt-in)
        record["allowDownload"] = false

        // Verification status
        record["isVerified"] = recording.hasProof
        record["verifiedAt"] = recording.proofCloudCreatedAt

        // Add audio as CKAsset
        if FileManager.default.fileExists(atPath: recording.fileURL.path) {
            let asset = CKAsset(fileURL: recording.fileURL)
            record["audioFile"] = asset
        }

        do {
            try await saveWithRetry(record, to: db)

            // Log activity
            let event = SharedAlbumActivityEvent.recordingAdded(
                albumId: album.id,
                actorId: currentUserId,
                actorDisplayName: currentUserName,
                recordingId: recording.id,
                recordingTitle: recording.title
            )
            try? await logActivity(event: event, for: album)

            logger.info("Added recording to shared album")
        } catch where isZoneOrShareDeletedError(error) {
            handleZoneNotFound(for: album)
            throw SharedAlbumError.shareNoLongerExists
        } catch {
            logger.error("Failed to add recording to shared album: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Delete a recording from a shared album
    func deleteRecordingFromSharedAlbum(recordingId: UUID, album: Album) async throws {
        guard album.isShared else { return }

        // Check permission: only owner/admin can delete any recording
        guard album.canDeleteAnyRecording else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Deleting recording from shared album: \(recordingId, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordID = CKRecord.ID(recordName: recordingId.uuidString, zoneID: zoneID)
            try await db.modifyRecords(saving: [], deleting: [recordID])
            logger.info("Deleted recording from shared album")
        } catch {
            logger.error("Failed to delete recording from shared album: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Fetch shared recording info for all recordings in a shared album
    func fetchSharedRecordingInfo(for album: Album) async -> [UUID: SharedRecordingItem] {
        guard album.isShared else { return [:] }

        logger.info("Fetching shared recording info for album: \(album.id, privacy: .private)")

        let predicate = NSPredicate(value: true)
        let query = CKQuery(recordType: "SharedRecording", predicate: predicate)

        var result: [UUID: SharedRecordingItem] = [:]

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let records = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: 500)

            for (_, recordResult) in records.matchResults {
                if case .success(let record) = recordResult {
                    guard let recordingId = UUID(uuidString: record.recordID.recordName) else {
                        continue
                    }

                    let sharedInfo = SharedRecordingItem(
                        id: UUID(),
                        recordingId: recordingId,
                        albumId: album.id,
                        creatorId: record["creatorId"] as? String ?? "unknown",
                        creatorDisplayName: record["creatorDisplayName"] as? String ?? "Unknown",
                        createdAt: record["createdAt"] as? Date ?? Date(),
                        wasImported: record["wasImported"] as? Bool ?? false,
                        recordedWithHeadphones: record["recordedWithHeadphones"] as? Bool ?? false,
                        isSensitive: record["isSensitive"] as? Bool ?? false,
                        sensitiveApproved: record["sensitiveApproved"] as? Bool ?? false,
                        sensitiveApprovedBy: record["sensitiveApprovedBy"] as? String,
                        sensitiveApprovedAt: record["sensitiveApprovedAt"] as? Date,
                        allowDownload: record["allowDownload"] as? Bool ?? false,
                        locationSharingMode: LocationSharingMode(rawValue: record["locationSharingMode"] as? String ?? "none") ?? .none,
                        sharedLatitude: record["sharedLatitude"] as? Double,
                        sharedLongitude: record["sharedLongitude"] as? Double,
                        sharedPlaceName: record["sharedPlaceName"] as? String,
                        isVerified: record["isVerified"] as? Bool ?? false,
                        verifiedAt: record["verifiedAt"] as? Date
                    )

                    result[recordingId] = sharedInfo
                }
            }

            logger.info("Fetched \(result.count) shared recording info items")
        } catch where isZoneOrShareDeletedError(error) {
            logger.warning("Shared album zone/share no longer exists during recording info fetch: \(error.localizedDescription)")
            handleZoneNotFound(for: album)
            return [:]
        } catch {
            logger.error("Failed to fetch shared recording info: \(error.localizedDescription)")
        }

        return result
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

            // Fetch stored roles from CloudKit
            let storedRoles = await fetchStoredParticipantRoles(for: album)

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

                let participantId = participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString
                let displayName = participant.userIdentity.nameComponents?.formatted() ?? "Participant"
                let storedRole = storedRoles[participantId] ?? .member
                let p = SharedAlbumParticipant(
                    id: participantId,
                    displayName: displayName,
                    role: storedRole,
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

    /// Resolve the current user's role in a shared album by checking the CKShare participants.
    /// Returns the updated album with `currentUserRole` populated, or the original album if resolution fails.
    func resolveCurrentUserRole(for album: Album) async -> Album {
        guard album.isShared else { return album }

        // Owner always gets admin
        if album.isOwner {
            var updated = album
            updated.currentUserRole = .admin
            return updated
        }

        do {
            guard let share = try await getShare(for: album) else {
                return album
            }

            // Get current user's CloudKit record ID
            guard let currentUserId = await getCurrentUserId() else {
                return album
            }

            // Check if current user is the share owner
            if share.owner.userIdentity.userRecordID?.recordName == currentUserId {
                var updated = album
                updated.currentUserRole = .admin
                return updated
            }

            // Fetch stored custom roles
            let storedRoles = await fetchStoredParticipantRoles(for: album)

            // Find current user in participants
            for participant in share.participants where participant.role != .owner {
                if participant.userIdentity.userRecordID?.recordName == currentUserId {
                    let role = storedRoles[currentUserId] ?? .member
                    var updated = album
                    updated.currentUserRole = role
                    return updated
                }
            }
        } catch {
            logger.error("Failed to resolve current user role: \(error.localizedDescription)")
        }

        return album
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

        logger.info("Changing role for participant \(participantId, privacy: .private) to \(newRole.rawValue)")
        isProcessing = true
        defer { isProcessing = false }

        // Store the role in a CloudKit record so it persists across devices
        let (db, zoneID) = try await databaseAndZone(for: album)
        let roleRecordID = CKRecord.ID(recordName: "role-\(participantId)", zoneID: zoneID)

        let record: CKRecord
        do {
            record = try await db.record(for: roleRecordID)
        } catch {
            record = CKRecord(recordType: "SharedAlbumParticipantRole", recordID: roleRecordID)
        }

        record["participantId"] = participantId
        record["role"] = newRole.rawValue

        do {
            try await saveWithRetry(record, to: db)
            logger.info("Saved participant role to CloudKit")
        } catch where isZoneOrShareDeletedError(error) {
            handleZoneNotFound(for: album)
            throw SharedAlbumError.shareNoLongerExists
        } catch {
            logger.error("Failed to save participant role: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }

        // Update CKShare participant permission to match role
        if let share = try await getShare(for: album) {
            for participant in share.participants {
                if participant.userIdentity.userRecordID?.recordName == participantId {
                    let permission: CKShare.ParticipantPermission = newRole == .viewer ? .readOnly : .readWrite
                    participant.permission = permission
                    break
                }
            }
            do {
                let (shareDb, _) = try await databaseAndZone(for: album)
                try await shareDb.save(share)
                logger.info("Updated CKShare participant permission")
            } catch {
                // CKShare save failed — revert the role record to prevent permission escalation
                // (role record says "viewer" but CKShare may still grant readWrite, or vice versa)
                logger.error("Failed to update CKShare permission: \(error.localizedDescription). Reverting role record.")
                do {
                    let revertRecord = try await db.record(for: roleRecordID)
                    // Delete the role record we just saved so it doesn't conflict with the CKShare state
                    try await db.deleteRecord(withID: revertRecord.recordID)
                    logger.info("Reverted role record after CKShare save failure")
                } catch {
                    logger.error("Failed to revert role record: \(error.localizedDescription)")
                }
                throw SharedAlbumError.networkError(error)
            }
        }

        // Log activity
        if let currentUserId = await getCurrentUserId() {
            let currentDisplayName = await getCurrentUserDisplayName()
            let event = SharedAlbumActivityEvent(
                albumId: album.id,
                actorId: currentUserId,
                actorDisplayName: currentDisplayName,
                eventType: .participantRoleChanged,
                targetParticipantId: participantId,
                newValue: newRole.displayName
            )
            try? await logActivity(event: event, for: album)
        }
    }

    /// Remove a participant from the album (admin only)
    func removeParticipant(album: Album, participantId: String) async throws {
        guard album.isShared && album.canManageParticipants else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Removing participant \(participantId, privacy: .private) from album: \(album.name, privacy: .private)")
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

            // Remove the participant's recordings from the shared album
            try? await removeUserRecordings(userId: participantId, album: album)

            // Clean up orphaned role record
            let (db, zoneID) = try await databaseAndZone(for: album)
            let roleRecordID = CKRecord.ID(recordName: "role-\(participantId)", zoneID: zoneID)
            try? await db.deleteRecord(withID: roleRecordID)

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let currentDisplayName = await getCurrentUserDisplayName()
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
                    eventType: .participantRemoved,
                    targetParticipantId: participantId
                )
                try? await logActivity(event: event, for: album)
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

        logger.info("Moving recording to shared album trash: \(localRecording.title, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        // Create trash item
        let trashItem = SharedAlbumTrashItem.from(
            sharedRecording: recording,
            recording: localRecording,
            deletedBy: deletedBy,
            deletedByDisplayName: deletedByDisplayName
        )

        do {
            // Store in CloudKit trash zone
            let (db, zoneID) = try await databaseAndZone(for: album)
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

            // Fetch original recording to copy the audio CKAsset before deleting
            let recordingRecordID = CKRecord.ID(recordName: localRecording.id.uuidString, zoneID: zoneID)
            do {
                let originalRecord = try await db.record(for: recordingRecordID)
                if let audioAsset = originalRecord["audioFile"] as? CKAsset {
                    trashRecord["audioFile"] = audioAsset
                }
            } catch {
                logger.warning("Could not fetch original recording to copy audio asset: \(error.localizedDescription)")
                // Continue without audio — metadata is still preserved in trash
            }

            // Save trash record and delete original
            try await db.modifyRecords(saving: [trashRecord], deleting: [recordingRecordID])

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

        logger.info("Restoring recording from trash: \(trashItem.title, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)

            // Recreate the recording record
            let recordID = CKRecord.ID(recordName: trashItem.recordingId.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: "SharedRecording", recordID: recordID)

            record["title"] = trashItem.title
            record["duration"] = trashItem.duration
            record["createdAt"] = trashItem.originalCreatedAt
            record["creatorId"] = trashItem.creatorId
            record["creatorDisplayName"] = trashItem.creatorDisplayName

            // Restore audio: first try the CKAsset stored on the trash CKRecord,
            // then fall back to local audioAssetReference path
            let trashRecordID = CKRecord.ID(recordName: "trash-\(trashItem.id.uuidString)", zoneID: zoneID)
            do {
                let trashCKRecord = try await db.record(for: trashRecordID)
                if let audioAsset = trashCKRecord["audioFile"] as? CKAsset {
                    record["audioFile"] = audioAsset
                }
            } catch {
                logger.warning("Could not fetch trash CKRecord to restore audio: \(error.localizedDescription)")
            }
            // Fallback: local file path from audioAssetReference
            if record["audioFile"] == nil, let audioRef = trashItem.audioAssetReference {
                let audioURL = URL(fileURLWithPath: audioRef)
                if FileManager.default.fileExists(atPath: audioURL.path) {
                    record["audioFile"] = CKAsset(fileURL: audioURL)
                }
            }

            try await db.modifyRecords(saving: [record], deleting: [trashRecordID])

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let currentDisplayName = await getCurrentUserDisplayName()
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
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

        logger.info("Permanently deleting: \(trashItem.title, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let trashRecordID = CKRecord.ID(recordName: "trash-\(trashItem.id.uuidString)", zoneID: zoneID)
            try await db.modifyRecords(saving: [], deleting: [trashRecordID])
            logger.info("Permanently deleted trash item")
        } catch {
            logger.error("Failed to permanently delete: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Fetch all trash items for an album
    func fetchTrashItems(for album: Album) async -> [SharedAlbumTrashItem] {
        guard album.isShared else { return [] }

        let query = CKQuery(recordType: "SharedAlbumTrash", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "deletedAt", ascending: false)]

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)

            var trashItems: [SharedAlbumTrashItem] = []
            for (_, result) in results {
                if case .success(let record) = result {
                    if let item = parseTrashRecord(record) {
                        trashItems.append(item)
                    }
                }
            }
            return trashItems
        } catch where isZoneOrShareDeletedError(error) {
            logger.warning("Shared album zone/share no longer exists during trash fetch: \(error.localizedDescription)")
            handleZoneNotFound(for: album)
            return []
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

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordIDsToDelete = itemsToPurge.map { item in
                CKRecord.ID(recordName: "trash-\(item.id.uuidString)", zoneID: zoneID)
            }
            try await db.modifyRecords(saving: [], deleting: recordIDsToDelete)
            logger.info("Purged expired trash items successfully")
        } catch where isZoneOrShareDeletedError(error) {
            logger.warning("Shared album zone/share no longer exists during trash purge: \(error.localizedDescription)")
            handleZoneNotFound(for: album)
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

        let trashIdString = record.recordID.recordName.replacingOccurrences(of: "trash-", with: "")
        guard let trashItemId = UUID(uuidString: trashIdString) else { return nil }

        return SharedAlbumTrashItem(
            id: trashItemId,
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

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
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

            try await db.save(record)
            logger.debug("Logged activity: \(event.eventType.rawValue)")
        } catch {
            logger.error("Failed to log activity: \(error.localizedDescription)")
            // Don't throw - activity logging is non-critical
        }
    }

    /// Fetch activity feed for an album
    func fetchActivityFeed(for album: Album, limit: Int = 50) async -> [SharedAlbumActivityEvent] {
        guard album.isShared else { return [] }

        let query = CKQuery(recordType: "SharedAlbumActivity", predicate: NSPredicate(value: true))
        query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: limit)

            var events: [SharedAlbumActivityEvent] = []
            for (_, result) in results {
                if case .success(let record) = result {
                    if let event = parseActivityRecord(record, albumId: album.id) {
                        events.append(event)
                    }
                }
            }
            return events
        } catch where isZoneOrShareDeletedError(error) {
            logger.warning("Shared album zone/share no longer exists during activity fetch: \(error.localizedDescription)")
            handleZoneNotFound(for: album)
            return []
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

        let activityIdString = record.recordID.recordName.replacingOccurrences(of: "activity-", with: "")
        guard let activityId = UUID(uuidString: activityIdString) else { return nil }

        return SharedAlbumActivityEvent(
            id: activityId,
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

    // MARK: - Comments

    /// Add a comment to a shared album recording
    func addComment(recordingId: UUID, recordingTitle: String, album: Album, text: String) async throws -> SharedAlbumComment {
        guard album.isShared else { throw SharedAlbumError.permissionDenied }
        guard text.count <= 500 else { throw SharedAlbumError.commentTooLong }

        let (db, zoneID) = try await databaseAndZone(for: album)
        let userId = await getCurrentUserId() ?? "unknown"
        let displayName = await getCurrentUserDisplayName()

        let comment = SharedAlbumComment(
            recordingId: recordingId,
            authorId: userId,
            authorDisplayName: displayName,
            text: text
        )

        let recordID = CKRecord.ID(recordName: "comment-\(comment.id.uuidString)", zoneID: zoneID)
        let record = CKRecord(recordType: "SharedAlbumComment", recordID: recordID)
        record["recordingId"] = recordingId.uuidString
        record["authorId"] = comment.authorId
        record["authorDisplayName"] = comment.authorDisplayName
        record["text"] = comment.text
        record["createdAt"] = comment.createdAt

        try await db.save(record)
        logger.debug("Added comment on recording \(recordingId)")

        // Log activity (non-critical)
        let event = SharedAlbumActivityEvent(
            albumId: album.id,
            actorId: userId,
            actorDisplayName: displayName,
            eventType: .commentAdded,
            targetRecordingId: recordingId,
            targetRecordingTitle: recordingTitle,
            newValue: text
        )
        try? await logActivity(event: event, for: album)

        return comment
    }

    /// Fetch comments for a recording in a shared album
    func fetchComments(for recordingId: UUID, album: Album) async -> [SharedAlbumComment] {
        guard album.isShared else { return [] }

        let predicate = NSPredicate(format: "recordingId == %@", recordingId.uuidString)
        let query = CKQuery(recordType: "SharedAlbumComment", predicate: predicate)
        query.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: 100)

            var comments: [SharedAlbumComment] = []
            for (_, result) in results {
                if case .success(let record) = result,
                   let comment = parseCommentRecord(record) {
                    comments.append(comment)
                }
            }
            return comments.sorted { $0.createdAt < $1.createdAt }
        } catch where isZoneOrShareDeletedError(error) {
            logger.warning("Shared album zone/share no longer exists during comments fetch: \(error.localizedDescription)")
            handleZoneNotFound(for: album)
            return []
        } catch {
            logger.error("Failed to fetch comments: \(error.localizedDescription)")
            return []
        }
    }

    /// Delete own comment
    func deleteComment(commentId: UUID, album: Album) async throws {
        guard album.isShared else { throw SharedAlbumError.permissionDenied }

        let (db, zoneID) = try await databaseAndZone(for: album)
        let recordID = CKRecord.ID(recordName: "comment-\(commentId.uuidString)", zoneID: zoneID)

        // Verify the current user is the comment author before deleting
        guard let currentUserId = await getCurrentUserId() else {
            throw SharedAlbumError.notSignedIn
        }
        let record = try await db.record(for: recordID)
        let commentAuthorId = record["authorId"] as? String
        guard commentAuthorId == currentUserId else {
            logger.warning("User \(currentUserId, privacy: .private) attempted to delete comment authored by \(commentAuthorId ?? "unknown", privacy: .private)")
            throw SharedAlbumError.permissionDenied
        }

        try await db.deleteRecord(withID: recordID)
        logger.debug("Deleted comment \(commentId)")
    }

    private func parseCommentRecord(_ record: CKRecord) -> SharedAlbumComment? {
        guard let recordingIdStr = record["recordingId"] as? String,
              let recordingId = UUID(uuidString: recordingIdStr),
              let authorId = record["authorId"] as? String,
              let authorDisplayName = record["authorDisplayName"] as? String,
              let text = record["text"] as? String,
              let createdAt = record["createdAt"] as? Date else {
            return nil
        }

        let idString = record.recordID.recordName.replacingOccurrences(of: "comment-", with: "")
        guard let commentId = UUID(uuidString: idString) else { return nil }

        return SharedAlbumComment(
            id: commentId,
            recordingId: recordingId,
            authorId: authorId,
            authorDisplayName: authorDisplayName,
            text: text,
            createdAt: createdAt
        )
    }

    // MARK: - Settings Management

    /// Update album settings
    func updateAlbumSettings(album: Album, settings: SharedAlbumSettings) async throws {
        guard album.isShared && album.canEditSettings else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Updating settings for album: \(album.name, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        let (db, zoneID) = try await databaseAndZone(for: album)
        let settingsRecordID = CKRecord.ID(recordName: "settings-\(album.id.uuidString)", zoneID: zoneID)

        // Try to fetch existing settings record or create new one
        let record: CKRecord
        do {
            record = try await db.record(for: settingsRecordID)
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
            try await saveWithRetry(record, to: db)
            logger.info("Updated album settings successfully")
        } catch where isZoneOrShareDeletedError(error) {
            handleZoneNotFound(for: album)
            throw SharedAlbumError.shareNoLongerExists
        } catch {
            logger.error("Failed to update settings: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    /// Fetch album settings
    func fetchAlbumSettings(for album: Album) async -> SharedAlbumSettings? {
        guard album.isShared else { return nil }

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let settingsRecordID = CKRecord.ID(recordName: "settings-\(album.id.uuidString)", zoneID: zoneID)
            let record = try await db.record(for: settingsRecordID)
            return parseSettingsRecord(record)
        } catch where isZoneOrShareDeletedError(error) {
            logger.warning("Shared album zone/share no longer exists during settings fetch: \(error.localizedDescription)")
            handleZoneNotFound(for: album)
            return nil
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

        // Only the recording creator can change location sharing
        let currentUserId = await getCurrentUserId()
        guard recording.creatorId == currentUserId else {
            throw SharedAlbumError.permissionDenied
        }

        // Check if user can share location
        if mode != .none {
            guard album.sharedSettings?.allowMembersToShareLocation ?? true else {
                throw SharedAlbumError.permissionDenied
            }
        }

        logger.info("Updating location sharing to \(mode.rawValue) for recording")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordID = CKRecord.ID(recordName: recording.recordingId.uuidString, zoneID: zoneID)

            let record = try await db.record(for: recordID)

            record["locationSharingMode"] = mode.rawValue

            if mode != .none, let lat = latitude, let lon = longitude,
               let approx = SharedRecordingItem.approximateLocation(latitude: lat, longitude: lon, mode: mode) {
                record["sharedLatitude"] = approx.latitude
                record["sharedLongitude"] = approx.longitude
                record["sharedPlaceName"] = placeName
            } else {
                record["sharedLatitude"] = nil
                record["sharedLongitude"] = nil
                record["sharedPlaceName"] = nil
            }

            try await withRateLimitRetry {
                try await self.saveWithRetry(record, to: db)
            }

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let currentDisplayName = await getCurrentUserDisplayName()
                let eventType: ActivityEventType = mode == .none ? .locationDisabled : .locationEnabled
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
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

        // Only the recording creator or album admin can mark as sensitive
        let currentUserId = await getCurrentUserId()
        guard recording.creatorId == currentUserId || album.currentUserRole == .admin else {
            throw SharedAlbumError.permissionDenied
        }

        logger.info("Marking recording as sensitive: \(isSensitive)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordID = CKRecord.ID(recordName: recording.recordingId.uuidString, zoneID: zoneID)

            let record = try await db.record(for: recordID)
            record["isSensitive"] = isSensitive
            record["sensitiveApproved"] = false
            record["sensitiveApprovedBy"] = nil

            try await withRateLimitRetry {
                try await self.saveWithRetry(record, to: db)
            }

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let currentDisplayName = await getCurrentUserDisplayName()
                let eventType: ActivityEventType = isSensitive ? .recordingMarkedSensitive : .recordingUnmarkedSensitive
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
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

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordID = CKRecord.ID(recordName: recording.recordingId.uuidString, zoneID: zoneID)

            let record = try await db.record(for: recordID)

            if let currentUserId = await getCurrentUserId() {
                let currentDisplayName = await getCurrentUserDisplayName()
                record["sensitiveApproved"] = approved
                record["sensitiveApprovedBy"] = approved ? currentUserId : nil
                record["sensitiveApprovedAt"] = approved ? Date() : nil

                try await saveWithRetry(record, to: db)

                // Log activity
                let eventType: ActivityEventType = approved ? .sensitiveRecordingApproved : .sensitiveRecordingRejected
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
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

    // MARK: - Album Rename

    /// Rename a shared album in CloudKit and update the CKShare title
    func renameSharedAlbum(_ album: Album, oldName: String, newName: String) async throws {
        guard album.isShared && album.isOwner else {
            throw SharedAlbumError.notOwner
        }

        logger.info("Renaming shared album from \"\(oldName, privacy: .private)\" to \"\(newName, privacy: .private)\"")
        isProcessing = true
        defer { isProcessing = false }

        let (db, zoneID) = try await databaseAndZone(for: album)
        let recordID = CKRecord.ID(recordName: album.id.uuidString, zoneID: zoneID)

        do {
            // Update the SharedAlbum record's name field
            let record = try await db.record(for: recordID)
            record["name"] = newName
            try await saveWithRetry(record, to: db)

            // Update CKShare title so share metadata reflects the new name
            if let share = try await getShare(for: album) {
                share[CKShare.SystemFieldKey.title] = newName
                try await privateDatabase.save(share)
            }

            // Log activity
            let currentUserId = await getCurrentUserId() ?? "unknown"
            let currentDisplayName = await getCurrentUserDisplayName()
            let event = SharedAlbumActivityEvent(
                albumId: album.id,
                actorId: currentUserId,
                actorDisplayName: currentDisplayName,
                eventType: .albumRenamed,
                oldValue: oldName,
                newValue: newName
            )
            try? await logActivity(event: event, for: album)

            logger.info("Renamed shared album successfully")
        } catch {
            logger.error("Failed to rename shared album: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    // MARK: - User Recording Cleanup (Leave/Remove)

    /// Remove all SharedRecording CKRecords created by a specific user from a shared album.
    /// Used when a user leaves or is removed — their local files are untouched.
    func removeUserRecordings(userId: String, album: Album) async throws {
        guard album.isShared else { return }

        logger.info("Removing recordings by user \(userId, privacy: .private) from album \(album.name, privacy: .private)")

        let predicate = NSPredicate(format: "creatorId == %@", userId)
        let query = CKQuery(recordType: "SharedRecording", predicate: predicate)

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID, resultsLimit: 500)

            var recordIDsToDelete: [CKRecord.ID] = []
            for (recordID, result) in results {
                if case .success = result {
                    recordIDsToDelete.append(recordID)
                }
            }

            guard !recordIDsToDelete.isEmpty else {
                logger.info("No recordings found for user \(userId, privacy: .private) in album \(album.name, privacy: .private)")
                return
            }

            try await db.modifyRecords(saving: [], deleting: recordIDsToDelete)
            logger.info("Removed \(recordIDsToDelete.count) recordings by user \(userId, privacy: .private)")

            // Log activity for each deletion
            let currentUserId = await getCurrentUserId() ?? userId
            let currentDisplayName = await getCurrentUserDisplayName()
            for recordID in recordIDsToDelete {
                let event = SharedAlbumActivityEvent.recordingDeleted(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
                    recordingId: UUID(uuidString: recordID.recordName) ?? UUID(),
                    recordingTitle: "(removed with participant)"
                )
                try? await logActivity(event: event, for: album)
            }
        } catch {
            logger.error("Failed to remove user recordings: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    // MARK: - Download Permission Toggle

    /// Toggle the allowDownload flag on a shared recording (creator only)
    func toggleDownloadPermission(recordingId: UUID, album: Album, allow: Bool) async throws {
        guard album.isShared else { return }

        logger.info("Setting allowDownload=\(allow) for recording \(recordingId, privacy: .private)")
        isProcessing = true
        defer { isProcessing = false }

        do {
            // Verify the current user is the recording creator
            guard let currentUserId = await getCurrentUserId() else {
                throw SharedAlbumError.notSignedIn
            }

            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordID = CKRecord.ID(recordName: recordingId.uuidString, zoneID: zoneID)
            let record = try await db.record(for: recordID)

            let recordCreatorId = record["creatorId"] as? String
            guard recordCreatorId == currentUserId else {
                logger.warning("User \(currentUserId, privacy: .private) attempted to toggle download permission on recording owned by \(recordCreatorId ?? "unknown", privacy: .private)")
                throw SharedAlbumError.permissionDenied
            }

            record["allowDownload"] = allow
            try await withRateLimitRetry {
                try await self.saveWithRetry(record, to: db)
            }

            // Log activity
            if let currentUserId = await getCurrentUserId() {
                let currentDisplayName = await getCurrentUserDisplayName()
                let eventType: ActivityEventType = allow ? .recordingDownloadEnabled : .recordingDownloadDisabled
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: currentDisplayName,
                    eventType: eventType,
                    targetRecordingId: recordingId
                )
                try await logActivity(event: event, for: album)
            }

            logger.info("Updated download permission successfully")
        } catch {
            logger.error("Failed to toggle download permission: \(error.localizedDescription)")
            throw SharedAlbumError.networkError(error)
        }
    }

    // MARK: - Audio Asset Download

    /// Download audio for a shared recording from CloudKit
    /// Returns a local file URL where the audio has been cached
    func fetchRecordingAudio(recordingId: UUID, album: Album, sharedInfo: SharedRecordingItem? = nil) async throws -> URL {
        let currentUserId = await getCurrentUserId() ?? ""

        // Check download permission: if not the creator and downloads are disabled, block
        if let info = sharedInfo {
            if info.creatorId != currentUserId && !info.allowDownload {
                throw SharedAlbumError.downloadNotAllowed
            }
        } else if album.isShared {
            // sharedInfo is nil — attempt to fetch the recording info from CloudKit before denying
            logger.info("fetchRecordingAudio called for shared album without sharedInfo — fetching from CloudKit")
            let (db, zoneID) = try await databaseAndZone(for: album)
            let recordID = CKRecord.ID(recordName: recordingId.uuidString, zoneID: zoneID)
            let record = try await db.record(for: recordID)
            let recordCreatorId = record["creatorId"] as? String ?? ""
            let allowDownload = record["allowDownload"] as? Bool ?? false
            if recordCreatorId != currentUserId && !allowDownload {
                throw SharedAlbumError.downloadNotAllowed
            }
        }

        // Check local cache first
        let cacheDir = sharedAlbumCacheDirectory(albumId: album.id)
        let cachedFile = cacheDir.appendingPathComponent("\(recordingId.uuidString).m4a")
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            // Membership validation for cached audio: if album is shared and user is not owner,
            // verify the album still has valid shared status before serving cached file
            if album.isShared && !album.isOwner {
                let sharedInfoMap = await fetchSharedRecordingInfo(for: album)
                if sharedInfoMap[recordingId] == nil {
                    // No valid shared info — user may no longer have access
                    try? FileManager.default.removeItem(at: cachedFile)
                    throw SharedAlbumError.permissionDenied
                }
            }
            return cachedFile
        }

        // Fetch from CloudKit using correct database for owner vs non-owner
        let (db, zoneID) = try await databaseAndZone(for: album)
        let recordID = CKRecord.ID(recordName: recordingId.uuidString, zoneID: zoneID)
        let record = try await db.record(for: recordID)

        guard let asset = record["audioFile"] as? CKAsset,
              let assetURL = asset.fileURL else {
            throw SharedAlbumError.downloadFailed
        }

        // Check file size before copying (max 200MB)
        let maxDownloadSize: Int64 = 200 * 1024 * 1024
        if let assetAttributes = try? FileManager.default.attributesOfItem(atPath: assetURL.path),
           let assetSize = assetAttributes[.size] as? Int64,
           assetSize > maxDownloadSize {
            throw SharedAlbumError.fileTooLarge
        }

        // Copy asset to local cache
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: cachedFile.path) {
            try FileManager.default.removeItem(at: cachedFile)
        }
        try FileManager.default.copyItem(at: assetURL, to: cachedFile)

        // Validate the downloaded file is not empty
        let attributes = try FileManager.default.attributesOfItem(atPath: cachedFile.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        if fileSize == 0 {
            try? FileManager.default.removeItem(at: cachedFile)
            throw SharedAlbumError.recordingNotFound
        }

        logger.info("Downloaded shared recording audio to cache: \(recordingId, privacy: .private)")
        return cachedFile
    }

    /// Get the cache directory for a shared album's audio files
    private func sharedAlbumCacheDirectory(albumId: UUID) -> URL {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("SharedAlbumAudio/\(albumId.uuidString)", isDirectory: true) }
        return caches.appendingPathComponent("SharedAlbumAudio/\(albumId.uuidString)", isDirectory: true)
    }

    // MARK: - Helper Methods

    /// Get current user's CloudKit ID
    func getCurrentUserId() async -> String? {
        // Return cached value if available
        if let cached = cachedCurrentUserId {
            return cached
        }

        do {
            let userRecordID = try await container.userRecordID()
            let userId = userRecordID.recordName
            cachedCurrentUserId = userId
            return userId
        } catch {
            logger.error("Failed to get current user ID: \(error.localizedDescription)")
            return nil
        }
    }

    /// Refresh the cached user ID (call on app launch or when needed)
    func refreshCachedUserId() async {
        cachedCurrentUserId = nil
        _ = await getCurrentUserId()
    }

    /// Fetch stored participant roles from CloudKit
    private func fetchStoredParticipantRoles(for album: Album) async -> [String: ParticipantRole] {
        let query = CKQuery(recordType: "SharedAlbumParticipantRole", predicate: NSPredicate(value: true))

        var roles: [String: ParticipantRole] = [:]

        do {
            let (db, zoneID) = try await databaseAndZone(for: album)
            let (results, _) = try await db.records(matching: query, inZoneWith: zoneID)
            for (_, result) in results {
                if case .success(let record) = result,
                   let participantId = record["participantId"] as? String,
                   let roleRaw = record["role"] as? String,
                   let role = ParticipantRole(rawValue: roleRaw) {
                    roles[participantId] = role
                }
            }
        } catch {
            logger.error("Failed to fetch stored roles: \(error.localizedDescription)")
        }

        return roles
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

    // MARK: - Real-Time Sync (CKDatabaseSubscription)

    /// Subscribe to changes in the private and shared databases for shared album zones
    func setupDatabaseSubscriptions() async {
        logger.info("Setting up database subscriptions for shared albums")

        // Subscribe to private database changes (owner sees participant changes)
        await subscribeToDatabase(privateDatabase, subscriptionID: "private-shared-albums")

        // Subscribe to shared database changes (participants see owner/other changes)
        await subscribeToDatabase(sharedDatabase, subscriptionID: "shared-shared-albums")
    }

    private let subscriptionCreatedKeyPrefix = "sharedAlbum_subscriptionCreated_"

    private func subscribeToDatabase(_ database: CKDatabase, subscriptionID: String) async {
        let subscriptionCreatedKey = "\(subscriptionCreatedKeyPrefix)\(subscriptionID)"

        // Skip if already successfully created
        if UserDefaults.standard.bool(forKey: subscriptionCreatedKey) {
            logger.debug("Subscription already marked as created: \(subscriptionID)")
            return
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            try await database.save(subscription)
            // Only mark as created when the save actually succeeds
            UserDefaults.standard.set(true, forKey: subscriptionCreatedKey)
            logger.info("Subscribed to database: \(subscriptionID)")
        } catch {
            // Subscription may already exist — that's fine
            if let ckError = error as? CKError, ckError.code == .serverRejectedRequest {
                logger.debug("Subscription already exists: \(subscriptionID)")
                UserDefaults.standard.set(true, forKey: subscriptionCreatedKey)
            } else {
                // Do NOT set subscriptionCreatedKey to true for other errors
                logger.error("Failed to subscribe to \(subscriptionID): \(error.localizedDescription)")
            }
        }
    }

    /// Handle a remote notification push (called from AppDelegate)
    func handleRemoteNotification() async {
        logger.info("Handling remote notification for shared albums")

        // Refresh all shared album data
        guard let appState = appState else { return }
        let sharedAlbums = appState.albums.filter { $0.isShared }

        for album in sharedAlbums {
            // Check if album was removed from local state (e.g., by a prior iteration's cleanup)
            guard appState.albums.contains(where: { $0.id == album.id }) else {
                logger.info("Skipping album that was removed during notification handling: \(album.name, privacy: .private)")
                continue
            }

            // Refresh recordings
            let sharedInfos = await fetchSharedRecordingInfo(for: album)

            // If the album was cleaned up by handleZoneNotFound during fetch, skip remaining work
            guard appState.albums.contains(where: { $0.id == album.id }) else {
                continue
            }

            for (id, info) in sharedInfos {
                appState.sharedRecordingInfoCache[id] = info
            }

            // Refresh activity
            _ = await fetchActivityFeed(for: album)

            // Purge expired trash
            try? await purgeExpiredTrashItems(for: album)
        }

        logger.info("Finished handling remote notification")
    }

    // MARK: - Network Monitor & Offline Queue

    private func startNetworkMonitor() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self else { return }
                let wasOffline = !self.isOnline
                self.isOnline = isSatisfied

                if wasOffline && isSatisfied {
                    self.logger.info("Network restored — retrying pending operations")
                    await self.retryPendingOperations()
                }
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }

    /// Queue a failed operation for retry when network returns
    func queuePendingOperation(type: String, albumId: UUID, recordingId: UUID? = nil, payload: [String: String] = [:]) {
        let op = PendingOperation(
            id: UUID(),
            operationType: type,
            albumId: albumId,
            recordingId: recordingId,
            payload: payload,
            createdAt: Date()
        )
        pendingOperations.append(op)
        savePendingOperations()
        logger.info("Queued pending operation: \(type)")
    }

    /// Retry all pending operations
    private func retryPendingOperations() async {
        guard !pendingOperations.isEmpty else { return }

        // Filter out operations older than 7 days (TTL)
        let ttlSeconds: TimeInterval = 7 * 24 * 3600
        let validOps = pendingOperations.filter { $0.createdAt.timeIntervalSinceNow > -ttlSeconds }
        let expiredCount = pendingOperations.count - validOps.count
        if expiredCount > 0 {
            logger.info("Dropping \(expiredCount) expired pending operations (older than 7 days)")
        }

        // Replace pendingOperations with only the valid (non-expired) ops.
        // Each operation is removed individually only after it succeeds.
        pendingOperations = validOps
        savePendingOperations()

        // Iterate over a snapshot; mutate pendingOperations as each op resolves
        let opsToRetry = validOps

        for op in opsToRetry {
            guard let appState = appState else { break }
            guard let album = appState.albums.first(where: { $0.id == op.albumId }) else { continue }

            do {
                switch op.operationType {
                case "addRecording":
                    if let recordingId = op.recordingId,
                       let recording = appState.recordings.first(where: { $0.id == recordingId }) {
                        let mode = LocationSharingMode(rawValue: op.payload["locationMode"] ?? "none") ?? .none
                        try await addRecordingToSharedAlbum(recording: recording, album: album, locationMode: mode)
                    }
                case "deleteRecording":
                    if let recordingId = op.recordingId {
                        try await deleteRecordingFromSharedAlbum(recordingId: recordingId, album: album)
                    }
                case "updateSettings":
                    if let settingsData = op.payload["settings"]?.data(using: .utf8),
                       let settings = try? JSONDecoder().decode(SharedAlbumSettings.self, from: settingsData) {
                        try await updateAlbumSettings(album: album, settings: settings)
                    }
                case "renameAlbum":
                    if let oldName = op.payload["oldName"],
                       let newName = op.payload["newName"] {
                        try await renameSharedAlbum(album, oldName: oldName, newName: newName)
                    }
                default:
                    logger.warning("Unknown pending operation type: \(op.operationType)")
                }

                // Success — remove this operation from the persisted queue
                pendingOperations.removeAll { $0.id == op.id }
                savePendingOperations()
                logger.info("Retried pending operation: \(op.operationType)")
            } catch where isZoneOrShareDeletedError(error) {
                // Zone/share deleted — drop the operation immediately and clean up
                logger.warning("Zone/share deleted during retry of \(op.operationType) — dropping operation and cleaning up album")
                pendingOperations.removeAll { $0.id == op.id }
                savePendingOperations()
                handleZoneNotFound(for: album)
            } catch {
                // Re-queue with incremented retry count, or drop if max retries exceeded
                if let idx = pendingOperations.firstIndex(where: { $0.id == op.id }) {
                    pendingOperations[idx].retryCount += 1
                    if pendingOperations[idx].retryCount >= self.maxRetryCount {
                        logger.error("Dropping operation \(op.operationType) after \(self.maxRetryCount) retries")
                        pendingOperations.remove(at: idx)
                    } else {
                        logger.error("Retry \(self.pendingOperations[idx].retryCount)/\(self.maxRetryCount) failed for \(op.operationType): \(error.localizedDescription)")
                    }
                }
                savePendingOperations()
            }
        }
    }

    private func savePendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            UserDefaults.standard.set(data, forKey: pendingOpsKey)
        }
    }

    private func loadPendingOperations() {
        if let data = UserDefaults.standard.data(forKey: pendingOpsKey),
           let ops = try? JSONDecoder().decode([PendingOperation].self, from: data) {
            pendingOperations = ops
        }
    }

    // MARK: - Stale Share Detection

    /// Check if a shared album's share still exists (owner may have stopped sharing)
    func validateShareExists(for album: Album) async -> Bool {
        guard album.isShared else { return false }

        if album.isOwner {
            // Owner's share is always valid from their perspective
            return true
        }

        // Non-owner: check if the zone still exists in shared database
        do {
            let allZones = try await sharedDatabase.allRecordZones()
            let exists = allZones.contains { $0.zoneID.zoneName == "SharedAlbum-\(album.id.uuidString)" }
            if !exists {
                shareStale = true
                logger.warning("Shared album no longer exists: \(album.name, privacy: .private)")
            }
            return exists
        } catch {
            // Network error — don't mark as stale, just return true
            logger.error("Failed to validate share: \(error.localizedDescription)")
            return true
        }
    }

    /// Check if an error indicates the shared album's zone or share has been deleted
    /// (e.g., owner deleted the album from another device).
    private func isZoneOrShareDeletedError(_ error: Error) -> Bool {
        if error is SharedAlbumError, case SharedAlbumError.shareNoLongerExists = error {
            return true
        }
        if let ckError = error as? CKError {
            return ckError.code == .zoneNotFound || ckError.code == .unknownItem || ckError.code == .userDeletedZone
        }
        return false
    }

    /// Remove a shared album from local state when the zone/share no longer exists.
    /// Called when we detect that the owner deleted the album on another device.
    private func handleZoneNotFound(for album: Album) {
        logger.warning("Shared album zone deleted by owner — removing from local state: \(album.name, privacy: .private) (id: \(album.id, privacy: .private))")
        shareStale = true

        // Remove pending operations for this album so they don't retry forever
        let beforeCount = pendingOperations.count
        pendingOperations.removeAll { $0.albumId == album.id }
        if pendingOperations.count != beforeCount {
            savePendingOperations()
            logger.info("Cleared \(beforeCount - self.pendingOperations.count) pending operations for deleted shared album")
        }

        // Remove album and associated recordings from local state
        appState?.removeSharedAlbum(album)
    }

    // MARK: - Audio Cache Management

    /// Evict cached audio files: delete files not accessed in 30 days,
    /// then LRU-evict oldest-accessed files if total cache exceeds 500MB.
    func evictAudioCacheIfNeeded() {
        guard let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else { return }
        let cacheBase = cachesDir.appendingPathComponent("SharedAlbumAudio", isDirectory: true)

        guard FileManager.default.fileExists(atPath: cacheBase.path) else { return }

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: cacheBase, includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey], options: [.skipsHiddenFiles]) else { return }

        struct CachedFile {
            let url: URL
            let size: Int64
            let lastAccessed: Date
        }

        var files: [CachedFile] = []
        var totalSize: Int64 = 0

        while let fileURL = enumerator.nextObject() as? URL {
            guard let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey]),
                  let size = values.fileSize,
                  let accessed = values.contentAccessDate else { continue }
            let entry = CachedFile(url: fileURL, size: Int64(size), lastAccessed: accessed)
            files.append(entry)
            totalSize += entry.size
        }

        // Phase 1: Delete files not accessed in 30 days
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        var staleEvicted: Int64 = 0
        files.removeAll { file in
            if file.lastAccessed < thirtyDaysAgo {
                do {
                    try fm.removeItem(at: file.url)
                    staleEvicted += file.size
                    totalSize -= file.size
                    logger.debug("Evicted stale cached audio (>30 days): \(file.url.lastPathComponent)")
                } catch {
                    logger.error("Failed to evict stale cache file: \(error.localizedDescription)")
                }
                return true
            }
            return false
        }
        if staleEvicted > 0 {
            logger.info("Evicted \(staleEvicted) bytes of stale (>30 days) cached audio")
        }

        // Phase 2: LRU eviction if total cache still exceeds 500MB limit
        guard totalSize > maxCacheSizeBytes else { return }

        // Sort oldest-accessed first (LRU eviction)
        files.sort { $0.lastAccessed < $1.lastAccessed }

        var evicted: Int64 = 0
        for file in files {
            guard totalSize - evicted > maxCacheSizeBytes else { break }
            do {
                try fm.removeItem(at: file.url)
                evicted += file.size
                logger.debug("Evicted cached audio: \(file.url.lastPathComponent) (\(file.size) bytes)")
            } catch {
                logger.error("Failed to evict cache file: \(error.localizedDescription)")
            }
        }

        if evicted > 0 {
            logger.info("Evicted \(evicted) bytes from shared album audio cache (LRU)")
        }
    }

    // MARK: - Background Trash Purge

    /// Purge expired trash items for all shared albums (call on app launch / foreground)
    func purgeAllExpiredTrash() async {
        guard let appState = appState else { return }
        let sharedAlbums = appState.albums.filter { $0.isShared }

        for album in sharedAlbums {
            do {
                try await purgeExpiredTrashItems(for: album)
            } catch {
                logger.error("Failed to purge trash for album \(album.name, privacy: .private): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Conflict Resolution & Rate Limiting Helpers

    /// Save a CKRecord with basic conflict resolution retry.
    /// On `serverRecordChanged`, fetches the latest server record, re-applies local changes, and retries.
    private func saveWithRetry(_ record: CKRecord, to db: CKDatabase, maxRetries: Int = 2) async throws {
        var currentRecord = record
        for attempt in 0...maxRetries {
            do {
                try await db.save(currentRecord)
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard attempt < maxRetries else { throw error }
                logger.info("Server record changed (attempt \(attempt + 1)/\(maxRetries + 1)), fetching latest and retrying")

                // Fetch the latest server record
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }

                // Re-apply local changes onto the server record
                for key in record.allKeys() {
                    serverRecord[key] = record[key]
                }
                currentRecord = serverRecord
            }
        }
    }

    /// Execute an async operation with rate limit retry.
    /// On `requestRateLimited`, waits the suggested duration and retries once.
    private func withRateLimitRetry<T>(_ operation: () async throws -> T) async throws -> T {
        do {
            return try await operation()
        } catch let error as CKError where error.code == .requestRateLimited {
            let retryAfter = error.userInfo[CKErrorRetryAfterKey] as? Double ?? 1.0
            logger.info("Rate limited — retrying after \(retryAfter) seconds")
            try await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
            return try await operation()
        }
    }
}

// MARK: - UICloudSharingController SwiftUI Bridge

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
