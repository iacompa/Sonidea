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
    var appearanceMode: AppearanceMode = .system {
        didSet {
            saveAppearanceMode()
        }
    }
    var appSettings: AppSettings = .default {
        didSet {
            saveAppSettings()
            // Apply quality preset to recorder
            recorder.qualityPreset = appSettings.recordingQuality
        }
    }

    let recorder = RecorderManager()
    let locationManager = LocationManager()

    private(set) var nextRecordingNumber: Int = 1

    private let recordingsKey = "savedRecordings"
    private let tagsKey = "savedTags"
    private let albumsKey = "savedAlbums"
    private let nextNumberKey = "nextRecordingNumber"
    private let appearanceModeKey = "appearanceMode"
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
        loadAppSettings()
        loadNextRecordingNumber()
        loadTags()
        loadAlbums()
        loadRecordings()
        seedDefaultTagsIfNeeded()
        ensureDraftsAlbum()
        migrateFavTagToFavorite()
        migrateRecordingsToDrafts()
        migrateInboxToDrafts()
        purgeOldTrashedRecordings()
        recorder.qualityPreset = appSettings.recordingQuality
        loadRecordButtonPosition()
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

    func addRecording(from rawData: RawRecordingData) {
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

        // Auto-transcribe if enabled
        if appSettings.autoTranscribe {
            Task {
                await autoTranscribe(recording: recording)
            }
        }
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

    func updateRecording(_ updated: RecordingItem) {
        guard let index = recordings.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        recordings[index] = updated
        saveRecordings()
    }

    func updateTranscript(_ text: String, for recordingID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return
        }
        recordings[index].transcript = text
        saveRecordings()
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
        saveRecordings()
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
        saveRecordings()
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
        saveRecordings()
    }

    func permanentlyDelete(_ recording: RecordingItem) {
        try? FileManager.default.removeItem(at: recording.fileURL)
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
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
            return true
        }

        // Check for duplicate name (excluding current tag)
        if tagExists(name: name, excludingID: tag.id) {
            return false
        }
        tags[index].name = name
        tags[index].colorHex = colorHex
        saveTags()
        return true
    }

    func deleteTag(_ tag: Tag) -> Bool {
        // Cannot delete protected tags
        if tag.isProtected {
            return false
        }
        tags.removeAll { $0.id == tag.id }
        // Remove tag from all recordings
        for i in recordings.indices {
            recordings[i].tagIDs.removeAll { $0 == tag.id }
        }
        saveTags()
        saveRecordings()
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
        return album
    }

    func deleteAlbum(_ album: Album) {
        guard album.canDelete else { return }
        albums.removeAll { $0.id == album.id }
        // Move recordings to Drafts
        for i in recordings.indices {
            if recordings[i].albumID == album.id {
                recordings[i].albumID = Album.draftsID
            }
        }
        saveAlbums()
        saveRecordings()
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
            }
        }
        saveRecordings()
    }

    func removeTagFromRecordings(_ tag: Tag, recordingIDs: Set<UUID>) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                recordings[i].tagIDs.removeAll { $0 == tag.id }
            }
        }
        saveRecordings()
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

    func importRecording(from url: URL, duration: TimeInterval) {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = url.lastPathComponent
        let destURL = documentsPath.appendingPathComponent(filename)

        // Copy file to documents
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: url, to: destURL)
        } catch {
            print("Failed to copy imported file: \(error)")
            return
        }

        let title = "Recording \(nextRecordingNumber)"
        nextRecordingNumber += 1
        saveNextRecordingNumber()

        let recording = RecordingItem(
            fileURL: destURL,
            createdAt: Date(),
            duration: duration,
            title: title,
            albumID: Album.draftsID
        )

        recordings.insert(recording, at: 0)
        saveRecordings()
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
        return true
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
