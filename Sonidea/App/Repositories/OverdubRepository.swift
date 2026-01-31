//
//  OverdubRepository.swift
//  Sonidea
//
//  Pure data operations for overdub groups, extracted from AppState.
//  Operates on inout arrays with no persistence or sync side effects.
//  AppState handles save/sync and file deletion after each operation.
//

import Foundation

/// Stateless repository for overdub group data operations.
/// All methods take `inout` arrays and return results.
/// Caller (AppState) is responsible for persistence, sync, and file I/O.
enum OverdubRepository {

    // MARK: - Queries

    static func overdubGroup(for id: UUID, in groups: [OverdubGroup]) -> OverdubGroup? {
        groups.first { $0.id == id }
    }

    static func overdubGroup(for recording: RecordingItem, in groups: [OverdubGroup]) -> OverdubGroup? {
        guard let groupId = recording.overdubGroupId else { return nil }
        return overdubGroup(for: groupId, in: groups)
    }

    static func recordings(in group: OverdubGroup, from allRecordings: [RecordingItem]) -> [RecordingItem] {
        let ids = Set(group.allRecordingIds)
        return allRecordings.filter { ids.contains($0.id) }
    }

    static func baseRecording(for group: OverdubGroup, from recordings: [RecordingItem]) -> RecordingItem? {
        recordings.first { $0.id == group.baseRecordingId }
    }

    static func layerRecordings(for group: OverdubGroup, from recordings: [RecordingItem]) -> [RecordingItem] {
        let layerIds = Set(group.layerRecordingIds)
        return recordings
            .filter { layerIds.contains($0.id) }
            .sorted { ($0.overdubIndex ?? 0) < ($1.overdubIndex ?? 0) }
    }

    static func overdubLayerCount(for recording: RecordingItem, in groups: [OverdubGroup]) -> Int {
        guard let groupId = recording.overdubGroupId,
              let group = overdubGroup(for: groupId, in: groups) else { return 0 }
        return group.layerCount
    }

    /// Check if a recording can have overdub layers added (data check only, no pro feature check).
    static func canAddLayer(to recording: RecordingItem, in groups: [OverdubGroup]) -> Bool {
        guard let groupId = recording.overdubGroupId else { return true }
        guard let group = overdubGroup(for: groupId, in: groups) else { return true }
        return group.canAddLayer
    }

    // MARK: - Mutations

    /// Create a new overdub group with a base recording.
    static func createOverdubGroup(
        baseRecording: RecordingItem,
        groups: inout [OverdubGroup],
        recordings: inout [RecordingItem]
    ) -> OverdubGroup {
        let group = OverdubGroup(baseRecordingId: baseRecording.id)

        if let index = recordings.firstIndex(where: { $0.id == baseRecording.id }) {
            recordings[index].overdubGroupId = group.id
            recordings[index].overdubRole = .base
            recordings[index].overdubIndex = 0
        }

        groups.append(group)
        return group
    }

    /// Add a layer recording to an overdub group.
    static func addLayer(
        groupId: UUID,
        layerRecording: RecordingItem,
        offsetSeconds: Double = 0,
        groups: inout [OverdubGroup],
        recordings: inout [RecordingItem]
    ) {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              groups[groupIndex].canAddLayer else { return }

        let layerIndex = groups[groupIndex].nextLayerIndex ?? 1

        if let recIndex = recordings.firstIndex(where: { $0.id == layerRecording.id }) {
            recordings[recIndex].overdubGroupId = groupId
            recordings[recIndex].overdubRole = .layer
            recordings[recIndex].overdubIndex = layerIndex
            recordings[recIndex].overdubOffsetSeconds = offsetSeconds
            recordings[recIndex].overdubSourceBaseId = groups[groupIndex].baseRecordingId
        }

        groups[groupIndex].addLayer(recordingId: layerRecording.id)
    }

    /// Remove the last layer from an overdub group.
    /// Returns the file URL of the removed layer recording (caller should delete it).
    static func removeLastLayer(
        groupId: UUID,
        groups: inout [OverdubGroup],
        recordings: inout [RecordingItem]
    ) -> URL? {
        guard let groupIndex = groups.firstIndex(where: { $0.id == groupId }),
              let lastLayerId = groups[groupIndex].layerRecordingIds.last else { return nil }

        let fileURL = recordings.first(where: { $0.id == lastLayerId })?.fileURL

        recordings.removeAll { $0.id == lastLayerId }
        groups[groupIndex].layerRecordingIds.removeLast()

        return fileURL
    }

    /// Update the offset for a layer recording.
    static func updateLayerOffset(
        recordingId: UUID,
        offsetSeconds: Double,
        recordings: inout [RecordingItem]
    ) {
        if let index = recordings.firstIndex(where: { $0.id == recordingId }) {
            recordings[index].overdubOffsetSeconds = offsetSeconds
        }
    }

    /// Validate overdub group integrity. Removes orphaned groups and dangling layer references.
    /// Returns file URLs of layer recordings that were removed (caller should delete them).
    static func validateIntegrity(
        groups: inout [OverdubGroup],
        recordings: inout [RecordingItem]
    ) -> [URL] {
        let recordingIds = Set(recordings.map { $0.id })
        let invalidGroups = groups.filter { !recordingIds.contains($0.baseRecordingId) }
        var removedFileURLs: [URL] = []

        if !invalidGroups.isEmpty {
            for group in invalidGroups {
                for layerId in group.layerRecordingIds {
                    if let layerRec = recordings.first(where: { $0.id == layerId }) {
                        removedFileURLs.append(layerRec.fileURL)
                    }
                    recordings.removeAll { $0.id == layerId }
                }
            }
            groups.removeAll { !recordingIds.contains($0.baseRecordingId) }
        }

        // Recompute recording IDs after removals above to avoid stale snapshot
        let currentRecordingIds = Set(recordings.map { $0.id })

        // Clean up layer references that point to missing recordings
        for i in groups.indices {
            groups[i].layerRecordingIds.removeAll { !currentRecordingIds.contains($0) }
        }

        return removedFileURLs
    }
}
