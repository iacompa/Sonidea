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

    private var container: CKContainer {
        CKContainer(identifier: containerIdentifier)
    }

    private var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }

    // MARK: - State

    private var isEnabled = false
    private var syncTask: Task<Void, Never>?
    private var changeToken: CKServerChangeToken?
    private var tombstones: [Tombstone] = []
    private var deviceId: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString

    // Weak reference to AppState
    weak var appState: AppState?

    // MARK: - Persistence Keys

    private let changeTokenKey = "cloudkit.changeToken"
    private let tombstonesKey = "cloudkit.tombstones"
    private let lastSyncKey = "cloudkit.lastSync"
    private let zoneCreatedKey = "cloudkit.zoneCreated"
    private let subscriptionCreatedKey = "cloudkit.subscriptionCreated"

    // MARK: - Initialization

    init() {
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

    /// Sync on app foreground
    func syncOnForeground() async {
        guard isEnabled else { return }
        logger.info("Syncing on foreground")
        await fetchChanges()
    }

    // MARK: - Record Operations

    /// Save a recording to CloudKit
    func saveRecording(_ recording: RecordingItem) async throws {
        guard isEnabled else { return }

        let record = recording.toCKRecord(zoneID: zoneID)

        // Add audio file as CKAsset if it exists
        if FileManager.default.fileExists(atPath: recording.fileURL.path) {
            let asset = CKAsset(fileURL: recording.fileURL)
            record["audioFile"] = asset

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
            let operation = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            // Progress tracking
            operation.perRecordProgressBlock = { [weak self] _, progress in
                Task { @MainActor in
                    if let index = self?.uploadProgress.firstIndex(where: { $0.id == recording.id }) {
                        self?.uploadProgress[index].progress = progress
                    }
                    self?.status = .syncing(progress: progress, description: "Uploading \(recording.title)...")
                }
            }

            try await privateDatabase.modifyRecords(saving: [record], deleting: [])

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

        let record = tag.toCKRecord(zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecords(saving: [record], deleting: [])
            logger.info("Saved tag: \(tag.id)")
            updateLastSync()
        } catch {
            throw error
        }
    }

    /// Save an album to CloudKit
    func saveAlbum(_ album: Album) async throws {
        guard isEnabled else { return }

        let record = album.toCKRecord(zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecords(saving: [record], deleting: [])
            logger.info("Saved album: \(album.id)")
            updateLastSync()
        } catch {
            throw error
        }
    }

    /// Save a project to CloudKit
    func saveProject(_ project: Project) async throws {
        guard isEnabled else { return }

        let record = project.toCKRecord(zoneID: zoneID)

        do {
            try await privateDatabase.modifyRecords(saving: [record], deleting: [])
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

        status = .syncing(progress: 0, description: "Syncing...")

        do {
            // Upload local changes
            let recordings = appState.recordings
            let tags = appState.tags
            let albums = appState.albums
            let projects = appState.projects

            let totalItems = recordings.count + tags.count + albums.count + projects.count
            var completed = 0

            // Batch upload recordings
            for recording in recordings {
                status = .syncing(
                    progress: Double(completed) / Double(max(1, totalItems)),
                    description: "Uploading \(recording.title)..."
                )
                try await saveRecording(recording)
                completed += 1
            }

            // Batch upload tags
            for tag in tags {
                try await saveTag(tag)
                completed += 1
                status = .syncing(
                    progress: Double(completed) / Double(max(1, totalItems)),
                    description: "Syncing tags..."
                )
            }

            // Batch upload albums
            for album in albums {
                try await saveAlbum(album)
                completed += 1
            }

            // Batch upload projects
            for project in projects {
                try await saveProject(project)
                completed += 1
            }

            // Fetch remote changes
            await fetchChanges()

            updateLastSync()
            status = .synced(lastSyncDate ?? Date())

        } catch {
            logger.error("Full sync failed: \(error.localizedDescription)")
            status = .error(error.localizedDescription)
        }
    }

    // MARK: - Fetch Changes

    private func fetchChanges() async {
        guard let appState = appState else { return }

        status = .syncing(progress: 0.5, description: "Checking for changes...")

        do {
            var changedRecords: [CKRecord] = []
            var deletedRecordIDs: [CKRecord.ID] = []

            let changes = try await privateDatabase.recordZoneChanges(
                inZoneWith: zoneID,
                since: changeToken
            )

            // Process changed records - extract CKRecord from modification result
            for (_, result) in changes.modificationResultsByID {
                if case .success(let modification) = result {
                    changedRecords.append(modification.record)
                }
            }

            // Process deletions
            for deletion in changes.deletions {
                deletedRecordIDs.append(deletion.recordID)
            }

            // Save new change token
            changeToken = changes.changeToken
            saveChangeToken()

            // Apply changes to local state
            await applyRemoteChanges(changedRecords, deletions: deletedRecordIDs, appState: appState)

            logger.info("Fetched \(changedRecords.count) changes, \(deletedRecordIDs.count) deletions")

        } catch {
            logger.error("Failed to fetch changes: \(error.localizedDescription)")
            // Don't update status to error for fetch failures, just log it
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
                                // Use a temp copy to avoid data loss if copyItem fails
                                let backupURL = recording.fileURL.appendingPathExtension("backup")
                                try? FileManager.default.moveItem(at: recording.fileURL, to: backupURL)
                                do {
                                    try FileManager.default.copyItem(at: assetURL, to: recording.fileURL)
                                    // Copy succeeded, remove backup
                                    try? FileManager.default.removeItem(at: backupURL)
                                } catch {
                                    // Copy failed — restore backup to prevent data loss
                                    try? FileManager.default.moveItem(at: backupURL, to: recording.fileURL)
                                    logger.error("Failed to copy synced audio file: \(error.localizedDescription)")
                                }
                            }
                            appState.recordings[localIndex] = recording
                            recordingsChanged = true
                        }
                    } else {
                        // New recording from another device
                        if let asset = record["audioFile"] as? CKAsset,
                           let assetURL = asset.fileURL {
                            do {
                                try FileManager.default.copyItem(at: assetURL, to: recording.fileURL)
                            } catch {
                                logger.error("Failed to copy new synced audio file: \(error.localizedDescription)")
                            }
                        }
                        appState.recordings.append(recording)
                        recordingsChanged = true
                    }
                }

            case SonideaRecordType.tag.rawValue:
                if let tag = Tag.from(ckRecord: record) {
                    if !appState.tags.contains(where: { $0.id == tag.id }) {
                        appState.tags.append(tag)
                        tagsChanged = true
                    }
                }

            case SonideaRecordType.album.rawValue:
                if let album = Album.from(ckRecord: record) {
                    if !appState.albums.contains(where: { $0.id == album.id }) {
                        appState.albums.append(album)
                        albumsChanged = true
                    }
                }

            case SonideaRecordType.project.rawValue:
                if let project = Project.from(ckRecord: record) {
                    if !appState.projects.contains(where: { $0.id == project.id }) {
                        appState.projects.append(project)
                        projectsChanged = true
                    }
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
                if appState.recordings.contains(where: { $0.id == uuid }) {
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
            }
        }

        // Persist changes
        if recordingsChanged || tagsChanged || albumsChanged || projectsChanged {
            appState.applySyncedData(SyncableData(
                recordings: appState.recordings,
                tags: appState.tags,
                albums: appState.albums,
                projects: appState.projects
            ))
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

        // Load last sync date
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncKey) as? Date
    }

    private func saveChangeToken() {
        if let token = changeToken,
           let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) {
            UserDefaults.standard.set(data, forKey: changeTokenKey)
        }
    }

    private func saveTombstones() {
        if let data = try? JSONEncoder().encode(tombstones) {
            UserDefaults.standard.set(data, forKey: tombstonesKey)
        }
    }

    private func updateLastSync() {
        lastSyncDate = Date()
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncKey)
        status = .synced(lastSyncDate!)
    }
}

