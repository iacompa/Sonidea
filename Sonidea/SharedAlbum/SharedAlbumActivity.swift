//
//  SharedAlbumActivity.swift
//  Sonidea
//
//  Activity feed events for shared albums.
//  Tracks all actions for trust and transparency.
//

import Foundation
import SwiftUI

/// Types of events that can occur in a shared album
enum ActivityEventType: String, Codable, CaseIterable {
    // Recording events
    case recordingAdded
    case recordingDeleted
    case recordingRestored
    case recordingRenamed
    case recordingMarkedSensitive
    case recordingUnmarkedSensitive
    case sensitiveRecordingApproved
    case sensitiveRecordingRejected

    // Location events
    case locationEnabled
    case locationDisabled
    case locationModeChanged

    // Participant events
    case participantJoined
    case participantLeft
    case participantRemoved
    case participantRoleChanged

    // Settings events
    case settingAllowDeletesChanged
    case settingTrashRestoreChanged
    case settingLocationDefaultChanged
    case settingRetentionDaysChanged
    case albumRenamed

    /// Human-readable category for filtering
    var category: ActivityCategory {
        switch self {
        case .recordingAdded, .recordingDeleted, .recordingRestored, .recordingRenamed,
             .recordingMarkedSensitive, .recordingUnmarkedSensitive,
             .sensitiveRecordingApproved, .sensitiveRecordingRejected:
            return .recordings
        case .locationEnabled, .locationDisabled, .locationModeChanged:
            return .location
        case .participantJoined, .participantLeft, .participantRemoved, .participantRoleChanged:
            return .participants
        case .settingAllowDeletesChanged, .settingTrashRestoreChanged,
             .settingLocationDefaultChanged, .settingRetentionDaysChanged, .albumRenamed:
            return .settings
        }
    }

    /// Icon name for display
    var iconName: String {
        switch self {
        case .recordingAdded: return "plus.circle.fill"
        case .recordingDeleted: return "trash.fill"
        case .recordingRestored: return "arrow.uturn.backward.circle.fill"
        case .recordingRenamed: return "pencil"
        case .recordingMarkedSensitive: return "eye.slash.fill"
        case .recordingUnmarkedSensitive: return "eye.fill"
        case .sensitiveRecordingApproved: return "checkmark.circle.fill"
        case .sensitiveRecordingRejected: return "xmark.circle.fill"
        case .locationEnabled: return "location.fill"
        case .locationDisabled: return "location.slash.fill"
        case .locationModeChanged: return "location.circle"
        case .participantJoined: return "person.badge.plus"
        case .participantLeft: return "person.badge.minus"
        case .participantRemoved: return "person.fill.xmark"
        case .participantRoleChanged: return "person.fill.questionmark"
        case .settingAllowDeletesChanged, .settingTrashRestoreChanged,
             .settingLocationDefaultChanged, .settingRetentionDaysChanged:
            return "gearshape.fill"
        case .albumRenamed: return "folder.fill"
        }
    }

    /// Icon color for display
    var iconColor: Color {
        switch self {
        case .recordingAdded, .recordingRestored, .sensitiveRecordingApproved:
            return .green
        case .recordingDeleted, .participantRemoved, .sensitiveRecordingRejected:
            return .red
        case .recordingRenamed, .albumRenamed:
            return .blue
        case .recordingMarkedSensitive, .recordingUnmarkedSensitive:
            return .orange
        case .locationEnabled, .locationModeChanged:
            return .purple
        case .locationDisabled:
            return .gray
        case .participantJoined:
            return .green
        case .participantLeft:
            return .orange
        case .participantRoleChanged:
            return .blue
        case .settingAllowDeletesChanged, .settingTrashRestoreChanged,
             .settingLocationDefaultChanged, .settingRetentionDaysChanged:
            return .gray
        }
    }
}

/// Categories for filtering activity events
enum ActivityCategory: String, CaseIterable {
    case all
    case recordings
    case location
    case participants
    case settings

    var displayName: String {
        switch self {
        case .all: return "All"
        case .recordings: return "Recordings"
        case .location: return "Location"
        case .participants: return "Participants"
        case .settings: return "Settings"
        }
    }
}

/// A single activity event in a shared album
struct SharedAlbumActivityEvent: Identifiable, Codable, Equatable {
    let id: UUID
    let albumId: UUID
    let timestamp: Date
    let actorId: String
    let actorDisplayName: String
    let eventType: ActivityEventType

    // Optional references for context
    var targetRecordingId: UUID?
    var targetRecordingTitle: String?
    var targetParticipantId: String?
    var targetParticipantName: String?
    var oldValue: String?
    var newValue: String?

    // MARK: - Computed Properties

    /// Generate a human-readable message for the event
    var displayMessage: String {
        switch eventType {
        case .recordingAdded:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) added \"\(title)\""
            }
            return "\(actorDisplayName) added a recording"

