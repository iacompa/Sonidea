//
//  AppState.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import Observation
import SwiftUI

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
    let recorder = RecorderManager()

    private(set) var nextRecordingNumber: Int = 1

    private let recordingsKey = "savedRecordings"
    private let tagsKey = "savedTags"
    private let albumsKey = "savedAlbums"
    private let nextNumberKey = "nextRecordingNumber"
    private let appearanceModeKey = "appearanceMode"
    private let tagMigrationKey = "didMigrateFavToFavorite"

    init() {
        loadAppearanceMode()
        loadNextRecordingNumber()
        loadTags()
        loadAlbums()
        loadRecordings()
        seedDefaultTagsIfNeeded()
        migrateFavTagToFavorite()
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
            title: title
        )

        recordings.insert(recording, at: 0)
        saveRecordings()
    }

    func updateRecording(_ updated: RecordingItem) {
        guard let index = recordings.firstIndex(where: { $0.id == updated.id }) else {
            return
        }
        recordings[index] = updated
        saveRecordings()
    }

    func deleteRecording(_ recording: RecordingItem) {
        try? FileManager.default.removeItem(at: recording.fileURL)
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
    }

    func deleteRecordings(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        recordings.remove(atOffsets: offsets)
        saveRecordings()
    }

    // MARK: - Tag Helpers

    func tag(for id: UUID) -> Tag? {
        tags.first { $0.id == id }
    }

    func tags(for ids: [UUID]) -> [Tag] {
        ids.compactMap { tag(for: $0) }
    }

    @discardableResult
    func createTag(name: String, colorHex: String) -> Tag {
        let tag = Tag(name: name, colorHex: colorHex)
        tags.append(tag)
        saveTags()
        return tag
    }

    func deleteTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        // Remove tag from all recordings
        for i in recordings.indices {
            recordings[i].tagIDs.removeAll { $0 == tag.id }
        }
        saveTags()
        saveRecordings()
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
        albums.removeAll { $0.id == album.id }
        // Remove album from all recordings
        for i in recordings.indices {
            if recordings[i].albumID == album.id {
                recordings[i].albumID = nil
            }
        }
        saveAlbums()
        saveRecordings()
    }

    func setAlbum(_ album: Album?, for recording: RecordingItem) -> RecordingItem {
        var updated = recording
        updated.albumID = album?.id
        updateRecording(updated)
        return updated
    }

    // MARK: - Search

    func searchRecordings(query: String, filterTagIDs: Set<UUID> = []) -> [RecordingItem] {
        var results = recordings

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
                return false
            }
        }

        return results
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

    private func seedDefaultTagsIfNeeded() {
        if tags.isEmpty {
            tags = Tag.defaultTags
            saveTags()
        }
    }
}
