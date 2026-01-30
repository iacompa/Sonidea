//
//  AlbumRepositoryTests.swift
//  SonideaTests
//
//  Tests for AlbumRepository: create, delete, rename, system albums, migrations.
//

import Testing
import Foundation
@testable import Sonidea

struct AlbumRepositoryTests {

    // MARK: - Queries

    @Test func albumForID() {
        let album = TestFixtures.makeAlbum(name: "My Album")
        let albums = [album]
        #expect(AlbumRepository.album(for: album.id, in: albums)?.name == "My Album")
    }

    @Test func albumForNilIDReturnsNil() {
        let albums = [TestFixtures.makeAlbum()]
        #expect(AlbumRepository.album(for: nil, in: albums) == nil)
    }

    @Test func recordingsInAlbum() {
        let albumID = UUID()
        let recordings = [
            TestFixtures.makeRecording(title: "In Album", albumID: albumID),
            TestFixtures.makeRecording(title: "Other"),
            TestFixtures.makeRecording(title: "Trashed", albumID: albumID, trashedAt: Date())
        ]
        let album = TestFixtures.makeAlbum(id: albumID)
        let result = AlbumRepository.recordings(in: album, from: recordings)
        #expect(result.count == 1)
        #expect(result[0].title == "In Album")
    }

    @Test func recordingCountInAlbum() {
        let albumID = UUID()
        let recordings = [
            TestFixtures.makeRecording(albumID: albumID),
            TestFixtures.makeRecording(albumID: albumID),
            TestFixtures.makeRecording()
        ]
        let album = TestFixtures.makeAlbum(id: albumID)
        #expect(AlbumRepository.recordingCount(in: album, from: recordings) == 2)
    }

    // MARK: - Create

    @Test func createAlbumSucceeds() {
        var albums: [Album] = []
        let album = AlbumRepository.createAlbum(name: "New Album", albums: &albums)
        #expect(album.name == "New Album")
        #expect(albums.count == 1)
    }

    // MARK: - Delete

    @Test func deleteAlbumMovesRecordingsToDrafts() {
        let album = TestFixtures.makeAlbum(name: "User Album")
        var albums = [album]
        var recordings = [
            TestFixtures.makeRecording(title: "Rec1", albumID: album.id),
            TestFixtures.makeRecording(title: "Rec2", albumID: album.id)
        ]

        let result = AlbumRepository.deleteAlbum(album, albums: &albums, recordings: &recordings)
        #expect(result)
        #expect(albums.isEmpty)
        #expect(recordings[0].albumID == Album.draftsID)
        #expect(recordings[1].albumID == Album.draftsID)
    }

    @Test func deleteSystemAlbumFails() {
        var albums = [Album.drafts]
        var recordings: [RecordingItem] = []

        let result = AlbumRepository.deleteAlbum(Album.drafts, albums: &albums, recordings: &recordings)
        #expect(!result)
        #expect(albums.count == 1)
    }

    // MARK: - Rename

    @Test func renameAlbumSucceeds() {
        let album = TestFixtures.makeAlbum(name: "Old Name")
        var albums = [album]

        let result = AlbumRepository.renameAlbum(album, to: "New Name", albums: &albums)
        #expect(result)
        #expect(albums[0].name == "New Name")
    }

    @Test func renameSystemAlbumFails() {
        var albums = [Album.drafts]
        let result = AlbumRepository.renameAlbum(Album.drafts, to: "Renamed", albums: &albums)
        #expect(!result)
        #expect(albums[0].name == "Drafts")
    }

    @Test func renameToEmptyStringFails() {
        let album = TestFixtures.makeAlbum(name: "Album")
        var albums = [album]
        let result = AlbumRepository.renameAlbum(album, to: "   ", albums: &albums)
        #expect(!result)
        #expect(albums[0].name == "Album")
    }

    @Test func renameTrimsWhitespace() {
        let album = TestFixtures.makeAlbum(name: "Old")
        var albums = [album]
        let result = AlbumRepository.renameAlbum(album, to: "  New Name  ", albums: &albums)
        #expect(result)
        #expect(albums[0].name == "New Name")
    }

    // MARK: - Set Album

    @Test func setAlbumForRecording() {
        let album = TestFixtures.makeAlbum()
        var recordings = [TestFixtures.makeRecording()]

        let updated = AlbumRepository.setAlbum(album, for: recordings[0], recordings: &recordings)
        #expect(updated?.albumID == album.id)
        #expect(recordings[0].albumID == album.id)
    }

