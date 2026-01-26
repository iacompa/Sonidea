//
//  AppState.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import Observation
import SwiftUI
import CoreLocation

// MARK: - UI Metrics (for Settings to access container geometry)

struct UIMetrics: Equatable {
    var containerSize: CGSize = .zero
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    var topBarHeight: CGFloat = 72
    var buttonDiameter: CGFloat = 80
}

@MainActor
@Observable
final class AppState {
    var recordings: [RecordingItem] = []
    var tags: [Tag] = []
    var albums: [Album] = []
    var projects: [Project] = []
    var overdubGroups: [OverdubGroup] = []
    var appearanceMode: AppearanceMode = .system {
        didSet {
            saveAppearanceMode()
        }
    }
    var selectedTheme: AppTheme = .system {
        didSet {
            saveSelectedTheme()
        }
    }
    var appSettings: AppSettings = .default {
        didSet {
            saveAppSettings()
            // Apply settings to recorder
            recorder.qualityPreset = appSettings.recordingQuality
            recorder.appSettings = appSettings
        }
    }

    let recorder = RecorderManager()
    let locationManager = LocationManager()
    let supportManager = SupportManager()
    let syncManager = iCloudSyncManager()
    let proofManager = ProofManager()
    let sharedAlbumManager = SharedAlbumManager()

    private(set) var nextRecordingNumber: Int = 1

    private let recordingsKey = "savedRecordings"
    private let tagsKey = "savedTags"
    private let albumsKey = "savedAlbums"
    private let projectsKey = "savedProjects"
    private let overdubGroupsKey = "savedOverdubGroups"
    private let nextNumberKey = "nextRecordingNumber"
    private let appearanceModeKey = "appearanceMode"
    private let selectedThemeKey = "selectedTheme"
    private let tagMigrationKey = "didMigrateFavToFavorite"
    private let appSettingsKey = "appSettings"
    private let draftsMigrationKey = "didMigrateToDrafts"

    // MARK: - Record Button Position State

    private let recordButtonPosXKey = "recordButtonPosX"
    private let recordButtonPosYKey = "recordButtonPosY"
    private let recordButtonHasStoredKey = "recordButtonHasStored"

    /// The persisted record button position (nil = use default)
    var recordButtonPosition: CGPoint? = nil

    /// Latest UI metrics from ContentView (used by Settings for reset)
    var uiMetrics: UIMetrics = UIMetrics()

    init() {
        loadAppearanceMode()
        loadSelectedTheme()
        loadAppSettings()
        loadNextRecordingNumber()
        loadTags()
        loadAlbums()
        loadProjects()
        loadOverdubGroups()
        loadRecordings()
        seedDefaultTagsIfNeeded()
        ensureDraftsAlbum()
        migrateFavTagToFavorite()
        migrateRecordingsToDrafts()
        migrateInboxToDrafts()
        purgeOldTrashedRecordings()
        recorder.qualityPreset = appSettings.recordingQuality
        recorder.appSettings = appSettings
        loadRecordButtonPosition()

        // Connect sync manager
        syncManager.appState = self

        // Connect shared album manager
        sharedAlbumManager.appState = self
    }

    // MARK: - Record Button Position Management

    /// Load persisted record button position
    private func loadRecordButtonPosition() {
        let hasStored = UserDefaults.standard.bool(forKey: recordButtonHasStoredKey)
        guard hasStored else {
            recordButtonPosition = nil
            return
        }
        let x = CGFloat(UserDefaults.standard.double(forKey: recordButtonPosXKey))
        let y = CGFloat(UserDefaults.standard.double(forKey: recordButtonPosYKey))
        recordButtonPosition = CGPoint(x: x, y: y)
    }

    /// Persist record button position
    func persistRecordButtonPosition() {
        guard let pos = recordButtonPosition else {
            UserDefaults.standard.set(false, forKey: recordButtonHasStoredKey)
            UserDefaults.standard.removeObject(forKey: recordButtonPosXKey)
            UserDefaults.standard.removeObject(forKey: recordButtonPosYKey)
            return
        }
        UserDefaults.standard.set(true, forKey: recordButtonHasStoredKey)
        UserDefaults.standard.set(Double(pos.x), forKey: recordButtonPosXKey)
        UserDefaults.standard.set(Double(pos.y), forKey: recordButtonPosYKey)
    }

    /// Clamp a position to valid bounds (container coordinate space)
    func clampRecordButtonPosition(
        _ point: CGPoint,
        containerSize: CGSize,
        safeInsets: EdgeInsets,
        topBarHeight: CGFloat,
        buttonDiameter: CGFloat
    ) -> CGPoint {
        let radius = buttonDiameter / 2
        let padding: CGFloat = 12

        let minX = padding + radius
        let maxX = containerSize.width - padding - radius
        let minY = topBarHeight + padding + radius
        // Allow button to go very low - just above the home indicator with minimal margin
        let maxY = containerSize.height - radius - 8

        let clampedX = min(max(point.x, minX), maxX)
        let clampedY = min(max(point.y, minY), maxY)

        return CGPoint(x: clampedX, y: clampedY)
    }

    /// Compute default position (bottom-center, Voice Memos style)
    func defaultRecordButtonPosition(
        containerSize: CGSize,
        safeInsets: EdgeInsets,
        topBarHeight: CGFloat,
        buttonDiameter: CGFloat
    ) -> CGPoint {
        let radius = buttonDiameter / 2

        let centerX = containerSize.width / 2
        // Position just above home indicator with small margin
        let bottomY = containerSize.height - radius - 24

        return CGPoint(x: centerX, y: bottomY)
    }

    /// Reset record button to default position
    func resetRecordButtonPosition() {
        // Use stored metrics if available, otherwise nil triggers default on next render
        if uiMetrics.containerSize.width > 0 && uiMetrics.containerSize.height > 0 {
            let defaultPos = defaultRecordButtonPosition(
                containerSize: uiMetrics.containerSize,
                safeInsets: uiMetrics.safeAreaInsets,
                topBarHeight: uiMetrics.topBarHeight,
                buttonDiameter: uiMetrics.buttonDiameter
            )
            recordButtonPosition = defaultPos
        } else {
            recordButtonPosition = nil
        }
        persistRecordButtonPosition()
    }

    /// Update and clamp position (called on drag end)
    func updateRecordButtonPosition(_ newPosition: CGPoint) {
        let clamped = clampRecordButtonPosition(
            newPosition,
            containerSize: uiMetrics.containerSize,
            safeInsets: uiMetrics.safeAreaInsets,
            topBarHeight: uiMetrics.topBarHeight,
            buttonDiameter: uiMetrics.buttonDiameter
        )
        recordButtonPosition = clamped
        persistRecordButtonPosition()
    }

    // MARK: - Support Manager Hooks

    /// Call when app becomes active/foreground
    func onAppBecameActive() {
        supportManager.registerActiveDayIfNeeded()
    }

    /// Call when recording is saved
    func onRecordingSaved() {
        supportManager.onRecordingSaved(totalRecordings: activeRecordings.count)
    }

    /// Call when export succeeds
    func onExportSuccess() {
        supportManager.onExportSuccess(totalRecordings: activeRecordings.count)
    }

    /// Call when transcription succeeds
    func onTranscriptionSuccess() {
        supportManager.onTranscriptionSuccess(totalRecordings: activeRecordings.count)
    }

    /// Call when recording state changes
    func onRecordingStateChanged(isRecording: Bool) {
        supportManager.setRecordingState(isRecording)
    }

    // MARK: - Filtered Recording Lists

    /// Active recordings (not trashed)
    var activeRecordings: [RecordingItem] {
        recordings.filter { !$0.isTrashed }
    }

