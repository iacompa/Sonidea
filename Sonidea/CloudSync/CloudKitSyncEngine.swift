//
//  CloudKitSyncEngine.swift
//  Sonidea
//
//  Production-grade CloudKit sync engine with:
//  - Real-time push notifications via CKSubscription
//  - Background sync tasks
//  - CKAssets for audio files
//  - Proper conflict resolution
//  - Tombstones for deletions
//  - Per-file progress tracking
//

import Foundation
import CloudKit
import Observation
import UIKit
import BackgroundTasks
import OSLog

// MARK: - Sync Status

@MainActor
enum CloudSyncStatus: Equatable {
    case disabled
    case initializing
    case syncing(progress: Double, description: String)
    case synced(Date)
    case error(String)
    case accountUnavailable
    case networkUnavailable

    var displayText: String {
        switch self {
        case .disabled: return "Sync Off"
        case .initializing: return "Setting up..."
        case .syncing(_, let desc): return desc
        case .synced(let date):
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Synced \(formatter.localizedString(for: date, relativeTo: Date()))"
        case .error(let msg): return msg
        case .accountUnavailable: return "Sign in to iCloud"
        case .networkUnavailable: return "No Connection"
        }
    }

    var iconName: String {
        switch self {
        case .disabled: return "icloud.slash"
        case .initializing, .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud.fill"
        case .error: return "exclamationmark.icloud.fill"
        case .accountUnavailable: return "person.icloud"
        case .networkUnavailable: return "icloud.slash"
        }
    }

    var progress: Double? {
        if case .syncing(let p, _) = self { return p }
        return nil
    }
}

// MARK: - Record Types

enum SonideaRecordType: String {
    case recording = "Recording"
    case tag = "Tag"
    case album = "Album"
    case project = "Project"
    case overdubGroup = "OverdubGroup"
    case tombstone = "Tombstone"  // For tracking deletions
    case syncState = "SyncState"  // For tracking sync metadata
}

// MARK: - Tombstone

struct Tombstone: Codable, Identifiable {
    let id: UUID
    let recordType: String
    let deletedAt: Date
    let deviceId: String
}

// MARK: - Pending Sync Operation

struct PendingSyncOperation: Codable, Identifiable {
    let id: UUID
    let operationType: OperationType
    let recordType: String      // SonideaRecordType rawValue
    let recordId: String        // UUID string of the record
    let createdAt: Date
    var retryCount: Int

    enum OperationType: String, Codable {
        case save
        case delete
    }

    init(operationType: OperationType, recordType: String, recordId: String) {
        self.id = UUID()
        self.operationType = operationType
        self.recordType = recordType
        self.recordId = recordId
        self.createdAt = Date()
        self.retryCount = 0
    }
}

// MARK: - CloudKit Sync Engine

@MainActor
@Observable
final class CloudKitSyncEngine {

    // MARK: - Observable State

    var status: CloudSyncStatus = .disabled
    var uploadProgress: [UploadProgress] = []
    var lastSyncDate: Date?
    var pendingChangesCount: Int = 0

    // MARK: - Configuration