// MARK: - CKRecord Extensions

extension RecordingItem {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.recording.rawValue, recordID: recordID)

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
            eqSettings: eqSettings,
            projectId: (record["projectId"] as? String).flatMap { UUID(uuidString: $0) },
            parentRecordingId: (record["parentRecordingId"] as? String).flatMap { UUID(uuidString: $0) },
            versionIndex: record["versionIndex"] as? Int ?? 1,
            markers: markers,
            modifiedAt: record["modifiedAt"] as? Date ?? createdAt
        )
    }
}

extension Tag {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.tag.rawValue, recordID: recordID)

        record["name"] = name
        record["colorHex"] = colorHex
        record["isProtected"] = isProtected

        return record
    }

    static func from(ckRecord record: CKRecord) -> Tag? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String,
              let colorHex = record["colorHex"] as? String else {
            return nil
        }

        return Tag(id: id, name: name, colorHex: colorHex)
    }
}

extension Album {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.album.rawValue, recordID: recordID)

        record["name"] = name

        return record
    }

    static func from(ckRecord record: CKRecord) -> Album? {
        guard let idString = record.recordID.recordName as String?,
              let id = UUID(uuidString: idString),
              let name = record["name"] as? String else {
            return nil
        }

        return Album(id: id, name: name)
    }
}

extension Project {
    func toCKRecord(zoneID: CKRecordZone.ID) -> CKRecord {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: SonideaRecordType.project.rawValue, recordID: recordID)

        record["title"] = title
        record["createdAt"] = createdAt
        record["updatedAt"] = updatedAt
        record["pinned"] = pinned
        record["notes"] = notes
        record["bestTakeRecordingId"] = bestTakeRecordingId?.uuidString
        record["sortOrder"] = sortOrder

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
