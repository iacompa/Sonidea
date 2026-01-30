//
//  OverdubGroupTests.swift
//  SonideaTests
//
//  Tests for OverdubGroup model: layer management, limits, computed properties.
//

import Testing
import Foundation
@testable import Sonidea

struct OverdubGroupTests {

    // MARK: - Constants

    @Test func maxLayersIsThree() {
        #expect(OverdubGroup.maxLayers == 3)
    }

    // MARK: - canAddLayer

    @Test func canAddLayerWhenEmpty() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [])
        #expect(group.canAddLayer)
        #expect(group.layerCount == 0)
    }

    @Test func canAddLayerWithTwoLayers() {
        let group = TestFixtures.makeOverdubGroup(
            layerRecordingIds: [UUID(), UUID()]
        )
        #expect(group.canAddLayer)
        #expect(group.layerCount == 2)
    }

    @Test func cannotAddLayerWhenFull() {
        let group = TestFixtures.makeOverdubGroup(
            layerRecordingIds: [UUID(), UUID(), UUID()]
        )
        #expect(!group.canAddLayer)
        #expect(group.layerCount == 3)
    }

    // MARK: - nextLayerIndex

    @Test func nextLayerIndexWhenEmpty() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [])
        #expect(group.nextLayerIndex == 1)
    }

    @Test func nextLayerIndexWithOneLayers() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [UUID()])
        #expect(group.nextLayerIndex == 2)
    }

    @Test func nextLayerIndexWithTwoLayers() {
        let group = TestFixtures.makeOverdubGroup(layerRecordingIds: [UUID(), UUID()])
        #expect(group.nextLayerIndex == 3)
    }

    @Test func nextLayerIndexWhenFull() {
        let group = TestFixtures.makeOverdubGroup(
            layerRecordingIds: [UUID(), UUID(), UUID()]
        )
        #expect(group.nextLayerIndex == nil)
    }

    // MARK: - allRecordingIds

    @Test func allRecordingIdsIncludesBase() {
        let baseId = UUID()
        let layer1 = UUID()
        let layer2 = UUID()
        let group = TestFixtures.makeOverdubGroup(
            baseRecordingId: baseId,
            layerRecordingIds: [layer1, layer2]
        )

        let allIds = group.allRecordingIds
        #expect(allIds.count == 3)
        #expect(allIds[0] == baseId)
        #expect(allIds[1] == layer1)
        #expect(allIds[2] == layer2)
    }

    @Test func allRecordingIdsWithNoLayers() {
        let baseId = UUID()
        let group = TestFixtures.makeOverdubGroup(
            baseRecordingId: baseId,
            layerRecordingIds: []
        )

        let allIds = group.allRecordingIds
        #expect(allIds.count == 1)
        #expect(allIds[0] == baseId)
    }

    // MARK: - addLayer

    @Test func addLayerSucceeds() {
        var group = TestFixtures.makeOverdubGroup(layerRecordingIds: [])
        let layerId = UUID()

        let result = group.addLayer(recordingId: layerId)
        #expect(result)
        #expect(group.layerCount == 1)
        #expect(group.layerRecordingIds.contains(layerId))
    }

    @Test func addLayerFailsWhenFull() {
        var group = TestFixtures.makeOverdubGroup(
            layerRecordingIds: [UUID(), UUID(), UUID()]
        )
        let layerId = UUID()

        let result = group.addLayer(recordingId: layerId)
        #expect(!result)
        #expect(group.layerCount == 3)
    }

    // MARK: - removeLayer

    @Test func removeLayerSucceeds() {
        let layerId = UUID()
        var group = TestFixtures.makeOverdubGroup(
            layerRecordingIds: [layerId, UUID()]
        )

        group.removeLayer(recordingId: layerId)
        #expect(group.layerCount == 1)
        #expect(!group.layerRecordingIds.contains(layerId))
    }

    @Test func removeLayerThatDoesNotExist() {
        var group = TestFixtures.makeOverdubGroup(
            layerRecordingIds: [UUID()]
        )
        let originalCount = group.layerCount

        group.removeLayer(recordingId: UUID())
        #expect(group.layerCount == originalCount)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let baseId = UUID()
        let layers = [UUID(), UUID()]
        let group = TestFixtures.makeOverdubGroup(
            baseRecordingId: baseId,
            layerRecordingIds: layers
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(OverdubGroup.self, from: data)

        #expect(decoded.id == group.id)
        #expect(decoded.baseRecordingId == baseId)
        #expect(decoded.layerRecordingIds == layers)
    }
}