    private let containerIdentifier = "iCloud.com.iacompa.sonidea"
    private let subscriptionID = "all-changes-subscription"
    private let zoneID = CKRecordZone.ID(zoneName: "SonideaZone", ownerName: CKCurrentUserDefaultName)
    private let backgroundTaskIdentifier = "com.iacompa.sonidea.sync"

    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "CloudKitSync")

    // MARK: - CloudKit Objects

    private let container: CKContainer
    private let privateDatabase: CKDatabase

    // MARK: - State

    private var isEnabled = false
    private var syncTask: Task<Void, Never>?
    private var accountChangeObserver: NSObjectProtocol?
    private var changeToken: CKServerChangeToken?
    private var tombstones: [Tombstone] = []
    private var pendingOperations: [PendingSyncOperation] = []
    private var deviceId: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    /// Tracks the last synced modifiedAt date per record ID to avoid re-uploading unchanged items
    private var lastSyncedDates: [String: Date] = [:]

    /// Tracks content fingerprints for lightweight records (tags, albums) to skip unchanged items during full sync
    private var lastSyncedFingerprints: [String: String] = [:]

    // Weak reference to AppState
    weak var appState: AppState?

    // MARK: - Persistence Keys

    private let changeTokenKey = "cloudkit.changeToken"
    private let tombstonesKey = "cloudkit.tombstones"
    private let lastSyncKey = "cloudkit.lastSync"
    private let zoneCreatedKey = "cloudkit.zoneCreated"
    private let subscriptionCreatedKey = "cloudkit.subscriptionCreated"
    private let lastSyncedDatesKey = "cloudkit.lastSyncedDates"
    private let lastSyncedFingerprintsKey = "cloudkit.lastSyncedFingerprints"
    private let pendingOperationsKey = "cloudkit.pendingOperations"

    // MARK: - Initialization

    init() {
        let c = CKContainer(identifier: "iCloud.com.iacompa.sonidea")
        self.container = c
        self.privateDatabase = c.privateCloudDatabase
        loadPersistedState()
    }

    // MARK: - Public API

    /// Enable CloudKit sync
    func enable() async {
        guard !isEnabled else { return }

        logger.info("Enabling CloudKit sync")
        status = .initializing
        isEnabled = true

        // Check account status
        do {
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                status = .accountUnavailable
                isEnabled = false
                return
            }
        } catch {
            logger.error("Failed to check account status: \(error.localizedDescription)")
            status = .error("iCloud unavailable")
            isEnabled = false
            return
        }

        // Observe iCloud account changes
        accountChangeObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name.CKAccountChanged,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.handleAccountChange()
            }
        }

        // Setup CloudKit infrastructure
        do {
            try await setupZone()
            try await setupSubscription()
            await performFullSync()
        } catch {
            logger.error("Failed to setup CloudKit: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
    }

    /// Disable CloudKit sync
    func disable() {
        logger.info("Disabling CloudKit sync")
        isEnabled = false
        syncTask?.cancel()
        syncTask = nil
        if let observer = accountChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            accountChangeObserver = nil
        }
        status = .disabled
    }

    /// Trigger sync (debounced)
    func triggerSync() {
        guard isEnabled else { return }

        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5s debounce
            guard !Task.isCancelled else { return }
            await performFullSync()
        }
    }

    /// Handle remote notification
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard isEnabled else { return }

        logger.info("Handling remote notification")

        // Parse the notification
        if let ckNotification = CKNotification(fromRemoteNotificationDictionary: userInfo) {
            if ckNotification.notificationType == .database {
                await fetchChanges()
            }
        }
    }

    /// Sync on app foreground — runs full sync to retry any failed uploads
    func syncOnForeground() async {
        guard isEnabled else { return }
        logger.info("Syncing on foreground")
        await performFullSync()
    }

    /// Handle iCloud account change (sign out, sign in as different user)
    private func handleAccountChange() async {
        logger.info("iCloud account changed, re-checking status")
        do {
            let accountStatus = try await container.accountStatus()
            if accountStatus == .available {
                // Account switched — reset sync state and re-setup
                changeToken = nil
                saveChangeToken()
                lastSyncedDates.removeAll()
                saveLastSyncedDates()
                lastSyncedFingerprints.removeAll()
                saveLastSyncedFingerprints()
                UserDefaults.standard.removeObject(forKey: zoneCreatedKey)
                UserDefaults.standard.removeObject(forKey: subscriptionCreatedKey)

                try await setupZone()
                try await setupSubscription()
                await performFullSync()
            } else {
                status = .accountUnavailable
            }
        } catch {
            logger.error("Failed to handle account change: \(error.localizedDescription)")
            status = .error("iCloud account error")
        }
    }

    // MARK: - Record Operations

    /// Save a recording to CloudKit
    func saveRecording(_ recording: RecordingItem) async throws {
        guard isEnabled else { return }

        // Fetch existing record to preserve server change tag, or create new
        let recordID = CKRecord.ID(recordName: recording.id.uuidString, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: SonideaRecordType.recording.rawValue, recordID: recordID)
        }

        // Populate fields on the (possibly existing) record
        let populateFields: (CKRecord) -> Void = { rec in
            recording.populateCKRecord(rec)
            // Add audio file as CKAsset if it exists
            if FileManager.default.fileExists(atPath: recording.fileURL.path) {
                let asset = CKAsset(fileURL: recording.fileURL)
                rec["audioFile"] = asset
            }
        }
        populateFields(record)

        // Check file size — warn for very large files (>200MB)
        if FileManager.default.fileExists(atPath: recording.fileURL.path) {
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: recording.fileURL.path)[.size] as? Int) ?? 0
            if fileSize > 200_000_000 {
                logger.warning("Large audio file (\(fileSize / 1_000_000)MB) for recording \(recording.id) — upload may be slow")
            }

            // Track upload progress
            let progress = UploadProgress(
                id: recording.id,
                fileName: recording.fileURL.lastPathComponent,
                progress: 0,
                status: .uploading
            )
            uploadProgress.append(progress)
        }

        status = .syncing(progress: 0, description: "Uploading \(recording.title)...")

        do {
            try await saveWithConflictResolution(record, populate: populateFields)

            // Mark upload complete
            if let index = uploadProgress.firstIndex(where: { $0.id == recording.id }) {
                uploadProgress[index].status = .completed
                uploadProgress[index].progress = 1.0
            }

            logger.info("Saved recording: \(recording.id)")
            updateLastSync()

        } catch {
            // Mark upload failed
            if let index = uploadProgress.firstIndex(where: { $0.id == recording.id }) {
                uploadProgress[index].status = .failed(error.localizedDescription)
            }
            throw error
        }
    }

    /// Delete a recording from CloudKit
    func deleteRecording(_ recordingId: UUID) async throws {
        guard isEnabled else { return }

        let recordID = CKRecord.ID(recordName: recordingId.uuidString, zoneID: zoneID)

        // Create tombstone
        let tombstone = Tombstone(
            id: recordingId,
            recordType: SonideaRecordType.recording.rawValue,
            deletedAt: Date(),
            deviceId: deviceId
        )
        tombstones.append(tombstone)
        saveTombstones()

        // Save tombstone record
        let tombstoneRecord = CKRecord(recordType: SonideaRecordType.tombstone.rawValue, recordID: CKRecord.ID(recordName: "tombstone-\(recordingId.uuidString)", zoneID: zoneID))
        tombstoneRecord["targetId"] = recordingId.uuidString
        tombstoneRecord["targetType"] = SonideaRecordType.recording.rawValue
        tombstoneRecord["deletedAt"] = tombstone.deletedAt
        tombstoneRecord["deviceId"] = deviceId

        do {
            try await privateDatabase.modifyRecords(saving: [tombstoneRecord], deleting: [recordID])
            logger.info("Deleted recording from CloudKit: \(recordingId)")
            updateLastSync()
        } catch {
            logger.error("Failed to delete recording: \(error.localizedDescription)")
            throw error
        }
    }

    /// Save a tag to CloudKit
    func saveTag(_ tag: Tag) async throws {
        guard isEnabled else { return }

        // Fetch existing record to preserve server change tag, or create new
        let recordID = CKRecord.ID(recordName: tag.id.uuidString, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: SonideaRecordType.tag.rawValue, recordID: recordID)
        }

        tag.populateCKRecord(record)

        do {
            try await saveWithConflictResolution(record) { rec in
                tag.populateCKRecord(rec)
            }
            logger.info("Saved tag: \(tag.id)")
            updateLastSync()
        } catch {
            throw error
        }
    }

    /// Save an album to CloudKit
    func saveAlbum(_ album: Album) async throws {
        guard isEnabled else { return }

        // Fetch existing record to preserve server change tag, or create new
        let recordID = CKRecord.ID(recordName: album.id.uuidString, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: SonideaRecordType.album.rawValue, recordID: recordID)
        }

        album.populateCKRecord(record)

        do {
            try await saveWithConflictResolution(record) { rec in
                album.populateCKRecord(rec)
            }
            logger.info("Saved album: \(album.id)")
            updateLastSync()
        } catch {
            throw error
        }
    }

    /// Save a project to CloudKit
    func saveProject(_ project: Project) async throws {
        guard isEnabled else { return }

        // Fetch existing record to preserve server change tag, or create new
        let recordID = CKRecord.ID(recordName: project.id.uuidString, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: SonideaRecordType.project.rawValue, recordID: recordID)
        }

        project.populateCKRecord(record)

        do {
            try await saveWithConflictResolution(record) { rec in
                project.populateCKRecord(rec)
            }
            logger.info("Saved project: \(project.id)")
            updateLastSync()
        } catch {
            throw error
        }
    }

    /// Delete a tag from CloudKit
    func deleteTag(_ tagId: UUID) async throws {
        guard isEnabled else { return }

        let recordID = CKRecord.ID(recordName: tagId.uuidString, zoneID: zoneID)

        // Create tombstone
        let tombstone = Tombstone(
            id: tagId,
            recordType: SonideaRecordType.tag.rawValue,
            deletedAt: Date(),
            deviceId: deviceId
        )
        tombstones.append(tombstone)
        saveTombstones()

        // Save tombstone record
        let tombstoneRecord = CKRecord(recordType: SonideaRecordType.tombstone.rawValue, recordID: CKRecord.ID(recordName: "tombstone-\(tagId.uuidString)", zoneID: zoneID))
        tombstoneRecord["targetId"] = tagId.uuidString
        tombstoneRecord["targetType"] = SonideaRecordType.tag.rawValue
        tombstoneRecord["deletedAt"] = tombstone.deletedAt
        tombstoneRecord["deviceId"] = deviceId

        do {
            try await privateDatabase.modifyRecords(saving: [tombstoneRecord], deleting: [recordID])
            logger.info("Deleted tag from CloudKit: \(tagId)")
            updateLastSync()
        } catch {
            logger.error("Failed to delete tag: \(error.localizedDescription)")
            throw error
        }
    }

    /// Delete an album from CloudKit
    func deleteAlbum(_ albumId: UUID) async throws {
        guard isEnabled else { return }

        let recordID = CKRecord.ID(recordName: albumId.uuidString, zoneID: zoneID)

        // Create tombstone
        let tombstone = Tombstone(
            id: albumId,
            recordType: SonideaRecordType.album.rawValue,
            deletedAt: Date(),
            deviceId: deviceId
        )
        tombstones.append(tombstone)
        saveTombstones()

        // Save tombstone record
        let tombstoneRecord = CKRecord(recordType: SonideaRecordType.tombstone.rawValue, recordID: CKRecord.ID(recordName: "tombstone-\(albumId.uuidString)", zoneID: zoneID))
        tombstoneRecord["targetId"] = albumId.uuidString
        tombstoneRecord["targetType"] = SonideaRecordType.album.rawValue
        tombstoneRecord["deletedAt"] = tombstone.deletedAt
        tombstoneRecord["deviceId"] = deviceId

        do {
            try await privateDatabase.modifyRecords(saving: [tombstoneRecord], deleting: [recordID])
            logger.info("Deleted album from CloudKit: \(albumId)")
            updateLastSync()
        } catch {
            logger.error("Failed to delete album: \(error.localizedDescription)")
            throw error
        }
    }

    /// Delete a project from CloudKit
    func deleteProject(_ projectId: UUID) async throws {
        guard isEnabled else { return }

        let recordID = CKRecord.ID(recordName: projectId.uuidString, zoneID: zoneID)

        // Create tombstone
        let tombstone = Tombstone(
            id: projectId,
            recordType: SonideaRecordType.project.rawValue,
            deletedAt: Date(),
            deviceId: deviceId
        )
        tombstones.append(tombstone)
        saveTombstones()

        // Save tombstone record
        let tombstoneRecord = CKRecord(recordType: SonideaRecordType.tombstone.rawValue, recordID: CKRecord.ID(recordName: "tombstone-\(projectId.uuidString)", zoneID: zoneID))
        tombstoneRecord["targetId"] = projectId.uuidString
        tombstoneRecord["targetType"] = SonideaRecordType.project.rawValue
        tombstoneRecord["deletedAt"] = tombstone.deletedAt
        tombstoneRecord["deviceId"] = deviceId

        do {
            try await privateDatabase.modifyRecords(saving: [tombstoneRecord], deleting: [recordID])
            logger.info("Deleted project from CloudKit: \(projectId)")
            updateLastSync()
        } catch {
            logger.error("Failed to delete project: \(error.localizedDescription)")
            throw error
        }
    }

    /// Save an overdub group to CloudKit
    func saveOverdubGroup(_ group: OverdubGroup) async throws {
        guard isEnabled else { return }

        // Fetch existing record to preserve server change tag, or create new
        let recordID = CKRecord.ID(recordName: group.id.uuidString, zoneID: zoneID)
        let record: CKRecord
        do {
            record = try await privateDatabase.record(for: recordID)
        } catch {
            record = CKRecord(recordType: SonideaRecordType.overdubGroup.rawValue, recordID: recordID)
        }

        group.populateCKRecord(record)

        do {
            try await saveWithConflictResolution(record) { rec in
                group.populateCKRecord(rec)
            }
            logger.info("Saved overdub group: \(group.id)")
            updateLastSync()
        } catch {
            throw error
        }
    }

    /// Delete an overdub group from CloudKit
    func deleteOverdubGroup(_ groupId: UUID) async throws {
        guard isEnabled else { return }

        let recordID = CKRecord.ID(recordName: groupId.uuidString, zoneID: zoneID)

        // Create tombstone
        let tombstone = Tombstone(
            id: groupId,
            recordType: SonideaRecordType.overdubGroup.rawValue,
            deletedAt: Date(),
            deviceId: deviceId
        )
        tombstones.append(tombstone)
        saveTombstones()

        // Save tombstone record
        let tombstoneRecord = CKRecord(recordType: SonideaRecordType.tombstone.rawValue, recordID: CKRecord.ID(recordName: "tombstone-\(groupId.uuidString)", zoneID: zoneID))
        tombstoneRecord["targetId"] = groupId.uuidString
        tombstoneRecord["targetType"] = SonideaRecordType.overdubGroup.rawValue
        tombstoneRecord["deletedAt"] = tombstone.deletedAt
        tombstoneRecord["deviceId"] = deviceId

        do {
            try await privateDatabase.modifyRecords(saving: [tombstoneRecord], deleting: [recordID])
            logger.info("Deleted overdub group from CloudKit: \(groupId)")
            updateLastSync()
        } catch {
            logger.error("Failed to delete overdub group: \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Zone Setup

    private func setupZone() async throws {
        // Check if zone already created
        if UserDefaults.standard.bool(forKey: zoneCreatedKey) {
            return
        }

        let zone = CKRecordZone(zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecordZones(saving: [zone], deleting: [])
            UserDefaults.standard.set(true, forKey: zoneCreatedKey)
            logger.info("Created custom zone")
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Zone already exists, that's fine
            UserDefaults.standard.set(true, forKey: zoneCreatedKey)
        }
    }

    // MARK: - Subscription Setup

    private func setupSubscription() async throws {
        // Check if subscription already created
        if UserDefaults.standard.bool(forKey: subscriptionCreatedKey) {
            return
        }

        let subscription = CKDatabaseSubscription(subscriptionID: subscriptionID)

        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true  // Silent push
        subscription.notificationInfo = notificationInfo

        do {
            try await privateDatabase.modifySubscriptions(saving: [subscription], deleting: [])
            UserDefaults.standard.set(true, forKey: subscriptionCreatedKey)
            logger.info("Created database subscription")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription might already exist
            UserDefaults.standard.set(true, forKey: subscriptionCreatedKey)
        }
    }

    // MARK: - Full Sync

    private func performFullSync() async {
        guard let appState = appState else { return }

        uploadProgress.removeAll()
        status = .syncing(progress: 0, description: "Syncing...")

        // Drain any queued operations from previous failed syncs
        await drainPendingOperations()

        // Upload local changes — skip items whose modifiedAt hasn't changed since last sync
        let recordings = appState.recordings
        let tags = appState.tags
        let albums = appState.albums
        let projects = appState.projects

        // Filter to only items that have changed since last synced
        let recordingsToSync = recordings.filter { recording in
            guard let lastSynced = lastSyncedDates[recording.id.uuidString] else { return true }
            return recording.modifiedAt > lastSynced
        }
        let projectsToSync = projects.filter { project in
            guard let lastSynced = lastSyncedDates[project.id.uuidString] else { return true }
            return project.updatedAt > lastSynced
        }
        // Filter tags and albums to only those whose content has changed since last sync
        let tagsToSync = tags.filter { tag in
            let fingerprint = "\(tag.name)|\(tag.colorHex)"
            return needsSync(id: tag.id.uuidString, fingerprint: fingerprint)
        }
        let albumsToSync = albums.filter { album in
            let fingerprint = "\(album.name)|\(album.isSystem)|\(album.isShared)"
            return needsSync(id: album.id.uuidString, fingerprint: fingerprint)
        }
        let totalItems = recordingsToSync.count + tagsToSync.count + albumsToSync.count + projectsToSync.count
        var completed = 0
        var quotaExceeded = false

        logger.info("Full sync: \(recordingsToSync.count)/\(recordings.count) recordings, \(tagsToSync.count)/\(tags.count) tags, \(albumsToSync.count)/\(albums.count) albums, \(projectsToSync.count)/\(projects.count) projects need upload")

        // Batch upload recordings (only changed ones)
        for recording in recordingsToSync {
            if quotaExceeded { break }
            status = .syncing(
                progress: Double(completed) / Double(max(1, totalItems)),
                description: "Uploading \(recording.title)..."
            )
            do {
                try await withRetry {
                    try await self.saveRecording(recording)
                }
                markSynced(id: recording.id.uuidString, modifiedAt: recording.modifiedAt)
            } catch let ckError as CKError where ckError.code == .quotaExceeded {
                logger.error("iCloud storage quota exceeded — stopping uploads")
                quotaExceeded = true
            } catch {
                logger.error("Failed to sync recording after retries: \(error.localizedDescription)")
                // Continue with next recording
            }
            completed += 1
            // Save progress periodically (every 10 items)
            if completed % 10 == 0 {
                saveLastSyncedDates()
            }
        }

        if quotaExceeded {
            saveLastSyncedDates()
            status = .error("iCloud storage full — recordings not backed up")
            return
        }

        // Batch upload tags (only changed ones)
        for tag in tagsToSync {
            let fingerprint = "\(tag.name)|\(tag.colorHex)"
            do {
                try await withRetry {
                    try await self.saveTag(tag)
                }
                markSyncedFingerprint(id: tag.id.uuidString, fingerprint: fingerprint)
            } catch {
                logger.error("Failed to sync tag after retries: \(error.localizedDescription)")
            }
            completed += 1
            status = .syncing(
                progress: Double(completed) / Double(max(1, totalItems)),
                description: "Syncing tags..."
            )
        }

        // Batch upload albums (only changed ones)
        for album in albumsToSync {
            let fingerprint = "\(album.name)|\(album.isSystem)|\(album.isShared)"
            do {
                try await withRetry {
                    try await self.saveAlbum(album)
                }
                markSyncedFingerprint(id: album.id.uuidString, fingerprint: fingerprint)
            } catch {
                logger.error("Failed to sync album after retries: \(error.localizedDescription)")
            }
            completed += 1
        }

        // Batch upload projects (only changed ones)
        for project in projectsToSync {
            do {
                try await withRetry {
                    try await self.saveProject(project)
                }
                markSynced(id: project.id.uuidString, modifiedAt: project.updatedAt)
            } catch {
                logger.error("Failed to sync project after retries: \(error.localizedDescription)")
            }
            completed += 1
        }

        // Batch upload overdub groups (lightweight — always sync all)
        if let overdubGroups = appState.overdubGroups as [OverdubGroup]? {
            for group in overdubGroups {
                do {
                    try await withRetry {
                        try await self.saveOverdubGroup(group)
                    }
                } catch {
                    logger.error("Failed to sync overdub group after retries: \(error.localizedDescription)")
                }
            }
        }

        // Persist the synced dates and fingerprints
        saveLastSyncedDates()
        saveLastSyncedFingerprints()

        // Fetch remote changes
        let fetchSucceeded = await fetchChanges()

        // Only show "Synced" if fetch succeeded
        if fetchSucceeded {
            updateLastSync()
            status = .synced(lastSyncDate ?? Date())
        } else {
            // Uploads succeeded but fetch failed — still persist sync dates
            // but don't claim we're fully synced
            status = .error("Failed to download changes")
        }
    }

    // MARK: - Fetch Changes

    /// Fetch remote changes. Returns `true` on success, `false` on failure.
    /// Handles `moreComing` pagination and tolerates individual record errors
    /// so that a single corrupted record does not abort the entire fetch loop.
    @discardableResult
    private func fetchChanges() async -> Bool {
        guard let appState = appState else { return false }

        status = .syncing(progress: 0.5, description: "Checking for changes...")

        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []
        var currentToken = changeToken
        var pageCount = 0
        var individualFailureCount = 0

        // Pagination loop — CloudKit may split large result sets across multiple pages.
        // Each page sets `moreComing = true` until the final page.
        var hasMore = true
        while hasMore {
            pageCount += 1
            hasMore = false

            do {
                let changes = try await privateDatabase.recordZoneChanges(
                    inZoneWith: zoneID,
                    since: currentToken
                )

                // Process changed records — handle individual record successes and failures
                for (recordID, result) in changes.modificationResultsByID {
                    switch result {
                    case .success(let modification):
                        changedRecords.append(modification.record)
                    case .failure(let recordError):
                        individualFailureCount += 1
                        logger.error("Failed to fetch record \(recordID.recordName): \(recordError.localizedDescription)")
                        #if DEBUG
                        print("[CloudKitSync] fetchChanges: skipping bad record \(recordID.recordName) — \(recordError.localizedDescription)")
                        #endif
                    }
                }

                // Process deletions
                for deletion in changes.deletions {
                    deletedRecordIDs.append(deletion.recordID)
                }

                // Advance the token for the next page (or final persist)
                currentToken = changes.changeToken

                // Continue if CloudKit indicates more pages are available
                hasMore = changes.moreComing
                if hasMore {
                    logger.info("Fetch page \(pageCount) complete, more pages coming...")
                }

            } catch let ckError as CKError where ckError.code == .changeTokenExpired {
                // Token expired — reset and retry with full fetch
                logger.warning("Change token expired, resetting and retrying full fetch")
                changeToken = nil
                saveChangeToken()
                return await fetchChanges()

            } catch let ckError as CKError where ckError.code == .zoneNotFound || ckError.code == .userDeletedZone {
                // Zone was deleted — attempt re-creation and full re-sync
                logger.warning("Zone deleted (code: \(ckError.code.rawValue)), attempting re-creation...")
                UserDefaults.standard.set(false, forKey: zoneCreatedKey)
                UserDefaults.standard.set(false, forKey: subscriptionCreatedKey)
                changeToken = nil
                saveChangeToken()
                do {
                    try await setupZone()
                    try await setupSubscription()
                    logger.info("Zone re-created successfully after deletion")
                    // Don't retry fetchChanges here — the zone is empty, so let performFullSync re-upload
                    return true
                } catch {
                    logger.error("Failed to re-create zone: \(error.localizedDescription)")
                    return false
                }

            } catch let ckError as CKError where isFatalCKError(ckError) {
                // Fundamental infrastructure errors — abort entirely
                logger.error("Fatal CloudKit error during fetch (page \(pageCount)): \(ckError.localizedDescription)")
                return false

            } catch {
                // Unexpected non-CK error — abort
                logger.error("Failed to fetch changes (page \(pageCount)): \(error.localizedDescription)")
                return false
            }
        }

        // Apply all accumulated changes to local state
        await applyRemoteChanges(changedRecords, deletions: deletedRecordIDs, appState: appState)

        // Persist token AFTER data is successfully applied
        changeToken = currentToken
        saveChangeToken()

        if individualFailureCount > 0 {
            logger.warning("Fetched \(changedRecords.count) changes, \(deletedRecordIDs.count) deletions across \(pageCount) page(s) — \(individualFailureCount) individual record(s) failed")
        } else {
            logger.info("Fetched \(changedRecords.count) changes, \(deletedRecordIDs.count) deletions across \(pageCount) page(s)")
        }

        return true
    }

    /// Returns `true` for CKError codes that represent fundamental infrastructure failures
    /// where continuing the fetch loop is pointless.
    private func isFatalCKError(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .notAuthenticated,
             .badContainer,
             .missingEntitlement,
             .managedAccountRestricted,
             .quotaExceeded,
             .incompatibleVersion:
            return true
        default:
            return false
        }
    }

    private func applyRemoteChanges(
        _ changedRecords: [CKRecord],
        deletions: [CKRecord.ID],
        appState: AppState
    ) async {
        var recordingsChanged = false
        var tagsChanged = false
        var albumsChanged = false
        var projectsChanged = false
        var overdubGroupsChanged = false

        // Apply modifications
        for record in changedRecords {
            switch record.recordType {
            case SonideaRecordType.recording.rawValue:
                if let recording = RecordingItem.from(ckRecord: record) {
                    // Check if this is newer than local
                    if let localIndex = appState.recordings.firstIndex(where: { $0.id == recording.id }) {
                        if recording.modifiedAt > appState.recordings[localIndex].modifiedAt {
                            // Download audio file if needed
                            if let asset = record["audioFile"] as? CKAsset,
                               let assetURL = asset.fileURL {
                                // Safely replace existing audio file with the synced version
                                let fm = FileManager.default
                                let backupURL = recording.fileURL.appendingPathExtension("backup")
                                let originalExists = fm.fileExists(atPath: recording.fileURL.path)

                                // Back up original file if it exists
                                if originalExists {
                                    try? fm.removeItem(at: backupURL) // Clean up stale backup
                                    try? fm.moveItem(at: recording.fileURL, to: backupURL)
                                }

                                do {
                                    // Remove destination if move failed (original still in place)
                                    if fm.fileExists(atPath: recording.fileURL.path) {
                                        try fm.removeItem(at: recording.fileURL)
                                    }
                                    try fm.copyItem(at: assetURL, to: recording.fileURL)
                                    // Copy succeeded, remove backup
                                    try? fm.removeItem(at: backupURL)
                                } catch {
                                    // Copy failed — restore backup if we have one
                                    if fm.fileExists(atPath: backupURL.path) && !fm.fileExists(atPath: recording.fileURL.path) {
                                        try? fm.moveItem(at: backupURL, to: recording.fileURL)
                                    }
                                    logger.error("Failed to copy synced audio file: \(error.localizedDescription)")
                                    // Do NOT update metadata when audio copy fails — prevents metadata/audio mismatch
                                    continue
                                }
                            }
                            appState.recordings[localIndex] = recording
                            markSynced(id: recording.id.uuidString, modifiedAt: recording.modifiedAt)
                            recordingsChanged = true
                        }
                    } else {
                        // New recording from another device
                        var audioCopied = false
                        if let asset = record["audioFile"] as? CKAsset,
                           let assetURL = asset.fileURL {
                            do {
                                try FileManager.default.copyItem(at: assetURL, to: recording.fileURL)
                                audioCopied = true
                            } catch {
                                logger.error("Failed to copy new synced audio file: \(error.localizedDescription)")
                            }
                        }
                        // Only add the recording if the audio file was successfully copied
                        if audioCopied {
                            // Dedup: skip if recording already exists locally
                            if appState.recordings.contains(where: { $0.id == recording.id }) {
                                logger.info("Skipping duplicate recording \(recording.id) — already exists locally")
                            } else {
                                appState.recordings.append(recording)
                                markSynced(id: recording.id.uuidString, modifiedAt: recording.modifiedAt)
                                recordingsChanged = true
                            }
                        } else {
                            logger.warning("Skipping new synced recording \(recording.id) — audio file not available")
                        }
                    }
                }

            case SonideaRecordType.tag.rawValue:
                if let tag = Tag.from(ckRecord: record) {
                    if let existingIndex = appState.tags.firstIndex(where: { $0.id == tag.id }) {
                        appState.tags[existingIndex] = tag
                    } else {
                        appState.tags.append(tag)
                    }
                    tagsChanged = true
                }

            case SonideaRecordType.album.rawValue:
                if let album = Album.from(ckRecord: record) {
                    if let existingIndex = appState.albums.firstIndex(where: { $0.id == album.id }) {
                        appState.albums[existingIndex] = album
                    } else {
                        appState.albums.append(album)
                    }
                    albumsChanged = true
                }

            case SonideaRecordType.project.rawValue:
                if let project = Project.from(ckRecord: record) {
                    if let existingIndex = appState.projects.firstIndex(where: { $0.id == project.id }) {
                        appState.projects[existingIndex] = project
                    } else {
                        appState.projects.append(project)
                    }
                    projectsChanged = true
                }

            case SonideaRecordType.overdubGroup.rawValue:
                if let group = OverdubGroup.from(ckRecord: record) {
                    if let existingIndex = appState.overdubGroups.firstIndex(where: { $0.id == group.id }) {
                        appState.overdubGroups[existingIndex] = group
                    } else {
                        appState.overdubGroups.append(group)
                    }
                    overdubGroupsChanged = true
                }

            case SonideaRecordType.tombstone.rawValue:
                // Handle tombstone - delete local record
                // Skip tombstones from this device (already applied locally)
                if let tombstoneDeviceId = record["deviceId"] as? String,
                   tombstoneDeviceId == deviceId {
                    continue
                }
                if let targetId = record["targetId"] as? String,
                   let targetUUID = UUID(uuidString: targetId),
                   let targetType = record["targetType"] as? String {

                    switch targetType {
                    case SonideaRecordType.recording.rawValue:
                        // Delete the audio file on disk before removing from state
                        if let recording = appState.recordings.first(where: { $0.id == targetUUID }) {
                            try? FileManager.default.removeItem(at: recording.fileURL)
                        }
                        appState.recordings.removeAll { $0.id == targetUUID }
                        recordingsChanged = true
                    case SonideaRecordType.tag.rawValue:
                        appState.tags.removeAll { $0.id == targetUUID }
                        tagsChanged = true
                    case SonideaRecordType.album.rawValue:
                        appState.albums.removeAll { $0.id == targetUUID }
                        albumsChanged = true
                    case SonideaRecordType.project.rawValue:
                        appState.projects.removeAll { $0.id == targetUUID }
                        projectsChanged = true
                    case SonideaRecordType.overdubGroup.rawValue:
                        appState.overdubGroups.removeAll { $0.id == targetUUID }
                        overdubGroupsChanged = true
                    default:
                        break
                    }
                }

            default:
                break
            }
        }

        // Apply deletions
        for recordID in deletions {
            let id = recordID.recordName
            if let uuid = UUID(uuidString: id) {
                if let recording = appState.recordings.first(where: { $0.id == uuid }) {
                    try? FileManager.default.removeItem(at: recording.fileURL)
                    appState.recordings.removeAll { $0.id == uuid }
                    recordingsChanged = true
                }
                if appState.tags.contains(where: { $0.id == uuid }) {
                    appState.tags.removeAll { $0.id == uuid }
                    tagsChanged = true
                }
                if appState.albums.contains(where: { $0.id == uuid }) {
                    appState.albums.removeAll { $0.id == uuid }
                    albumsChanged = true
                }
                if appState.projects.contains(where: { $0.id == uuid }) {
                    appState.projects.removeAll { $0.id == uuid }
                    projectsChanged = true
                }
                if appState.overdubGroups.contains(where: { $0.id == uuid }) {
                    appState.overdubGroups.removeAll { $0.id == uuid }
                    overdubGroupsChanged = true
                }
            }
        }

        // Persist changes
        if recordingsChanged || tagsChanged || albumsChanged || projectsChanged || overdubGroupsChanged {
            appState.applySyncedData(SyncableData(
                recordings: appState.recordings,
                tags: appState.tags,
                albums: appState.albums,
                projects: appState.projects,
                overdubGroups: appState.overdubGroups
            ))
            // Persist synced dates so restored recordings aren't re-uploaded
            saveLastSyncedDates()
        }
    }

    // MARK: - Background Sync Scheduling

    /// Schedule a background sync task for when the app is suspended
    func scheduleBackgroundSync() {
        let request = BGProcessingTaskRequest(identifier: backgroundTaskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(request)
            logger.info("Scheduled background sync task")
        } catch {
            logger.error("Failed to schedule background sync: \(error.localizedDescription)")
        }
    }

    // MARK: - Persistence

    private func loadPersistedState() {
        // Load change token
        if let tokenData = UserDefaults.standard.data(forKey: changeTokenKey) {
            changeToken = try? NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: tokenData
            )
        }

        // Load tombstones
        if let data = UserDefaults.standard.data(forKey: tombstonesKey) {
            tombstones = (try? JSONDecoder().decode([Tombstone].self, from: data)) ?? []
        }

        // Prune old tombstones (older than 90 days)
        let cutoff = Date().addingTimeInterval(-90 * 86400)
        let countBefore = tombstones.count
        tombstones.removeAll { $0.deletedAt < cutoff }
        if tombstones.count < countBefore {
            saveTombstones()
        }

        // Load last sync date
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date

        // Load last synced dates for incremental sync
        if let dict = UserDefaults.standard.dictionary(forKey: lastSyncedDatesKey) as? [String: Date] {
            lastSyncedDates = dict
        }

        // Load content fingerprints for lightweight records
        if let dict = UserDefaults.standard.dictionary(forKey: lastSyncedFingerprintsKey) as? [String: String] {
            lastSyncedFingerprints = dict
        }

        // Load pending operations queue
        if let data = UserDefaults.standard.data(forKey: pendingOperationsKey) {
            pendingOperations = (try? JSONDecoder().decode([PendingSyncOperation].self, from: data)) ?? []
        }
        // Prune stale pending operations (older than 7 days)
        let opCutoff = Date().addingTimeInterval(-7 * 86400)
        pendingOperations.removeAll { $0.createdAt < opCutoff }
    }

    private func saveChangeToken() {
        if let token = changeToken,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: changeTokenKey)
        } else {
            UserDefaults.standard.removeObject(forKey: changeTokenKey)
        }
    }

    private func saveTombstones() {
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: tombstonesKey)
        }
    }

    private func saveLastSyncedDates() {
        UserDefaults.standard.set(lastSyncedDates, forKey: lastSyncedDatesKey)
    }

    private func saveLastSyncedFingerprints() {
        UserDefaults.standard.set(lastSyncedFingerprints, forKey: lastSyncedFingerprintsKey)
    }

    /// Check if a lightweight record needs re-syncing by comparing its content fingerprint
    private func needsSync(id: String, fingerprint: String) -> Bool {
        lastSyncedFingerprints[id] != fingerprint
    }

    /// Mark a lightweight record as synced with its content fingerprint
    private func markSyncedFingerprint(id: String, fingerprint: String) {
        lastSyncedFingerprints[id] = fingerprint
    }

    /// Record that a specific item was successfully synced at a given modifiedAt date
    private func markSynced(id: String, modifiedAt: Date) {
        lastSyncedDates[id] = modifiedAt
    }

    private func updateLastSync() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
        status = .synced(lastSyncDate!)
    }

    // MARK: - Pending Operations Queue

    /// Queue a failed operation for retry on next full sync
    func queuePendingOperation(operationType: PendingSyncOperation.OperationType, recordType: String, recordId: String) {
        // Avoid duplicates
        if pendingOperations.contains(where: { $0.recordId == recordId && $0.operationType == operationType }) {
            return
        }
        let op = PendingSyncOperation(operationType: operationType, recordType: recordType, recordId: recordId)
        pendingOperations.append(op)
        savePendingOperations()
        pendingChangesCount = pendingOperations.count
        logger.info("Queued pending \(operationType.rawValue) for \(recordType) \(recordId)")
    }

    private func savePendingOperations() {
        if let data = try? JSONEncoder().encode(pendingOperations) {
            UserDefaults.standard.set(data, forKey: pendingOperationsKey)
        }
        pendingChangesCount = pendingOperations.count
    }

    /// Drain the pending operations queue — called at the start of performFullSync
    private func drainPendingOperations() async {
        guard let appState = appState, !pendingOperations.isEmpty else { return }

        logger.info("Draining \(self.pendingOperations.count) pending operations")
        var remaining: [PendingSyncOperation] = []

        for var op in pendingOperations {
            do {
                switch (op.operationType, op.recordType) {
                case (.save, SonideaRecordType.recording.rawValue):
                    if let recording = appState.recordings.first(where: { $0.id.uuidString == op.recordId }) {
                        try await withRetry { try await self.saveRecording(recording) }
                        markSynced(id: recording.id.uuidString, modifiedAt: recording.modifiedAt)
                    }
                case (.delete, SonideaRecordType.recording.rawValue):
                    if let uuid = UUID(uuidString: op.recordId) {
                        try await withRetry { try await self.deleteRecording(uuid) }
                    }
                case (.save, SonideaRecordType.tag.rawValue):
                    if let tag = appState.tags.first(where: { $0.id.uuidString == op.recordId }) {
                        try await withRetry { try await self.saveTag(tag) }
                    }
                case (.delete, SonideaRecordType.tag.rawValue):
                    if let uuid = UUID(uuidString: op.recordId) {
                        try await withRetry { try await self.deleteTag(uuid) }
                    }
                case (.save, SonideaRecordType.album.rawValue):
                    if let album = appState.albums.first(where: { $0.id.uuidString == op.recordId }) {
                        try await withRetry { try await self.saveAlbum(album) }
                    }
                case (.delete, SonideaRecordType.album.rawValue):
                    if let uuid = UUID(uuidString: op.recordId) {
                        try await withRetry { try await self.deleteAlbum(uuid) }
                    }
                case (.save, SonideaRecordType.project.rawValue):
                    if let project = appState.projects.first(where: { $0.id.uuidString == op.recordId }) {
                        try await withRetry { try await self.saveProject(project) }
                    }
                case (.delete, SonideaRecordType.project.rawValue):
                    if let uuid = UUID(uuidString: op.recordId) {
                        try await withRetry { try await self.deleteProject(uuid) }
                    }
                case (.save, SonideaRecordType.overdubGroup.rawValue):
                    if let group = appState.overdubGroups.first(where: { $0.id.uuidString == op.recordId }) {
                        try await withRetry { try await self.saveOverdubGroup(group) }
                    }
                case (.delete, SonideaRecordType.overdubGroup.rawValue):
                    if let uuid = UUID(uuidString: op.recordId) {
                        try await withRetry { try await self.deleteOverdubGroup(uuid) }
                    }
                default:
                    break
                }
            } catch {
                op.retryCount += 1
                if op.retryCount < 5 {
                    remaining.append(op)
                } else {
                    logger.error("Dropping pending operation after 5 retries: \(op.recordType) \(op.recordId)")
                }
            }
        }

        pendingOperations = remaining
        savePendingOperations()
    }

    // MARK: - Retry Helper

    /// Retry an async operation with exponential backoff and CKError-aware delays
    private func withRetry<T>(maxAttempts: Int = 3, initialDelay: TimeInterval = 1.0, operation: () async throws -> T) async throws -> T {
        var lastError: Error?
        let effectiveMaxAttempts = maxAttempts
        for attempt in 0..<effectiveMaxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Check for rate limiting / zone busy — use server-provided retry delay
                if let ckError = error as? CKError,
                   (ckError.code == .requestRateLimited || ckError.code == .zoneBusy) {
                    let retryAfter = ckError.retryAfterSeconds ?? (initialDelay * pow(2.0, Double(attempt)))
                    if attempt < effectiveMaxAttempts - 1 {
                        logger.warning("Rate limited, retrying in \(retryAfter)s (attempt \(attempt + 1))")
                        try? await Task.sleep(nanoseconds: UInt64(retryAfter * 1_000_000_000))
                        continue
                    }
                }

                if attempt < effectiveMaxAttempts - 1 {
                    let delay = initialDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    logger.warning("Retry attempt \(attempt + 1) after error: \(error.localizedDescription)")
                }
            }
        }
        throw lastError ?? CKError(.internalError)
    }

    // MARK: - Conflict-Resolving Save

    /// Save a CKRecord with serverRecordChanged conflict resolution.
    /// On conflict, re-applies fields from the populate closure onto the server record and retries.
    private func saveWithConflictResolution(
        _ record: CKRecord,
        maxRetries: Int = 2,
        populate: (CKRecord) -> Void
    ) async throws {
        var currentRecord = record
        for attempt in 0...maxRetries {
            do {
                try await privateDatabase.modifyRecords(saving: [currentRecord], deleting: [])
                return
            } catch let error as CKError where error.code == .serverRecordChanged {
                guard attempt < maxRetries else { throw error }
                guard let serverRecord = error.userInfo[CKRecordChangedErrorServerRecordKey] as? CKRecord else {
                    throw error
                }
                logger.info("serverRecordChanged on \(currentRecord.recordType), re-applying fields (attempt \(attempt + 1)/\(maxRetries + 1))")
                populate(serverRecord)
                currentRecord = serverRecord
            }
        }
    }
}

