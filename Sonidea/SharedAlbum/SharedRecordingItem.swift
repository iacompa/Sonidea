//
//  SharedRecordingItem.swift
//  Sonidea
//
//  Wrapper model for recordings in a shared album context.
//  Tracks creator attribution, location sharing, and sensitive mode.
//

import Foundation

/// A wrapper for recordings in shared album context with additional metadata
struct SharedRecordingItem: Identifiable, Codable, Equatable {
    let id: UUID
    let recordingId: UUID
    let albumId: UUID
    let creatorId: String
    let creatorDisplayName: String
    let createdAt: Date

    // MARK: - Attribution

    /// Whether this recording was imported from external source
    var wasImported: Bool = false

    /// Whether this was recorded with headphones connected
    var recordedWithHeadphones: Bool = false

    // MARK: - Sensitive Mode

    /// Whether this recording is marked as sensitive
    var isSensitive: Bool = false

    /// Whether admin has approved this sensitive recording for viewing
    var sensitiveApproved: Bool = false

    /// ID of admin who approved the sensitive recording
    var sensitiveApprovedBy: String?

    /// When the sensitive recording was approved
    var sensitiveApprovedAt: Date?

    // MARK: - Location Sharing

    /// Location sharing mode for this recording
    var locationSharingMode: LocationSharingMode = .none

    /// Shared latitude (may be approximated based on mode)
    var sharedLatitude: Double?

    /// Shared longitude (may be approximated based on mode)
    var sharedLongitude: Double?

    /// Human-readable place name
    var sharedPlaceName: String?

    // MARK: - Download Permission

    /// Whether other users are allowed to download (cache locally) this recording
    var allowDownload: Bool = false

    // MARK: - Verified Status

    /// Whether this recording has been verified/authenticated
    var isVerified: Bool = false

    /// When the recording was verified
    var verifiedAt: Date?

    // MARK: - Computed Properties

    /// Whether this recording has shared location data
    var hasSharedLocation: Bool {
        locationSharingMode != .none && sharedLatitude != nil && sharedLongitude != nil
    }

    /// Whether this recording requires sensitive content warning
    var requiresSensitiveWarning: Bool {
        isSensitive && !sensitiveApproved
    }

    /// Creator initials for avatar display
    var creatorInitials: String {
        SharedAlbumParticipant.generateInitials(from: creatorDisplayName)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        recordingId: UUID,
        albumId: UUID,
        creatorId: String,
        creatorDisplayName: String,
        createdAt: Date = Date(),
        wasImported: Bool = false,
        recordedWithHeadphones: Bool = false,
        isSensitive: Bool = false,
        sensitiveApproved: Bool = false,
        sensitiveApprovedBy: String? = nil,
        sensitiveApprovedAt: Date? = nil,
        allowDownload: Bool = false,
        locationSharingMode: LocationSharingMode = .none,
        sharedLatitude: Double? = nil,
        sharedLongitude: Double? = nil,
        sharedPlaceName: String? = nil,
        isVerified: Bool = false,
        verifiedAt: Date? = nil
    ) {
        self.id = id
        self.recordingId = recordingId
        self.albumId = albumId
        self.creatorId = creatorId
        self.creatorDisplayName = creatorDisplayName
        self.createdAt = createdAt
        self.wasImported = wasImported
        self.recordedWithHeadphones = recordedWithHeadphones
        self.isSensitive = isSensitive
        self.sensitiveApproved = sensitiveApproved
        self.sensitiveApprovedBy = sensitiveApprovedBy
        self.sensitiveApprovedAt = sensitiveApprovedAt
        self.allowDownload = allowDownload
        self.locationSharingMode = locationSharingMode
        self.sharedLatitude = sharedLatitude
        self.sharedLongitude = sharedLongitude
        self.sharedPlaceName = sharedPlaceName
        self.isVerified = isVerified
        self.verifiedAt = verifiedAt
    }

    // MARK: - Location Helpers

    /// Apply location approximation based on sharing mode
    static func approximateLocation(
        latitude: Double,
        longitude: Double,
        mode: LocationSharingMode
    ) -> (latitude: Double, longitude: Double)? {
        switch mode {
        case .none:
            return nil
        case .precise:
            return (latitude, longitude)
        case .approximate:
            // Round to ~500m precision (about 3 decimal places for lat/lon)
            let roundedLat = (latitude * 200).rounded() / 200  // ~500m
            let roundedLon = (longitude * 200).rounded() / 200
            return (roundedLat, roundedLon)
        }
    }

    /// Create a SharedRecordingItem from a RecordingItem
    static func from(
        recording: RecordingItem,
        albumId: UUID,
        creatorId: String,
        creatorDisplayName: String,
        locationMode: LocationSharingMode = .none
    ) -> SharedRecordingItem {
        var sharedLat: Double?
        var sharedLon: Double?

        if locationMode != .none, let lat = recording.latitude, let lon = recording.longitude {
            if let approx = approximateLocation(latitude: lat, longitude: lon, mode: locationMode) {
                sharedLat = approx.latitude
                sharedLon = approx.longitude
            }
        }

        return SharedRecordingItem(
            recordingId: recording.id,
            albumId: albumId,
            creatorId: creatorId,
            creatorDisplayName: creatorDisplayName,
            createdAt: recording.createdAt,
            locationSharingMode: locationMode,
            sharedLatitude: sharedLat,
            sharedLongitude: sharedLon,
            sharedPlaceName: locationMode != .none ? recording.locationLabel : nil,
            isVerified: recording.hasProof,
            verifiedAt: recording.proofCloudCreatedAt
        )
    }
}

// MARK: - Badge Types for SharedRecordingRow

enum SharedRecordingBadge: String, CaseIterable {
    case imported
    case headphones
    case sensitive
    case verified
    case location

    var iconName: String {
        switch self {
        case .imported: return "square.and.arrow.down"
        case .headphones: return "headphones"
        case .sensitive: return "eye.slash"
        case .verified: return "checkmark.seal.fill"
        case .location: return "location.fill"
        }
    }

    var displayName: String {
        switch self {
        case .imported: return "Imported"
        case .headphones: return "Headphones"
        case .sensitive: return "Sensitive"
        case .verified: return "Verified"
        case .location: return "Location"
        }
    }
}
