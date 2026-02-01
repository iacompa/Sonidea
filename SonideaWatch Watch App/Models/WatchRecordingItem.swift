//
//  WatchRecordingItem.swift
//  SonideaWatch Watch App
//
//  Lightweight recording model for watchOS.
//

import Foundation

struct WatchRecordingItem: Identifiable, Equatable, Hashable {
    let id: UUID
    let fileName: String  // Just the filename — resolved to documents dir at runtime
    let createdAt: Date
    let duration: TimeInterval
    var title: String
    var isTransferred: Bool

    /// Cached documents directory — resolved once per process to avoid
    /// repeated `FileManager.urls(for:in:)` calls on every `fileURL` access.
    static let documentsDirectory: URL = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
    }()

    /// Full file URL, resolved at runtime from the current documents directory.
    /// This avoids data loss when the app sandbox path changes on updates.
    var fileURL: URL {
        Self.documentsDirectory.appendingPathComponent(fileName)
    }

    init(id: UUID = UUID(), fileURL: URL, createdAt: Date = Date(), duration: TimeInterval, title: String, isTransferred: Bool = false) {
        self.id = id
        self.fileName = fileURL.lastPathComponent
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

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    var formattedDate: String {
        Self.dateFormatter.string(from: createdAt)
    }

    var shortDate: String {
        Self.shortDateFormatter.string(from: createdAt)
    }
}

// MARK: - Codable with migration from old absolute-URL format

extension WatchRecordingItem: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, fileName, fileURL, createdAt, duration, title, isTransferred
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        title = try container.decode(String.self, forKey: .title)
        isTransferred = try container.decodeIfPresent(Bool.self, forKey: .isTransferred) ?? false

        // New format: just the filename. Old format: full absolute URL.
        if let name = try container.decodeIfPresent(String.self, forKey: .fileName) {
            fileName = name
        } else if let url = try container.decodeIfPresent(URL.self, forKey: .fileURL) {
            fileName = url.lastPathComponent
        } else {
            fileName = "\(id.uuidString).m4a"
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(fileName, forKey: .fileName)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(duration, forKey: .duration)
        try container.encode(title, forKey: .title)
        try container.encode(isTransferred, forKey: .isTransferred)
    }
}
