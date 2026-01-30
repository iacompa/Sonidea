//
//  OverdubRepositoryTests.swift
//  SonideaTests
//
//  Tests for OverdubRepository: create, add/remove layers, validate integrity.
//

import Testing
import Foundation
@testable import Sonidea

struct OverdubRepositoryTests {

    // MARK: - Queries

    @Test func overdubGroupByID() {
        let group = TestFixtures.makeOverdubGroup()
        let groups = [group]
        #expect(OverdubRepository.overdubGroup(for: group.id, in: groups) != nil)
    }

    @Test func overdubGroupForRecording() {
        let group = TestFixtures.makeOverdubGroup()
        let recording = TestFixtures.makeRecording(overdubGroupId: group.id)
        let groups = [group]
        #expect(OverdubRepository.overdubGroup(for: recording, in: groups) != nil)
    }

    @Test func overdubGroupForRecordingWithoutGroup() {
        let recording = TestFixtures.makeRecording()
        #expect(OverdubRepository.overdubGroup(for: recording, in: []) == nil)
    }

    @Test func recordingsInGroup() {
        let baseId = UUID()
        let layerId = UUID()
        let group = TestFixtures.makeOverdubGroup(baseRecordingId: baseId, layerRecordingIds: [layerId])
        let recordings = [
            TestFixtures.makeRecording(id: baseId, title: "Base"),
            TestFixtures.makeRecording(id: layerId, title: "Layer"),
            TestFixtures.makeRecording(title: "Other")
        ]
        let result = OverdubRepository.recordings(in: group, from: recordings)
        #expect(result.count == 2)
    }

    @Test func baseRecording() {
        let baseId = UUID()
        let group = TestFixtures.makeOverdubGroup(baseRecordingId: baseId)
        let recordings = [TestFixtures.makeRecording(id: baseId, title: "Base")]
        #expect(OverdubRepository.baseRecording(for: group, from: recordings)?.title == "Base")
    }