// MARK: - CKRecord Extensions

extension RecordingItem {
    /// Populate an existing CKRecord with this recording's fields.
    /// Use this instead of toCKRecord when you already have a record (e.g. fetched from server).
    func populateCKRecord(_ record: CKRecord) {
        record["title"] = title
        record["notes"] = notes
        record["duration"] = duration
        record["createdAt"] = createdAt
        record["modifiedAt"] = modifiedAt
        record["tagIDs"] = tagIDs.map { $0.uuidString }
        record["albumID"] = albumID?.uuidString
        record["locationLabel"] = locationLabel
        record["transcript"] = transcript
        record["latitude"] = latitude
        record["longitude"] = longitude
        record["trashedAt"] = trashedAt
        record["lastPlaybackPosition"] = lastPlaybackPosition
        record["iconColorHex"] = iconColorHex
        record["iconName"] = iconName
        record["projectId"] = projectId?.uuidString
        record["parentRecordingId"] = parentRecordingId?.uuidString
        record["versionIndex"] = versionIndex
        record["fileExtension"] = fileURL.pathExtension

        // Markers as JSON
        if let markersData = try? JSONEncoder().encode(markers) {
            record["markersJSON"] = String(data: markersData, encoding: .utf8)
        }

        // EQ settings as JSON
        if let eqData = try? JSONEncoder().encode(eqSettings) {
            record["eqSettingsJSON"] = String(data: eqData, encoding: .utf8)
        }

        // Proof fields
        record["proofStatusRaw"] = proofStatusRaw
        record["proofSHA256"] = proofSHA256
        record["proofCloudCreatedAt"] = proofCloudCreatedAt
        record["proofCloudRecordName"] = proofCloudRecordName

        // Location proof fields
        record["locationModeRaw"] = locationModeRaw
        record["locationProofHash"] = locationProofHash
        record["locationProofStatusRaw"] = locationProofStatusRaw

        // Overdub fields
        record["overdubGroupId"] = overdubGroupId?.uuidString
        record["overdubRoleRaw"] = overdubRoleRaw
        record["overdubIndex"] = overdubIndex
        record["overdubOffsetSeconds"] = overdubOffsetSeconds
        record["overdubSourceBaseId"] = overdubSourceBaseId?.uuidString

        // Metronome tracking
        record["wasRecordedWithMetronome"] = wasRecordedWithMetronome

        // Icon classification fields
        record["iconSourceRaw"] = iconSourceRaw
        if let predictions = iconPredictions,
           let data = try? JSONEncoder().encode(predictions) {
            record["iconPredictionsJSON"] = String(data: data, encoding: .utf8)
        }
        if let secondary = secondaryIcons {
            record["secondaryIcons"] = secondary
        }
    }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.recording.rawValue, recordID: recordID)
        populateCKRecord(record)
        return record
    }

    static func from(ckRecord record: CKRecord) -> RecordingItem? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let title = record["title"] as? String,
              let duration = record["duration"] as? TimeInterval,
              let createdAt = record["createdAt"] as? Date,
              let fileExtension = record["fileExtension"] as? String else {
            return nil
        }

        // Reconstruct file URL
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileURL = documentsURL.appendingPathComponent("\(id.uuidString).\(fileExtension)")

        // Parse tag IDs
        let tagIDStrings = record["tagIDs"] as? [String] ?? []
        let tagIDs = tagIDStrings.compactMap { UUID(uuidString: $0) }

        // Parse markers
        var markers: [Marker] = []
        if let markersJSON = record["markersJSON"] as? String,
           let data = markersJSON.data(using: .utf8) {
            markers = (try? JSONDecoder().decode([Marker].self, from: data)) ?? []
        }

        // Parse EQ settings
        var eqSettings: EQSettings?
        if let eqJSON = record["eqSettingsJSON"] as? String,
           let data = eqJSON.data(using: .utf8) {
            eqSettings = try? JSONDecoder().decode(EQSettings.self, from: data)
        }

        // Parse icon predictions
        var iconPredictions: [IconPrediction]?
        if let predictionsJSON = record["iconPredictionsJSON"] as? String,
           let data = predictionsJSON.data(using: .utf8) {
            iconPredictions = try? JSONDecoder().decode([IconPrediction].self, from: data)
        }

        return RecordingItem(
            id: id,
            fileURL: fileURL,
            createdAt: createdAt,
            duration: duration,
            title: title,
            notes: record["notes"] as? String ?? "",
            tagIDs: tagIDs,
            albumID: (record["albumID"] as? String).flatMap { UUID(uuidString: $0) },
            locationLabel: record["locationLabel"] as? String ?? "",
            transcript: record["transcript"] as? String ?? "",
            latitude: record["latitude"] as? Double,
            longitude: record["longitude"] as? Double,
            trashedAt: record["trashedAt"] as? Date,
            lastPlaybackPosition: record["lastPlaybackPosition"] as? TimeInterval ?? 0,
            iconColorHex: record["iconColorHex"] as? String,
            iconName: record["iconName"] as? String,
            iconSourceRaw: record["iconSourceRaw"] as? String,
            iconPredictions: iconPredictions,
            secondaryIcons: record["secondaryIcons"] as? [String],
            eqSettings: eqSettings,
            projectId: (record["projectId"] as? String).flatMap { UUID(uuidString: $0) },
            parentRecordingId: (record["parentRecordingId"] as? String).flatMap { UUID(uuidString: $0) },
            versionIndex: record["versionIndex"] as? Int ?? 1,
            proofStatusRaw: record["proofStatusRaw"] as? String,
            proofSHA256: record["proofSHA256"] as? String,
            proofCloudCreatedAt: record["proofCloudCreatedAt"] as? Date,
            proofCloudRecordName: record["proofCloudRecordName"] as? String,
            locationModeRaw: record["locationModeRaw"] as? String,
            locationProofHash: record["locationProofHash"] as? String,
            locationProofStatusRaw: record["locationProofStatusRaw"] as? String,
            markers: markers,
            overdubGroupId: (record["overdubGroupId"] as? String).flatMap { UUID(uuidString: $0) },
            overdubRoleRaw: record["overdubRoleRaw"] as? String,
            overdubIndex: record["overdubIndex"] as? Int,
            overdubOffsetSeconds: record["overdubOffsetSeconds"] as? Double ?? 0,
            overdubSourceBaseId: (record["overdubSourceBaseId"] as? String).flatMap { UUID(uuidString: $0) },
            wasRecordedWithMetronome: record["wasRecordedWithMetronome"] as? Bool ?? false,
            modifiedAt: record["modifiedAt"] as? Date ?? createdAt
        )
    }
}

