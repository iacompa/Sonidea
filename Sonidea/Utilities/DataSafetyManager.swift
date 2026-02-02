//
//  DataSafetyManager.swift
//  Sonidea
//
//  Atomic file-based persistence with checksums, backup rotation, and auto-recovery.
//  Replaces raw UserDefaults JSON persistence with a crash-safe, corruption-resistant layer.
//

import Foundation
import CryptoKit
import os

// MARK: - Safe Envelope

/// Wraps every persisted collection with metadata for integrity verification.
struct SafeEnvelope<T: Codable>: Codable {
    /// Schema version for future migrations
    let schemaVersion: Int
    /// SHA-256 hex digest of the JSON-encoded payload
    let checksum: String
    /// When the envelope was written
    let savedAt: Date
    /// Number of items in the collection (for quick sanity checks)
    let itemCount: Int
    /// The actual data payload
    let payload: T

    static var currentSchemaVersion: Int { 1 }
}

// MARK: - Schema Migration

/// Framework for future schema migrations. Each version bump adds a case
/// with a migration closure. Currently a no-op (version 1 is the baseline).
enum SchemaMigration {
    /// Migrate payload data from `fromVersion` to `currentSchemaVersion`.
    /// Returns the payload data re-encoded at the current schema version,
    /// or nil if no migration was needed.
    static func migrate<T: Codable>(payload: [T], from fromVersion: Int) -> [T] {
        // No migrations yet — version 1 is the only version.
        // Future migrations would be chained here:
        // if fromVersion < 2 { payload = migrateV1toV2(payload) }
        // if fromVersion < 3 { payload = migrateV2toV3(payload) }
        return payload
    }
}

// MARK: - Data Safety Error

enum DataSafetyError: LocalizedError {
    case checksumMismatch(expected: String, actual: String)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case directoryCreationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .checksumMismatch(let expected, let actual):
            return "Checksum mismatch: expected \(expected), got \(actual)"
        case .encodingFailed(let error):
            return "Encoding failed: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Decoding failed: \(error.localizedDescription)"
        case .writeFailed(let error):
            return "Write failed: \(error.localizedDescription)"
        case .directoryCreationFailed(let error):
            return "Directory creation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - Collection Identifier

/// Identifies each persisted collection for file naming.
enum CollectionID: String, CaseIterable {
    case recordings
    case tags
    case albums
    case projects
    case overdubGroups

    /// Primary filename (e.g., "recordings.safe.json")
    var filename: String { "\(rawValue).safe.json" }

    /// Backup filename for a given slot (1 = newest backup, 3 = oldest)
    func backupFilename(slot: Int) -> String {
        "\(rawValue).backup\(slot).json"
    }