    /// Trashed recordings
    var trashedRecordings: [RecordingItem] {
        recordings.filter { $0.isTrashed }
    }

    var trashedCount: Int {
        trashedRecordings.count
    }

    /// Recordings with coordinates
    var recordingsWithLocation: [RecordingItem] {
        activeRecordings.filter { $0.hasCoordinates }
    }

    // MARK: - Recording Management

    /// Result of attempting to add a recording
    enum AddRecordingResult {
        case success(RecordingItem)
        case failure(String)
    }

    /// Add a recording from raw data, returns success/failure result
    @discardableResult
    func addRecording(from rawData: RawRecordingData) -> AddRecordingResult {
        print("🎙️ [AppState] Attempting to add recording from: \(rawData.fileURL.lastPathComponent)")
        print("   Duration: \(rawData.duration)s, Created: \(rawData.createdAt)")

        // Verify the file exists and is valid before adding
        let fileStatus = AudioDebug.verifyAudioFile(url: rawData.fileURL)
        guard fileStatus.isValid else {
            let errorMsg = fileStatus.errorMessage ?? "Unknown verification error"
            print("❌ [AppState] Cannot add recording - file verification failed: \(errorMsg)")
            AudioDebug.logFileInfo(url: rawData.fileURL, context: "AppState.addRecording - failed verification")
            return .failure(errorMsg)
        }

        print("✅ [AppState] File verified, adding recording: \(rawData.fileURL.lastPathComponent)")

        let title = "Recording \(nextRecordingNumber)"
        nextRecordingNumber += 1
        saveNextRecordingNumber()

        let recording = RecordingItem(
            fileURL: rawData.fileURL,
            createdAt: rawData.createdAt,
            duration: rawData.duration,
            title: title,
            albumID: Album.draftsID,
            locationLabel: rawData.locationLabel,
            latitude: rawData.latitude,
            longitude: rawData.longitude
        )

        recordings.insert(recording, at: 0)
        saveRecordings()

        print("✅ [AppState] Recording added successfully: \(title)")

        // Trigger iCloud sync for new recording
        triggerSyncForNewRecording(recording)

        // Auto-transcribe if enabled
        if appSettings.autoTranscribe {
            Task {
                await autoTranscribe(recording: recording)
            }
        }

        // Auto-classify icon if enabled
        if appSettings.autoSelectIcon {
            Task {
                await autoClassifyIcon(recording: recording)
            }
        }

        return .success(recording)
    }

    private func autoTranscribe(recording: RecordingItem) async {
        do {
            let transcript = try await TranscriptionManager.shared.transcribe(
                audioURL: recording.fileURL,
                language: appSettings.transcriptionLanguage
            )
            updateTranscript(transcript, for: recording.id)
        } catch {
            print("Auto-transcribe failed: \(error)")
        }
    }

    private func autoClassifyIcon(recording: RecordingItem) async {
        let updated = await AudioIconClassifierManager.shared.classifyAndUpdateIfNeeded(
            recording: recording,
            autoSelectEnabled: appSettings.autoSelectIcon
        )

        // Only update if icon was actually changed
        if updated.iconName != recording.iconName {
            await MainActor.run {
                updateRecording(updated)
            }
        }
    }

    func updateRecording(_ updated: RecordingItem) {
        guard let index = recordings.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        var recording = updated
        recording.modifiedAt = Date()
        recordings[index] = recording
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForRecording(recording)
    }

