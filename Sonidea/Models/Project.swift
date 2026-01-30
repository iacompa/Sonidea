//
//  Project.swift
//  Sonidea
//
//  Project model for grouping recordings into versioned takes.
//  A Project contains multiple versions (V1, V2, V3...) of a recording idea.
//

import Foundation

struct Project: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    let createdAt: Date
    var updatedAt: Date
    var pinned: Bool
    var notes: String
    var bestTakeRecordingId: UUID?

    // Optional sort order for manual ordering
    var sortOrder: Int?

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pinned: Bool = false,
        notes: String = "",
        bestTakeRecordingId: UUID? = nil,
        sortOrder: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pinned = pinned
        self.notes = notes
        self.bestTakeRecordingId = bestTakeRecordingId
        self.sortOrder = sortOrder
    }

    // MARK: - Convenience Initializer from Recording

    /// Creates a new project from an existing recording (converts recording to V1)
    static func fromRecording(_ recording: RecordingItem) -> Project {
        Project(
            title: recording.title,
            createdAt: Date(),
            updatedAt: Date(),
            pinned: false,
            notes: "",
            bestTakeRecordingId: nil
        )
    }

    // MARK: - Formatted Properties

    var formattedCreatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var formattedUpdatedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: updatedAt)
    }

    // MARK: - Hashable

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Project Statistics

struct ProjectStats {
    let versionCount: Int
    let totalDuration: TimeInterval
    let oldestVersion: Date?
    let newestVersion: Date?
    let hasBestTake: Bool

    var formattedTotalDuration: String {
        let minutes = Int(totalDuration) / 60
        let seconds = Int(totalDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    static let empty = ProjectStats(
        versionCount: 0,
        totalDuration: 0,
        oldestVersion: nil,
        newestVersion: nil,
        hasBestTake: false
    )
}
