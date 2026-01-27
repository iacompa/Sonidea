//
//  Album.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import CloudKit

// MARK: - Shared Album Settings Enums

/// Permission levels for trash restore operations
enum TrashRestorePermission: String, Codable, CaseIterable {
    case adminsOnly
    case anyParticipant

    var displayName: String {
        switch self {
        case .adminsOnly: return "Admins Only"
        case .anyParticipant: return "Any Participant"
        }
    }
}

/// Location sharing modes for shared recordings
enum LocationSharingMode: String, Codable, CaseIterable {
    case none       // Default - no location shared
    case approximate  // ~500m precision
    case precise    // Full precision

    var displayName: String {
        switch self {
        case .none: return "Off"
        case .approximate: return "Approximate"
        case .precise: return "Precise"
        }
    }

    var description: String {
        switch self {
        case .none: return "Location not shared"
        case .approximate: return "~500m precision"
        case .precise: return "Exact location"
        }
    }
}

/// Participant roles in a shared album
enum ParticipantRole: String, Codable, CaseIterable {
    case admin   // Creator: invite/remove, settings, delete anything
    case member  // Add recordings, edit own metadata, delete (if allowed)
    case viewer  // Listen only

    var displayName: String {
        switch self {
        case .admin: return "Admin"
        case .member: return "Member"
        case .viewer: return "Viewer"
        }
    }

    var description: String {
        switch self {
        case .admin: return "Full control: manage participants, settings, delete any recording"
        case .member: return "Add recordings, edit own recordings, delete (if allowed)"
        case .viewer: return "Listen only, cannot add or modify"
        }
    }

    var canAddRecordings: Bool {
        self == .admin || self == .member
    }

    var canDeleteAnyRecording: Bool {
        self == .admin
    }

    var canManageParticipants: Bool {
        self == .admin
    }

    var canEditSettings: Bool {
        self == .admin
    }
}

// MARK: - Shared Album Settings

struct SharedAlbumSettings: Codable, Equatable, Hashable {
    /// Allow members to delete recordings (default: only Admin can delete)
    var allowMembersToDelete: Bool = false

    /// Who can restore items from trash
    var trashRestorePermission: TrashRestorePermission = .adminsOnly

    /// How long items stay in trash before permanent deletion (7-30 days)
    var trashRetentionDays: Int = 14

    /// Default location sharing mode for new recordings
    var defaultLocationSharingMode: LocationSharingMode = .none

    /// Allow members to share their location (default: true)
    var allowMembersToShareLocation: Bool = true

    /// Require admin approval for sensitive recordings
    var requireSensitiveApproval: Bool = false

