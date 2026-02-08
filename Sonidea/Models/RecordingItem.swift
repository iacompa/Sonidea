//
//  RecordingItem.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import SwiftUI
import CoreLocation

// MARK: - Overdub Role

/// Role of a recording in an overdub group
enum OverdubRole: String, Codable {
    case none   // Not part of an overdub
    case base   // The original/base track
    case layer  // A recorded layer on top
}

// MARK: - Icon Source

/// Source of the recording's icon (auto-detected vs user-selected)
enum IconSource: String, Codable {
    case auto   // Automatically detected by classifier
    case user   // Manually selected by user
}

// MARK: - Title Source

/// Source of the recording's title
enum TitleSource: String, Codable {
    case user       // User manually edited
    case location   // Generated from locationLabel
    case context    // Generated from transcript
    case generic    // Default "Recording N"
}

/// A single icon classification prediction from SoundAnalysis
struct IconPrediction: Codable, Equatable {
    let iconSymbol: String   // SF Symbol name
    let confidence: Float    // 0.0 to 1.0

    /// Minimum threshold for suggestions (60%)
    static let suggestionThreshold: Float = 0.60
}

// MARK: - Preset Icons for Recordings

/// Preset tintable SF Symbol icons for recordings
enum PresetIcon: String, CaseIterable, Codable {
    case waveform = "waveform"
    case mic = "mic.fill"
    case musicNote = "music.note"
    case musicMic = "music.mic"
    case speaker = "speaker.wave.2.fill"
    case phone = "phone.fill"
    case video = "video.fill"
    case person = "person.fill"
    case people = "person.2.fill"
    case guitar = "guitars"
    case pianokeys = "music.note.list"
    case drum = "cylinder.fill"
    case headphones = "headphones"
    case brain = "brain.head.profile"
    case sparkles = "sparkles"

    /// Human-readable display name
    var displayName: String {
        switch self {
        case .waveform: return "Waveform"
        case .mic: return "Microphone"
        case .musicNote: return "Music Note"
        case .musicMic: return "Vocal"
        case .speaker: return "Speaker"
        case .phone: return "Phone Call"
        case .video: return "Video"
        case .person: return "Person"
        case .people: return "People"
        case .guitar: return "Guitar"
        case .pianokeys: return "Piano"
        case .drum: return "Drums"
        case .headphones: return "Headphones"
        case .brain: return "Idea"
        case .sparkles: return "Creative"
        }
    }

    /// SF Symbol name for rendering
    var systemName: String {
        rawValue
    }
}

struct RecordingItem: Identifiable, Codable, Equatable {
    let id: UUID
    let fileURL: URL
    let createdAt: Date
    let duration: TimeInterval

    /// Last modification time (for sync conflict resolution)
    var modifiedAt: Date

    var title: String
    var notes: String
    var tagIDs: [UUID]
    var albumID: UUID?
    var locationLabel: String
    var transcript: String

    // Timestamped transcription segments for tappable word display
    var transcriptionSegments: [TranscriptionSegment]?

    // GPS coordinates
    var latitude: Double?
    var longitude: Double?

    // Trash support
    var trashedAt: Date?

    // Smart resume - last playback position
    var lastPlaybackPosition: TimeInterval

    // Icon color customization (hex string, e.g. "#3A3A3C")
    var iconColorHex: String?

    // Preset icon (SF Symbol name)
    var iconName: String?

    // Icon source: "auto" (classifier) or "user" (manual selection)
    var iconSourceRaw: String?

    // Top 3 classification predictions (sorted by confidence desc, only those >= 0.855)
    var iconPredictions: [IconPrediction]?

    // Secondary icons for top bar display (max 2, shown alongside main icon)
    // Main icon is iconName; these are additional icons shown in the 3-icon strip
    var secondaryIcons: [String]?

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

    /// Location proof status stored as raw string (independent from date proof)
    var locationProofStatusRaw: String?

    // MARK: - Waveform Editing

    /// Markers for this recording
    var markers: [Marker]

    // MARK: - Overdub (Record Over Track)

    /// ID of the overdub group this recording belongs to (nil = not part of overdub)
    var overdubGroupId: UUID?

    /// Role in overdub group: base track or layer
    var overdubRoleRaw: String?

    /// Layer index (1, 2, or 3) for layer recordings; nil for base or non-overdub
    var overdubIndex: Int?

