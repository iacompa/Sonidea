//
//  iCloudSyncManager.swift
//  Sonidea
//
//  Unified sync manager that orchestrates CloudKit sync with fallback to iCloud Documents.
//  Provides a single interface for the app to use.
//

import Foundation
import Observation
import UIKit
import OSLog

// MARK: - Sync Status (unified)

@MainActor
enum SyncStatusState: Equatable {
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
        case .syncing(let progress, let desc):
            if progress > 0 {
                return "\(desc) (\(Int(progress * 100))%)"
            }
            return desc
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

    // For backward compatibility
    static func == (lhs: SyncStatusState, rhs: SyncStatusState) -> Bool {
        switch (lhs, rhs) {
        case (.disabled, .disabled): return true
        case (.initializing, .initializing): return true
        case (.syncing(let p1, let d1), .syncing(let p2, let d2)): return p1 == p2 && d1 == d2
        case (.synced(let d1), .synced(let d2)): return d1 == d2
        case (.error(let e1), .error(let e2)): return e1 == e2
        case (.accountUnavailable, .accountUnavailable): return true
        case (.networkUnavailable, .networkUnavailable): return true
        default: return false
        }
    }
}

// MARK: - iCloud Sync Manager

@MainActor
@Observable
final class iCloudSyncManager {

    // MARK: - Observable State

    var status: SyncStatusState = .disabled
    var lastSyncDate: Date?
    var syncError: String?
    var syncProgress: SyncProgress = .idle
    var uploadProgress: [UploadProgress] = []

    // Convenience properties
    var isSyncing: Bool {
        if case .syncing = status { return true }
        if case .initializing = status { return true }
        return false
    }

    // MARK: - Engines

    private let cloudKitEngine = CloudKitSyncEngine()
    private let logger = Logger(subsystem: "com.iacompa.sonidea", category: "iCloudSync")

    // Weak reference to avoid retain cycle
    weak var appState: AppState? {
        didSet {
            cloudKitEngine.appState = appState
        }
    }

    // MARK: - Configuration

    private var isEnabled = false

    /// Minimum interval between foreground syncs (debounce rapid foreground/background cycling)
    private static let foregroundSyncDebounceInterval: TimeInterval = 30
    private var lastForegroundSyncDate: Date = .distantPast

    // MARK: - iCloud Availability

    var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    // MARK: - Initialization

    init() {
        // Observe CloudKit engine status changes
        observeCloudKitStatus()
    }

    private func observeCloudKitStatus() {
        withObservationTracking {
            // Access tracked properties to register observation
            _ = self.cloudKitEngine.status
            _ = self.cloudKitEngine.lastSyncDate
            _ = self.cloudKitEngine.uploadProgress
        } onChange: {
            // Re-register observation and apply updated status on next main actor turn
            Task { @MainActor [weak self] in
                self?.updateStatusFromEngine()
                self?.observeCloudKitStatus()
            }
        }
    }

    // MARK: - Public API

    /// Enable iCloud sync
    func enableSync() async {
        guard !isEnabled else { return }

        logger.info("Enabling iCloud sync")
        isEnabled = true
        status = .initializing

        // Use CloudKit as primary sync
        await cloudKitEngine.enable()

        // Mirror status from CloudKit engine
        updateStatusFromEngine()
    }

    /// Disable iCloud sync
    func disableSync() {
        logger.info("Disabling iCloud sync")
        isEnabled = false
        cloudKitEngine.disable()
        status = .disabled
        syncError = nil
    }

    /// Perform sync now
    func syncNow() async {
        guard isEnabled else { return }
        cloudKitEngine.triggerSync()
        updateStatusFromEngine()
    }

