//
//  WatchRecordingItem.swift
//  SonideaWatch Watch App
//
//  Lightweight recording model for watchOS.
//

import Foundation

struct WatchRecordingItem: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
    var title: String
    var isTransferred: Bool

    init(id: UUID = UUID(), fileURL: URL, createdAt: Date = Date(), duration: TimeInterval, title: String, isTransferred: Bool = false) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.title = title
        self.isTransferred = isTransferred
    }

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }

    var shortDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: createdAt)
    }
}
