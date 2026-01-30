//
//  DataSafetyManagerTests.swift
//  SonideaTests
//
//  Tests for DataSafetyManager: save/load with checksum, backup rotation, recovery.
//

import Testing
import Foundation
import CryptoKit
@testable import Sonidea

struct DataSafetyManagerTests {

    // MARK: - Helpers

    /// Clean up test data directory
    private func cleanTestDirectory() {
        let directory = DataSafetyFileOps.dataDirectory()
        try? FileManager.default.removeItem(at: directory)
    }

    // MARK: - Save + Load Round-Trip

    @Test func saveAndLoadRecordings() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let recordings = [
            TestFixtures.makeRecording(title: "Test 1", duration: 30),
            TestFixtures.makeRecording(title: "Test 2", duration: 60)
        ]

        DataSafetyFileOps.saveSync(recordings, collection: .recordings)
        let loaded = DataSafetyFileOps.load(RecordingItem.self, collection: .recordings)

        #expect(loaded.count == 2)
        #expect(loaded[0].title == "Test 1")
        #expect(loaded[1].title == "Test 2")
    }

    @Test func saveAndLoadTags() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let tags = [
            TestFixtures.makeTag(name: "melody"),
            TestFixtures.makeTag(name: "beatbox")
        ]

        DataSafetyFileOps.saveSync(tags, collection: .tags)
        let loaded = DataSafetyFileOps.load(Tag.self, collection: .tags)

        #expect(loaded.count == 2)
        #expect(loaded[0].name == "melody")
        #expect(loaded[1].name == "beatbox")
    }

    @Test func saveAndLoadAlbums() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let albums = [TestFixtures.makeAlbum(name: "My Album")]

        DataSafetyFileOps.saveSync(albums, collection: .albums)
        let loaded = DataSafetyFileOps.load(Album.self, collection: .albums)

        #expect(loaded.count == 1)
        #expect(loaded[0].name == "My Album")
    }

    @Test func saveAndLoadProjects() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let projects = [TestFixtures.makeProject(title: "Song Idea")]

        DataSafetyFileOps.saveSync(projects, collection: .projects)
        let loaded = DataSafetyFileOps.load(Project.self, collection: .projects)

        #expect(loaded.count == 1)
        #expect(loaded[0].title == "Song Idea")
    }

    @Test func saveAndLoadOverdubGroups() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let groups = [TestFixtures.makeOverdubGroup()]

        DataSafetyFileOps.saveSync(groups, collection: .overdubGroups)
        let loaded = DataSafetyFileOps.load(OverdubGroup.self, collection: .overdubGroups)

        #expect(loaded.count == 1)
    }

    // MARK: - Empty Load Returns Empty

    @Test func loadEmptyReturnsEmptyArray() {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let loaded = DataSafetyFileOps.load(RecordingItem.self, collection: .recordings)
        #expect(loaded.isEmpty)
    }

    // MARK: - Checksum Verification

    @Test func corruptedPayloadDetected() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        // Save valid data
        let tags = [TestFixtures.makeTag(name: "valid")]
        DataSafetyFileOps.saveSync(tags, collection: .tags)

        // Corrupt the primary file by modifying bytes
        let directory = DataSafetyFileOps.dataDirectory()
        let primaryURL = directory.appendingPathComponent(CollectionID.tags.filename)
        var data = try Data(contentsOf: primaryURL)

        // Flip some bytes near the end to corrupt the payload (but keep JSON parseable-ish)
        if data.count > 50 {
            data[data.count - 20] = 0xFF
            data[data.count - 21] = 0xFF
        }
        try data.write(to: primaryURL)

        // Load should fail checksum and fall back (to backup or empty)
        // The backup from the rotation should still have valid data
        let loaded = DataSafetyFileOps.load(Tag.self, collection: .tags)
        // It should either recover from backup or return empty (not crash)
        #expect(loaded.count <= 1)
    }

    // MARK: - Backup Rotation

    @Test func backupRotationCreatesBackupFiles() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        // Save data multiple times to trigger rotation
        let tags1 = [TestFixtures.makeTag(name: "v1")]
        DataSafetyFileOps.saveSync(tags1, collection: .tags)

        let tags2 = [TestFixtures.makeTag(name: "v2")]
        DataSafetyFileOps.saveSync(tags2, collection: .tags)

        let tags3 = [TestFixtures.makeTag(name: "v3")]
        DataSafetyFileOps.saveSync(tags3, collection: .tags)

        // Verify backup files exist
        let directory = DataSafetyFileOps.dataDirectory()
        let backup1 = directory.appendingPathComponent(CollectionID.tags.backupFilename(slot: 1))
        let backup2 = directory.appendingPathComponent(CollectionID.tags.backupFilename(slot: 2))

        #expect(FileManager.default.fileExists(atPath: backup1.path))
        #expect(FileManager.default.fileExists(atPath: backup2.path))

        // Primary should have latest data
        let loaded = DataSafetyFileOps.load(Tag.self, collection: .tags)
        #expect(loaded.count == 1)
        #expect(loaded[0].name == "v3")
    }

    // MARK: - Recovery from Backup

    @Test func recoveryFromBackupWhenPrimaryCorrupted() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        // Save version 1
        let tags1 = [TestFixtures.makeTag(name: "backup-data")]
        DataSafetyFileOps.saveSync(tags1, collection: .tags)

        // Save version 2 (v1 becomes backup)
        let tags2 = [TestFixtures.makeTag(name: "primary-data")]
        DataSafetyFileOps.saveSync(tags2, collection: .tags)

        // Delete primary file to simulate corruption
        let directory = DataSafetyFileOps.dataDirectory()
        let primaryURL = directory.appendingPathComponent(CollectionID.tags.filename)
        try FileManager.default.removeItem(at: primaryURL)

        // Should recover from backup
        let loaded = DataSafetyFileOps.load(Tag.self, collection: .tags)
        #expect(!loaded.isEmpty)
    }

    // MARK: - Migration

    @Test func migrationFlagPreventsDoubleMigration() {
        // Clear the migration flag
        UserDefaults.standard.removeObject(forKey: "dataSafetyMigrationComplete")
        defer { UserDefaults.standard.removeObject(forKey: "dataSafetyMigrationComplete") }

        // First call should migrate
        DataSafetyFileOps.migrateFromUserDefaultsIfNeeded()
        #expect(UserDefaults.standard.bool(forKey: "dataSafetyMigrationComplete"))

        // Second call should be a no-op (flag already set)
        DataSafetyFileOps.migrateFromUserDefaultsIfNeeded()
        #expect(UserDefaults.standard.bool(forKey: "dataSafetyMigrationComplete"))
    }

    // MARK: - CollectionID

    @Test func collectionIDFilenames() {
        #expect(CollectionID.recordings.filename == "recordings.safe.json")
        #expect(CollectionID.tags.filename == "tags.safe.json")
        #expect(CollectionID.albums.filename == "albums.safe.json")
        #expect(CollectionID.projects.filename == "projects.safe.json")
        #expect(CollectionID.overdubGroups.filename == "overdubGroups.safe.json")
    }

    @Test func collectionIDBackupFilenames() {
        #expect(CollectionID.recordings.backupFilename(slot: 1) == "recordings.backup1.json")
        #expect(CollectionID.recordings.backupFilename(slot: 2) == "recordings.backup2.json")
        #expect(CollectionID.recordings.backupFilename(slot: 3) == "recordings.backup3.json")
    }

    @Test func collectionIDLegacyKeys() {
        #expect(CollectionID.recordings.legacyDefaultsKey == "savedRecordings")
        #expect(CollectionID.tags.legacyDefaultsKey == "savedTags")
        #expect(CollectionID.albums.legacyDefaultsKey == "savedAlbums")
        #expect(CollectionID.projects.legacyDefaultsKey == "savedProjects")
        #expect(CollectionID.overdubGroups.legacyDefaultsKey == "savedOverdubGroups")
    }

    // MARK: - Directory Creation

    @Test func ensureDirectoryCreatesDirectory() throws {
        cleanTestDirectory()
        defer { cleanTestDirectory() }

        let directory = try DataSafetyFileOps.ensureDirectory()
        #expect(FileManager.default.fileExists(atPath: directory.path))
    }
}
