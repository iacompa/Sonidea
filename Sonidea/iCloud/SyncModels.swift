//
//  SyncModels.swift
//  Sonidea
//
//  Models for iCloud sync functionality.
//

import Foundation
import UIKit

// MARK: - Syncable Data Container

/// Container for all data that should be synced to iCloud
struct SyncableData: Codable {
    var recordings: [RecordingItem]
    var tags: [Tag]
    var albums: [Album]
    var projects: [Project]
    var lastModified: Date
    var deviceIdentifier: String

    static let empty = SyncableData(
        recordings: [],
        tags: [],
        albums: [],
        projects: [],
        lastModified: Date.distantPast,
        deviceIdentifier: ""
    )

    init(
        recordings: [RecordingItem],
        tags: [Tag],
        albums: [Album],
        projects: [Project],
        lastModified: Date = Date(),
        deviceIdentifier: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    ) {
        self.recordings = recordings
        self.tags = tags
        self.albums = albums
        self.projects = projects
        self.lastModified = lastModified
        self.deviceIdentifier = deviceIdentifier
    }
}

// MARK: - Sync Status

enum SyncStatus: Equatable {
    case idle
    case syncing
    case success(Date)
    case error(String)

    var isIdle: Bool {
        if case .idle = self { return true }
        return false
    }

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }
}

// MARK: - Sync Error

enum SyncError: Error, LocalizedError {
    case iCloudUnavailable
    case notSignedIn
    case containerNotFound
    case networkError(Error)
    case encodingError(Error)
    case decodingError(Error)
    case fileOperationFailed(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available on this device"
        case .notSignedIn:
            return "Please sign in to iCloud in Settings"
        case .containerNotFound:
            return "iCloud container not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode data: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode data: \(error.localizedDescription)"
        case .fileOperationFailed(let error):
            return "File operation failed: \(error.localizedDescription)"
        case .unknown(let error):
            return "Unknown error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Sync Progress

struct SyncProgress {
    var phase: SyncPhase
    var current: Int
    var total: Int

    var progress: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total)
    }

    static let idle = SyncProgress(phase: .idle, current: 0, total: 0)
}

enum SyncPhase: String {
    case idle = "Idle"
    case preparingData = "Preparing data..."
    case uploadingMetadata = "Uploading metadata..."
    case uploadingAudio = "Uploading audio files..."
    case downloadingMetadata = "Downloading metadata..."
    case downloadingAudio = "Downloading audio files..."
    case mergingData = "Merging data..."
    case complete = "Complete"
}
