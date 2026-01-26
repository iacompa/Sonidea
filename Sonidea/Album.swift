//
//  Album.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import CloudKit

struct Album: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    let createdAt: Date
    var isSystem: Bool

    // MARK: - Sharing Properties

    /// Whether this album is shared with others (born-shared albums only)
    var isShared: Bool

    /// The CloudKit share URL for this album (if shared)
    var shareURL: URL?

    /// Number of participants in the shared album (including owner)
    var participantCount: Int

    /// Whether the current user is the owner of this shared album
    var isOwner: Bool

    /// CloudKit record name for the share (used to fetch CKShare)
    var cloudKitShareRecordName: String?

    /// Per-album preference: skip consent prompt when adding recordings
    var skipAddRecordingConsent: Bool

    // System albums cannot be deleted
    var canDelete: Bool {
        !isSystem
    }

    // System albums cannot be renamed
    var canRename: Bool {
        !isSystem && !isShared  // Shared albums cannot be renamed by non-owners
    }

    /// Shared albums cannot be converted from existing albums
    var canConvertToShared: Bool {
        false  // Never allow converting - must be born-shared
    }

    init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        isSystem: Bool = false,
        isShared: Bool = false,
        shareURL: URL? = nil,
        participantCount: Int = 1,
        isOwner: Bool = true,
        cloudKitShareRecordName: String? = nil,
        skipAddRecordingConsent: Bool = false
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.isSystem = isSystem
        self.isShared = isShared
        self.shareURL = shareURL
        self.participantCount = participantCount
        self.isOwner = isOwner
        self.cloudKitShareRecordName = cloudKitShareRecordName
        self.skipAddRecordingConsent = skipAddRecordingConsent
    }

    // Well-known system album IDs
    static let draftsID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    static let importsID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

    static let drafts = Album(
        id: draftsID,
        name: "Drafts",
        createdAt: Date(timeIntervalSince1970: 0),
        isSystem: true
    )

    static let imports = Album(
        id: importsID,
        name: "Imports",
        createdAt: Date(timeIntervalSince1970: 0),
        isSystem: true
    )

    /// Check if this is the Imports album
    var isImportsAlbum: Bool {
        id == Album.importsID
    }

    /// Check if this is the Drafts album
    var isDraftsAlbum: Bool {
        id == Album.draftsID
    }
}

// MARK: - Shared Album Participant

struct SharedAlbumParticipant: Identifiable, Codable, Equatable {
    let id: String  // CKShare.Participant userIdentity hash
    var displayName: String
    var isOwner: Bool
    var acceptanceStatus: ParticipantStatus

    enum ParticipantStatus: String, Codable {
        case pending
        case accepted
        case removed
    }
}
