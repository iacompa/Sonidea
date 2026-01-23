//
//  RecordingItem.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import SwiftUI

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

    // Trash support
    var trashedAt: Date?

    // Smart resume - last playback position
    var lastPlaybackPosition: TimeInterval

    // Icon color customization (hex string, e.g. "#3A3A3C")
    var iconColorHex: String?

    // Default icon color (dark neutral gray)
    static let defaultIconColorHex = "#3A3A3C"

    var isTrashed: Bool {
        trashedAt != nil
    }

    // Icon color with fallback to default
    var iconColor: Color {
        if let hex = iconColorHex, let color = Color(hex: hex) {
            return color
        }
        return Color(hex: Self.defaultIconColorHex) ?? Color(.systemGray4)
    }

    // Auto-purge after 30 days
    var shouldPurge: Bool {
        guard let trashedAt = trashedAt else { return false }
        let daysSinceTrashed = Calendar.current.dateComponents([.day], from: trashedAt, to: Date()).day ?? 0
        return daysSinceTrashed >= 30
    }

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

    var trashedDateFormatted: String? {
        guard let trashedAt = trashedAt else { return nil }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: trashedAt)
    }

    var daysUntilPurge: Int? {
        guard let trashedAt = trashedAt else { return nil }
        let daysSinceTrashed = Calendar.current.dateComponents([.day], from: trashedAt, to: Date()).day ?? 0
        return max(0, 30 - daysSinceTrashed)
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
        transcript: String = "",
        trashedAt: Date? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        iconColorHex: String? = nil
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
        self.trashedAt = trashedAt
        self.lastPlaybackPosition = lastPlaybackPosition
        self.iconColorHex = iconColorHex
    }
}

// Raw data returned by RecorderManager
struct RawRecordingData {
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
}
