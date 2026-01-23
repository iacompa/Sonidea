//
//  RecordingItem.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation

struct RecordingItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval

    var title: String
    var notes: String
    var tagIDs: [UUID]
    var albumID: UUID?
    var locationLabel: String
    var transcript: String

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    init(
        id: UUID = UUID(),
        fileURL: URL,
        createdAt: Date = Date(),
        duration: TimeInterval,
        title: String,
        notes: String = "",
        tagIDs: [UUID] = [],
        albumID: UUID? = nil,
        locationLabel: String = "",
        transcript: String = ""
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.title = title
        self.notes = notes
        self.tagIDs = tagIDs
        self.albumID = albumID
        self.locationLabel = locationLabel
        self.transcript = transcript
    }
}

// Raw data returned by RecorderManager
struct RawRecordingData {
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
}
