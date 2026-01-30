//
//  TestHelpers.swift
//  SonideaTests
//
//  Test fixtures and factory methods for creating test data.
//

import Foundation
@testable import Sonidea

/// Factory methods for creating test data with sensible defaults
enum TestFixtures {

    // MARK: - Dummy URLs

    /// A dummy file URL for recordings (does not need to exist for model tests)
    static func dummyFileURL(filename: String = "test-recording.m4a") -> URL {
        URL(fileURLWithPath: "/tmp/sonidea-tests/\(filename)")
    }

    // MARK: - RecordingItem

    static func makeRecording(
        id: UUID = UUID(),
        fileURL: URL? = nil,
        createdAt: Date = Date(),
        duration: TimeInterval = 60.0,
        title: String = "Test Recording",
        notes: String = "",
        tagIDs: [UUID] = [],
        albumID: UUID? = nil,
        locationLabel: String = "",
        transcript: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        trashedAt: Date? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        iconColorHex: String? = nil,
        iconName: String? = nil,
        iconSourceRaw: String? = nil,
        iconPredictions: [IconPrediction]? = nil,
        secondaryIcons: [String]? = nil,
        eqSettings: EQSettings? = nil,
        projectId: UUID? = nil,
        parentRecordingId: UUID? = nil,
        versionIndex: Int = 1,
        proofStatusRaw: String? = nil,
        proofSHA256: String? = nil,
        proofCloudCreatedAt: Date? = nil,
        proofCloudRecordName: String? = nil,
        locationModeRaw: String? = nil,
        locationProofHash: String? = nil,
        locationProofStatusRaw: String? = nil,
        markers: [Marker] = [],
        overdubGroupId: UUID? = nil,
        overdubRoleRaw: String? = nil,
        overdubIndex: Int? = nil,
        overdubOffsetSeconds: Double = 0,
        overdubSourceBaseId: UUID? = nil,
        modifiedAt: Date? = nil
    ) -> RecordingItem {
        RecordingItem(
            id: id,
            fileURL: fileURL ?? dummyFileURL(filename: "\(id.uuidString).m4a"),
            createdAt: createdAt,
            duration: duration,
            title: title,
            notes: notes,
            tagIDs: tagIDs,
            albumID: albumID,
            locationLabel: locationLabel,
            transcript: transcript,
            latitude: latitude,
            longitude: longitude,
            trashedAt: trashedAt,
            lastPlaybackPosition: lastPlaybackPosition,
            iconColorHex: iconColorHex,
            iconName: iconName,
            iconSourceRaw: iconSourceRaw,
            iconPredictions: iconPredictions,
            secondaryIcons: secondaryIcons,
            eqSettings: eqSettings,
            projectId: projectId,
            parentRecordingId: parentRecordingId,
            versionIndex: versionIndex,
            proofStatusRaw: proofStatusRaw,
            proofSHA256: proofSHA256,
            proofCloudCreatedAt: proofCloudCreatedAt,
            proofCloudRecordName: proofCloudRecordName,
            locationModeRaw: locationModeRaw,
            locationProofHash: locationProofHash,
            locationProofStatusRaw: locationProofStatusRaw,
            markers: markers,
            overdubGroupId: overdubGroupId,
            overdubRoleRaw: overdubRoleRaw,
            overdubIndex: overdubIndex,
            overdubOffsetSeconds: overdubOffsetSeconds,
            overdubSourceBaseId: overdubSourceBaseId,
            modifiedAt: modifiedAt
        )
    }

    // MARK: - Tag

    static func makeTag(
        id: UUID = UUID(),
        name: String = "Test Tag",
        colorHex: String = "#4ECDC4"
    ) -> Tag {
        Tag(id: id, name: name, colorHex: colorHex)
    }

    // MARK: - Album

    static func makeAlbum(
        id: UUID = UUID(),
        name: String = "Test Album",
        createdAt: Date = Date(),
        isSystem: Bool = false,
        isShared: Bool = false,
        shareURL: URL? = nil,
        participantCount: Int = 1,
        isOwner: Bool = true,
        cloudKitShareRecordName: String? = nil,
        skipAddRecordingConsent: Bool = false,
        sharedSettings: SharedAlbumSettings? = nil,
        currentUserRole: ParticipantRole? = nil,
        participants: [SharedAlbumParticipant]? = nil
    ) -> Album {
        Album(
            id: id,
            name: name,
            createdAt: createdAt,
            isSystem: isSystem,
            isShared: isShared,
            shareURL: shareURL,
            participantCount: participantCount,
            isOwner: isOwner,
            cloudKitShareRecordName: cloudKitShareRecordName,
            skipAddRecordingConsent: skipAddRecordingConsent,
            sharedSettings: sharedSettings,
            currentUserRole: currentUserRole,
            participants: participants
        )
    }

    // MARK: - Project

    static func makeProject(
        id: UUID = UUID(),
        title: String = "Test Project",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinned: Bool = false,
        notes: String = "",
        bestTakeRecordingId: UUID? = nil,
        sortOrder: Int? = nil
    ) -> Project {
        Project(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: updatedAt,
            pinned: pinned,
            notes: notes,
            bestTakeRecordingId: bestTakeRecordingId,
            sortOrder: sortOrder
        )
    }

    // MARK: - OverdubGroup

    static func makeOverdubGroup(
        id: UUID = UUID(),
        baseRecordingId: UUID = UUID(),
        layerRecordingIds: [UUID] = [],
        createdAt: Date = Date()
    ) -> OverdubGroup {
        OverdubGroup(
            id: id,
            baseRecordingId: baseRecordingId,
            layerRecordingIds: layerRecordingIds,
            createdAt: createdAt
        )
    }
}