extension Tag {
    /// Populate an existing CKRecord with this tag's fields.
    func populateCKRecord(_ record: CKRecord) {
        record["name"] = name
        record["colorHex"] = colorHex
        record["isProtected"] = isProtected
    }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.tag.rawValue, recordID: recordID)
        populateCKRecord(record)
        return record
    }

    static func from(ckRecord record: CKRecord) -> Tag? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String,
              let colorHex = record["colorHex"] as? String else {
            return nil
        }

        // Note: isProtected is a computed property derived from the tag's ID
        // (id == Tag.favoriteTagID), so it does not need to be decoded from the
        // CKRecord. The ID is already restored from the record name above.
        return Tag(id: id, name: name, colorHex: colorHex)
    }
}

extension Album {
    /// Populate an existing CKRecord with this album's fields.
    /// Note: Shared album fields (isShared, shareURL, participants, etc.) are managed
    /// by CloudKit sharing infrastructure separately and are NOT synced here.
    func populateCKRecord(_ record: CKRecord) {
        record["name"] = name
        record["createdAt"] = createdAt
        record["isSystem"] = isSystem
    }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.album.rawValue, recordID: recordID)
        populateCKRecord(record)
        return record
    }

    static func from(ckRecord record: CKRecord) -> Album? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String else {
            return nil
        }

        return Album(
            id: id,
            name: name,
            createdAt: record["createdAt"] as? Date ?? Date(),
            isSystem: record["isSystem"] as? Bool ?? false
        )
    }
}

