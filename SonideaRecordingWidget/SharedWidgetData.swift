//
//  SharedWidgetData.swift
//  SonideaRecordingWidget
//
//  Shared data model for home screen widgets. Written by the main app,
//  read by the widget extension via App Group shared container.
//

import Foundation

/// Data written by the main app for widget consumption.
/// Stored in the App Group shared container as JSON.
struct SharedWidgetData: Codable {
    let recentRecordings: [WidgetRecordingInfo]
    let totalRecordingCount: Int
    let lastUpdated: Date

    static let appGroupID = "group.com.iacompa.sonidea"
    static let fileName = "widget_data.json"

    /// URL to the shared data file in the App Group container.
    static var fileURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(fileName)
    }

    /// Save widget data to the shared container.
    func save() {
        guard let url = Self.fileURL else { return }
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Load widget data from the shared container.
    static func load() -> SharedWidgetData? {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedWidgetData.self, from: data)
    }
}

/// Lightweight recording info for widget display.
struct WidgetRecordingInfo: Codable, Identifiable {
    let id: UUID
    let title: String
    let duration: TimeInterval
    let createdAt: Date
    let iconName: String?

    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: createdAt)
    }
}
