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

            // Add owner
            let owner = share.owner
            let ownerParticipant = SharedAlbumParticipant(
                id: owner.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                displayName: owner.userIdentity.nameComponents?.formatted() ?? "Owner",
                isOwner: true,
                acceptanceStatus: .accepted
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

                let p = SharedAlbumParticipant(
                    id: participant.userIdentity.userRecordID?.recordName ?? UUID().uuidString,
                    displayName: participant.userIdentity.nameComponents?.formatted() ?? "Participant",
                    isOwner: false,
                    acceptanceStatus: status
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
