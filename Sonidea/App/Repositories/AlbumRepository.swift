//
//  AlbumRepository.swift
//  Sonidea
//
//  Pure data operations for albums, extracted from AppState.
//  Operates on inout arrays with no persistence or sync side effects.
//  AppState handles save/sync after each operation.
//

import Foundation

/// Stateless repository for album data operations.
/// All methods take `inout` arrays and return results.
/// Caller (AppState) is responsible for persistence and sync.
enum AlbumRepository {

    // MARK: - Queries

    static func album(for id: UUID?, in albums: [Album]) -> Album? {
        guard let id = id else { return nil }
        return albums.first { $0.id == id }
    }

    static func recordings(in album: Album, from recordings: [RecordingItem]) -> [RecordingItem] {
        recordings.filter { !$0.isTrashed && $0.albumID == album.id }
    }

    static func recordingCount(in album: Album, from recordings: [RecordingItem]) -> Int {
        recordings.filter { !$0.isTrashed && $0.albumID == album.id }.count
    }

    // MARK: - Mutations

    /// Create a new user album. Returns the created album.
    @discardableResult
    static func createAlbum(name: String, albums: inout [Album]) -> Album {
        let album = Album(name: name)
        albums.append(album)
        return album
    }

    /// Delete an album and move its recordings to Drafts.
    /// Returns true if deletion succeeded (system albums cannot be deleted).
    static func deleteAlbum(
        _ album: Album,
        albums: inout [Album],
        recordings: inout [RecordingItem]
    ) -> Bool {
        guard album.canDelete else { return false }
        let albumId = album.id
        albums.removeAll { $0.id == albumId }
        for i in recordings.indices {
            if recordings[i].albumID == albumId {
                recordings[i].albumID = Album.draftsID
                recordings[i].modifiedAt = Date()
            }
        }
        return true
    }

    /// Rename an album. Returns true if rename succeeded.
    /// System albums cannot be renamed. Empty names are rejected.
    static func renameAlbum(
        _ album: Album,
        to newName: String,
        albums: inout [Album]
    ) -> Bool {
        guard album.canRename else { return false }
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else {
            return false
        }
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return false }
        albums[index].name = trimmedName
        return true
    }

    /// Assign an album to a recording. Returns the updated recording.
    static func setAlbum(
        _ album: Album?,
        for recording: RecordingItem,
        recordings: inout [RecordingItem]
    ) -> RecordingItem? {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else {
            return nil
        }
        recordings[index].albumID = album?.id ?? Album.draftsID
        recordings[index].modifiedAt = Date()
        return recordings[index]
    }

    /// Set album for multiple recordings at once.
    static func setAlbumForRecordings(
        _ album: Album?,
        recordingIDs: Set<UUID>,
        recordings: inout [RecordingItem]
    ) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                recordings[i].albumID = album?.id ?? Album.draftsID
                recordings[i].modifiedAt = Date()
            }
        }
    }

    // MARK: - System Album Management

    /// Ensure the Drafts system album exists. Also deduplicates any extra Drafts albums.
    /// Returns flags indicating which arrays were modified.
    @discardableResult
    static func ensureDraftsAlbum(
        albums: inout [Album],
        recordings: inout [RecordingItem]
    ) -> (albumsChanged: Bool, recordingsChanged: Bool) {
        var albumsChanged = false
        var recordingsChanged = false

        if !albums.contains(where: { $0.id == Album.draftsID }) {
            albums.insert(Album.drafts, at: 0)
            albumsChanged = true
        }

        // Deduplicate: merge any extra "Drafts" albums into the canonical one
        let duplicateDrafts = albums.filter { $0.id != Album.draftsID && $0.name == "Drafts" }
        if !duplicateDrafts.isEmpty {
            for dup in duplicateDrafts {
                for i in recordings.indices {
                    if recordings[i].albumID == dup.id {
                        recordings[i].albumID = Album.draftsID
                        recordingsChanged = true
                    }
                }
                albums.removeAll { $0.id == dup.id }
            }
            albumsChanged = true
        }

        return (albumsChanged, recordingsChanged)
    }

    /// Ensure the Imports system album exists. Returns true if it was created.
    @discardableResult
    static func ensureImportsAlbum(albums: inout [Album]) -> Bool {
        guard !albums.contains(where: { $0.id == Album.importsID }) else { return false }
        let insertIndex = albums.firstIndex(where: { $0.id == Album.draftsID }).map { $0 + 1 } ?? 0
        albums.insert(Album.imports, at: insertIndex)
        return true
    }

    /// Ensure the Watch Recordings system album exists. Returns true if it was created.
    @discardableResult
    static func ensureWatchRecordingsAlbum(albums: inout [Album]) -> Bool {
        guard !albums.contains(where: { $0.id == Album.watchRecordingsID }) else { return false }
        let insertIndex: Int
        if let importsIdx = albums.firstIndex(where: { $0.id == Album.importsID }) {
            insertIndex = importsIdx + 1
        } else if let draftsIdx = albums.firstIndex(where: { $0.id == Album.draftsID }) {
            insertIndex = draftsIdx + 1
        } else {
            insertIndex = 0
        }
        albums.insert(Album.watchRecordings, at: insertIndex)
        return true
    }

    // MARK: - Migrations

    /// Migrate recordings with nil albumID to Drafts. Returns true if any changed.
    static func migrateRecordingsToDrafts(recordings: inout [RecordingItem]) -> Bool {
        var changed = false
        for i in recordings.indices {
            if recordings[i].albumID == nil {
                recordings[i].albumID = Album.draftsID
                changed = true
            }
        }
        return changed
    }

    /// Migrate "Inbox" album name to "Drafts". Returns true if migration occurred.
    static func migrateInboxToDrafts(albums: inout [Album]) -> Bool {
        if let index = albums.firstIndex(where: { $0.id == Album.draftsID && $0.name == "Inbox" }) {
            albums[index].name = "Drafts"
            return true
        }
        return false
    }
}