    /// Handle remote notification (called from AppDelegate)
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) async {
        guard isEnabled else { return }
        await cloudKitEngine.handleRemoteNotification(userInfo)
        updateStatusFromEngine()
    }

    /// Sync on app foreground (debounced to prevent rapid foreground/background cycling from triggering multiple syncs)
    func syncOnForeground() async {
        guard isEnabled else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(lastForegroundSyncDate)
        guard elapsed >= Self.foregroundSyncDebounceInterval else {
            logger.info("Foreground sync debounced — last sync was \(Int(elapsed))s ago (minimum \(Int(Self.foregroundSyncDebounceInterval))s)")
            return
        }

        lastForegroundSyncDate = now
        await cloudKitEngine.syncOnForeground()
        updateStatusFromEngine()
    }

    /// Schedule a background sync task
    func scheduleBackgroundSync() {
        guard isEnabled else { return }
        cloudKitEngine.scheduleBackgroundSync()
    }

    // MARK: - Sync Triggers

    func onRecordingCreated(_ recording: RecordingItem) {
        guard isEnabled else { return }
        Task {
            // Request extra background execution time for the upload
            let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "SyncNewRecording") {
                // Expiration handler — nothing to clean up, CloudKit handles interruption
            }
            defer {
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
            do {
                try await cloudKitEngine.saveRecording(recording)
                updateStatusFromEngine()
            } catch {
                logger.error("Failed to sync new recording: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Recording", recordId: recording.id.uuidString)
            }
        }
    }

    func onRecordingUpdated(_ recording: RecordingItem) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveRecording(recording)
                updateStatusFromEngine()
            } catch {
                logger.error("Failed to sync recording update: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Recording", recordId: recording.id.uuidString)
            }
        }
    }

    func onAudioEdited(_ recording: RecordingItem) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveRecording(recording)
                updateStatusFromEngine()
            } catch {
                logger.error("Failed to sync audio edit: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Recording", recordId: recording.id.uuidString)
            }
        }
    }

    func onRecordingDeleted(_ recordingId: UUID) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.deleteRecording(recordingId)
                updateStatusFromEngine()
            } catch {
                logger.error("Failed to sync deletion: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .delete, recordType: "Recording", recordId: recordingId.uuidString)
            }
        }
    }

    func onMetadataChanged() {
        guard isEnabled else { return }
        cloudKitEngine.triggerSync()
    }

    func onTagCreated(_ tag: Tag) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveTag(tag)
            } catch {
                logger.error("Failed to sync new tag: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Tag", recordId: tag.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onTagUpdated(_ tag: Tag) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveTag(tag)
            } catch {
                logger.error("Failed to sync tag update: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Tag", recordId: tag.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onTagDeleted(_ tagId: UUID) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.deleteTag(tagId)
            } catch {
                logger.error("Failed to sync tag deletion: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .delete, recordType: "Tag", recordId: tagId.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onAlbumCreated(_ album: Album) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveAlbum(album)
            } catch {
                logger.error("Failed to sync new album: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Album", recordId: album.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onAlbumUpdated(_ album: Album) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveAlbum(album)
            } catch {
                logger.error("Failed to sync album update: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Album", recordId: album.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onAlbumDeleted(_ albumId: UUID) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.deleteAlbum(albumId)
            } catch {
                logger.error("Failed to sync album deletion: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .delete, recordType: "Album", recordId: albumId.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onProjectCreated(_ project: Project) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveProject(project)
            } catch {
                logger.error("Failed to sync new project: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Project", recordId: project.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onProjectUpdated(_ project: Project) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveProject(project)
            } catch {
                logger.error("Failed to sync project update: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "Project", recordId: project.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onProjectDeleted(_ projectId: UUID) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.deleteProject(projectId)
            } catch {
                logger.error("Failed to sync project deletion: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .delete, recordType: "Project", recordId: projectId.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onOverdubGroupCreated(_ group: OverdubGroup) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveOverdubGroup(group)
            } catch {
                logger.error("Failed to sync new overdub group: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "OverdubGroup", recordId: group.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onOverdubGroupUpdated(_ group: OverdubGroup) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.saveOverdubGroup(group)
            } catch {
                logger.error("Failed to sync overdub group update: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .save, recordType: "OverdubGroup", recordId: group.id.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    func onOverdubGroupDeleted(_ groupId: UUID) {
        guard isEnabled else { return }
        Task {
            do {
                try await cloudKitEngine.deleteOverdubGroup(groupId)
            } catch {
                logger.error("Failed to sync overdub group deletion: \(error.localizedDescription)")
                cloudKitEngine.queuePendingOperation(operationType: .delete, recordType: "OverdubGroup", recordId: groupId.uuidString)
            }
            updateStatusFromEngine()
        }
    }

    // MARK: - Status Updates

    private func updateStatusFromEngine() {
        // Convert CloudSyncStatus to SyncStatusState
        status = convertStatus(cloudKitEngine.status)
        lastSyncDate = cloudKitEngine.lastSyncDate
        uploadProgress = cloudKitEngine.uploadProgress
    }

    private func convertStatus(_ cloudStatus: CloudSyncStatus) -> SyncStatusState {
        switch cloudStatus {
        case .disabled:
            return .disabled
        case .initializing:
            return .initializing
        case .syncing(let progress, let description):
            return .syncing(progress: progress, description: description)
        case .synced(let date):
            return .synced(date)
        case .error(let message):
            return .error(message)
        case .accountUnavailable:
            return .accountUnavailable
        case .networkUnavailable:
            return .networkUnavailable
        }
    }
}

// MARK: - Sync Progress (backward compatibility)

struct SyncProgress: Equatable {
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

// MARK: - Sync Error

enum SyncError: Error, LocalizedError {
    case iCloudUnavailable
    case notSignedIn
    case containerNotFound
    case networkError(Error)
    case encodingError(Error)
    case decodingError(Error)
    case fileOperationFailed(Error)
    case cloudKitError(Error)
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable:
            return "iCloud is not available"
        case .notSignedIn:
            return "Please sign in to iCloud"
        case .containerNotFound:
            return "iCloud container not found"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .encodingError(let error):
            return "Failed to encode: \(error.localizedDescription)"
        case .decodingError(let error):
            return "Failed to decode: \(error.localizedDescription)"
        case .fileOperationFailed(let error):
            return "File error: \(error.localizedDescription)"
        case .cloudKitError(let error):
            return "CloudKit error: \(error.localizedDescription)"
        case .unknown(let error):
            return error.localizedDescription
        }
    }
}

// MARK: - Upload Progress

struct UploadProgress: Identifiable, Equatable {
    let id: UUID
    let fileName: String
    var progress: Double
    var status: UploadStatus

    enum UploadStatus: Equatable {
        case pending
        case uploading
        case completed
        case failed(String)
    }
}

// MARK: - Syncable Data

struct SyncableData: Codable {
    var recordings: [RecordingItem]
    var tags: [Tag]
    var albums: [Album]
    var projects: [Project]
    var overdubGroups: [OverdubGroup]
    var lastModified: Date
    var deviceIdentifier: String

    static let empty = SyncableData(
        recordings: [],
        tags: [],
        albums: [],
        projects: [],
        overdubGroups: [],
        lastModified: Date.distantPast,
        deviceIdentifier: ""
    )

    init(
        recordings: [RecordingItem],
        tags: [Tag],
        albums: [Album],
        projects: [Project],
        overdubGroups: [OverdubGroup] = [],
        lastModified: Date = Date(),
        deviceIdentifier: String = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    ) {
        self.recordings = recordings
        self.tags = tags
        self.albums = albums
        self.projects = projects
        self.overdubGroups = overdubGroups
        self.lastModified = lastModified
        self.deviceIdentifier = deviceIdentifier
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        recordings = try container.decode([RecordingItem].self, forKey: .recordings)
        tags = try container.decode([Tag].self, forKey: .tags)
        albums = try container.decode([Album].self, forKey: .albums)
        projects = try container.decode([Project].self, forKey: .projects)
        overdubGroups = try container.decodeIfPresent([OverdubGroup].self, forKey: .overdubGroups) ?? []
        lastModified = try container.decode(Date.self, forKey: .lastModified)
        deviceIdentifier = try container.decode(String.self, forKey: .deviceIdentifier)
    }
}

// MARK: - AppState Extension for Sync

extension AppState {

    /// Get all data as a syncable container
    func getSyncableData() -> SyncableData {
        SyncableData(
            recordings: recordings,
            tags: tags,
            albums: albums,
            projects: projects,
            overdubGroups: overdubGroups
        )
    }

    /// Apply synced data from iCloud
    func applySyncedData(_ data: SyncableData) {
        // Persist BEFORE updating in-memory state to guarantee durability
        // Use data.recordings (the parameter) — not self.recordings which is stale
        DataSafetyFileOps.saveSync(data.recordings, collection: .recordings)
        DataSafetyFileOps.saveSync(data.tags, collection: .tags)
        DataSafetyFileOps.saveSync(data.albums, collection: .albums)
        DataSafetyFileOps.saveSync(data.projects, collection: .projects)
        DataSafetyFileOps.saveSync(data.overdubGroups, collection: .overdubGroups)
        // UserDefaults fallback for transition period
        if let encoded = try? JSONEncoder().encode(data.recordings) {
            UserDefaults.standard.set(encoded, forKey: "savedRecordings")
        }
        if let encoded = try? JSONEncoder().encode(data.tags) {
            UserDefaults.standard.set(encoded, forKey: "savedTags")
        }
        if let encoded = try? JSONEncoder().encode(data.albums) {
            UserDefaults.standard.set(encoded, forKey: "savedAlbums")
        }
        if let encoded = try? JSONEncoder().encode(data.projects) {
            UserDefaults.standard.set(encoded, forKey: "savedProjects")
        }
        // Now update in-memory state (triggers SwiftUI reactivity)
        recordings = data.recordings
        tags = data.tags
        albums = data.albums
        projects = data.projects
        overdubGroups = data.overdubGroups

        // Rebuild transcript search index in background after sync
        Task.detached(priority: .background) {
            try? await TranscriptSearchService.shared.rebuildIndex(from: data.recordings)
        }
    }

    // MARK: - Sync Trigger Hooks

    func triggerSyncForRecording(_ recording: RecordingItem) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onRecordingUpdated(recording)
        }
    }

    func triggerSyncForNewRecording(_ recording: RecordingItem) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onRecordingCreated(recording)
        }
    }

    func triggerSyncForDeletion(_ recordingId: UUID) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onRecordingDeleted(recordingId)
        }
    }

    func triggerSyncForMetadata() {
        if appSettings.iCloudSyncEnabled {
            syncManager.onMetadataChanged()
        }
    }

    func triggerSyncForTag(_ tag: Tag) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onTagCreated(tag)
        }
    }

    func triggerSyncForTagUpdate(_ tag: Tag) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onTagUpdated(tag)
        }
    }

    func triggerSyncForTagDeletion(_ tagId: UUID) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onTagDeleted(tagId)
        }
    }

    func triggerSyncForAlbum(_ album: Album) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onAlbumCreated(album)
        }
    }

    func triggerSyncForAlbumUpdate(_ album: Album) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onAlbumUpdated(album)
        }
    }

    func triggerSyncForAlbumDeletion(_ albumId: UUID) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onAlbumDeleted(albumId)
        }
    }

    func triggerSyncForProject(_ project: Project) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onProjectCreated(project)
        }
    }

    func triggerSyncForProjectUpdate(_ project: Project) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onProjectUpdated(project)
        }
    }

    func triggerSyncForProjectDeletion(_ projectId: UUID) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onProjectDeleted(projectId)
        }
    }

    func triggerSyncForOverdubGroup(_ group: OverdubGroup) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onOverdubGroupCreated(group)
        }
    }

    func triggerSyncForOverdubGroupUpdate(_ group: OverdubGroup) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onOverdubGroupUpdated(group)
        }
    }

    func triggerSyncForOverdubGroupDeletion(_ groupId: UUID) {
        if appSettings.iCloudSyncEnabled {
            syncManager.onOverdubGroupDeleted(groupId)
        }
    }
}