    func updateTranscript(_ text: String, for recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return
        }
        recordings[index].transcript = text
        recordings[index].modifiedAt = Date()
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForRecording(recordings[index])
    }

    func updatePlaybackPosition(_ position: TimeInterval, for recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return
        }
        recordings[index].lastPlaybackPosition = position
        saveRecordings()
    }

    func updateRecordingLocation(recordingID: UUID, latitude: Double, longitude: Double, label: String) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return
        }
        recordings[index].latitude = latitude
        recordings[index].longitude = longitude
        recordings[index].locationLabel = label
        recordings[index].modifiedAt = Date()
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForRecording(recordings[index])
    }

    func recording(for id: UUID) -> RecordingItem? {
        recordings.first { $0.id == id }
    }

    func recordings(for ids: [UUID]) -> [RecordingItem] {
        ids.compactMap { id in recordings.first { $0.id == id && !$0.isTrashed } }
    }

    // MARK: - Trash Management

    func moveToTrash(_ recording: RecordingItem) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else {
            return
        }
        recordings[index].trashedAt = Date()
        recordings[index].modifiedAt = Date()
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForRecording(recordings[index])
    }

    func moveToTrash(at offsets: IndexSet, from list: [RecordingItem]) {
        for index in offsets {
            let recording = list[index]
            moveToTrash(recording)
        }
    }

    func restoreFromTrash(_ recording: RecordingItem) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else {
            return
        }
        recordings[index].trashedAt = nil
        recordings[index].modifiedAt = Date()
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForRecording(recordings[index])
    }

    func permanentlyDelete(_ recording: RecordingItem) {
        let recordingId = recording.id
        try? FileManager.default.removeItem(at: recording.fileURL)
        recordings.removeAll { $0.id == recordingId }
        saveRecordings()

        // Trigger iCloud sync for deletion
        triggerSyncForDeletion(recordingId)
    }

    func emptyTrash() {
        for recording in trashedRecordings {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        recordings.removeAll { $0.isTrashed }
        saveRecordings()
    }

    private func purgeOldTrashedRecordings() {
        let toDelete = recordings.filter { $0.shouldPurge }
        for recording in toDelete {
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        recordings.removeAll { $0.shouldPurge }
        if !toDelete.isEmpty {
            saveRecordings()
        }
    }

    func deleteRecording(_ recording: RecordingItem) {
        // Now moves to trash instead of permanent delete
        moveToTrash(recording)
    }

    func deleteRecordings(at offsets: IndexSet) {
        // Now moves to trash instead of permanent delete
        for index in offsets {
            let recording = activeRecordings[index]
            moveToTrash(recording)
        }
    }

    // MARK: - Tag Helpers

    func tag(for id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }

    func tags(for ids: [UUID]) -> [Tag] {
        // Return in tag order
        ids.compactMap { id in tags.first { $0.id == id } }
    }

    func tagUsageCount(_ tag: Tag) -> Int {
        recordings.filter { $0.tagIDs.contains(tag.id) }.count
    }

    func tagExists(name: String, excludingID: UUID? = nil) -> Bool {
        tags.contains { tag in
            tag.name.lowercased() == name.lowercased() && tag.id != excludingID
        }
    }

    @discardableResult
    func createTag(name: String, colorHex: String) -> Tag? {
        guard !tagExists(name: name) else { return nil }
        let tag = Tag(name: name, colorHex: colorHex)
        tags.append(tag)
        saveTags()

        // Trigger iCloud sync
        triggerSyncForMetadata()

        return tag
    }

    func updateTag(_ tag: Tag, name: String, colorHex: String) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else {
            return false
        }

        // Protected tags cannot be renamed, only recolored
        if tag.isProtected {
            tags[index].colorHex = colorHex
            saveTags()
            triggerSyncForTagUpdate(tags[index])
            return true
        }

        // Check for duplicate name (excluding current tag)
        if tagExists(name: name, excludingID: tag.id) {
            return false
        }
        tags[index].name = name
        tags[index].colorHex = colorHex
        saveTags()

        // Trigger iCloud sync
        triggerSyncForTagUpdate(tags[index])

        return true
    }

    func deleteTag(_ tag: Tag) -> Bool {
        // Cannot delete protected tags
        if tag.isProtected {
            return false
        }
        let tagId = tag.id
        tags.removeAll { $0.id == tagId }
        // Remove tag from all recordings
        for i in recordings.indices {
            recordings[i].tagIDs.removeAll { $0 == tagId }
            recordings[i].modifiedAt = Date()
        }
        saveTags()
        saveRecordings()

        // Trigger iCloud sync for tag deletion
        triggerSyncForTagDeletion(tagId)

        return true
    }

    func mergeTags(sourceTagIDs: Set<UUID>, destinationTagID: UUID) {
        guard let _ = tag(for: destinationTagID) else { return }

        // Update all recordings to use destination tag
        for i in recordings.indices {
            var newTagIDs = recordings[i].tagIDs

            // Check if recording has any of the source tags
            let hasSourceTag = newTagIDs.contains { sourceTagIDs.contains($0) }
            if hasSourceTag {
                // Remove all source tags
                newTagIDs.removeAll { sourceTagIDs.contains($0) }
                // Add destination tag if not already present
                if !newTagIDs.contains(destinationTagID) {
                    newTagIDs.append(destinationTagID)
                }
                recordings[i].tagIDs = newTagIDs
            }
        }

        // Delete merged tags (except destination)
        for tagID in sourceTagIDs where tagID != destinationTagID {
            if let tag = tag(for: tagID), !tag.isProtected {
                tags.removeAll { $0.id == tagID }
            }
        }

        saveTags()
        saveRecordings()
    }

    func moveTag(from source: IndexSet, to destination: Int) {
        tags.move(fromOffsets: source, toOffset: destination)
        saveTags()
    }

    func toggleTag(_ tag: Tag, for recording: RecordingItem) -> RecordingItem {
        var updated = recording
        if updated.tagIDs.contains(tag.id) {
            updated.tagIDs.removeAll { $0 == tag.id }
        } else {
            updated.tagIDs.append(tag.id)
        }
        updateRecording(updated)
        return updated
    }

    func toggleFavorite(for recording: RecordingItem) -> RecordingItem {
        guard let favoriteTag = tags.first(where: { $0.name.lowercased() == "favorite" }) else {
            return recording
        }
        return toggleTag(favoriteTag, for: recording)
    }

    func isFavorite(_ recording: RecordingItem) -> Bool {
        recording.tagIDs.contains(Tag.favoriteTagID)
    }

    /// Get the favorite tag ID (always exists as it's protected)
    var favoriteTagID: UUID {
        Tag.favoriteTagID
    }

    // MARK: - Album Helpers

    func album(for id: UUID?) -> Album? {
        guard let id = id else { return nil }
        return albums.first { $0.id == id }
    }

    @discardableResult
    func createAlbum(name: String) -> Album {
        let album = Album(name: name)
        albums.append(album)
        saveAlbums()

        // Trigger iCloud sync
        triggerSyncForMetadata()

        return album
    }

    func deleteAlbum(_ album: Album) {
        guard album.canDelete else { return }
        let albumId = album.id
        albums.removeAll { $0.id == albumId }
        // Move recordings to Drafts
        for i in recordings.indices {
            if recordings[i].albumID == albumId {
                recordings[i].albumID = Album.draftsID
                recordings[i].modifiedAt = Date()
            }
        }
        saveAlbums()
        saveRecordings()

        // Trigger iCloud sync for album deletion
        triggerSyncForAlbumDeletion(albumId)
    }

    func setAlbum(_ album: Album?, for recording: RecordingItem) -> RecordingItem {
        var updated = recording
        updated.albumID = album?.id ?? Album.draftsID
        updateRecording(updated)
        return updated
    }

    private func ensureDraftsAlbum() {
        if !albums.contains(where: { $0.id == Album.draftsID }) {
            albums.insert(Album.drafts, at: 0)
            saveAlbums()
        }
    }

    /// Ensure the Imports system album exists (called on first external import)
    func ensureImportsAlbum() {
        if !albums.contains(where: { $0.id == Album.importsID }) {
            // Insert after Drafts (at index 1) or at beginning if no Drafts
            let insertIndex = albums.firstIndex(where: { $0.id == Album.draftsID }).map { $0 + 1 } ?? 0
            albums.insert(Album.imports, at: insertIndex)
            saveAlbums()

            // Trigger iCloud sync for new album
            triggerSyncForAlbum(Album.imports)
        }
    }

    /// Check if Imports album exists
    var hasImportsAlbum: Bool {
        albums.contains(where: { $0.id == Album.importsID })
    }

    // MARK: - Shared Album Management

    /// Get all shared albums
    var sharedAlbums: [Album] {
        albums.filter { $0.isShared }
    }

    /// Get non-shared albums (for album picker sections)
    var personalAlbums: [Album] {
        albums.filter { !$0.isShared }
    }

    /// Add a newly created shared album
    func addSharedAlbum(_ album: Album) {
        albums.append(album)
        saveAlbums()

        // Trigger iCloud sync
        triggerSyncForAlbum(album)
    }

    /// Remove a shared album (when leaving or owner stops sharing)
    func removeSharedAlbum(_ album: Album) {
        guard album.isShared else { return }

        let albumId = album.id
        albums.removeAll { $0.id == albumId }

        // Remove recordings associated with this shared album from local state
        // (They live in CloudKit shared zone, not locally persisted)
        recordings.removeAll { $0.albumID == albumId }

        saveAlbums()
        saveRecordings()
    }

    /// Update shared album properties (participant count, etc.)
    func updateSharedAlbum(_ album: Album) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index] = album
        saveAlbums()
    }

    /// Check if recording can be added to album (handles shared album consent)
    func canAddRecordingToAlbum(_ album: Album, skipConsent: Bool = false) -> Bool {
        // For shared albums, check if consent is required
        if album.isShared && !album.skipAddRecordingConsent && !skipConsent {
            return false  // Need to show consent sheet
        }
        return true
    }

    /// Update shared album consent preference
    func setSkipConsentForAlbum(_ album: Album, skip: Bool) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index].skipAddRecordingConsent = skip
        saveAlbums()
    }

    /// Add recording to shared album (with CloudKit sync)
    func addRecordingToSharedAlbum(_ recording: RecordingItem, album: Album) {
        guard album.isShared else {
            // Not shared, use regular method
            _ = setAlbum(album, for: recording)
            return
        }

        // Update local state
        var updated = recording
        updated.albumID = album.id
        updated.modifiedAt = Date()
        updateRecording(updated)

        // Sync to CloudKit shared zone
        Task {
            do {
                try await sharedAlbumManager.addRecordingToSharedAlbum(recording: updated, album: album)
            } catch {
                print("Failed to sync recording to shared album: \(error)")
            }
        }
    }

    /// Delete recording from shared album (deletes for everyone)
    func deleteRecordingFromSharedAlbum(_ recording: RecordingItem, album: Album) {
        guard album.isShared else {
            // Not shared, use regular delete
            moveToTrash(recording)
            return
        }

        // Remove from local state
        let recordingId = recording.id
        recordings.removeAll { $0.id == recordingId }
        saveRecordings()

        // Delete from CloudKit shared zone
        Task {
            do {
                try await sharedAlbumManager.deleteRecordingFromSharedAlbum(recordingId: recordingId, album: album)
            } catch {
                print("Failed to delete recording from shared album: \(error)")
            }
        }
    }

    // MARK: - Enhanced Shared Album Management

    /// Cache for shared recording metadata
    private(set) var sharedRecordingInfoCache: [UUID: SharedRecordingItem] = [:]

    /// Get shared recording info for a recording (from cache or creates default)
    func sharedRecordingInfo(for recording: RecordingItem, in album: Album) -> SharedRecordingItem? {
        guard album.isShared else { return nil }

        if let cached = sharedRecordingInfoCache[recording.id] {
            return cached
        }

        // Create default shared recording info
        return nil
    }

    /// Update cached shared recording info
    func updateSharedRecordingInfo(_ info: SharedRecordingItem) {
        sharedRecordingInfoCache[info.recordingId] = info
    }

    /// Clear shared recording info cache
    func clearSharedRecordingInfoCache() {
        sharedRecordingInfoCache.removeAll()
    }

    /// Move recording to shared album trash
    func moveToSharedAlbumTrash(
        recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        let displayName = await sharedAlbumManager.getCurrentUserDisplayName()
        let userId = await sharedAlbumManager.getCurrentUserId() ?? "unknown"

        let trashItem = try await sharedAlbumManager.moveToTrash(
            recording: sharedInfo,
            localRecording: recording,
            album: album,
            deletedBy: userId,
            deletedByDisplayName: displayName
        )

        // Remove from local recordings
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()

        // Clear from cache
        sharedRecordingInfoCache.removeValue(forKey: recording.id)
    }

    /// Restore recording from shared album trash
    func restoreFromSharedAlbumTrash(
        trashItem: SharedAlbumTrashItem,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.restoreFromTrash(trashItem: trashItem, album: album)

        // The recording will be re-synced from CloudKit
        // For now, we don't need to do anything local
    }

    /// Update location sharing for a recording in shared album
    func updateLocationSharing(
        for recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        mode: LocationSharingMode,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.updateLocationSharing(
            recording: sharedInfo,
            mode: mode,
            album: album,
            latitude: recording.latitude,
            longitude: recording.longitude,
            placeName: recording.locationLabel
        )

        // Update cache with new mode
        var updatedInfo = sharedInfo
        updatedInfo.locationSharingMode = mode
        if mode != .none, let lat = recording.latitude, let lon = recording.longitude {
            let approx = SharedRecordingItem.approximateLocation(latitude: lat, longitude: lon, mode: mode)
            updatedInfo.sharedLatitude = approx.latitude
            updatedInfo.sharedLongitude = approx.longitude
            updatedInfo.sharedPlaceName = recording.locationLabel
        } else {
            updatedInfo.sharedLatitude = nil
            updatedInfo.sharedLongitude = nil
            updatedInfo.sharedPlaceName = nil
        }
        sharedRecordingInfoCache[recording.id] = updatedInfo
    }

    /// Mark recording as sensitive in shared album
    func markRecordingSensitive(
        recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        isSensitive: Bool,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.markRecordingSensitive(
            recording: sharedInfo,
            isSensitive: isSensitive,
            album: album
        )

        // Update cache
        var updatedInfo = sharedInfo
        updatedInfo.isSensitive = isSensitive
        updatedInfo.sensitiveApproved = false
        sharedRecordingInfoCache[recording.id] = updatedInfo
    }

    /// Get recordings with pending sensitive approval (for admin)
    func pendingSensitiveApprovals(in album: Album) -> [(recording: RecordingItem, sharedInfo: SharedRecordingItem)] {
        guard album.isShared, album.currentUserRole == .admin else { return [] }

        return recordings(in: album).compactMap { recording -> (RecordingItem, SharedRecordingItem)? in
            guard let info = sharedRecordingInfoCache[recording.id],
                  info.isSensitive && !info.sensitiveApproved else {
                return nil
            }
            return (recording, info)
        }
    }

    /// Refresh shared album data from CloudKit
    func refreshSharedAlbumData(for album: Album) async {
        guard album.isShared else { return }

        // Fetch fresh settings
        if let settings = await sharedAlbumManager.fetchAlbumSettings(for: album) {
            var updatedAlbum = album
            updatedAlbum.sharedSettings = settings
            updateSharedAlbum(updatedAlbum)
        }

        // Fetch participants
        let participants = await sharedAlbumManager.fetchParticipants(for: album)
        if !participants.isEmpty {
            var updatedAlbum = album
            updatedAlbum.participants = participants
            updatedAlbum.participantCount = participants.count
            updateSharedAlbum(updatedAlbum)
        }

        // Purge expired trash items
        do {
            try await sharedAlbumManager.purgeExpiredTrashItems(for: album)
        } catch {
            print("Failed to purge expired trash items: \(error)")
        }
    }

    private func migrateRecordingsToDrafts() {
        let didMigrate = UserDefaults.standard.bool(forKey: draftsMigrationKey)
        guard !didMigrate else { return }

        var changed = false
        for i in recordings.indices {
            if recordings[i].albumID == nil {
                recordings[i].albumID = Album.draftsID
                changed = true
            }
        }

        if changed {
            saveRecordings()
        }
        UserDefaults.standard.set(true, forKey: draftsMigrationKey)
    }

    /// Migrate existing "Inbox" album to "Drafts"
    private func migrateInboxToDrafts() {
        // Find if there's an album with name "Inbox" and the system ID
        if let index = albums.firstIndex(where: { $0.id == Album.draftsID && $0.name == "Inbox" }) {
            albums[index].name = "Drafts"
            saveAlbums()
        }
    }

    // MARK: - Album Search Helpers

    func recordings(in album: Album) -> [RecordingItem] {
        activeRecordings.filter { $0.albumID == album.id }
    }

    func recordingCount(in album: Album) -> Int {
        activeRecordings.filter { $0.albumID == album.id }.count
    }

    func searchAlbums(query: String) -> [Album] {
        guard !query.isEmpty else { return albums }
        let lowercasedQuery = query.lowercased()
        return albums.filter { $0.name.lowercased().contains(lowercasedQuery) }
    }

    // MARK: - Storage Size Helpers

    /// Cache for recording file sizes [RecordingID: Bytes]
    private var recordingSizeCache: [UUID: Int64] = [:]

    /// Get file size for a recording (cached)
    func recordingFileSize(_ recording: RecordingItem) -> Int64 {
        if let cached = recordingSizeCache[recording.id] {
            return cached
        }
        let size = recording.fileSizeBytes ?? 0
        recordingSizeCache[recording.id] = size
        return size
    }

    /// Get total size of all recordings in an album (bytes)
    func albumTotalBytes(_ album: Album) -> Int64 {
        recordings(in: album).reduce(0) { sum, recording in
            sum + recordingFileSize(recording)
        }
    }

    /// Get formatted total size of an album (e.g., "124 MB")
    func albumTotalSizeFormatted(_ album: Album) -> String {
        StorageFormatter.format(albumTotalBytes(album))
    }

    /// Get total size of all recordings in a project (bytes)
    func projectTotalBytes(_ project: Project) -> Int64 {
        recordings(in: project).reduce(0) { sum, recording in
            sum + recordingFileSize(recording)
        }
    }

    /// Get formatted total size of a project (e.g., "45.2 MB")
    func projectTotalSizeFormatted(_ project: Project) -> String {
        StorageFormatter.format(projectTotalBytes(project))
    }

    /// Invalidate size cache for a specific recording (call when recording is deleted/moved)
    func invalidateSizeCache(for recordingID: UUID) {
        recordingSizeCache.removeValue(forKey: recordingID)
    }

    /// Clear all size caches (call after major sync operations)
    func clearSizeCache() {
        recordingSizeCache.removeAll()
    }

    // MARK: - Search

    func searchRecordings(query: String, filterTagIDs: Set<UUID> = []) -> [RecordingItem] {
        var results = activeRecordings

        // Filter by tags if any selected
        if !filterTagIDs.isEmpty {
            results = results.filter { recording in
                !filterTagIDs.isDisjoint(with: Set(recording.tagIDs))
            }
        }

        // Filter by search query
        if !query.isEmpty {
            let lowercasedQuery = query.lowercased()
            results = results.filter { recording in
                // Match title
                if recording.title.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match notes
                if recording.notes.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match location
                if recording.locationLabel.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match tag names
                let recordingTags = tags(for: recording.tagIDs)
                if recordingTags.contains(where: { $0.name.lowercased().contains(lowercasedQuery) }) {
                    return true
                }
                // Match album name
                if let album = album(for: recording.albumID),
                   album.name.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match transcript
                if recording.transcript.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match project title
                if let projectId = recording.projectId,
                   let project = project(for: projectId),
                   project.title.lowercased().contains(lowercasedQuery) {
                    return true
                }
                return false
            }
        }

        return results
    }

    // MARK: - Spot Computation (for Map)

    /// All recording spots (clustered by location)
    func allSpots() -> [RecordingSpot] {
        SpotClustering.computeSpots(
            recordings: activeRecordings,
            favoriteTagID: favoriteTagID,
            filterFavoritesOnly: false
        )
    }

    /// Top spots by total recording count
    func topSpots(limit: Int = 3) -> [RecordingSpot] {
        Array(allSpots().sorted { $0.totalCount > $1.totalCount }.prefix(limit))
    }

    /// Top spots with favorite recordings (sorted by favorite count)
    func topFavoriteSpots(limit: Int = 3) -> [RecordingSpot] {
        let spotsWithFavorites = SpotClustering.computeSpots(
            recordings: activeRecordings,
            favoriteTagID: favoriteTagID,
            filterFavoritesOnly: true
        )
        return Array(spotsWithFavorites.sorted { $0.favoriteCount > $1.favoriteCount }.prefix(limit))
    }

    /// Least used spots (at least 1 recording, sorted ascending)
    func leastUsedSpots(limit: Int = 3) -> [RecordingSpot] {
        let spots = allSpots().filter { $0.totalCount >= 1 }
        return Array(spots.sorted { $0.totalCount < $1.totalCount }.prefix(limit))
    }

    // MARK: - Batch Operations

    func addTagToRecordings(_ tag: Tag, recordingIDs: Set<UUID>) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) && !recordings[i].tagIDs.contains(tag.id) {
                recordings[i].tagIDs.append(tag.id)
                recordings[i].modifiedAt = Date()
            }
        }
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForMetadata()
    }

    func removeTagFromRecordings(_ tag: Tag, recordingIDs: Set<UUID>) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                recordings[i].tagIDs.removeAll { $0 == tag.id }
                recordings[i].modifiedAt = Date()
            }
        }
        saveRecordings()

        // Trigger iCloud sync
        triggerSyncForMetadata()
    }

    func setAlbumForRecordings(_ album: Album?, recordingIDs: Set<UUID>) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                recordings[i].albumID = album?.id ?? Album.draftsID
            }
        }
        saveRecordings()
    }

    func moveRecordingsToTrash(recordingIDs: Set<UUID>) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                recordings[i].trashedAt = Date()
            }
        }
        saveRecordings()
    }

    // MARK: - Import

    func importRecording(from url: URL, duration: TimeInterval, title: String? = nil, albumID: UUID = Album.draftsID) throws {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Use UUID-based filename to avoid conflicts, preserving original extension
        let fileExtension = url.pathExtension.lowercased()
        let uniqueFilename = "\(UUID().uuidString).\(fileExtension)"
        let destURL = documentsPath.appendingPathComponent(uniqueFilename)

        // Copy file to documents
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: url, to: destURL)

        // Use provided title or generate one
        let recordingTitle = title ?? "Recording \(nextRecordingNumber)"
        if title == nil {
            nextRecordingNumber += 1
            saveNextRecordingNumber()
        }

        let recording = RecordingItem(
            fileURL: destURL,
            createdAt: Date(),
            duration: duration,
            title: recordingTitle,
            albumID: albumID
        )

        recordings.insert(recording, at: 0)
        saveRecordings()

        // Trigger async waveform sampling
        Task {
            _ = await WaveformSampler.shared.samples(for: destURL, targetSampleCount: 150)
        }
    }

    // MARK: - Tag Migration

    private func migrateFavTagToFavorite() {
        let didMigrate = UserDefaults.standard.bool(forKey: tagMigrationKey)
        guard !didMigrate else { return }

        // Check if "fav" tag exists
        guard let favIndex = tags.firstIndex(where: { $0.name.lowercased() == "fav" }) else {
            UserDefaults.standard.set(true, forKey: tagMigrationKey)
            return
        }

        // Check if "favorite" already exists
        let favoriteExists = tags.contains { $0.name.lowercased() == "favorite" }

        if favoriteExists {
            // Don't create duplicate, just mark migration done
        } else {
            // Rename "fav" to "favorite"
            tags[favIndex].name = "favorite"
            saveTags()
        }

        UserDefaults.standard.set(true, forKey: tagMigrationKey)
    }

    // MARK: - Persistence

    private func saveRecordings() {
        if let data = try? JSONEncoder().encode(recordings) {
            UserDefaults.standard.set(data, forKey: recordingsKey)
        }
    }

    private func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: recordingsKey),
              let saved = try? JSONDecoder().decode([RecordingItem].self, from: data) else {
            return
        }
        recordings = saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func saveTags() {
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: tagsKey)
        }
    }

    private func loadTags() {
        guard let data = UserDefaults.standard.data(forKey: tagsKey),
              let saved = try? JSONDecoder().decode([Tag].self, from: data) else {
            return
        }
        tags = saved
    }

    private func saveAlbums() {
        if let data = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(data, forKey: albumsKey)
        }
    }

    private func loadAlbums() {
        guard let data = UserDefaults.standard.data(forKey: albumsKey),
              let saved = try? JSONDecoder().decode([Album].self, from: data) else {
            return
        }
        albums = saved
    }

    private func saveNextRecordingNumber() {
        UserDefaults.standard.set(nextRecordingNumber, forKey: nextNumberKey)
    }

    private func loadNextRecordingNumber() {
        let saved = UserDefaults.standard.integer(forKey: nextNumberKey)
        nextRecordingNumber = saved > 0 ? saved : 1
    }

    private func saveAppearanceMode() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
    }

    private func loadAppearanceMode() {
        guard let rawValue = UserDefaults.standard.string(forKey: appearanceModeKey),
              let mode = AppearanceMode(rawValue: rawValue) else {
            return
        }
        appearanceMode = mode
    }

    private func saveSelectedTheme() {
        UserDefaults.standard.set(selectedTheme.rawValue, forKey: selectedThemeKey)
    }

    private func loadSelectedTheme() {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedThemeKey),
              let theme = AppTheme(rawValue: rawValue) else {
            return
        }
        selectedTheme = theme
    }

    private func saveAppSettings() {
        if let data = try? JSONEncoder().encode(appSettings) {
            UserDefaults.standard.set(data, forKey: appSettingsKey)
        }
    }

    private func loadAppSettings() {
        guard let data = UserDefaults.standard.data(forKey: appSettingsKey),
              let saved = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return
        }
        appSettings = saved
    }

    private func seedDefaultTagsIfNeeded() {
        if tags.isEmpty {
            tags = Tag.defaultTags
            saveTags()
        } else {
            // Ensure the protected favorite tag always exists
            ensureFavoriteTagExists()
        }
    }

    private func ensureFavoriteTagExists() {
        // Check if favorite tag exists by its stable ID
        if !tags.contains(where: { $0.id == Tag.favoriteTagID }) {
            // Recreate the favorite tag with default color
            let favoriteTag = Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: "#FF6B6B")
            tags.insert(favoriteTag, at: 0)
            saveTags()
        }
    }

    // MARK: - Album Rename

    func renameAlbum(_ album: Album, to newName: String) -> Bool {
        // System albums cannot be renamed
        guard album.canRename else { return false }

        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            return false
        }

        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }

        albums[index].name = trimmedName
        saveAlbums()

        // Trigger iCloud sync for album update
        triggerSyncForAlbumUpdate(albums[index])

        return true
    }

    // MARK: - Project Management

    /// Get a project by ID
    func project(for id: UUID?) -> Project? {
        guard let id = id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Get all recordings (versions) belonging to a project, sorted by version index
    func recordings(in project: Project) -> [RecordingItem] {
        activeRecordings
            .filter { $0.projectId == project.id }
            .sorted { $0.versionIndex < $1.versionIndex }
    }

    /// Get recording count for a project
    func recordingCount(in project: Project) -> Int {
        activeRecordings.filter { $0.projectId == project.id }.count
    }

    /// Get the next version number for a project
    func nextVersionIndex(for project: Project) -> Int {
        let versions = recordings(in: project)
        return (versions.map { $0.versionIndex }.max() ?? 0) + 1
    }

    /// Get the best take recording for a project
    func bestTake(for project: Project) -> RecordingItem? {
        guard let bestTakeId = project.bestTakeRecordingId else { return nil }
        return recording(for: bestTakeId)
    }

    /// Create a new project from an existing recording (recording becomes V1)
    @discardableResult
    func createProject(from recording: RecordingItem, title: String? = nil) -> Project {
        // Create the project
        let project = Project(
            title: title ?? recording.title,
            createdAt: Date(),
            updatedAt: Date()
        )

        // Update the recording to belong to this project as V1
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].projectId = project.id
            recordings[index].parentRecordingId = nil
            recordings[index].versionIndex = 1
            recordings[index].modifiedAt = Date()
        }

        projects.insert(project, at: 0)
        saveProjects()
        saveRecordings()

        // Trigger iCloud sync for new project
        triggerSyncForProject(project)

        return project
    }

    /// Create a new empty project
    @discardableResult
    func createProject(title: String) -> Project {
        let project = Project(title: title)
        projects.insert(project, at: 0)
        saveProjects()

        // Trigger iCloud sync for new project
        triggerSyncForProject(project)

        return project
    }

    /// Add a recording as a new version to an existing project
    func addVersion(recording: RecordingItem, to project: Project) {
        let nextVersion = nextVersionIndex(for: project)

        // Find the latest version to link as parent
        let versions = recordings(in: project)
        let latestVersion = versions.last

        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].projectId = project.id
            recordings[index].parentRecordingId = latestVersion?.id
            recordings[index].versionIndex = nextVersion
        }

        // Update project's updatedAt
        if let projectIndex = projects.firstIndex(where: { $0.id == project.id }) {
            projects[projectIndex].updatedAt = Date()
        }

        saveRecordings()
        saveProjects()
    }

    /// Remove a recording from its project (makes it standalone)
    func removeFromProject(recording: RecordingItem) {
        guard let projectId = recording.projectId else { return }

        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].projectId = nil
            recordings[index].parentRecordingId = nil
            recordings[index].versionIndex = 1
        }

        // Update project's updatedAt
        if let projectIndex = projects.firstIndex(where: { $0.id == projectId }) {
            projects[projectIndex].updatedAt = Date()

            // If this was the best take, clear it
            if projects[projectIndex].bestTakeRecordingId == recording.id {
                projects[projectIndex].bestTakeRecordingId = nil
            }
        }

        saveRecordings()
        saveProjects()
    }

    /// Set the best take for a project
    func setBestTake(_ recording: RecordingItem, for project: Project) {
        guard recording.projectId == project.id else { return }

        if let projectIndex = projects.firstIndex(where: { $0.id == project.id }) {
            projects[projectIndex].bestTakeRecordingId = recording.id
            projects[projectIndex].updatedAt = Date()
            saveProjects()

            // Trigger iCloud sync for project update
            triggerSyncForProjectUpdate(projects[projectIndex])
        }
    }

    /// Clear the best take for a project
    func clearBestTake(for project: Project) {
        if let projectIndex = projects.firstIndex(where: { $0.id == project.id }) {
            projects[projectIndex].bestTakeRecordingId = nil
            projects[projectIndex].updatedAt = Date()
            saveProjects()

            // Trigger iCloud sync for project update
            triggerSyncForProjectUpdate(projects[projectIndex])
        }
    }

    /// Update project properties
    func updateProject(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            var updated = project
            updated.updatedAt = Date()
            projects[index] = updated
            saveProjects()

            // Trigger iCloud sync for project update
            triggerSyncForProjectUpdate(updated)
        }
    }

    /// Toggle project pin status
    func toggleProjectPin(_ project: Project) {
        if let index = projects.firstIndex(where: { $0.id == project.id }) {
            projects[index].pinned.toggle()
            projects[index].updatedAt = Date()
            saveProjects()

            // Trigger iCloud sync for project update
            triggerSyncForProjectUpdate(projects[index])
        }
    }

    /// Delete a project (recordings become standalone)
    func deleteProject(_ project: Project) {
        let projectId = project.id

        // Remove project association from all recordings
        for i in recordings.indices {
            if recordings[i].projectId == projectId {
                recordings[i].projectId = nil
                recordings[i].parentRecordingId = nil
                recordings[i].versionIndex = 1
            }
        }

        projects.removeAll { $0.id == projectId }
        saveProjects()
        saveRecordings()

        // Trigger iCloud sync for project deletion
        triggerSyncForProjectDeletion(projectId)
    }

    /// Get project statistics
    func stats(for project: Project) -> ProjectStats {
        let versions = recordings(in: project)
        let totalDuration = versions.reduce(0) { $0 + $1.duration }
        let dates = versions.map { $0.createdAt }

        return ProjectStats(
            versionCount: versions.count,
            totalDuration: totalDuration,
            oldestVersion: dates.min(),
            newestVersion: dates.max(),
            hasBestTake: project.bestTakeRecordingId != nil
        )
    }

    /// Search projects by query
    func searchProjects(query: String) -> [Project] {
        guard !query.isEmpty else { return projects }
        let lowercasedQuery = query.lowercased()
        return projects.filter { project in
            // Match title
            if project.title.lowercased().contains(lowercasedQuery) {
                return true
            }
            // Match notes
            if project.notes.lowercased().contains(lowercasedQuery) {
                return true
            }
            return false
        }
    }

    /// Get all projects sorted (pinned first, then by updatedAt)
    var sortedProjects: [Project] {
        projects.sorted { a, b in
            if a.pinned != b.pinned {
                return a.pinned
            }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Get recordings that are standalone (not part of any project)
    var standaloneRecordings: [RecordingItem] {
        activeRecordings.filter { $0.projectId == nil }
    }

    // MARK: - Project Persistence

    private func saveProjects() {
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: projectsKey)
        }
    }

    private func loadProjects() {
        guard let data = UserDefaults.standard.data(forKey: projectsKey),
              let saved = try? JSONDecoder().decode([Project].self, from: data) else {
            return
        }
        projects = saved
    }

    // MARK: - Overdub Groups Persistence

    private func saveOverdubGroups() {
        if let data = try? JSONEncoder().encode(overdubGroups) {
            UserDefaults.standard.set(data, forKey: overdubGroupsKey)
        }
    }

    private func loadOverdubGroups() {
        guard let data = UserDefaults.standard.data(forKey: overdubGroupsKey),
              let saved = try? JSONDecoder().decode([OverdubGroup].self, from: data) else {
            return
        }
        overdubGroups = saved
    }

    // MARK: - Overdub Group Management

    /// Get overdub group by ID
    func overdubGroup(for id: UUID) -> OverdubGroup? {
        overdubGroups.first { $0.id == id }
    }

    /// Get overdub group for a recording (if it belongs to one)
    func overdubGroup(for recording: RecordingItem) -> OverdubGroup? {
        guard let groupId = recording.overdubGroupId else { return nil }
        return overdubGroup(for: groupId)
    }

    /// Get all recordings in an overdub group
    func recordings(in group: OverdubGroup) -> [RecordingItem] {
        let ids = Set(group.allRecordingIds)
        return recordings.filter { ids.contains($0.id) }
    }

    /// Get the base recording for an overdub group
    func baseRecording(for group: OverdubGroup) -> RecordingItem? {
        recordings.first { $0.id == group.baseRecordingId }
    }

    /// Get layer recordings for an overdub group (ordered by index)
    func layerRecordings(for group: OverdubGroup) -> [RecordingItem] {
        let layerIds = Set(group.layerRecordingIds)
        return recordings
            .filter { layerIds.contains($0.id) }
            .sorted { ($0.overdubIndex ?? 0) < ($1.overdubIndex ?? 0) }
    }

    /// Create a new overdub group with a base recording
    func createOverdubGroup(baseRecording: RecordingItem) -> OverdubGroup {
        let group = OverdubGroup(baseRecordingId: baseRecording.id)

        // Update the base recording
        if let index = recordings.firstIndex(where: { $0.id == baseRecording.id }) {
            recordings[index].overdubGroupId = group.id
            recordings[index].overdubRole = .base
            recordings[index].overdubIndex = 0
        }

        overdubGroups.append(group)
        saveOverdubGroups()
        saveRecordings()

        return group
    }

    /// Add a layer recording to an overdub group
    func addLayerToOverdubGroup(
        groupId: UUID,
        layerRecording: RecordingItem,
        offsetSeconds: Double = 0
    ) {
        guard var group = overdubGroup(for: groupId),
              group.canAddLayer else { return }

        let layerIndex = group.nextLayerIndex ?? 1

        // Update the layer recording
        if let index = recordings.firstIndex(where: { $0.id == layerRecording.id }) {
            recordings[index].overdubGroupId = groupId
            recordings[index].overdubRole = .layer
            recordings[index].overdubIndex = layerIndex
            recordings[index].overdubOffsetSeconds = offsetSeconds
            recordings[index].overdubSourceBaseId = group.baseRecordingId
        }

        // Add to group
        group.addLayer(recordingId: layerRecording.id)

        // Update the group in storage
        if let groupIndex = overdubGroups.firstIndex(where: { $0.id == groupId }) {
            overdubGroups[groupIndex] = group
        }

        saveOverdubGroups()
        saveRecordings()
    }

    /// Check if a recording can have overdub layers added
    func canAddOverdubLayer(to recording: RecordingItem) -> Bool {
        // If not part of an overdub group yet, it can start one
        guard let groupId = recording.overdubGroupId else { return true }

        // If already in a group, check if group has room
        guard let group = overdubGroup(for: groupId) else { return true }
        return group.canAddLayer
    }

    /// Get the number of existing layers for a recording
    func overdubLayerCount(for recording: RecordingItem) -> Int {
        guard let groupId = recording.overdubGroupId,
              let group = overdubGroup(for: groupId) else { return 0 }
        return group.layerCount
    }

    /// Update layer offset for sync adjustment
    func updateLayerOffset(recordingId: UUID, offsetSeconds: Double) {
        if let index = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[index].overdubOffsetSeconds = offsetSeconds
            saveRecordings()
        }
    }
}

