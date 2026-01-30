//
//  TrashOperationsTests.swift
//  SonideaTests
//
//  Tests for RecordingRepository: permanentlyDelete, emptyTrash, purgeOldTrashed.
//

import Testing
import Foundation
@testable import Sonidea

struct TrashOperationsTests {

    // MARK: - permanentlyDelete

    @Test func permanentlyDeleteStandaloneRecording() {
        let rec = TestFixtures.makeRecording(title: "Solo")
        var recordings = [rec]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.permanentlyDelete(rec, recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.isEmpty)
        #expect(result.removedRecordingIDs.contains(rec.id))
        #expect(result.fileURLsToDelete.count == 1)
        #expect(!result.overdubGroupsChanged)
    }

    @Test func permanentlyDeleteBaseRecordingRemovesAllLayers() {
        let baseId = UUID()
        let layer1Id = UUID()
        let layer2Id = UUID()
        let groupId = UUID()

        let baseRec = TestFixtures.makeRecording(id: baseId, title: "Base",
            overdubGroupId: groupId, overdubRoleRaw: "base")
        let layer1 = TestFixtures.makeRecording(id: layer1Id, title: "Layer 1",
            overdubGroupId: groupId, overdubRoleRaw: "layer", overdubIndex: 1)
        let layer2 = TestFixtures.makeRecording(id: layer2Id, title: "Layer 2",
            overdubGroupId: groupId, overdubRoleRaw: "layer", overdubIndex: 2)
        let other = TestFixtures.makeRecording(title: "Other")

        var recordings = [baseRec, layer1, layer2, other]
        var groups = [TestFixtures.makeOverdubGroup(id: groupId, baseRecordingId: baseId, layerRecordingIds: [layer1Id, layer2Id])]

        let result = RecordingRepository.permanentlyDelete(baseRec, recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 1) // Only "Other" remains
        #expect(recordings[0].title == "Other")
        #expect(groups.isEmpty)
        #expect(result.removedRecordingIDs.contains(baseId))
        #expect(result.removedRecordingIDs.contains(layer1Id))
        #expect(result.removedRecordingIDs.contains(layer2Id))
        #expect(result.fileURLsToDelete.count == 3) // base + 2 layers
        #expect(result.overdubGroupsChanged)
        #expect(result.removedOverdubGroupIDs.contains(groupId))
    }

    @Test func permanentlyDeleteLayerKeepsOthers() {
        let baseId = UUID()
        let layer1Id = UUID()
        let layer2Id = UUID()
        let groupId = UUID()

        let baseRec = TestFixtures.makeRecording(id: baseId, title: "Base",
            overdubGroupId: groupId, overdubRoleRaw: "base")
        let layer1 = TestFixtures.makeRecording(id: layer1Id, title: "Layer 1",
            overdubGroupId: groupId, overdubRoleRaw: "layer", overdubIndex: 1)
        let layer2 = TestFixtures.makeRecording(id: layer2Id, title: "Layer 2",
            overdubGroupId: groupId, overdubRoleRaw: "layer", overdubIndex: 2)

        var recordings = [baseRec, layer1, layer2]
        var groups = [TestFixtures.makeOverdubGroup(id: groupId, baseRecordingId: baseId, layerRecordingIds: [layer1Id, layer2Id])]

        let result = RecordingRepository.permanentlyDelete(layer1, recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 2) // Base + Layer 2
        #expect(groups.count == 1)
        #expect(groups[0].layerRecordingIds == [layer2Id])
        #expect(result.removedRecordingIDs == [layer1Id])
        #expect(result.fileURLsToDelete.count == 1)
        #expect(result.overdubGroupsChanged)
        #expect(result.removedOverdubGroupIDs.isEmpty) // Group still exists
    }

    @Test func permanentlyDeleteRecordingNotInGroup() {
        let rec = TestFixtures.makeRecording()
        var recordings = [rec]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.permanentlyDelete(rec, recordings: &recordings, overdubGroups: &groups)

        #expect(!result.overdubGroupsChanged)
        #expect(result.removedOverdubGroupIDs.isEmpty)
    }

    @Test func permanentlyDeleteReturnsCorrectFileURLs() {
        let rec = TestFixtures.makeRecording()
        var recordings = [rec]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.permanentlyDelete(rec, recordings: &recordings, overdubGroups: &groups)

        #expect(result.fileURLsToDelete.count == 1)
        #expect(result.fileURLsToDelete[0] == rec.fileURL)
    }

    // MARK: - emptyTrash