    /// Legacy UserDefaults key for fallback loading
    var legacyDefaultsKey: String {
        switch self {
        case .recordings: return "savedRecordings"
        case .tags: return "savedTags"
        case .albums: return "savedAlbums"
        case .projects: return "savedProjects"
        case .overdubGroups: return "savedOverdubGroups"
        }
    }
}

// MARK: - DataSafetyManager (Actor)

/// Thread-safe persistence manager using atomic file writes with checksums and backup rotation.
/// Use for async save operations from the main actor.
actor DataSafetyManager {
    private static let logger = Logger(subsystem: "com.iacompa.sonidea", category: "DataSafety")

    /// Number of backup slots to maintain per collection
    static let backupSlots = 3

    /// Shared singleton
    static let shared = DataSafetyManager()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    // MARK: - Save

    /// Save a collection with checksum envelope and backup rotation.
    /// Uses atomic writes (temp file + rename) to prevent corruption.
    func save<T: Codable>(_ items: [T], collection: CollectionID) throws {
        let directory = try DataSafetyFileOps.ensureDirectory()

        // Encode payload
        let payloadData: Data
        do {
            payloadData = try encoder.encode(items)
        } catch {
            Self.logger.error("Encoding failed for \(collection.rawValue): \(error.localizedDescription)")
            throw DataSafetyError.encodingFailed(error)
        }

        // Compute checksum
        let checksum = SHA256.hash(data: payloadData).hexString

        // Build envelope
        let envelope = SafeEnvelope<[T]>(
            schemaVersion: SafeEnvelope<[T]>.currentSchemaVersion,
            checksum: checksum,
            savedAt: Date(),
            itemCount: items.count,
            payload: items
        )

        let envelopeData: Data
        do {
            envelopeData = try encoder.encode(envelope)
        } catch {
            Self.logger.error("Envelope encoding failed for \(collection.rawValue): \(error.localizedDescription)")
            throw DataSafetyError.encodingFailed(error)
        }

        // Rotate backups before writing new primary
        let primaryURL = directory.appendingPathComponent(collection.filename)
        rotateBackups(collection: collection, directory: directory)

        // Atomic write (OS-level temp file + rename)
        do {
            let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
            try envelopeData.write(to: primaryURL, options: writeOptions)
        } catch {
            Self.logger.error("Atomic write failed for \(collection.rawValue): \(error.localizedDescription)")
            throw DataSafetyError.writeFailed(error)
        }

        Self.logger.info("Saved \(collection.rawValue): \(items.count) items, checksum=\(checksum.prefix(8))…")
    }

    /// Load a collection with checksum verification and auto-recovery.
    /// Recovery cascade: primary -> backups (newest first) -> legacy UserDefaults.
    func load<T: Codable>(_ type: T.Type, collection: CollectionID) -> [T] {
        DataSafetyFileOps.load(type, collection: collection)
    }

    // MARK: - Backup Rotation

    /// Rotate backups: slot 3 deleted, 2->3, 1->2, primary->1
    private func rotateBackups(collection: CollectionID, directory: URL) {
        let fm = FileManager.default

        // Delete oldest backup (slot 3)
        let slot3 = directory.appendingPathComponent(collection.backupFilename(slot: Self.backupSlots))
        try? fm.removeItem(at: slot3)

        // Shift each slot up: 2->3, 1->2
        for slot in stride(from: Self.backupSlots - 1, through: 1, by: -1) {
            let source = directory.appendingPathComponent(collection.backupFilename(slot: slot))
            let dest = directory.appendingPathComponent(collection.backupFilename(slot: slot + 1))
            if fm.fileExists(atPath: source.path) {
                try? fm.moveItem(at: source, to: dest)
            }
        }

        // Copy current primary to slot 1 (copy, not move, so primary stays until overwritten atomically)
        let primary = directory.appendingPathComponent(collection.filename)
        let slot1 = directory.appendingPathComponent(collection.backupFilename(slot: 1))
        if fm.fileExists(atPath: primary.path) {
            try? fm.copyItem(at: primary, to: slot1)
        }
    }

    // MARK: - Migration

    /// One-time migration from UserDefaults to file-based storage.
    /// Delegates to the synchronous implementation in DataSafetyFileOps.
    func migrateFromUserDefaultsIfNeeded() {
        DataSafetyFileOps.migrateFromUserDefaultsIfNeeded()
    }
}

// MARK: - DataSafetyFileOps (Synchronous)

/// Synchronous file operations for use during AppState.init() where actor methods cannot be called.
/// Also used as the shared loading logic called by both sync and async paths.
enum DataSafetyFileOps {
    private static let logger = Logger(subsystem: "com.iacompa.sonidea", category: "DataSafetyFileOps")

    /// Application Support directory for Sonidea data files
    static func dataDirectory() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("SonideaData", isDirectory: true)
    }