    static let `default` = SharedAlbumSettings()
}

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

    // MARK: - Enhanced Sharing Settings

    /// Shared album settings (only for shared albums)
    var sharedSettings: SharedAlbumSettings?

    /// Current user's role in this shared album
    var currentUserRole: ParticipantRole?

    /// Cached participants list
    var participants: [SharedAlbumParticipant]?

    // System albums cannot be deleted
    var canDelete: Bool {
        !isSystem
    }

    // System albums cannot be renamed
    var canRename: Bool {
        if isSystem { return false }
        if isShared { return isOwner }  // Only owner can rename shared albums
        return true
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
        skipAddRecordingConsent: Bool = false,
        sharedSettings: SharedAlbumSettings? = nil,
        currentUserRole: ParticipantRole? = nil,
        participants: [SharedAlbumParticipant]? = nil
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
        self.sharedSettings = sharedSettings
        self.currentUserRole = currentUserRole
        self.participants = participants
    }

    // MARK: - Role-Based Permission Helpers

    /// Check if current user can delete any recording
    var canDeleteAnyRecording: Bool {
        guard isShared else { return true }
        return currentUserRole?.canDeleteAnyRecording ?? isOwner
    }

    /// Check if current user can delete their own recordings
    var canDeleteOwnRecording: Bool {
        guard isShared else { return true }
        if currentUserRole == .admin { return true }
        return sharedSettings?.allowMembersToDelete ?? false
    }

    /// Check if current user can add recordings
    var canAddRecordings: Bool {
        guard isShared else { return true }
        return currentUserRole?.canAddRecordings ?? false
    }

    /// Check if current user can manage participants
    var canManageParticipants: Bool {
        guard isShared else { return false }
        return currentUserRole?.canManageParticipants ?? isOwner
    }

    /// Check if current user can edit settings
    var canEditSettings: Bool {
        guard isShared else { return false }
        return currentUserRole?.canEditSettings ?? isOwner
    }

    /// Check if current user can restore from trash
    var canRestoreFromTrash: Bool {
        guard isShared else { return true }
        let permission = sharedSettings?.trashRestorePermission ?? .adminsOnly
        switch permission {
        case .adminsOnly:
            return currentUserRole == .admin
        case .anyParticipant:
            return true
        }
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

struct SharedAlbumParticipant: Identifiable, Codable, Equatable, Hashable {
    let id: String  // CKShare.Participant userIdentity hash
    var displayName: String
    var role: ParticipantRole
    var acceptanceStatus: ParticipantStatus
    var joinedAt: Date?
    var avatarInitials: String?  // For display (e.g., "JD" for John Doe)

    enum ParticipantStatus: String, Codable {
        case pending
        case accepted
        case removed
    }

    /// Legacy compatibility: check if participant is owner
    var isOwner: Bool {
        role == .admin
    }

    init(
        id: String,
        displayName: String,
        role: ParticipantRole = .member,
        acceptanceStatus: ParticipantStatus = .pending,
        joinedAt: Date? = nil,
        avatarInitials: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.role = role
        self.acceptanceStatus = acceptanceStatus
        self.joinedAt = joinedAt
        self.avatarInitials = avatarInitials
    }

    /// Legacy initializer for backward compatibility
    init(id: String, displayName: String, isOwner: Bool, acceptanceStatus: ParticipantStatus) {
        self.id = id
        self.displayName = displayName
        self.role = isOwner ? .admin : .member
        self.acceptanceStatus = acceptanceStatus
        self.joinedAt = nil
        self.avatarInitials = nil
    }

    /// Generate initials from display name
    static func generateInitials(from name: String) -> String {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.isEmpty { return "?" }
        if words.count == 1 {
            return String(words[0].prefix(2)).uppercased()
        }
        let firstInitial = words[0].prefix(1)
        let lastInitial = words[words.count - 1].prefix(1)
        return "\(firstInitial)\(lastInitial)".uppercased()
    }
}

// MARK: - Shared Album Visual Styling

import SwiftUI

/// Consistent gold color for shared albums across the app
extension Color {
    static let sharedAlbumGold = Color(red: 0.95, green: 0.78, blue: 0.18)
    static let sharedAlbumGoldDark = Color(red: 0.85, green: 0.68, blue: 0.13)
}

/// Reusable view for album titles with shared album gold glow styling
struct AlbumTitleView: View {
    let album: Album
    var font: Font = .body
    var showBadge: Bool = true

    var body: some View {
        HStack(spacing: 6) {
            // Album name with conditional gold glow
            if album.isShared {
                Text(album.name)
                    .font(font)
                    .foregroundColor(.sharedAlbumGold)
                    .shadow(color: .sharedAlbumGold.opacity(0.7), radius: 6, x: 0, y: 0)
                    .shadow(color: .sharedAlbumGold.opacity(0.35), radius: 12, x: 0, y: 0)
                    .accessibilityLabel("\(album.name), shared album")
            } else {
                Text(album.name)
                    .font(font)
                    .foregroundColor(.primary)
            }

            // Badges
            if album.isShared && showBadge {
                SharedAlbumBadge()
            } else if album.isSystem {
                SystemAlbumBadge()
            }
        }
    }
}

/// Orange "SYSTEM" badge for system albums
struct SystemAlbumBadge: View {
    var body: some View {
        Text("SYSTEM")
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundColor(.orange)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.orange.opacity(0.2))
            .cornerRadius(4)
    }
}

/// Complete album row view for pickers/lists with consistent shared album styling
struct AlbumRowView: View {
    @Environment(AppState.self) private var appState

    let album: Album
    var isSelected: Bool = false
    var showRecordingCount: Bool = true

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                AlbumTitleView(album: album)

                if showRecordingCount {
                    HStack(spacing: 4) {
                        Text("\(appState.recordingCount(in: album)) recordings")
                        Text("•")
                        Text(appState.albumTotalSizeFormatted(album))
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }

            Spacer()

            if isSelected {
                Image(systemName: "checkmark")
                    .foregroundColor(album.isShared ? .sharedAlbumGold : .blue)
                    .fontWeight(.semibold)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Compact album chip for inline display
struct AlbumChip: View {
    let album: Album

    var body: some View {
        HStack(spacing: 4) {
            if album.isShared {
                Image(systemName: "person.2.fill")
                    .font(.system(size: 10))
            }

            Text(album.name)
                .font(.caption)
                .fontWeight(.medium)
        }
        .foregroundColor(album.isShared ? .sharedAlbumGold : .secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(album.isShared ? Color.sharedAlbumGold.opacity(0.12) : Color.secondary.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(album.isShared ? Color.sharedAlbumGold.opacity(0.3) : Color.secondary.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: album.isShared ? .sharedAlbumGold.opacity(0.2) : .clear, radius: 4, x: 0, y: 0)
    }
}
