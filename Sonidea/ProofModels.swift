//
//  ProofModels.swift
//  Sonidea
//
//  Tamper-evident proof models for recording verification.
//  Uses SHA-256 hashing + CloudKit server timestamps.
//

import Foundation

// MARK: - Proof Status

enum ProofStatus: String, Codable, CaseIterable {
    case none       // Not yet hashed/uploaded
    case pending    // Hash computed, awaiting CloudKit upload
    case proven     // Successfully stored in CloudKit
    case mismatch   // Re-hash doesn't match stored hash (file modified)
    case error      // CloudKit error occurred

    var displayName: String {
        switch self {
        case .none: return "Not Verified"
        case .pending: return "Pending"
        case .proven: return "Verified"
        case .mismatch: return "Mismatch"
        case .error: return "Error"
        }
    }

    var iconName: String {
        switch self {
        case .none: return "shield"
        case .pending: return "shield.lefthalf.filled"
        case .proven: return "checkmark.shield.fill"
        case .mismatch: return "exclamationmark.shield.fill"
        case .error: return "xmark.shield.fill"
        }
    }

    var badgeColor: String {
        switch self {
        case .none: return "gray"
        case .pending: return "orange"
        case .proven: return "green"
        case .mismatch: return "red"
        case .error: return "red"
        }
    }
}

// MARK: - Location Mode

enum LocationMode: String, Codable, CaseIterable {
    case precise    // High-accuracy GPS
    case approx     // Reduced accuracy
    case manual     // User-entered address
    case off        // No location captured

    var displayName: String {
        switch self {
        case .precise: return "Precise"
        case .approx: return "Approximate"
        case .manual: return "Manual"
        case .off: return "Off"
        }
    }

    var confidenceLabel: String {
        switch self {
        case .precise: return "GPS Precise"
        case .approx: return "GPS Approx"
        case .manual: return "Manual Entry"
        case .off: return "Location Off"
        }
    }

    var iconName: String {
        switch self {
        case .precise: return "location.fill"
        case .approx: return "location"
        case .manual: return "pencil.and.list.clipboard"
        case .off: return "location.slash"
        }
    }
}

// MARK: - Location Payload

struct LocationPayload: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double?
    let altitude: Double?
    let timestamp: Date
    let manualAddress: String?

    /// Canonical JSON for hashing (sorted keys, no whitespace)
    var canonicalJSON: Data? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(self)
    }
}

// MARK: - Proof Receipt

struct ProofReceipt: Codable, Identifiable, Equatable {
    let id: UUID
    let recordingID: UUID
    let sha256Hash: String
    let cloudRecordName: String?
    let cloudCreatedAt: Date?
    let locationPayload: LocationPayload?
    let locationMode: LocationMode
    let locationProofHash: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        recordingID: UUID,
        sha256Hash: String,
        cloudRecordName: String? = nil,
        cloudCreatedAt: Date? = nil,
        locationPayload: LocationPayload? = nil,
        locationMode: LocationMode = .off,
        locationProofHash: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.recordingID = recordingID
        self.sha256Hash = sha256Hash
        self.cloudRecordName = cloudRecordName
        self.cloudCreatedAt = cloudCreatedAt
        self.locationPayload = locationPayload
        self.locationMode = locationMode
        self.locationProofHash = locationProofHash
        self.createdAt = createdAt
    }

    /// Whether this receipt has been confirmed by CloudKit
    var isCloudConfirmed: Bool {
        cloudRecordName != nil && cloudCreatedAt != nil
    }
}

// MARK: - Pending Proof Item (for offline queue)

struct PendingProofItem: Codable, Identifiable {
    let id: UUID
    let recordingID: UUID
    let sha256Hash: String
    let locationPayload: LocationPayload?
    let locationMode: LocationMode
    let createdAt: Date
    var retryCount: Int
    var lastRetryAt: Date?

    init(
        id: UUID = UUID(),
        recordingID: UUID,
        sha256Hash: String,
        locationPayload: LocationPayload? = nil,
        locationMode: LocationMode = .off,
        createdAt: Date = Date(),
        retryCount: Int = 0,
        lastRetryAt: Date? = nil
    ) {
        self.id = id
        self.recordingID = recordingID
        self.sha256Hash = sha256Hash
        self.locationPayload = locationPayload
        self.locationMode = locationMode
        self.createdAt = createdAt
        self.retryCount = retryCount
        self.lastRetryAt = lastRetryAt
    }

    /// Maximum retry attempts before giving up
    static let maxRetries = 5

    /// Whether this item should be retried
    var shouldRetry: Bool {
        retryCount < Self.maxRetries
    }
}