    /// Ensure the data directory exists, creating it if needed.
    @discardableResult
    static func ensureDirectory() throws -> URL {
        let directory = dataDirectory()
        if !FileManager.default.fileExists(atPath: directory.path) {
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw DataSafetyError.directoryCreationFailed(error)
            }
        }
        return directory
    }

    // MARK: - Load (Synchronous)

    /// Load a collection with checksum verification and auto-recovery.
    /// Recovery cascade: primary file -> backups (newest first) -> legacy UserDefaults.
    static func load<T: Codable>(_ type: T.Type, collection: CollectionID) -> [T] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        let directory = dataDirectory()

        // Try primary file
        let primaryURL = directory.appendingPathComponent(collection.filename)
        if let items: [T] = loadAndVerify(url: primaryURL, decoder: decoder) {
            logger.info("Loaded \(collection.rawValue) from primary: \(items.count) items")
            return items
        }

        // Try backups (newest first)
        for slot in 1...DataSafetyManager.backupSlots {
            let backupURL = directory.appendingPathComponent(collection.backupFilename(slot: slot))
            // First try as envelope
            if let items: [T] = loadAndVerify(url: backupURL, decoder: decoder) {
                logger.warning("Recovered \(collection.rawValue) from backup slot \(slot): \(items.count) items")
                return items
            }
            // Then try as raw array (legacy migration backup)
            if let items: [T] = loadRawArray(url: backupURL, decoder: decoder) {
                logger.warning("Recovered \(collection.rawValue) from legacy backup slot \(slot): \(items.count) items")
                return items
            }
        }

        // Fall back to UserDefaults (legacy)
        if let data = UserDefaults.standard.data(forKey: collection.legacyDefaultsKey) {
            do {
                let items = try decoder.decode([T].self, from: data)
                logger.warning("Recovered \(collection.rawValue) from legacy UserDefaults: \(items.count) items")
                return items
            } catch {
                logger.error("Legacy UserDefaults decode failed for \(collection.rawValue): \(error.localizedDescription)")
            }
        }

        logger.info("No data found for \(collection.rawValue), returning empty")
        return []
    }

    /// Attempt to load and verify a SafeEnvelope from a file URL.
    /// Returns nil if file doesn't exist, can't be decoded, or checksum fails.
    private static func loadAndVerify<T: Codable>(url: URL, decoder: JSONDecoder) -> [T]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        guard let data = try? Data(contentsOf: url) else {
            logger.warning("Cannot read file: \(url.lastPathComponent)")
            return nil
        }

        // Decode envelope
        let envelope: SafeEnvelope<[T]>
        do {
            envelope = try decoder.decode(SafeEnvelope<[T]>.self, from: data)
        } catch {
            logger.warning("Envelope decode failed for \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }

        // Verify checksum
        let payloadEncoder = JSONEncoder()
        payloadEncoder.dateEncodingStrategy = .secondsSince1970
        payloadEncoder.outputFormatting = [.sortedKeys]
        guard let payloadData = try? payloadEncoder.encode(envelope.payload) else {
            logger.warning("Cannot re-encode payload for checksum verification: \(url.lastPathComponent)")
            return nil
        }

        let actualChecksum = SHA256.hash(data: payloadData).hexString
        guard actualChecksum == envelope.checksum else {
            logger.error("Checksum mismatch for \(url.lastPathComponent): expected \(envelope.checksum.prefix(8))…, got \(actualChecksum.prefix(8))…")
            return nil
        }

        // Run schema migration if the envelope is from an older version
        if envelope.schemaVersion < SafeEnvelope<[T]>.currentSchemaVersion {
            logger.info("Migrating \(url.lastPathComponent) from schema v\(envelope.schemaVersion) to v\(SafeEnvelope<[T]>.currentSchemaVersion)")
            return SchemaMigration.migrate(payload: envelope.payload, from: envelope.schemaVersion)
        }

        return envelope.payload
    }

    /// Attempt to load a raw JSON array from a file (for legacy migration backups).
    private static func loadRawArray<T: Codable>(url: URL, decoder: JSONDecoder) -> [T]? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }

        do {
            return try decoder.decode([T].self, from: data)
        } catch {
            return nil
        }
    }

    // MARK: - Migration (Synchronous)

    /// One-time migration: copy existing UserDefaults data to file-based backup slots.
    /// Keeps UserDefaults data intact as fallback. Safe to call multiple times.
    static func migrateFromUserDefaultsIfNeeded() {
        let migrationKey = "dataSafetyMigrationComplete"
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        logger.info("Starting one-time migration from UserDefaults to file-based storage")

        for collection in CollectionID.allCases {
            guard let data = UserDefaults.standard.data(forKey: collection.legacyDefaultsKey) else {
                continue
            }

            do {
                let directory = try ensureDirectory()
                // Write raw UserDefaults data as a backup file (raw array format)
                // The next persist call will create a proper envelope as the primary file
                let backupURL = directory.appendingPathComponent(collection.backupFilename(slot: 1))
                let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
                try data.write(to: backupURL, options: writeOptions)
                logger.info("Migrated \(collection.rawValue) to backup file (\(data.count) bytes)")
            } catch {
                logger.error("Migration failed for \(collection.rawValue): \(error.localizedDescription)")
            }
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
        logger.info("Migration complete")
    }

    // MARK: - Save (Synchronous)

    /// Synchronous save for use in flushPendingSaves() during background transition.
    static func saveSync<T: Codable>(_ items: [T], collection: CollectionID) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]

        guard let directory = try? ensureDirectory() else {
            logger.error("Cannot ensure directory for sync save of \(collection.rawValue)")
            return
        }

        // Encode payload
        guard let payloadData = try? encoder.encode(items) else {
            logger.error("Sync encode failed for \(collection.rawValue)")
            return
        }

        let checksum = SHA256.hash(data: payloadData).hexString

        let envelope = SafeEnvelope<[T]>(
            schemaVersion: SafeEnvelope<[T]>.currentSchemaVersion,
            checksum: checksum,
            savedAt: Date(),
            itemCount: items.count,
            payload: items
        )

        guard let envelopeData = try? encoder.encode(envelope) else {
            logger.error("Sync envelope encode failed for \(collection.rawValue)")
            return
        }

        // Rotate backups
        let fm = FileManager.default
        let oldestBackup = directory.appendingPathComponent(collection.backupFilename(slot: DataSafetyManager.backupSlots))
        try? fm.removeItem(at: oldestBackup)

        for slot in stride(from: DataSafetyManager.backupSlots - 1, through: 1, by: -1) {
            let source = directory.appendingPathComponent(collection.backupFilename(slot: slot))
            let dest = directory.appendingPathComponent(collection.backupFilename(slot: slot + 1))
            if fm.fileExists(atPath: source.path) {
                try? fm.moveItem(at: source, to: dest)
            }
        }

        let primary = directory.appendingPathComponent(collection.filename)
        let slot1 = directory.appendingPathComponent(collection.backupFilename(slot: 1))
        if fm.fileExists(atPath: primary.path) {
            try? fm.copyItem(at: primary, to: slot1)
        }

        // Atomic write
        do {
            let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtection]
            try envelopeData.write(to: primary, options: writeOptions)
            logger.info("Sync saved \(collection.rawValue): \(items.count) items")
        } catch {
            logger.error("Sync write failed for \(collection.rawValue): \(error.localizedDescription)")
        }
    }
}
