//
//  AlbumTests.swift
//  SonideaTests
//
//  Tests for Album model: system albums, permissions, sharing, Codable.
//

import Testing
import Foundation
@testable import Sonidea

struct AlbumTests {

    // MARK: - Well-Known IDs Stability

    @Test func wellKnownIDsAreStable() {
        #expect(Album.draftsID == UUID(uuidString: "00000000-0000-0000-0000-000000000003")!)
        #expect(Album.importsID == UUID(uuidString: "00000000-0000-0000-0000-000000000002")!)
        #expect(Album.watchRecordingsID == UUID(uuidString: "00000000-0000-0000-0000-000000000004")!)
    }

    // MARK: - System Album Properties

    @Test func systemAlbumCannotBeDeleted() {
        let album = TestFixtures.makeAlbum(isSystem: true)
        #expect(!album.canDelete)
    }

    @Test func systemAlbumCannotBeRenamed() {
        let album = TestFixtures.makeAlbum(isSystem: true)
        #expect(!album.canRename)
    }

    @Test func userAlbumCanBeDeleted() {
        let album = TestFixtures.makeAlbum(isSystem: false)
        #expect(album.canDelete)
    }

    @Test func userAlbumCanBeRenamed() {
        let album = TestFixtures.makeAlbum(isSystem: false, isShared: false)
        #expect(album.canRename)
    }

    // MARK: - Shared Album Permissions

    @Test func sharedAlbumOwnerCanRename() {
        let album = TestFixtures.makeAlbum(isShared: true, isOwner: true)
        #expect(album.canRename)
    }

    @Test func sharedAlbumNonOwnerCannotRename() {
        let album = TestFixtures.makeAlbum(isShared: true, isOwner: false)
        #expect(!album.canRename)
    }

    @Test func adminCanDeleteAnyRecording() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .admin
        )
        #expect(album.canDeleteAnyRecording)
    }

    @Test func memberCannotDeleteAnyRecording() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .member
        )
        #expect(!album.canDeleteAnyRecording)
    }

    @Test func viewerCannotAddRecordings() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .viewer
        )
        #expect(!album.canAddRecordings)
    }

    @Test func memberCanAddRecordings() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .member
        )
        #expect(album.canAddRecordings)
    }

    @Test func adminCanManageParticipants() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .admin
        )
        #expect(album.canManageParticipants)
    }

    @Test func memberCannotManageParticipants() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .member
        )
        #expect(!album.canManageParticipants)
    }

    @Test func adminCanEditSettings() {
        let album = TestFixtures.makeAlbum(
            isShared: true,
            currentUserRole: .admin
        )
        #expect(album.canEditSettings)
    }

    // MARK: - Trash Restore Permission

    @Test func adminCanRestoreFromTrashWithAdminsOnly() {
        let settings = SharedAlbumSettings(trashRestorePermission: .adminsOnly)
        let album = TestFixtures.makeAlbum(
            isShared: true,
            sharedSettings: settings,
            currentUserRole: .admin
        )
        #expect(album.canRestoreFromTrash)
    }

    @Test func memberCannotRestoreFromTrashWithAdminsOnly() {
        let settings = SharedAlbumSettings(trashRestorePermission: .adminsOnly)
        let album = TestFixtures.makeAlbum(
            isShared: true,
            sharedSettings: settings,
            currentUserRole: .member
        )
        #expect(!album.canRestoreFromTrash)
    }

    @Test func memberCanRestoreFromTrashWithAnyParticipant() {
        let settings = SharedAlbumSettings(trashRestorePermission: .anyParticipant)
        let album = TestFixtures.makeAlbum(
            isShared: true,
            sharedSettings: settings,
            currentUserRole: .member
        )
        #expect(album.canRestoreFromTrash)
    }

    // MARK: - Member Delete Permission

    @Test func memberCanDeleteOwnWhenAllowed() {
        var settings = SharedAlbumSettings()
        settings.allowMembersToDelete = true
        let album = TestFixtures.makeAlbum(
            isShared: true,
            sharedSettings: settings,
            currentUserRole: .member
        )
        #expect(album.canDeleteOwnRecording)
    }

    @Test func memberCannotDeleteOwnWhenNotAllowed() {
        var settings = SharedAlbumSettings()
        settings.allowMembersToDelete = false
        let album = TestFixtures.makeAlbum(
            isShared: true,
            sharedSettings: settings,
            currentUserRole: .member
        )
        #expect(!album.canDeleteOwnRecording)
    }

    // MARK: - Album Type Checks

    @Test func isDraftsAlbum() {
        let drafts = Album.drafts
        #expect(drafts.isDraftsAlbum)
        #expect(!drafts.isImportsAlbum)
        #expect(!drafts.isWatchRecordingsAlbum)
    }

    @Test func isImportsAlbum() {
        let imports = Album.imports
        #expect(imports.isImportsAlbum)
        #expect(!imports.isDraftsAlbum)
    }

    @Test func isWatchRecordingsAlbum() {
        let watch = Album.watchRecordings
        #expect(watch.isWatchRecordingsAlbum)
        #expect(!watch.isDraftsAlbum)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let album = TestFixtures.makeAlbum(
            name: "My Album",
            isSystem: false,
            isShared: true,
            participantCount: 3,
            isOwner: true,
            sharedSettings: SharedAlbumSettings(),
            currentUserRole: .admin
        )

        let data = try JSONEncoder().encode(album)
        let decoded = try JSONDecoder().decode(Album.self, from: data)

        #expect(decoded.id == album.id)
        #expect(decoded.name == "My Album")
        #expect(decoded.isShared)
        #expect(decoded.participantCount == 3)
        #expect(decoded.isOwner)
        #expect(decoded.currentUserRole == .admin)
        #expect(decoded.sharedSettings != nil)
    }

    // MARK: - Cannot Convert to Shared

    @Test func cannotConvertToShared() {
        let album = TestFixtures.makeAlbum()
        #expect(!album.canConvertToShared)
    }

    // MARK: - Generate Initials

    @Test func generateInitialsFromFullName() {
        #expect(SharedAlbumParticipant.generateInitials(from: "John Doe") == "JD")
    }

    @Test func generateInitialsFromSingleName() {
        let initials = SharedAlbumParticipant.generateInitials(from: "John")
        #expect(initials == "JO")
    }

    @Test func generateInitialsFromEmptyName() {
        #expect(SharedAlbumParticipant.generateInitials(from: "") == "?")
    }

    @Test func generateInitialsFromThreeNames() {
        #expect(SharedAlbumParticipant.generateInitials(from: "John Michael Doe") == "JD")
    }

    // MARK: - Non-Shared Album Permissions

    @Test func nonSharedAlbumCanDeleteAnyRecording() {
        let album = TestFixtures.makeAlbum(isShared: false)
        #expect(album.canDeleteAnyRecording)
    }

    @Test func nonSharedAlbumCanDeleteOwnRecording() {
        let album = TestFixtures.makeAlbum(isShared: false)
        #expect(album.canDeleteOwnRecording)
    }

    @Test func nonSharedAlbumCannotManageParticipants() {
        let album = TestFixtures.makeAlbum(isShared: false)
        #expect(!album.canManageParticipants)
    }
}
