//
//  RecordingItem.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import SwiftUI
import CoreLocation

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

    // GPS coordinates
    var latitude: Double?
    var longitude: Double?

    // Trash support
    var trashedAt: Date?

    // Smart resume - last playback position
    var lastPlaybackPosition: TimeInterval

    // Icon color customization (hex string, e.g. "#3A3A3C")
    var iconColorHex: String?

    // Per-recording EQ settings
    var eqSettings: EQSettings?

    // Default icon color (dark neutral gray)
    static let defaultIconColorHex = "#3A3A3C"

    var isTrashed: Bool {
        trashedAt != nil
    }

    // Icon color with fallback to default (legacy property)
    var iconColor: Color {
        if let hex = iconColorHex, let color = Color(hex: hex) {
            return color
        }
        return Color(hex: Self.defaultIconColorHex) ?? Color(.systemGray4)
    }

    // MARK: - Adaptive Icon Colors

    /// Returns the background color for the icon tile, adapting to color scheme
    func iconTileBackground(for colorScheme: ColorScheme) -> Color {
        if let hex = iconColorHex, let baseColor = Color(hex: hex) {
            // User has chosen a custom color
            if colorScheme == .light {
                // Light mode: show a lighter, tinted version
                return baseColor.opacity(0.2)
            } else {
                // Dark mode: show a richer version
                return baseColor.opacity(0.35)
            }
        } else {
            // Default case - no custom color
            if colorScheme == .light {
                return Color(.systemGray5)
            } else {
                return Color(.systemGray4)
            }
        }
    }

    /// Returns the border color for the icon tile
    func iconTileBorder(for colorScheme: ColorScheme) -> Color {
        if let hex = iconColorHex, let baseColor = Color(hex: hex) {
            // User has chosen a custom color
            if colorScheme == .light {
                return baseColor.opacity(0.4)
            } else {
                return baseColor.opacity(0.5)
            }
        } else {
            // Default case
            if colorScheme == .light {
                return Color(.systemGray4)
            } else {
                return Color.clear
            }
        }
    }

    /// Returns the symbol color for the waveform icon
    func iconSymbolColor(for colorScheme: ColorScheme) -> Color {
        if let hex = iconColorHex, Color(hex: hex) != nil {
            // User has chosen a custom color - use the base color for the symbol
            if colorScheme == .light {
                // Light mode with tinted bg: use the actual color for contrast
                return Color(hex: hex) ?? .primary
            } else {
                // Dark mode: use white for better visibility on darker bg
                return .white
            }
        } else {
            // Default case - use primary color
            return .primary
        }
    }

    // Check if recording has valid coordinates
    var hasCoordinates: Bool {
        guard let lat = latitude, let lon = longitude else { return false }
        return lat != 0 || lon != 0
    }

    // Get CLLocationCoordinate2D if coordinates exist
    var coordinate: CLLocationCoordinate2D? {
        guard hasCoordinates, let lat = latitude, let lon = longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
        latitude: Double? = nil,
        longitude: Double? = nil,
        trashedAt: Date? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        iconColorHex: String? = nil,
        eqSettings: EQSettings? = nil
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
        self.latitude = latitude
        self.longitude = longitude
        self.trashedAt = trashedAt
        self.lastPlaybackPosition = lastPlaybackPosition
        self.iconColorHex = iconColorHex
        self.eqSettings = eqSettings
    }
}

// Raw data returned by RecorderManager
struct RawRecordingData {
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval
    let latitude: Double?
    let longitude: Double?
    let locationLabel: String
}

// MARK: - Recording Spot (for Map clustering)

struct RecordingSpot: Identifiable, Equatable {
    let id: String // cluster key based on rounded coordinates
    let centerCoordinate: CLLocationCoordinate2D
    var displayName: String
    var totalCount: Int
    var favoriteCount: Int
    var recordingIDs: [UUID]

    static func == (lhs: RecordingSpot, rhs: RecordingSpot) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Spot Clustering Helper

enum SpotClustering {
    /// Cluster key by rounding to ~100m (3 decimal places)
    static func clusterKey(latitude: Double, longitude: Double) -> String {
        let roundedLat = (latitude * 1000).rounded() / 1000
        let roundedLon = (longitude * 1000).rounded() / 1000
        return "\(roundedLat),\(roundedLon)"
    }

    /// Compute spots from recordings
    static func computeSpots(
        recordings: [RecordingItem],
        favoriteTagID: UUID?,
        filterFavoritesOnly: Bool = false
    ) -> [RecordingSpot] {
        // Filter to recordings with coordinates
        var recordingsToCluster = recordings.filter { $0.hasCoordinates }

        // If filtering favorites only, apply that filter
        if filterFavoritesOnly, let favID = favoriteTagID {
            recordingsToCluster = recordingsToCluster.filter { $0.tagIDs.contains(favID) }
        }

        // Group by cluster key
        var clusters: [String: (recordings: [RecordingItem], lat: Double, lon: Double)] = [:]

        for recording in recordingsToCluster {
            guard let lat = recording.latitude, let lon = recording.longitude else { continue }
            let key = clusterKey(latitude: lat, longitude: lon)

            if clusters[key] == nil {
                clusters[key] = (recordings: [recording], lat: lat, lon: lon)
            } else {
                clusters[key]?.recordings.append(recording)
            }
        }

        // Convert to RecordingSpot array
        return clusters.map { key, value in
            let recordings = value.recordings

            // Find most common location label for display name
            let labelCounts = Dictionary(grouping: recordings.filter { !$0.locationLabel.isEmpty }, by: { $0.locationLabel })
            let mostCommonLabel = labelCounts.max(by: { $0.value.count < $1.value.count })?.key ?? "Unknown Spot"

            // Count favorites
            let favoriteCount: Int
            if let favID = favoriteTagID {
                favoriteCount = recordings.filter { $0.tagIDs.contains(favID) }.count
            } else {
                favoriteCount = 0
            }

            return RecordingSpot(
                id: key,
                centerCoordinate: CLLocationCoordinate2D(latitude: value.lat, longitude: value.lon),
                displayName: mostCommonLabel,
                totalCount: recordings.count,
                favoriteCount: favoriteCount,
                recordingIDs: recordings.map { $0.id }
            )
        }
    }
}
