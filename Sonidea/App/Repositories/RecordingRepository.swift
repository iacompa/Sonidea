//
//  RecordingRepository.swift
//  Sonidea
//
//  Pure data operations for recordings, extracted from AppState.
//  Operates on inout arrays with no persistence or sync side effects.
//  AppState handles save/sync and file I/O after each operation.
//

import Foundation

/// Stateless repository for recording data operations.
/// All methods take `inout` arrays and return results.
/// Caller (AppState) is responsible for persistence, sync, and file I/O.
enum RecordingRepository {

    // MARK: - Queries

    static func recording(for id: UUID, in recordings: [RecordingItem]) -> RecordingItem? {
        recordings.first { $0.id == id }
    }

    static func recordings(for ids: [UUID], in recordings: [RecordingItem]) -> [RecordingItem] {
        ids.compactMap { id in recordings.first { $0.id == id && !$0.isTrashed } }
    }

    static func activeRecordings(from recordings: [RecordingItem]) -> [RecordingItem] {
        recordings.filter { !$0.isTrashed }
    }

    static func trashedRecordings(from recordings: [RecordingItem]) -> [RecordingItem] {
        recordings.filter { $0.isTrashed }
    }

    static func recordingsWithLocation(from recordings: [RecordingItem]) -> [RecordingItem] {
        recordings.filter { !$0.isTrashed && $0.hasCoordinates }
    }

    // MARK: - Mutations

    /// Update a recording in the array. Returns true if the recording was found and updated.
    @discardableResult
    static func updateRecording(
        _ updated: RecordingItem,
        recordings: inout [RecordingItem]
    ) -> Bool {
        guard let index = recordings.firstIndex(where: { $0.id == updated.id }) else {
            return false
        }
        var recording = updated
        recording.modifiedAt = Date()
        recordings[index] = recording
        return true
    }