extension Project {
    /// Populate an existing CKRecord with this project's fields.
    func populateCKRecord(_ record: CKRecord) {
        record["title"] = title
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        record["pinned"] = pinned
        record["notes"] = notes
        record["bestTakeRecordingId"] = bestTakeRecordingId?.uuidString
        record["sortOrder"] = sortOrder
    }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.project.rawValue, recordID: recordID)
        populateCKRecord(record)
        return record
    }

    static func from(ckRecord record: CKRecord) -> Project? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let title = record["title"] as? String,
              let createdAt = record["createdAt"] as? Date else {
            return nil
        }

        return Project(
            id: id,
            title: title,
            createdAt: createdAt,
            updatedAt: record["updatedAt"] as? Date ?? createdAt,
            pinned: record["pinned"] as? Bool ?? false,
            notes: record["notes"] as? String ?? "",
            bestTakeRecordingId: (record["bestTakeRecordingId"] as? String).flatMap { UUID(uuidString: $0) },
            sortOrder: record["sortOrder"] as? Int
        )
    }
}

extension OverdubGroup {
    /// Populate an existing CKRecord with this overdub group's fields.
    func populateCKRecord(_ record: CKRecord) {
        record["baseRecordingId"] = baseRecordingId.uuidString
        record["createdAt"] = createdAt

        // Layer recording IDs as JSON array of strings
        let layerStrings = layerRecordingIds.map { $0.uuidString }
        if let data = try? JSONEncoder().encode(layerStrings) {
            record["layerRecordingIdsJSON"] = String(data: data, encoding: .utf8)
        }

        // Mix settings as JSON
        if let data = try? JSONEncoder().encode(mixSettings) {
            record["mixSettingsJSON"] = String(data: data, encoding: .utf8)
        }
    }

    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.overdubGroup.rawValue, recordID: recordID)
        populateCKRecord(record)
        return record
    }

    static func from(ckRecord record: CKRecord) -> OverdubGroup? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let baseRecordingIdString = record["baseRecordingId"] as? String,
              let baseRecordingId = UUID(uuidString: baseRecordingIdString),
              let createdAt = record["createdAt"] as? Date else {
            return nil
        }

        // Parse layer recording IDs
        var layerRecordingIds: [UUID] = []
        if let layerJSON = record["layerRecordingIdsJSON"] as? String,
           let data = layerJSON.data(using: .utf8),
           let layerStrings = try? JSONDecoder().decode([String].self, from: data) {
            layerRecordingIds = layerStrings.compactMap { UUID(uuidString: $0) }
        }

        // Parse mix settings
        var mixSettings = MixSettings()
        if let mixJSON = record["mixSettingsJSON"] as? String,
           let data = mixJSON.data(using: .utf8) {
            mixSettings = (try? JSONDecoder().decode(MixSettings.self, from: data)) ?? MixSettings()
        }

        return OverdubGroup(
            id: id,
            baseRecordingId: baseRecordingId,
            layerRecordingIds: layerRecordingIds,
            createdAt: createdAt,
            mixSettings: mixSettings
        )
    }
}