    @Test func layerRecordingsSorted() {
        let layer1Id = UUID()
        let layer2Id = UUID()
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [layer1Id, layer2Id])
        let recordings = [
            TestFixtures.makeRecording(id: layer2Id, title: "Layer 2", overdubIndex: 2),
            TestFixtures.makeRecording(id: layer1Id, title: "Layer 1", overdubIndex: 1)
        ]
        let result = OverdubRepository.layerRecordings(for: group, from: recordings)
        #expect(result[0].title == "Layer 1")
        #expect(result[1].title == "Layer 2")
    }

    @Test func overdubLayerCount() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [UUID(), UUID()])
        let recording = TestFixtures.makeRecording(overdubGroupId: group.id)
        #expect(OverdubRepository.overdubLayerCount(for: recording, in: [group]) == 2)
    }

    @Test func overdubLayerCountNoGroup() {
        let recording = TestFixtures.makeRecording()
        #expect(OverdubRepository.overdubLayerCount(for: recording, in: []) == 0)
    }

    @Test func canAddLayerNewRecording() {
        let recording = TestFixtures.makeRecording()
        #expect(OverdubRepository.canAddLayer(to: recording, in: []))
    }

    @Test func canAddLayerGroupNotFull() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [UUID()])
        let recording = TestFixtures.makeRecording(overdubGroupId: group.id)
        #expect(OverdubRepository.canAddLayer(to: recording, in: [group]))
    }

    @Test func cannotAddLayerGroupFull() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [UUID(), UUID(), UUID()])
        let recording = TestFixtures.makeRecording(overdubGroupId: group.id)
        #expect(!OverdubRepository.canAddLayer(to: recording, in: [group]))
    }

    // MARK: - Create

    @Test func createOverdubGroupSetsBaseRole() {
        let baseRec = TestFixtures.makeRecording(title: "Base")
        var groups: [OverdubGroup] = []
        var recordings = [baseRec]

        let group = OverdubRepository.createOverdubGroup(
            baseRecording: baseRec,
            groups: &groups,
            recordings: &recordings
        )

        #expect(groups.count == 1)
        #expect(group.baseRecordingId == baseRec.id)
        #expect(recordings[0].overdubGroupId == group.id)
        #expect(recordings[0].overdubRole == .base)
        #expect(recordings[0].overdubIndex == 0)
    }

    // MARK: - Add Layer

    @Test func addLayerSetsMetadata() {
        let baseRec = TestFixtures.makeRecording(title: "Base")
        var groups: [OverdubGroup] = []
        var recordings = [baseRec]

        let group = OverdubRepository.createOverdubGroup(
            baseRecording: baseRec,
            groups: &groups,
            recordings: &recordings
        )

        let layerRec = TestFixtures.makeRecording(title: "Layer")
        recordings.append(layerRec)

        OverdubRepository.addLayer(
            groupId: group.id,
            layerRecording: layerRec,
            offsetSeconds: 0.5,
            groups: &groups,
            recordings: &recordings
        )

        #expect(groups[0].layerRecordingIds.count == 1)
        #expect(recordings[1].overdubGroupId == group.id)
        #expect(recordings[1].overdubRole == .layer)
        #expect(recordings[1].overdubIndex == 1)
        #expect(recordings[1].overdubOffsetSeconds == 0.5)
        #expect(recordings[1].overdubSourceBaseId == baseRec.id)
    }

    @Test func addLayerToFullGroupDoesNothing() {
        let baseId = UUID()
        let group = TestFixtures.makeOverdubGroup(
            baseRecordingId: baseId,
            layerRecordingIds: [UUID(), UUID(), UUID()]
        )
        var groups = [group]
        var recordings = [TestFixtures.makeRecording(id: baseId)]
        let newLayer = TestFixtures.makeRecording(title: "Extra")
        recordings.append(newLayer)

        OverdubRepository.addLayer(
            groupId: group.id,
            layerRecording: newLayer,
            groups: &groups,
            recordings: &recordings
        )

        #expect(groups[0].layerRecordingIds.count == 3) // Unchanged
    }

    // MARK: - Remove Layer

    @Test func removeLastLayerReturnsFileURL() {
        let baseId = UUID()
        let layerId = UUID()
        let layerRec = TestFixtures.makeRecording(id: layerId, title: "Layer")
        var groups = [TestFixtures.makeOverdubGroup(baseRecordingId: baseId, layerRecordingIds: [layerId])]
        var recordings = [TestFixtures.makeRecording(id: baseId), layerRec]

        let removedURL = OverdubRepository.removeLastLayer(
            groupId: groups[0].id,
            groups: &groups,
            recordings: &recordings
        )

        #expect(removedURL != nil)
        #expect(groups[0].layerRecordingIds.isEmpty)
        #expect(recordings.count == 1)
    }

    @Test func removeLastLayerFromEmptyGroupReturnsNil() {
        let group = TestFixtures.makeOverdubGroup()
        var groups = [group]
        var recordings: [RecordingItem] = []

        let removedURL = OverdubRepository.removeLastLayer(
            groupId: group.id,
            groups: &groups,
            recordings: &recordings
        )

        #expect(removedURL == nil)
    }

    // MARK: - Update Layer Offset

    @Test func updateLayerOffset() {
        let recId = UUID()
        var recordings = [TestFixtures.makeRecording(id: recId, overdubOffsetSeconds: 0.0)]

        OverdubRepository.updateLayerOffset(
            recordingId: recId,
            offsetSeconds: 1.5,
            recordings: &recordings
        )

        #expect(recordings[0].overdubOffsetSeconds == 1.5)
    }

    // MARK: - Validate Integrity

    @Test func validateIntegrityRemovesOrphanedGroups() {
        // Group whose base recording is missing
        let missingBaseId = UUID()
        let layerId = UUID()
        let orphanedGroup = TestFixtures.makeOverdubGroup(
            baseRecordingId: missingBaseId,
            layerRecordingIds: [layerId]
        )

        let layerRec = TestFixtures.makeRecording(id: layerId)
        var groups = [orphanedGroup]
        var recordings = [layerRec]

        let removedURLs = OverdubRepository.validateIntegrity(
            groups: &groups,
            recordings: &recordings
        )

        #expect(groups.isEmpty)
        #expect(recordings.isEmpty) // Layer removed too
        #expect(removedURLs.count == 1) // Layer file URL returned
    }

    @Test func validateIntegrityCleansDanglingLayerRefs() {
        let baseId = UUID()
        let existingLayerId = UUID()
        let missingLayerId = UUID()

        var groups = [TestFixtures.makeOverdubGroup(
            baseRecordingId: baseId,
            layerRecordingIds: [existingLayerId, missingLayerId]
        )]
        var recordings = [
            TestFixtures.makeRecording(id: baseId),
            TestFixtures.makeRecording(id: existingLayerId)
        ]

        _ = OverdubRepository.validateIntegrity(groups: &groups, recordings: &recordings)

        #expect(groups[0].layerRecordingIds == [existingLayerId])
    }

    @Test func validateIntegrityNoChanges() {
        let baseId = UUID()
        let layerId = UUID()
        var groups = [TestFixtures.makeOverdubGroup(baseRecordingId: baseId, layerRecordingIds: [layerId])]
        var recordings = [
            TestFixtures.makeRecording(id: baseId),
            TestFixtures.makeRecording(id: layerId)
        ]

        let removedURLs = OverdubRepository.validateIntegrity(groups: &groups, recordings: &recordings)
        #expect(removedURLs.isEmpty)
        #expect(groups.count == 1)
        #expect(recordings.count == 2)
    }
}