    /// Update transcript for a recording. Returns true if successful.
    @discardableResult
    static func updateTranscript(
        _ text: String,
        for recordingID: UUID,
        recordings: inout [RecordingItem]
    ) -> Bool {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return false
        }
        recordings[index].transcript = text
        recordings[index].modifiedAt = Date()
        return true
    }

    /// Update playback position for a recording.
    static func updatePlaybackPosition(
        _ position: TimeInterval,
        for recordingID: UUID,
        recordings: inout [RecordingItem]
    ) {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else { return }
        recordings[index].lastPlaybackPosition = position
    }

    /// Update location for a recording. Returns the updated recording if successful.
    static func updateRecordingLocation(
        recordingID: UUID,
        latitude: Double,
        longitude: Double,
        label: String,
        recordings: inout [RecordingItem]
    ) -> RecordingItem? {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return nil
        }
        recordings[index].latitude = latitude
        recordings[index].longitude = longitude
        recordings[index].locationLabel = label
        recordings[index].modifiedAt = Date()
        return recordings[index]
    }

    /// Clear location for a recording. Returns the updated recording if successful.
    static func clearRecordingLocation(
        recordingID: UUID,
        recordings: inout [RecordingItem]
    ) -> RecordingItem? {
        guard let index = recordings.firstIndex(where: { $0.id == recordingID }) else {
            return nil
        }
        recordings[index].latitude = nil
        recordings[index].longitude = nil
        recordings[index].locationLabel = ""
        recordings[index].modifiedAt = Date()
        return recordings[index]
    }

    // MARK: - Trash

    /// Move a recording to trash. Returns true if successful.
    @discardableResult
    static func moveToTrash(
        _ recording: RecordingItem,
        recordings: inout [RecordingItem]
    ) -> Bool {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else {
            return false
        }
        recordings[index].trashedAt = Date()
        recordings[index].modifiedAt = Date()
        return true
    }

    /// Move multiple recordings to trash.
    static func moveToTrash(
        recordingIDs: Set<UUID>,
        recordings: inout [RecordingItem]
    ) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                recordings[i].trashedAt = Date()
                recordings[i].modifiedAt = Date()
            }
        }
    }

    /// Restore a recording from trash. Returns the restored recording.
    /// Also clears overdub metadata if the base recording is gone.
    static func restoreFromTrash(
        _ recording: RecordingItem,
        recordings: inout [RecordingItem]
    ) -> RecordingItem? {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else {
            return nil
        }
        recordings[index].trashedAt = nil
        recordings[index].modifiedAt = Date()

        // If restoring a layer, verify its base still exists
        if recording.overdubRole == .layer,
           let baseId = recording.overdubSourceBaseId,
           !recordings.contains(where: { $0.id == baseId && !$0.isTrashed }) {
            recordings[index].overdubGroupId = nil
            recordings[index].overdubRole = .none
            recordings[index].overdubIndex = nil
            recordings[index].overdubSourceBaseId = nil
        }

        return recordings[index]
    }

    /// Collect recordings that should be purged (trashed > 30 days).
    static func recordsToPurge(from recordings: [RecordingItem]) -> [RecordingItem] {
        recordings.filter { $0.shouldPurge }
    }

    // MARK: - Batch Tag Operations

    /// Add a tag to multiple recordings.
    static func addTag(
        _ tag: Tag,
        recordingIDs: Set<UUID>,
        recordings: inout [RecordingItem]
    ) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) && !recordings[i].tagIDs.contains(tag.id) {
                recordings[i].tagIDs.append(tag.id)
                recordings[i].modifiedAt = Date()
            }
        }
    }

    /// Remove a tag from multiple recordings.
    static func removeTag(
        _ tag: Tag,
        recordingIDs: Set<UUID>,
        recordings: inout [RecordingItem]
    ) {
        for i in recordings.indices {
            if recordingIDs.contains(recordings[i].id) {
                let hadTag = recordings[i].tagIDs.contains(tag.id)
                recordings[i].tagIDs.removeAll { $0 == tag.id }
                if hadTag {
                    recordings[i].modifiedAt = Date()
                }
            }
        }
    }

    // MARK: - Permanent Deletion

    /// Result of a permanent deletion operation.
    /// Contains all data changes performed and file URLs for the caller to delete from disk.
    struct PermanentDeleteResult {
        let removedRecordingIDs: Set<UUID>
        let fileURLsToDelete: [URL]
        let removedOverdubGroupIDs: Set<UUID>
        let overdubGroupsChanged: Bool
    }

    /// Permanently delete a recording and its associated overdub data.
    /// If deleting a base recording, removes all its layers too.
    /// If deleting a layer, removes it from the group's layerRecordingIds.
    /// Returns file URLs and IDs for the caller to handle file I/O and sync.
    static func permanentlyDelete(
        _ recording: RecordingItem,
        recordings: inout [RecordingItem],
        overdubGroups: inout [OverdubGroup]
    ) -> PermanentDeleteResult {
        var fileURLsToDelete: [URL] = []
        var removedRecordingIDs: Set<UUID> = []
        var removedGroupIDs: Set<UUID> = []
        var groupsChanged = false

        // Handle overdub group cleanup
        if let groupId = recording.overdubGroupId,
           let group = overdubGroups.first(where: { $0.id == groupId }) {

            if recording.overdubRole == .base {
                // Deleting base: remove all layers too
                for layerId in group.layerRecordingIds {
                    if let layerRec = recordings.first(where: { $0.id == layerId }) {
                        fileURLsToDelete.append(layerRec.fileURL)
                    }
                    removedRecordingIDs.insert(layerId)
                }
                recordings.removeAll { group.layerRecordingIds.contains($0.id) }
                overdubGroups.removeAll { $0.id == groupId }
                removedGroupIDs.insert(groupId)
                groupsChanged = true
            } else if recording.overdubRole == .layer {
                // Remove this layer from the group
                if let groupIndex = overdubGroups.firstIndex(where: { $0.id == groupId }) {
                    overdubGroups[groupIndex].layerRecordingIds.removeAll { $0 == recording.id }
                    groupsChanged = true
                }
            }
        }

        // Remove the recording itself
        fileURLsToDelete.append(recording.fileURL)
        removedRecordingIDs.insert(recording.id)
        recordings.removeAll { $0.id == recording.id }

        return PermanentDeleteResult(
            removedRecordingIDs: removedRecordingIDs,
            fileURLsToDelete: fileURLsToDelete,
            removedOverdubGroupIDs: removedGroupIDs,
            overdubGroupsChanged: groupsChanged
        )
    }

    /// Empty trash: permanently delete all trashed recordings.
    /// Handles overdub group cleanup for trashed base recordings (including
    /// active layers that belong to a trashed base).
    static func emptyTrash(
        recordings: inout [RecordingItem],
        overdubGroups: inout [OverdubGroup]
    ) -> PermanentDeleteResult {
        var fileURLsToDelete: [URL] = []
        var removedRecordingIDs: Set<UUID> = []
        var removedGroupIDs: Set<UUID> = []
        var groupsChanged = false

        let trashedIds = Set(recordings.filter { $0.isTrashed }.map { $0.id })

        // Clean up overdub groups: if a trashed recording is a base,
        // remove its active layers too (they can't exist without the base)
        for recording in recordings where recording.isTrashed {
            if let groupId = recording.overdubGroupId,
               recording.overdubRole == .base,
               let group = overdubGroups.first(where: { $0.id == groupId }) {
                // Remove active layers that belong to this group
                for layerId in group.layerRecordingIds where !trashedIds.contains(layerId) {
                    if let layerRec = recordings.first(where: { $0.id == layerId }) {
                        fileURLsToDelete.append(layerRec.fileURL)
                    }
                    removedRecordingIDs.insert(layerId)
                }
                recordings.removeAll { group.layerRecordingIds.contains($0.id) && !trashedIds.contains($0.id) }
                overdubGroups.removeAll { $0.id == groupId }
                removedGroupIDs.insert(groupId)
                groupsChanged = true
            } else if recording.overdubRole == .layer,
                      let groupId = recording.overdubGroupId,
                      let groupIdx = overdubGroups.firstIndex(where: { $0.id == groupId }) {
                // Remove this trashed layer from its parent group
                overdubGroups[groupIdx].layerRecordingIds.removeAll { $0 == recording.id }
                groupsChanged = true
            }
        }

        // Collect all trashed recordings for deletion
        let trashed = recordings.filter { $0.isTrashed }
        for recording in trashed {
            fileURLsToDelete.append(recording.fileURL)
            removedRecordingIDs.insert(recording.id)
        }
        recordings.removeAll { $0.isTrashed }

        return PermanentDeleteResult(
            removedRecordingIDs: removedRecordingIDs,
            fileURLsToDelete: fileURLsToDelete,
            removedOverdubGroupIDs: removedGroupIDs,
            overdubGroupsChanged: groupsChanged
        )
    }

    /// Purge recordings that have been trashed for more than 30 days.
    /// Same overdub cleanup logic as emptyTrash but only for expired items.
    static func purgeOldTrashed(
        recordings: inout [RecordingItem],
        overdubGroups: inout [OverdubGroup]
    ) -> PermanentDeleteResult {
        let toDelete = recordings.filter { $0.shouldPurge }
        guard !toDelete.isEmpty else {
            return PermanentDeleteResult(
                removedRecordingIDs: [],
                fileURLsToDelete: [],
                removedOverdubGroupIDs: [],
                overdubGroupsChanged: false
            )
        }

        var fileURLsToDelete: [URL] = []
        var removedRecordingIDs: Set<UUID> = []
        var removedGroupIDs: Set<UUID> = []
        var groupsChanged = false

        let purgeIds = Set(toDelete.map { $0.id })

        // Clean up overdub groups for purged base recordings
        for recording in toDelete {
            if let groupId = recording.overdubGroupId,
               recording.overdubRole == .base,
               let group = overdubGroups.first(where: { $0.id == groupId }) {
                for layerId in group.layerRecordingIds where !purgeIds.contains(layerId) {
                    if let layerRec = recordings.first(where: { $0.id == layerId }) {
                        fileURLsToDelete.append(layerRec.fileURL)
                    }
                    removedRecordingIDs.insert(layerId)
                }
                recordings.removeAll { group.layerRecordingIds.contains($0.id) && !purgeIds.contains($0.id) }
                overdubGroups.removeAll { $0.id == groupId }
                removedGroupIDs.insert(groupId)
                groupsChanged = true
            } else if recording.overdubRole == .layer,
                      let groupId = recording.overdubGroupId,
                      let groupIdx = overdubGroups.firstIndex(where: { $0.id == groupId }) {
                // Remove this purged layer from its parent group
                overdubGroups[groupIdx].layerRecordingIds.removeAll { $0 == recording.id }
                groupsChanged = true
            }
        }

        // Remove purged recordings
        for recording in toDelete {
            fileURLsToDelete.append(recording.fileURL)
            removedRecordingIDs.insert(recording.id)
        }
        recordings.removeAll { $0.shouldPurge }

        return PermanentDeleteResult(
            removedRecordingIDs: removedRecordingIDs,
            fileURLsToDelete: fileURLsToDelete,
            removedOverdubGroupIDs: removedGroupIDs,
            overdubGroupsChanged: groupsChanged
        )
    }
}
