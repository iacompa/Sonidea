//
//  iCloudSyncManager.swift
//  Sonidea
//
//  Manages iCloud sync for recordings, tags, albums, and projects.
//  Uses iCloud Documents (ubiquity container) for file-based sync.
//

import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class iCloudSyncManager {

    // MARK: - Observable State

    var isSyncing: Bool = false
    var lastSyncDate: Date?
    var syncError: String?
    var syncProgress: SyncProgress = .idle

    // MARK: - Configuration

    private let metadataFileName = "sonidea-data.json"
    private let audioDirectoryName = "Audio"

    // Weak reference to avoid retain cycle (set by AppState)
    weak var appState: AppState?

    // MARK: - iCloud Availability

    var iCloudAvailable: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    var ubiquityContainerURL: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: nil)
    }

    private var documentsURL: URL? {
        ubiquityContainerURL?.appendingPathComponent("Documents")
    }

    private var metadataURL: URL? {
        documentsURL?.appendingPathComponent(metadataFileName)
    }

    private var audioDirectoryURL: URL? {
        documentsURL?.appendingPathComponent(audioDirectoryName)
    }

    // MARK: - Initialization

    init() {
        loadLastSyncDate()
    }

    // MARK: - Public Methods

    /// Enable iCloud sync - performs initial sync
    func enableSync() async {
        guard iCloudAvailable else {
            syncError = SyncError.iCloudUnavailable.localizedDescription
            return
        }

        // Create directories if needed
        await ensureDirectoriesExist()

        // Perform initial sync
        await syncNow()
    }

    /// Disable iCloud sync
    func disableSync() {
        // Just clear local sync state, don't delete cloud data
        syncError = nil
        isSyncing = false
    }

    /// Perform a full sync with iCloud
    func syncNow() async {
        guard iCloudAvailable else {
            syncError = SyncError.iCloudUnavailable.localizedDescription
            return
        }

        guard let appState = appState else {
            syncError = "App state not available"
            return
        }

        guard !isSyncing else { return }

        isSyncing = true
        syncError = nil
        syncProgress = SyncProgress(phase: .preparingData, current: 0, total: 5)

        do {
            // Step 1: Ensure directories exist
            await ensureDirectoriesExist()

            // Step 2: Read remote data
            syncProgress.phase = .downloadingMetadata
            syncProgress.current = 1
            let remoteData = await readRemoteMetadata()

            // Step 3: Merge data
            syncProgress.phase = .mergingData
            syncProgress.current = 2
            let localData = appState.getSyncableData()
            let merged = mergeData(local: localData, remote: remoteData)

            // Step 4: Write merged metadata to iCloud
            syncProgress.phase = .uploadingMetadata
            syncProgress.current = 3
            try await writeMetadataToiCloud(merged)

            // Step 5: Sync audio files
            syncProgress.phase = .uploadingAudio
            syncProgress.current = 4
            try await syncAudioFiles(recordings: merged.recordings)

            // Step 6: Apply merged data to local state
            appState.applySyncedData(merged)

            // Success
            syncProgress.phase = .complete
            syncProgress.current = 5
            lastSyncDate = Date()
            saveLastSyncDate()
            syncError = nil

        } catch {
            syncError = error.localizedDescription
        }

        isSyncing = false
        syncProgress = .idle
    }

    // MARK: - Private Methods

    private func ensureDirectoriesExist() async {
        guard let documentsURL = documentsURL,
              let audioURL = audioDirectoryURL else { return }

        let fileManager = FileManager.default

        // Create Documents directory
        if !fileManager.fileExists(atPath: documentsURL.path) {
            try? fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
        }

        // Create Audio directory
        if !fileManager.fileExists(atPath: audioURL.path) {
            try? fileManager.createDirectory(at: audioURL, withIntermediateDirectories: true)
        }
    }

    private func readRemoteMetadata() async -> SyncableData? {
        guard let metadataURL = metadataURL else { return nil }

        // Check if file exists and is downloaded
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: metadataURL.path) else {
            return nil
        }

        // Try to download if in cloud
        do {
            try fileManager.startDownloadingUbiquitousItem(at: metadataURL)
        } catch {
            // File might already be local, continue
        }

        // Wait briefly for download (in production, use NSMetadataQuery for proper monitoring)
        try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds

        // Read the file
        guard let data = fileManager.contents(atPath: metadataURL.path) else {
            return nil
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(SyncableData.self, from: data)
        } catch {
            print("Failed to decode remote metadata: \(error)")
            return nil
        }
    }

    private func writeMetadataToiCloud(_ syncData: SyncableData) async throws {
        guard let metadataURL = metadataURL else {
            throw SyncError.containerNotFound
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(syncData)

            // Write using file coordinator for safe iCloud access
            let coordinator = NSFileCoordinator()
            var coordinatorError: NSError?

            coordinator.coordinate(writingItemAt: metadataURL, options: .forReplacing, error: &coordinatorError) { url in
                try? data.write(to: url, options: .atomic)
            }

            if let error = coordinatorError {
                throw SyncError.fileOperationFailed(error)
            }
        } catch let error as SyncError {
            throw error
        } catch {
            throw SyncError.encodingError(error)
        }
    }

    private func syncAudioFiles(recordings: [RecordingItem]) async throws {
        guard let audioDirectoryURL = audioDirectoryURL else {
            throw SyncError.containerNotFound
        }

        let fileManager = FileManager.default
        let localDocumentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]

        for recording in recordings {
            let localFileURL = recording.fileURL
            let fileName = "\(recording.id.uuidString).\(localFileURL.pathExtension)"
            let cloudFileURL = audioDirectoryURL.appendingPathComponent(fileName)

            // Upload local file to cloud if it exists locally but not in cloud
            if fileManager.fileExists(atPath: localFileURL.path) {
                if !fileManager.fileExists(atPath: cloudFileURL.path) {
                    do {
                        try fileManager.copyItem(at: localFileURL, to: cloudFileURL)
                    } catch {
                        print("Failed to upload audio file: \(error)")
                    }
                }
            }

            // Download cloud file to local if it exists in cloud but not locally
            if fileManager.fileExists(atPath: cloudFileURL.path) {
                if !fileManager.fileExists(atPath: localFileURL.path) {
                    // Start download
                    try? fileManager.startDownloadingUbiquitousItem(at: cloudFileURL)

                    // Wait for download (simplified - in production use NSMetadataQuery)
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                    // Copy to local documents
                    let localDestination = localDocumentsURL.appendingPathComponent(localFileURL.lastPathComponent)
                    do {
                        try fileManager.copyItem(at: cloudFileURL, to: localDestination)
                    } catch {
                        print("Failed to download audio file: \(error)")
                    }
                }
            }
        }
    }

    // MARK: - Data Merging

    private func mergeData(local: SyncableData, remote: SyncableData?) -> SyncableData {
        guard let remote = remote else {
            return local
        }

        // Simple last-write-wins strategy based on lastModified timestamp
        // In a more sophisticated implementation, we'd merge per-item based on individual timestamps

        if local.lastModified > remote.lastModified {
            // Local is newer - use local data
            return SyncableData(
                recordings: local.recordings,
                tags: mergeTags(local: local.tags, remote: remote.tags),
                albums: mergeAlbums(local: local.albums, remote: remote.albums),
                projects: local.projects,
                lastModified: Date()
            )
        } else {
            // Remote is newer - use remote data but preserve local audio file paths
            return SyncableData(
                recordings: mergeRecordings(local: local.recordings, remote: remote.recordings),
                tags: mergeTags(local: local.tags, remote: remote.tags),
                albums: mergeAlbums(local: local.albums, remote: remote.albums),
                projects: remote.projects,
                lastModified: Date()
            )
        }
    }

    private func mergeRecordings(local: [RecordingItem], remote: [RecordingItem]) -> [RecordingItem] {
        var merged: [RecordingItem] = []
        var localDict = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        var remoteIDs = Set<UUID>()

        // For remote recordings, prefer local version if it exists (preserves file URL)
        for remoteRecording in remote {
            remoteIDs.insert(remoteRecording.id)
            if let localRecording = localDict[remoteRecording.id] {
                // Use local recording to preserve local file URL
                merged.append(localRecording)
                localDict.removeValue(forKey: remoteRecording.id)
            } else {
                // Recording only exists remotely - will need to download audio file
                merged.append(remoteRecording)
            }
        }

        // Add any local recordings not in remote
        merged.append(contentsOf: localDict.values)

        return merged
    }

    private func mergeTags(local: [Tag], remote: [Tag]) -> [Tag] {
        // Union of both tag sets, preferring local for conflicts
        var merged = local
        let localIDs = Set(local.map { $0.id })

        for remoteTag in remote {
            if !localIDs.contains(remoteTag.id) {
                merged.append(remoteTag)
            }
        }

        return merged
    }

    private func mergeAlbums(local: [Album], remote: [Album]) -> [Album] {
        // Union of both album sets, preferring local for conflicts
        var merged = local
        let localIDs = Set(local.map { $0.id })

        for remoteAlbum in remote {
            if !localIDs.contains(remoteAlbum.id) {
                merged.append(remoteAlbum)
            }
        }

        return merged
    }

    // MARK: - Persistence

    private let lastSyncDateKey = "iCloudLastSyncDate"

    private func saveLastSyncDate() {
        UserDefaults.standard.set(lastSyncDate, forKey: lastSyncDateKey)
    }

    private func loadLastSyncDate() {
        lastSyncDate = UserDefaults.standard.object(forKey: lastSyncDateKey) as? Date
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
            projects: projects
        )
    }

    /// Apply synced data from iCloud
    func applySyncedData(_ data: SyncableData) {
        // Update collections
        recordings = data.recordings
        tags = data.tags
        albums = data.albums
        projects = data.projects

        // Persist locally
        saveAllData()
    }

    /// Save all data to local storage
    private func saveAllData() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: "savedRecordings")
        }
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: "savedTags")
        }
        if let data = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(data, forKey: "savedAlbums")
        }
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: "savedProjects")
        }
    }
}
