//
//  RecordingItem.swift
//  Sonidea
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

    // MARK: - Project & Versioning

    /// Parent project ID (nil = standalone recording)
    var projectId: UUID?

    /// Link to previous version in chain (nil = root/V1)
    var parentRecordingId: UUID?

    /// Sequential version number (1 = V1, 2 = V2, etc.)
    var versionIndex: Int

    // MARK: - Proof Receipts (Tamper-Evident Timestamps)

    /// Proof status stored as raw string
    var proofStatusRaw: String?

    /// SHA-256 hash of the audio file
    var proofSHA256: String?

    /// CloudKit server timestamp when proof was recorded
    var proofCloudCreatedAt: Date?

    /// CloudKit record name for the proof
    var proofCloudRecordName: String?

    /// Location mode stored as raw string
    var locationModeRaw: String?

    /// SHA-256 hash of the location payload JSON
    var locationProofHash: String?

    // Default icon color (dark neutral gray)
    static let defaultIconColorHex = "#3A3A3C"

    var isTrashed: Bool {
        trashedAt != nil
    }

    /// Whether this recording belongs to a project
    var belongsToProject: Bool {
        projectId != nil
    }

    /// Whether this is the root/first version in a project (V1)
    var isRootVersion: Bool {
        parentRecordingId == nil && projectId != nil
    }

    /// Formatted version label (e.g., "V1", "V2")
    var versionLabel: String {
        "V\(versionIndex)"
    }

    /// Proof status enum (computed from raw string)
    var proofStatus: ProofStatus {
        get {
            guard let raw = proofStatusRaw else { return .none }
            return ProofStatus(rawValue: raw) ?? .none
        }
        set {
            proofStatusRaw = newValue.rawValue
        }
    }

    /// Location mode enum (computed from raw string)
    var locationMode: LocationMode {
        get {
            guard let raw = locationModeRaw else { return .off }
            return LocationMode(rawValue: raw) ?? .off
        }
        set {
            locationModeRaw = newValue.rawValue
        }
    }

    /// Whether this recording has a verified proof
    var hasProof: Bool {
        proofStatus == .proven
    }

    /// Whether proof is pending upload
    var proofPending: Bool {
        proofStatus == .pending
    }

    // Icon color with fallback to default (legacy property)
    var iconColor: Color {
        if let hex = iconColorHex, let color = Color(hex: hex) {
            return color
        }
        return Color(hex: Self.defaultIconColorHex) ?? Color(.systemGray4)
    }

    // MARK: - Stable Icon Tile Colors (no automatic changes based on edits/tags/selection)

    /// Returns whether this recording has a user-set custom icon color
    var hasCustomIconColor: Bool {
        if let hex = iconColorHex, Color(hex: hex) != nil {
            return true
        }
        return false
    }

    /// Returns the stable background color for the icon tile
    /// This color is ONLY determined by iconColorHex - nothing else affects it
    func iconTileBackground(for colorScheme: ColorScheme) -> Color {
        if let hex = iconColorHex, let baseColor = Color(hex: hex) {
            // User has explicitly set a custom color
            // Use a fixed, stable opacity that works well in both modes
            return baseColor.opacity(colorScheme == .light ? 0.15 : 0.25)
        } else {
            // Default: stable system gray that doesn't change based on any recording state
            return colorScheme == .light ? Color(.systemGray5) : Color(.systemGray5)
        }
    }

    /// Returns the stable border color for the icon tile
    func iconTileBorder(for colorScheme: ColorScheme) -> Color {
        if let hex = iconColorHex, let baseColor = Color(hex: hex) {
            return baseColor.opacity(colorScheme == .light ? 0.3 : 0.4)
        } else {
            return colorScheme == .light ? Color(.systemGray4) : Color.clear
        }
    }

    /// Returns the symbol color for the waveform icon with proper contrast
    func iconSymbolColor(for colorScheme: ColorScheme) -> Color {
        if let hex = iconColorHex, let baseColor = Color(hex: hex) {
            // User has a custom color - ensure good contrast
            if colorScheme == .light {
                // Light mode: use the custom color itself (darker on light bg)
                return baseColor
            } else {
                // Dark mode: use white for visibility on darker backgrounds
                return .white
            }
        } else {
            // Default: primary color works well on system gray backgrounds
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

    // MARK: - File Size

    /// File size in bytes (nil if file doesn't exist)
    var fileSizeBytes: Int64? {
        StorageFormatter.fileSize(at: fileURL)
    }

    /// Human-readable file size (e.g., "9.8 MB")
    var fileSizeFormatted: String {
        StorageFormatter.formattedFileSize(at: fileURL)
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
        eqSettings: EQSettings? = nil,
        projectId: UUID? = nil,
        parentRecordingId: UUID? = nil,
        versionIndex: Int = 1,
        proofStatusRaw: String? = nil,
        proofSHA256: String? = nil,
        proofCloudCreatedAt: Date? = nil,
        proofCloudRecordName: String? = nil,
        locationModeRaw: String? = nil,
        locationProofHash: String? = nil
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
        self.projectId = projectId
        self.parentRecordingId = parentRecordingId
        self.versionIndex = versionIndex
        self.proofStatusRaw = proofStatusRaw
        self.proofSHA256 = proofSHA256
        self.proofCloudCreatedAt = proofCloudCreatedAt
        self.proofCloudRecordName = proofCloudRecordName
        self.locationModeRaw = locationModeRaw
        self.locationProofHash = locationProofHash
    }

    // MARK: - Codable with Migration Support

    enum CodingKeys: String, CodingKey {
        case id, fileURL, createdAt, duration, title, notes, tagIDs, albumID
        case locationLabel, transcript, latitude, longitude, trashedAt
        case lastPlaybackPosition, iconColorHex, eqSettings
        case projectId, parentRecordingId, versionIndex
        case proofStatusRaw, proofSHA256, proofCloudCreatedAt, proofCloudRecordName
        case locationModeRaw, locationProofHash
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        tagIDs = try container.decode([UUID].self, forKey: .tagIDs)
        albumID = try container.decodeIfPresent(UUID.self, forKey: .albumID)
        locationLabel = try container.decode(String.self, forKey: .locationLabel)
        transcript = try container.decode(String.self, forKey: .transcript)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        lastPlaybackPosition = try container.decode(TimeInterval.self, forKey: .lastPlaybackPosition)
        iconColorHex = try container.decodeIfPresent(String.self, forKey: .iconColorHex)
        eqSettings = try container.decodeIfPresent(EQSettings.self, forKey: .eqSettings)

        // Migration: new fields with defaults for existing recordings
        projectId = try container.decodeIfPresent(UUID.self, forKey: .projectId)
        parentRecordingId = try container.decodeIfPresent(UUID.self, forKey: .parentRecordingId)
        versionIndex = try container.decodeIfPresent(Int.self, forKey: .versionIndex) ?? 1

        // Migration: proof receipt fields
        proofStatusRaw = try container.decodeIfPresent(String.self, forKey: .proofStatusRaw)
        proofSHA256 = try container.decodeIfPresent(String.self, forKey: .proofSHA256)
        proofCloudCreatedAt = try container.decodeIfPresent(Date.self, forKey: .proofCloudCreatedAt)
        proofCloudRecordName = try container.decodeIfPresent(String.self, forKey: .proofCloudRecordName)
        locationModeRaw = try container.decodeIfPresent(String.self, forKey: .locationModeRaw)
        locationProofHash = try container.decodeIfPresent(String.self, forKey: .locationProofHash)
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