    /// Time offset in seconds for layer alignment (default 0)
    var overdubOffsetSeconds: Double

    /// For layers: points to the base recording ID
    var overdubSourceBaseId: UUID?

    /// Whether the metronome/click track was active when this recording was made
    var wasRecordedWithMetronome: Bool

    // MARK: - Actual Recording Quality (for downgrade detection)

    /// Actual sample rate the recording was captured at (may differ from preset due to Bluetooth/VP)
    var actualSampleRate: Double?

    /// Actual channel count the recording was captured at (may differ from preset due to Bluetooth/VP)
    var actualChannelCount: Int?

    // MARK: - Original Audio Backup (Reset to Original)

    /// Filename of the original audio backup in Application Support/originals/ (not full path, for portability)
    var originalAudioFileName: String?

    /// Original recording duration before any edits
    var originalDuration: TimeInterval?

    /// Original proof status before editing (stored as raw value string)
    var originalProofStatus: String?

    /// Original proof SHA-256 hash before editing
    var originalProofSHA: String?

    // MARK: - Auto-Naming

    /// Auto-generated title suggestion (from transcript analysis)
    var autoTitle: String?

    /// Title source tracking (user, location, context, generic)
    var titleSourceRaw: String?

    /// Title source enum (computed from raw string)
    var titleSource: TitleSource {
        get {
            guard let raw = titleSourceRaw else { return .generic }
            return TitleSource(rawValue: raw) ?? .generic
        }
        set {
            titleSourceRaw = newValue.rawValue
        }
    }

    // Default icon color (dark neutral gray)
    static let defaultIconColorHex = "#3A3A3C"

    /// Icon source enum (computed from raw string)
    var iconSource: IconSource {
        get {
            guard let raw = iconSourceRaw else { return .auto }
            return IconSource(rawValue: raw) ?? .auto
        }
        set {
            iconSourceRaw = newValue.rawValue
        }
    }

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

    /// Location proof status enum (computed from raw string, independent from date proof)
    var locationProofStatus: LocationProofStatus {
        get {
            guard let raw = locationProofStatusRaw else { return .none }
            return LocationProofStatus(rawValue: raw) ?? .none
        }
        set {
            locationProofStatusRaw = newValue.rawValue
        }
    }

    /// Whether this recording has a verified proof
    var hasProof: Bool {
        proofStatus == .proven
    }

    /// Overdub role enum (computed from raw string)
    var overdubRole: OverdubRole {
        get {
            guard let raw = overdubRoleRaw else { return .none }
            return OverdubRole(rawValue: raw) ?? .none
        }
        set {
            overdubRoleRaw = newValue == .none ? nil : newValue.rawValue
        }
    }

    /// Whether this recording is part of an overdub group
    var isPartOfOverdub: Bool {
        overdubGroupId != nil
    }

    /// Whether this is the base track in an overdub group
    var isOverdubBase: Bool {
        overdubRole == .base
    }

    /// Whether this is a layer in an overdub group
    var isOverdubLayer: Bool {
        overdubRole == .layer
    }

