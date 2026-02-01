//
//  RecordingRepositoryTests.swift
//  SonideaTests
//
//  Tests for RecordingRepository: update, trash, restore, batch ops.
//

import Testing
import Foundation
@testable import Sonidea

struct RecordingRepositoryTests {

    // MARK: - Queries

    @Test func recordingForID() {
        let rec = TestFixtures.makeRecording(title: "Found")
        let recordings = [rec]
        #expect(RecordingRepository.recording(for: rec.id, in: recordings)?.title == "Found")
    }

    @Test func recordingForMissingID() {
        #expect(RecordingRepository.recording(for: UUID(), in: []) == nil)
    }

    @Test func recordingsForIDs() {
        let rec1 = TestFixtures.makeRecording(title: "One")
        let rec2 = TestFixtures.makeRecording(title: "Two")
        let trashed = TestFixtures.makeRecording(title: "Trashed", trashedAt: Date())
        let recordings = [rec1, rec2, trashed]

        let result = RecordingRepository.recordings(for: [rec1.id, rec2.id, trashed.id], in: recordings)
        #expect(result.count == 2)
    }

    @Test func activeRecordings() {
        let recordings = [
            TestFixtures.makeRecording(title: "Active"),
            TestFixtures.makeRecording(title: "Trashed", trashedAt: Date())
        ]
        let result = RecordingRepository.activeRecordings(from: recordings)
        #expect(result.count == 1)
        #expect(result[0].title == "Active")
    }

    @Test func trashedRecordings() {
        let recordings = [
            TestFixtures.makeRecording(title: "Active"),
            TestFixtures.makeRecording(title: "Trashed", trashedAt: Date())
        ]
        let result = RecordingRepository.trashedRecordings(from: recordings)
        #expect(result.count == 1)
        #expect(result[0].title == "Trashed")
    }

    @Test func recordingsWithLocation() {
        let recordings = [
            TestFixtures.makeRecording(title: "Located", latitude: 37.77, longitude: -122.42),
            TestFixtures.makeRecording(title: "No Location"),
            TestFixtures.makeRecording(title: "Trashed Located", latitude: 40.0, longitude: -74.0, trashedAt: Date())
        ]
        let result = RecordingRepository.recordingsWithLocation(from: recordings)
        #expect(result.count == 1)
        #expect(result[0].title == "Located")
    }

    // MARK: - Update

    @Test func updateRecordingSucceeds() {
        var rec = TestFixtures.makeRecording(title: "Old")
        var recordings = [rec]
        rec.title = "New"

        let result = RecordingRepository.updateRecording(rec, recordings: &recordings)
        #expect(result)
        #expect(recordings[0].title == "New")
        #expect(recordings[0].modifiedAt != nil)
    }

    @Test func updateRecordingMissingFails() {
        var recordings: [RecordingItem] = []
        let rec = TestFixtures.makeRecording()
        let result = RecordingRepository.updateRecording(rec, recordings: &recordings)
        #expect(!result)
    }

    @Test func updateTranscript() {
        let rec = TestFixtures.makeRecording()
        var recordings = [rec]

        let result = RecordingRepository.updateTranscript("Hello world", for: rec.id, recordings: &recordings)
        #expect(result)
        #expect(recordings[0].transcript == "Hello world")
    }

    @Test func updateTranscriptMissingFails() {
        var recordings: [RecordingItem] = []
        let result = RecordingRepository.updateTranscript("text", for: UUID(), recordings: &recordings)
        #expect(!result)
    }

    @Test func updatePlaybackPosition() {
        let rec = TestFixtures.makeRecording()
        var recordings = [rec]

        RecordingRepository.updatePlaybackPosition(42.5, for: rec.id, recordings: &recordings)
        #expect(recordings[0].lastPlaybackPosition == 42.5)
    }

    @Test func updateRecordingLocation() {
        let rec = TestFixtures.makeRecording()
        var recordings = [rec]

        let updated = RecordingRepository.updateRecordingLocation(
            recordingID: rec.id,
            latitude: 37.77,
            longitude: -122.42,
            label: "San Francisco",
            recordings: &recordings
        )
        #expect(updated != nil)
        #expect(recordings[0].latitude == 37.77)
        #expect(recordings[0].longitude == -122.42)
        #expect(recordings[0].locationLabel == "San Francisco")
    }

    @Test func clearRecordingLocation() {
        let rec = TestFixtures.makeRecording(locationLabel: "SF", latitude: 37.77, longitude: -122.42)
        var recordings = [rec]

        let updated = RecordingRepository.clearRecordingLocation(recordingID: rec.id, recordings: &recordings)
        #expect(updated != nil)
        #expect(recordings[0].latitude == nil)
        #expect(recordings[0].longitude == nil)
        #expect(recordings[0].locationLabel == "")
    }

