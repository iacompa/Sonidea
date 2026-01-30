//
//  SharedAlbumComment.swift
//  Sonidea
//
//  Comment model for shared album recordings.
//

import Foundation

struct SharedAlbumComment: Identifiable, Equatable {
    let id: UUID
    let recordingId: UUID
    let authorId: String
    let authorDisplayName: String
    let text: String
    let createdAt: Date

    var authorInitials: String {
        SharedAlbumParticipant.generateInitials(from: authorDisplayName)
    }

    var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: createdAt, relativeTo: Date())
    }

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        authorId: String,
        authorDisplayName: String,
        text: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordingId = recordingId
        self.authorId = authorId
        self.authorDisplayName = authorDisplayName
        self.text = text
        self.createdAt = createdAt
    }
}