    @Test func setNilAlbumDefaultsToDrafts() {
        let album = TestFixtures.makeAlbum()
        var recordings = [TestFixtures.makeRecording(albumID: album.id)]

        let updated = AlbumRepository.setAlbum(nil, for: recordings[0], recordings: &recordings)
        #expect(updated?.albumID == Album.draftsID)
    }

    @Test func setAlbumForMultipleRecordings() {
        let album = TestFixtures.makeAlbum()
        let rec1 = TestFixtures.makeRecording(title: "Rec1")
        let rec2 = TestFixtures.makeRecording(title: "Rec2")
        let rec3 = TestFixtures.makeRecording(title: "Rec3")
        var recordings = [rec1, rec2, rec3]

        AlbumRepository.setAlbumForRecordings(album, recordingIDs: [rec1.id, rec3.id], recordings: &recordings)
        #expect(recordings[0].albumID == album.id)
        #expect(recordings[1].albumID != album.id)
        #expect(recordings[2].albumID == album.id)
    }

    // MARK: - System Album Management

    @Test func ensureDraftsAlbumCreatesIfMissing() {
        var albums: [Album] = []
        var recordings: [RecordingItem] = []

        let result = AlbumRepository.ensureDraftsAlbum(albums: &albums, recordings: &recordings)
        #expect(result.albumsChanged)
        #expect(albums.contains(where: { $0.id == Album.draftsID }))
    }

    @Test func ensureDraftsAlbumDoesNotDuplicate() {
        var albums = [Album.drafts]
        var recordings: [RecordingItem] = []

        let result = AlbumRepository.ensureDraftsAlbum(albums: &albums, recordings: &recordings)
        #expect(!result.albumsChanged)
        #expect(albums.count == 1)
    }

    @Test func ensureDraftsAlbumDeduplicates() {
        let dupDrafts = TestFixtures.makeAlbum(name: "Drafts")
        var albums = [Album.drafts, dupDrafts]
        var recordings = [TestFixtures.makeRecording(albumID: dupDrafts.id)]

        let result = AlbumRepository.ensureDraftsAlbum(albums: &albums, recordings: &recordings)
        #expect(result.albumsChanged)
        #expect(result.recordingsChanged)
        #expect(albums.count == 1)
        #expect(recordings[0].albumID == Album.draftsID)
    }

    @Test func ensureImportsAlbumCreatesAfterDrafts() {
        var albums = [Album.drafts]
        let created = AlbumRepository.ensureImportsAlbum(albums: &albums)
        #expect(created)
        #expect(albums.count == 2)
        #expect(albums[1].id == Album.importsID)
    }

    @Test func ensureImportsAlbumDoesNotDuplicate() {
        var albums = [Album.drafts, Album.imports]
        let created = AlbumRepository.ensureImportsAlbum(albums: &albums)
        #expect(!created)
        #expect(albums.count == 2)
    }

    @Test func ensureWatchRecordingsAlbumCreatesAfterImports() {
        var albums = [Album.drafts, Album.imports]
        let created = AlbumRepository.ensureWatchRecordingsAlbum(albums: &albums)
        #expect(created)
        #expect(albums.count == 3)
        #expect(albums[2].id == Album.watchRecordingsID)
    }

    @Test func ensureWatchRecordingsAlbumCreatesAfterDraftsIfNoImports() {
        var albums = [Album.drafts]
        let created = AlbumRepository.ensureWatchRecordingsAlbum(albums: &albums)
        #expect(created)
        #expect(albums[1].id == Album.watchRecordingsID)
    }

    // MARK: - Migrations

    @Test func migrateRecordingsToDrafts() {
        var recordings = [
            TestFixtures.makeRecording(albumID: nil),
            TestFixtures.makeRecording(albumID: UUID())
        ]

        let changed = AlbumRepository.migrateRecordingsToDrafts(recordings: &recordings)
        #expect(changed)
        #expect(recordings[0].albumID == Album.draftsID)
        #expect(recordings[1].albumID != Album.draftsID) // Unchanged
    }

    @Test func migrateRecordingsToDraftsNoOp() {
        var recordings = [TestFixtures.makeRecording(albumID: Album.draftsID)]
        let changed = AlbumRepository.migrateRecordingsToDrafts(recordings: &recordings)
        #expect(!changed)
    }

    @Test func migrateInboxToDrafts() {
        var albums = [Album(id: Album.draftsID, name: "Inbox", createdAt: Date(), isSystem: true)]
        let changed = AlbumRepository.migrateInboxToDrafts(albums: &albums)
        #expect(changed)
        #expect(albums[0].name == "Drafts")
    }

    @Test func migrateInboxToDraftsNoOp() {
        var albums = [Album.drafts]
        let changed = AlbumRepository.migrateInboxToDrafts(albums: &albums)
        #expect(!changed)
    }
}