    // MARK: - Trash

    @Test func moveToTrash() {
        let rec = TestFixtures.makeRecording()
        var recordings = [rec]

        let result = RecordingRepository.moveToTrash(rec, recordings: &recordings)
        #expect(result)
        #expect(recordings[0].trashedAt != nil)
    }

    @Test func moveToTrashMissingFails() {
        var recordings: [RecordingItem] = []
        let rec = TestFixtures.makeRecording()
        let result = RecordingRepository.moveToTrash(rec, recordings: &recordings)
        #expect(!result)
    }

    @Test func moveToTrashBatch() {
        let rec1 = TestFixtures.makeRecording(title: "R1")
        let rec2 = TestFixtures.makeRecording(title: "R2")
        let rec3 = TestFixtures.makeRecording(title: "R3")
        var recordings = [rec1, rec2, rec3]

        RecordingRepository.moveToTrash(recordingIDs: [rec1.id, rec3.id], recordings: &recordings)
        #expect(recordings[0].trashedAt != nil)
        #expect(recordings[1].trashedAt == nil)
        #expect(recordings[2].trashedAt != nil)
    }

    @Test func restoreFromTrash() {
        let rec = TestFixtures.makeRecording(trashedAt: Date())
        var recordings = [rec]

        let restored = RecordingRepository.restoreFromTrash(rec, recordings: &recordings)
        #expect(restored != nil)
        #expect(recordings[0].trashedAt == nil)
    }

    @Test func restoreLayerWithMissingBaseClearsOverdub() {
        let rec = TestFixtures.makeRecording(
            trashedAt: Date(),
            overdubGroupId: UUID(),
            overdubRoleRaw: "layer",
            overdubIndex: 1,
            overdubSourceBaseId: UUID() // Base doesn't exist
        )
        var recordings = [rec]

        let restored = RecordingRepository.restoreFromTrash(rec, recordings: &recordings)
        #expect(restored != nil)
        #expect(recordings[0].overdubGroupId == nil)
        #expect(recordings[0].overdubRole == .none)
    }

    @Test func restoreLayerWithExistingBaseKeepsOverdub() {
        let baseId = UUID()
        let groupId = UUID()
        let baseRec = TestFixtures.makeRecording(id: baseId)
        let layerRec = TestFixtures.makeRecording(
            trashedAt: Date(),
            overdubGroupId: groupId,
            overdubRoleRaw: "layer",
            overdubIndex: 1,
            overdubSourceBaseId: baseId
        )
        var recordings = [baseRec, layerRec]

        let restored = RecordingRepository.restoreFromTrash(layerRec, recordings: &recordings)
        #expect(restored != nil)
        #expect(recordings[1].overdubGroupId == groupId) // Kept
    }

    @Test func recordsToPurge() {
        let old = TestFixtures.makeRecording(
            trashedAt: Date().addingTimeInterval(-31 * 86400) // 31 days ago
        )
        let recent = TestFixtures.makeRecording(
            trashedAt: Date().addingTimeInterval(-1 * 86400) // 1 day ago
        )
        let active = TestFixtures.makeRecording()

        let toPurge = RecordingRepository.recordsToPurge(from: [old, recent, active])
        #expect(toPurge.count == 1)
        #expect(toPurge[0].id == old.id)
    }

    // MARK: - Batch Tag Operations

    @Test func addTagToRecordings() {
        let tag = TestFixtures.makeTag()
        let rec1 = TestFixtures.makeRecording(title: "R1")
        let rec2 = TestFixtures.makeRecording(title: "R2")
        var recordings = [rec1, rec2]

        RecordingRepository.addTag(tag, recordingIDs: [rec1.id], recordings: &recordings)
        #expect(recordings[0].tagIDs.contains(tag.id))
        #expect(!recordings[1].tagIDs.contains(tag.id))
    }

    @Test func addTagDoesNotDuplicate() {
        let tag = TestFixtures.makeTag()
        let rec = TestFixtures.makeRecording(tagIDs: [tag.id])
        var recordings = [rec]

        RecordingRepository.addTag(tag, recordingIDs: [rec.id], recordings: &recordings)
        #expect(recordings[0].tagIDs.filter { $0 == tag.id }.count == 1)
    }

    @Test func removeTagFromRecordings() {
        let tag = TestFixtures.makeTag()
        let rec = TestFixtures.makeRecording(tagIDs: [tag.id])
        var recordings = [rec]

        RecordingRepository.removeTag(tag, recordingIDs: [rec.id], recordings: &recordings)
        #expect(!recordings[0].tagIDs.contains(tag.id))
    }
}