// MARK: - Pending Actions (for AppIntents, Widgets, Quick Actions)

enum PendingActionKeys {
    static let pendingStartRecording = "pendingStartRecording"
}

extension AppState {
    /// Check and consume pending start recording action
    func consumePendingStartRecording() {
        let pending = UserDefaults.standard.bool(forKey: PendingActionKeys.pendingStartRecording)
        guard pending else { return }

        // Clear the flag first to prevent double triggers
        UserDefaults.standard.set(false, forKey: PendingActionKeys.pendingStartRecording)

        // Start recording if not already recording
        if !recorder.isRecording {
            recorder.startRecording()
        }
    }

    /// Set the pending start recording flag (called from AppIntent/Quick Action)
    static func setPendingStartRecording() {
        UserDefaults.standard.set(true, forKey: PendingActionKeys.pendingStartRecording)
    }
}

// MARK: - Debug Mode for Shared Albums Testing

extension AppState {
    private static let sharedAlbumsDebugModeKey = "sharedAlbumsDebugMode"
    private static let debugSharedAlbumIdKey = "debugSharedAlbumId"

    /// Whether debug mode is enabled for shared albums
    var isSharedAlbumsDebugMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.sharedAlbumsDebugModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sharedAlbumsDebugModeKey) }
    }

    /// The debug shared album ID (stored to maintain consistency)
    private var debugSharedAlbumId: UUID {
        if let idString = UserDefaults.standard.string(forKey: Self.debugSharedAlbumIdKey),
           let id = UUID(uuidString: idString) {
            return id
        }
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: Self.debugSharedAlbumIdKey)
        return newId
    }

    /// Enable debug mode and create mock shared album
    func enableSharedAlbumsDebugMode() {
        isSharedAlbumsDebugMode = true
        createMockSharedAlbum()
    }

    /// Disable debug mode and remove mock data
    func disableSharedAlbumsDebugMode() {
        isSharedAlbumsDebugMode = false
        removeMockSharedAlbum()
    }

    /// Create a mock shared album with sample data
    private func createMockSharedAlbum() {
        let albumId = debugSharedAlbumId

        // Check if already exists
        if albums.contains(where: { $0.id == albumId }) {
            return
        }

        // Create mock participants
        let participants = [
            SharedAlbumParticipant(
                id: "user_001",
                displayName: "You (Admin)",
                role: .admin,
                acceptanceStatus: .accepted,
                joinedAt: Date().addingTimeInterval(-86400 * 7),
                avatarInitials: "YO"
            ),
            SharedAlbumParticipant(
                id: "user_002",
                displayName: "Sarah Johnson",
                role: .member,
                acceptanceStatus: .accepted,
                joinedAt: Date().addingTimeInterval(-86400 * 5),
                avatarInitials: "SJ"
            ),
            SharedAlbumParticipant(
                id: "user_003",
                displayName: "Mike Chen",
                role: .member,
                acceptanceStatus: .accepted,
                joinedAt: Date().addingTimeInterval(-86400 * 3),
                avatarInitials: "MC"
            ),
            SharedAlbumParticipant(
                id: "user_004",
                displayName: "Emily Davis",
                role: .viewer,
                acceptanceStatus: .pending,
                joinedAt: nil,
                avatarInitials: "ED"
            )
        ]

        // Create the shared album
        let sharedAlbum = Album(
            id: albumId,
            name: "Demo Shared Album",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            isSystem: false,
            isShared: true,
            shareURL: URL(string: "https://www.icloud.com/share/demo"),
            participantCount: participants.count,
            isOwner: true,
            cloudKitShareRecordName: "demo_share_record",
            skipAddRecordingConsent: false,
            sharedSettings: SharedAlbumSettings(
                allowMembersToDelete: true,
                trashRestorePermission: .anyParticipant,
                trashRetentionDays: 14,
                defaultLocationSharingMode: .approximate,
                allowMembersToShareLocation: true,
                requireSensitiveApproval: false
            ),
            currentUserRole: .admin,
            participants: participants
        )

        albums.append(sharedAlbum)
        saveAlbums()

        // Create mock recordings
        createMockRecordingsForDebugAlbum(albumId: albumId)

        // Create mock shared recording info
        createMockSharedRecordingInfo(albumId: albumId)
    }

    /// Create mock recordings for the debug shared album
    private func createMockRecordingsForDebugAlbum(albumId: UUID) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let mockRecordings: [(title: String, duration: TimeInterval, daysAgo: Int, lat: Double?, lon: Double?, notes: String)] = [
            ("Team Brainstorm Session", 847.5, 1, 37.7749, -122.4194, "Weekly team meeting - discussed Q2 roadmap"),
            ("Interview with Dr. Smith", 1523.0, 2, 37.7849, -122.4094, "Expert interview for research project"),
            ("Field Notes - Park Visit", 324.0, 3, 37.7694, -122.4862, "Nature sounds and observations"),
            ("Quick Voice Memo", 45.0, 4, nil, nil, "Reminder about tomorrow's presentation"),
            ("Client Feedback Call", 1892.0, 5, 37.7849, -122.4294, "Quarterly review with client"),
            ("Music Idea #7", 128.0, 6, nil, nil, "Melody idea for new project")
        ]

        for (index, mock) in mockRecordings.enumerated() {
            let recordingId = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 100))")!

            // Create a placeholder file URL (won't actually play)
            let fileURL = documentsURL.appendingPathComponent("demo_recording_\(index).m4a")

            let recording = RecordingItem(
                id: recordingId,
                fileURL: fileURL,
                createdAt: Date().addingTimeInterval(-86400 * Double(mock.daysAgo)),
                duration: mock.duration,
                title: mock.title,
                notes: mock.notes,
                tagIDs: [],
                albumID: albumId,
                locationLabel: mock.lat != nil ? "San Francisco, CA" : "",
                transcript: "",
                latitude: mock.lat,
                longitude: mock.lon,
                trashedAt: nil,
                lastPlaybackPosition: 0,
                iconColorHex: nil,
                iconName: nil
            )

            recordings.append(recording)
        }

        saveRecordings()
    }

    /// Create mock shared recording info for debug recordings
    private func createMockSharedRecordingInfo(albumId: UUID) {
        let albumRecordings = recordings.filter { $0.albumID == albumId }

        let creators = [
            ("user_001", "You", "YO"),
            ("user_002", "Sarah Johnson", "SJ"),
            ("user_003", "Mike Chen", "MC")
        ]

        for (index, recording) in albumRecordings.enumerated() {
            let creator = creators[index % creators.count]

            let locationMode: LocationSharingMode = recording.latitude != nil ? .approximate : .none

            let sharedInfo = SharedRecordingItem(
                id: UUID(),
                recordingId: recording.id,
                albumId: albumId,
                creatorId: creator.0,
                creatorDisplayName: creator.1,
                createdAt: recording.createdAt,
                wasImported: index == 1,
                recordedWithHeadphones: index == 2,
                isSensitive: index == 3,
                sensitiveApproved: index == 3,
                sensitiveApprovedBy: index == 3 ? "user_001" : nil,
                locationSharingMode: locationMode,
                sharedLatitude: locationMode != .none ? recording.latitude : nil,
                sharedLongitude: locationMode != .none ? recording.longitude : nil,
                sharedPlaceName: locationMode != .none ? "San Francisco, CA" : nil,
                isVerified: index < 3,
                verifiedAt: index < 3 ? recording.createdAt : nil
            )

            sharedRecordingInfoCache[recording.id] = sharedInfo
        }
    }

    /// Remove mock shared album and associated data
    private func removeMockSharedAlbum() {
        let albumId = debugSharedAlbumId

        // Remove the album
        albums.removeAll { $0.id == albumId }
        saveAlbums()

        // Remove associated recordings
        let recordingIds = recordings.filter { $0.albumID == albumId }.map { $0.id }
        recordings.removeAll { $0.albumID == albumId }
        saveRecordings()

        // Clear cached shared info
        for id in recordingIds {
            sharedRecordingInfoCache.removeValue(forKey: id)
        }
    }

    /// Get mock activity feed for debug mode
    func debugMockActivityFeed() -> [SharedAlbumActivityEvent] {
        guard isSharedAlbumsDebugMode else { return [] }

        let albumId = debugSharedAlbumId
        let albumRecordings = recordings.filter { $0.albumID == albumId }

        var events: [SharedAlbumActivityEvent] = []

        // Generate mock activity events
        let activities: [(type: ActivityEventType, actorId: String, actorName: String, hoursAgo: Int)] = [
            (.recordingAdded, "user_002", "Sarah Johnson", 2),
            (.recordingAdded, "user_003", "Mike Chen", 5),
            (.locationEnabled, "user_002", "Sarah Johnson", 6),
            (.participantJoined, "user_003", "Mike Chen", 72),
            (.recordingAdded, "user_001", "You", 96),
            (.participantJoined, "user_002", "Sarah Johnson", 120),
            (.settingAllowDeletesChanged, "user_001", "You", 168)
        ]

        for (index, activity) in activities.enumerated() {
            let event = SharedAlbumActivityEvent(
                id: UUID(),
                albumId: albumId,
                timestamp: Date().addingTimeInterval(-3600 * Double(activity.hoursAgo)),
                actorId: activity.actorId,
                actorDisplayName: activity.actorName,
                eventType: activity.type,
                targetRecordingId: activity.type == .recordingAdded ? albumRecordings[safe: index % albumRecordings.count]?.id : nil,
                targetRecordingTitle: activity.type == .recordingAdded ? albumRecordings[safe: index % albumRecordings.count]?.title : nil,
                targetParticipantId: activity.type == .participantJoined ? activity.actorId : nil,
                targetParticipantName: activity.type == .participantJoined ? activity.actorName : nil,
                oldValue: activity.type == .settingAllowDeletesChanged ? "Off" : nil,
                newValue: activity.type == .settingAllowDeletesChanged ? "On" : nil
            )
            events.append(event)
        }

        return events.sorted { $0.timestamp > $1.timestamp }
    }

    /// Get mock trash items for debug mode
    func debugMockTrashItems() -> [SharedAlbumTrashItem] {
        guard isSharedAlbumsDebugMode else { return [] }

        let albumId = debugSharedAlbumId

        return [
            SharedAlbumTrashItem(
                id: UUID(),
                recordingId: UUID(),
                albumId: albumId,
                title: "Deleted Meeting Notes",
                duration: 456.0,
                creatorId: "user_002",
                creatorDisplayName: "Sarah Johnson",
                deletedBy: "user_001",
                deletedByDisplayName: "You",
                deletedAt: Date().addingTimeInterval(-86400 * 2),
                originalCreatedAt: Date().addingTimeInterval(-86400 * 10),
                audioAssetReference: nil
            ),
            SharedAlbumTrashItem(
                id: UUID(),
                recordingId: UUID(),
                albumId: albumId,
                title: "Old Voice Memo",
                duration: 89.0,
                creatorId: "user_003",
                creatorDisplayName: "Mike Chen",
                deletedBy: "user_003",
                deletedByDisplayName: "Mike Chen",
                deletedAt: Date().addingTimeInterval(-86400 * 12),
                originalCreatedAt: Date().addingTimeInterval(-86400 * 20),
                audioAssetReference: nil
            )
        ]
    }
}

// Safe array subscript extension
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