    /// Formatted layer label (e.g., "Layer 1")
    var overdubLayerLabel: String? {
        guard isOverdubLayer, let index = overdubIndex else { return nil }
        return "Layer \(index)"
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

    /// The preset icon for this recording (defaults to waveform)
    /// NOTE: This only works for icons in the PresetIcon enum. For full icon support, use displayIconSymbol.
    var presetIcon: PresetIcon {
        get {
            guard let name = iconName else { return .waveform }
            return PresetIcon(rawValue: name) ?? .waveform
        }
        set {
            iconName = newValue.rawValue
        }
    }

    /// SF Symbol name for displaying the recording's icon
    /// This is the single source of truth for icon display - use this instead of presetIcon.systemName
    var displayIconSymbol: String {
        iconName ?? "waveform"
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
        latitude != nil && longitude != nil
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
        let safeDuration = max(0, duration)
        let minutes = Int(safeDuration) / 60
        let seconds = Int(safeDuration) % 60
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
        CachedDateFormatter.mediumDateTime.string(from: createdAt)
    }

    var trashedDateFormatted: String? {
        guard let trashedAt = trashedAt else { return nil }
        return CachedDateFormatter.mediumDateTime.string(from: trashedAt)
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
        transcriptionSegments: [TranscriptionSegment]? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil,
        trashedAt: Date? = nil,
        lastPlaybackPosition: TimeInterval = 0,
        iconColorHex: String? = nil,
        iconName: String? = nil,
        iconSourceRaw: String? = nil,
        iconPredictions: [IconPrediction]? = nil,
        secondaryIcons: [String]? = nil,
        eqSettings: EQSettings? = nil,
        projectId: UUID? = nil,
        parentRecordingId: UUID? = nil,
        versionIndex: Int = 1,
        proofStatusRaw: String? = nil,
        proofSHA256: String? = nil,
        proofCloudCreatedAt: Date? = nil,
        proofCloudRecordName: String? = nil,
        locationModeRaw: String? = nil,
        locationProofHash: String? = nil,
        locationProofStatusRaw: String? = nil,
        markers: [Marker] = [],
        // Overdub fields
        overdubGroupId: UUID? = nil,
        overdubRoleRaw: String? = nil,
        overdubIndex: Int? = nil,
        overdubOffsetSeconds: Double = 0,
        overdubSourceBaseId: UUID? = nil,
        wasRecordedWithMetronome: Bool = false,
        modifiedAt: Date? = nil,
        // Actual recording quality fields
        actualSampleRate: Double? = nil,
        actualChannelCount: Int? = nil,
        // Original audio backup fields
        originalAudioFileName: String? = nil,
        originalDuration: TimeInterval? = nil,
        originalProofStatus: String? = nil,
        originalProofSHA: String? = nil,
        // Auto-naming fields
        autoTitle: String? = nil,
        titleSourceRaw: String? = nil
    ) {
        self.id = id
        self.fileURL = fileURL
        self.createdAt = createdAt
        self.duration = duration
        self.modifiedAt = modifiedAt ?? createdAt
        self.title = title
        self.notes = notes
        self.tagIDs = tagIDs
        self.albumID = albumID
        self.locationLabel = locationLabel
        self.transcript = transcript
        self.transcriptionSegments = transcriptionSegments
        self.latitude = latitude
        self.longitude = longitude
        self.trashedAt = trashedAt
        self.lastPlaybackPosition = lastPlaybackPosition
        self.iconColorHex = iconColorHex
        self.iconName = iconName
        self.iconSourceRaw = iconSourceRaw
        self.iconPredictions = iconPredictions
        self.secondaryIcons = secondaryIcons
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
        self.locationProofStatusRaw = locationProofStatusRaw
        self.markers = markers
        // Overdub fields
        self.overdubGroupId = overdubGroupId
        self.overdubRoleRaw = overdubRoleRaw
        self.overdubIndex = overdubIndex
        self.overdubOffsetSeconds = overdubOffsetSeconds
        self.overdubSourceBaseId = overdubSourceBaseId
        self.wasRecordedWithMetronome = wasRecordedWithMetronome
        // Actual recording quality fields
        self.actualSampleRate = actualSampleRate
        self.actualChannelCount = actualChannelCount
        // Original audio backup fields
        self.originalAudioFileName = originalAudioFileName
        self.originalDuration = originalDuration
        self.originalProofStatus = originalProofStatus
        self.originalProofSHA = originalProofSHA
        // Auto-naming fields
        self.autoTitle = autoTitle
        self.titleSourceRaw = titleSourceRaw
    }

    // MARK: - Codable with Migration Support

    enum CodingKeys: String, CodingKey {
        case id, fileURL, createdAt, duration, modifiedAt, title, notes, tagIDs, albumID
        case locationLabel, transcript, transcriptionSegments, latitude, longitude, trashedAt
        case lastPlaybackPosition, iconColorHex, iconName, iconSourceRaw, iconPredictions, secondaryIcons, eqSettings
        case projectId, parentRecordingId, versionIndex
        case proofStatusRaw, proofSHA256, proofCloudCreatedAt, proofCloudRecordName
        case locationModeRaw, locationProofHash, locationProofStatusRaw
        case markers
        // Overdub fields
        case overdubGroupId, overdubRoleRaw, overdubIndex, overdubOffsetSeconds, overdubSourceBaseId
        case wasRecordedWithMetronome
        // Actual recording quality fields
        case actualSampleRate, actualChannelCount
        // Original audio backup fields
        case originalAudioFileName, originalDuration, originalProofStatus, originalProofSHA
        // Auto-naming fields
        case autoTitle, titleSourceRaw
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        id = try container.decode(UUID.self, forKey: .id)
        fileURL = try container.decode(URL.self, forKey: .fileURL)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        duration = try container.decode(TimeInterval.self, forKey: .duration)
        // Migration: modifiedAt defaults to createdAt for existing recordings
        modifiedAt = try container.decodeIfPresent(Date.self, forKey: .modifiedAt) ?? createdAt
        title = try container.decode(String.self, forKey: .title)
        notes = try container.decode(String.self, forKey: .notes)
        tagIDs = try container.decode([UUID].self, forKey: .tagIDs)
        albumID = try container.decodeIfPresent(UUID.self, forKey: .albumID)
        locationLabel = try container.decode(String.self, forKey: .locationLabel)
        transcript = try container.decode(String.self, forKey: .transcript)
        // Migration: transcriptionSegments not present in older recordings
        transcriptionSegments = try container.decodeIfPresent([TranscriptionSegment].self, forKey: .transcriptionSegments)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        trashedAt = try container.decodeIfPresent(Date.self, forKey: .trashedAt)
        lastPlaybackPosition = try container.decode(TimeInterval.self, forKey: .lastPlaybackPosition)
        iconColorHex = try container.decodeIfPresent(String.self, forKey: .iconColorHex)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName)
        // Migration: existing recordings with iconName set by user should be treated as user source
        // New recordings without iconSourceRaw default to nil (auto classification can run)
        iconSourceRaw = try container.decodeIfPresent(String.self, forKey: .iconSourceRaw)
        iconPredictions = try container.decodeIfPresent([IconPrediction].self, forKey: .iconPredictions)
        // Migration: pinnedIcons renamed to secondaryIcons, try both keys for backwards compatibility
        secondaryIcons = try container.decodeIfPresent([String].self, forKey: .secondaryIcons)
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
        locationProofStatusRaw = try container.decodeIfPresent(String.self, forKey: .locationProofStatusRaw)

        // Migration: markers with empty default for existing recordings
        markers = try container.decodeIfPresent([Marker].self, forKey: .markers) ?? []

        // Migration: overdub fields with defaults for existing recordings
        overdubGroupId = try container.decodeIfPresent(UUID.self, forKey: .overdubGroupId)
        overdubRoleRaw = try container.decodeIfPresent(String.self, forKey: .overdubRoleRaw)
        overdubIndex = try container.decodeIfPresent(Int.self, forKey: .overdubIndex)
        overdubOffsetSeconds = try container.decodeIfPresent(Double.self, forKey: .overdubOffsetSeconds) ?? 0
        overdubSourceBaseId = try container.decodeIfPresent(UUID.self, forKey: .overdubSourceBaseId)

        // Migration: metronome tracking with false default for existing recordings
        wasRecordedWithMetronome = try container.decodeIfPresent(Bool.self, forKey: .wasRecordedWithMetronome) ?? false

        // Migration: actual recording quality fields with nil defaults for existing recordings
        actualSampleRate = try container.decodeIfPresent(Double.self, forKey: .actualSampleRate)
        actualChannelCount = try container.decodeIfPresent(Int.self, forKey: .actualChannelCount)

        // Migration: original audio backup fields with nil defaults for existing recordings
        originalAudioFileName = try container.decodeIfPresent(String.self, forKey: .originalAudioFileName)
        originalDuration = try container.decodeIfPresent(TimeInterval.self, forKey: .originalDuration)
        originalProofStatus = try container.decodeIfPresent(String.self, forKey: .originalProofStatus)
        originalProofSHA = try container.decodeIfPresent(String.self, forKey: .originalProofSHA)

        // Migration: auto-naming fields with nil defaults for existing recordings
        autoTitle = try container.decodeIfPresent(String.self, forKey: .autoTitle)
        titleSourceRaw = try container.decodeIfPresent(String.self, forKey: .titleSourceRaw)
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
    let wasRecordedWithMetronome: Bool
    let metronomeBPM: Double?
    let actualSampleRate: Double?
    let actualChannelCount: Int?
}

// MARK: - Recording Spot (for Map clustering)

struct RecordingSpot: Identifiable, Equatable, Hashable {
    let id: String // cluster key based on rounded coordinates
    let centerCoordinate: CLLocationCoordinate2D
    var displayName: String
    var totalCount: Int
    var favoriteCount: Int
    var recordingIDs: [UUID]

    static func == (lhs: RecordingSpot, rhs: RecordingSpot) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
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