        case .recordingDeleted:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) deleted \"\(title)\""
            }
            return "\(actorDisplayName) deleted a recording"

        case .recordingRestored:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) restored \"\(title)\""
            }
            return "\(actorDisplayName) restored a recording"

        case .recordingRenamed:
            if let oldName = oldValue, let newName = newValue {
                return "\(actorDisplayName) renamed \"\(oldName)\" to \"\(newName)\""
            }
            return "\(actorDisplayName) renamed a recording"

        case .recordingMarkedSensitive:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) marked \"\(title)\" as sensitive"
            }
            return "\(actorDisplayName) marked a recording as sensitive"

        case .recordingUnmarkedSensitive:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) unmarked \"\(title)\" as sensitive"
            }
            return "\(actorDisplayName) unmarked a recording as sensitive"

        case .sensitiveRecordingApproved:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) approved \"\(title)\""
            }
            return "\(actorDisplayName) approved a sensitive recording"

        case .sensitiveRecordingRejected:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) rejected \"\(title)\""
            }
            return "\(actorDisplayName) rejected a sensitive recording"

        case .locationEnabled:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) enabled location for \"\(title)\""
            }
            return "\(actorDisplayName) enabled location sharing"

        case .locationDisabled:
            if let title = targetRecordingTitle {
                return "\(actorDisplayName) disabled location for \"\(title)\""
            }
            return "\(actorDisplayName) disabled location sharing"

        case .locationModeChanged:
            if let mode = newValue {
                return "\(actorDisplayName) changed location to \(mode)"
            }
            return "\(actorDisplayName) changed location mode"

        case .participantJoined:
            if let name = targetParticipantName {
                return "\(name) joined the album"
            }
            return "\(actorDisplayName) joined the album"

        case .participantLeft:
            if let name = targetParticipantName {
                return "\(name) left the album"
            }
            return "\(actorDisplayName) left the album"

        case .participantRemoved:
            if let name = targetParticipantName {
                return "\(actorDisplayName) removed \(name)"
            }
            return "\(actorDisplayName) removed a participant"

        case .participantRoleChanged:
            if let name = targetParticipantName, let role = newValue {
                return "\(actorDisplayName) changed \(name)'s role to \(role)"
            }
            return "\(actorDisplayName) changed a participant's role"

        case .settingAllowDeletesChanged:
            if let value = newValue {
                let enabled = value.lowercased() == "true"
                return "\(actorDisplayName) \(enabled ? "enabled" : "disabled") member deletion"
            }
            return "\(actorDisplayName) changed deletion settings"

        case .settingTrashRestoreChanged:
            if let value = newValue {
                return "\(actorDisplayName) set trash restore to \(value)"
            }
            return "\(actorDisplayName) changed trash restore settings"

        case .settingLocationDefaultChanged:
            if let mode = newValue {
                return "\(actorDisplayName) set default location to \(mode)"
            }
            return "\(actorDisplayName) changed location defaults"

        case .settingRetentionDaysChanged:
            if let days = newValue {
                return "\(actorDisplayName) set trash retention to \(days) days"
            }
            return "\(actorDisplayName) changed trash retention"

        case .albumRenamed:
            if let oldName = oldValue, let newName = newValue {
                return "\(actorDisplayName) renamed album from \"\(oldName)\" to \"\(newName)\""
            }
            return "\(actorDisplayName) renamed the album"
        }
    }

    /// Relative time string (e.g., "2 hours ago")
    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: timestamp, relativeTo: Date())
    }

    /// Actor initials for avatar
    var actorInitials: String {
        SharedAlbumParticipant.generateInitials(from: actorDisplayName)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        albumId: UUID,
        timestamp: Date = Date(),
        actorId: String,
        actorDisplayName: String,
        eventType: ActivityEventType,
        targetRecordingId: UUID? = nil,
        targetRecordingTitle: String? = nil,
        targetParticipantId: String? = nil,
        targetParticipantName: String? = nil,
        oldValue: String? = nil,
        newValue: String? = nil
    ) {
        self.id = id
        self.albumId = albumId
        self.timestamp = timestamp
        self.actorId = actorId
        self.actorDisplayName = actorDisplayName
        self.eventType = eventType
        self.targetRecordingId = targetRecordingId
        self.targetRecordingTitle = targetRecordingTitle
        self.targetParticipantId = targetParticipantId
        self.targetParticipantName = targetParticipantName
        self.oldValue = oldValue
        self.newValue = newValue
    }

    // MARK: - Factory Methods

    /// Create a recording added event
    static func recordingAdded(
        albumId: UUID,
        actorId: String,
        actorDisplayName: String,
        recordingId: UUID,
        recordingTitle: String
    ) -> SharedAlbumActivityEvent {
        SharedAlbumActivityEvent(
            albumId: albumId,
            actorId: actorId,
            actorDisplayName: actorDisplayName,
            eventType: .recordingAdded,
            targetRecordingId: recordingId,
            targetRecordingTitle: recordingTitle
        )
    }

    /// Create a recording deleted event
    static func recordingDeleted(
        albumId: UUID,
        actorId: String,
        actorDisplayName: String,
        recordingId: UUID,
        recordingTitle: String
    ) -> SharedAlbumActivityEvent {
        SharedAlbumActivityEvent(
            albumId: albumId,
            actorId: actorId,
            actorDisplayName: actorDisplayName,
            eventType: .recordingDeleted,
            targetRecordingId: recordingId,
            targetRecordingTitle: recordingTitle
        )
    }

    /// Create a participant joined event
    static func participantJoined(
        albumId: UUID,
        participantId: String,
        participantName: String
    ) -> SharedAlbumActivityEvent {
        SharedAlbumActivityEvent(
            albumId: albumId,
            actorId: participantId,
            actorDisplayName: participantName,
            eventType: .participantJoined,
            targetParticipantId: participantId,
            targetParticipantName: participantName
        )
    }

    /// Create a settings changed event
    static func settingChanged(
        albumId: UUID,
        actorId: String,
        actorDisplayName: String,
        eventType: ActivityEventType,
        oldValue: String?,
        newValue: String
    ) -> SharedAlbumActivityEvent {
        SharedAlbumActivityEvent(
            albumId: albumId,
            actorId: actorId,
            actorDisplayName: actorDisplayName,
            eventType: eventType,
            oldValue: oldValue,
            newValue: newValue
        )
    }
}