    @Test func emptyTrashRemovesAllTrashedRecordings() {
        let active = TestFixtures.makeRecording(title: "Active")
        let trashed1 = TestFixtures.makeRecording(title: "Trashed 1", trashedAt: Date())
        let trashed2 = TestFixtures.makeRecording(title: "Trashed 2", trashedAt: Date())
        var recordings = [active, trashed1, trashed2]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.emptyTrash(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 1)
        #expect(recordings[0].title == "Active")
        #expect(result.removedRecordingIDs.contains(trashed1.id))
        #expect(result.removedRecordingIDs.contains(trashed2.id))
        #expect(result.fileURLsToDelete.count == 2)
    }

    @Test func emptyTrashPreservesActiveRecordings() {
        let active = TestFixtures.makeRecording(title: "Active")
        var recordings = [active]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.emptyTrash(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 1)
        #expect(result.removedRecordingIDs.isEmpty)
    }

    @Test func emptyTrashCleansOverdubGroupForTrashedBase() {
        let baseId = UUID()
        let layerId = UUID()
        let groupId = UUID()

        let base = TestFixtures.makeRecording(id: baseId, title: "Base", trashedAt: Date(),
            overdubGroupId: groupId, overdubRoleRaw: "base")
        let layer = TestFixtures.makeRecording(id: layerId, title: "Layer",
            overdubGroupId: groupId, overdubRoleRaw: "layer", overdubIndex: 1)

        var recordings = [base, layer]
        var groups = [TestFixtures.makeOverdubGroup(id: groupId, baseRecordingId: baseId, layerRecordingIds: [layerId])]

        let result = RecordingRepository.emptyTrash(recordings: &recordings, overdubGroups: &groups)

        // Both base (trashed) and layer (active but orphaned) should be removed
        #expect(recordings.isEmpty)
        #expect(groups.isEmpty)
        #expect(result.removedRecordingIDs.contains(baseId))
        #expect(result.removedRecordingIDs.contains(layerId))
        #expect(result.overdubGroupsChanged)
    }

    @Test func emptyTrashOnEmptyTrashIsNoOp() {
        let active = TestFixtures.makeRecording()
        var recordings = [active]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.emptyTrash(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 1)
        #expect(result.removedRecordingIDs.isEmpty)
        #expect(result.fileURLsToDelete.isEmpty)
        #expect(!result.overdubGroupsChanged)
    }

    // MARK: - purgeOldTrashed

    @Test func purgeOldTrashedRemovesOlderThan30Days() {
        let old = TestFixtures.makeRecording(
            title: "Old Trashed",
            trashedAt: Date().addingTimeInterval(-31 * 86400) // 31 days ago
        )
        let recent = TestFixtures.makeRecording(
            title: "Recent Trashed",
            trashedAt: Date().addingTimeInterval(-1 * 86400) // 1 day ago
        )
        let active = TestFixtures.makeRecording(title: "Active")

        var recordings = [old, recent, active]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.purgeOldTrashed(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 2) // Recent + Active
        #expect(result.removedRecordingIDs.contains(old.id))
        #expect(!result.removedRecordingIDs.contains(recent.id))
        #expect(result.fileURLsToDelete.count == 1)
    }

    @Test func purgeOldTrashedKeepsRecentlyTrashed() {
        let recent = TestFixtures.makeRecording(
            title: "Recent",
            trashedAt: Date().addingTimeInterval(-10 * 86400) // 10 days ago
        )
        var recordings = [recent]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.purgeOldTrashed(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 1)
        #expect(result.removedRecordingIDs.isEmpty)
    }

    @Test func purgeOldTrashedCleansOverdubGroups() {
        let baseId = UUID()
        let layerId = UUID()
        let groupId = UUID()

        let base = TestFixtures.makeRecording(
            id: baseId,
            title: "Old Base",
            trashedAt: Date().addingTimeInterval(-31 * 86400),
            overdubGroupId: groupId,
            overdubRoleRaw: "base"
        )
        let layer = TestFixtures.makeRecording(
            id: layerId,
            title: "Active Layer",
            overdubGroupId: groupId,
            overdubRoleRaw: "layer",
            overdubIndex: 1
        )

        var recordings = [base, layer]
        var groups = [TestFixtures.makeOverdubGroup(id: groupId, baseRecordingId: baseId, layerRecordingIds: [layerId])]

        let result = RecordingRepository.purgeOldTrashed(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.isEmpty) // Both removed
        #expect(groups.isEmpty)
        #expect(result.overdubGroupsChanged)
        #expect(result.removedRecordingIDs.contains(baseId))
        #expect(result.removedRecordingIDs.contains(layerId))
    }

    @Test func purgeOldTrashedWithNoExpiredItems() {
        let active = TestFixtures.makeRecording()
        var recordings = [active]
        var groups: [OverdubGroup] = []

        let result = RecordingRepository.purgeOldTrashed(recordings: &recordings, overdubGroups: &groups)

        #expect(recordings.count == 1)
        #expect(result.removedRecordingIDs.isEmpty)
        #expect(result.fileURLsToDelete.isEmpty)
        #expect(!result.overdubGroupsChanged)
    }
}
