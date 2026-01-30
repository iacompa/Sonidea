//
//  TagRepository.swift
//  Sonidea
//
//  Pure data operations for tags, extracted from AppState.
//  Operates on inout arrays with no persistence or sync side effects.
//  AppState handles save/sync after each operation.
//

import Foundation
import SwiftUI

/// Stateless repository for tag data operations.
/// All methods take `inout` arrays and return results.
/// Caller (AppState) is responsible for persistence and sync.
enum TagRepository {

    // MARK: - Queries

    static func tag(for id: UUID, in tags: [Tag]) -> Tag? {
        tags.first { $0.id == id }
    }

    static func tags(for ids: [UUID], in allTags: [Tag]) -> [Tag] {
        ids.compactMap { id in allTags.first { $0.id == id } }
    }

    static func tagUsageCount(_ tag: Tag, in recordings: [RecordingItem]) -> Int {
        recordings.filter { $0.tagIDs.contains(tag.id) }.count
    }

    static func tagExists(name: String, excludingID: UUID? = nil, in tags: [Tag]) -> Bool {
        tags.contains { tag in
            tag.name.lowercased() == name.lowercased() && tag.id != excludingID
        }
    }

    static func isFavorite(_ recording: RecordingItem) -> Bool {
        recording.tagIDs.contains(Tag.favoriteTagID)
    }

    // MARK: - Mutations

    /// Create a new tag. Returns the tag if successful, nil if duplicate name exists.
    @discardableResult
    static func createTag(name: String, colorHex: String, tags: inout [Tag]) -> Tag? {
        guard !tagExists(name: name, in: tags) else { return nil }
        let tag = Tag(name: name, colorHex: colorHex)
        tags.append(tag)
        return tag
    }

    /// Update a tag's name and color. Returns true if successful.
    /// Protected tags can only be recolored, not renamed.
    static func updateTag(
        _ tag: Tag,
        name: String,
        colorHex: String,
        tags: inout [Tag]
    ) -> Bool {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else {
            return false
        }

        if tag.isProtected {
            tags[index].colorHex = colorHex
            return true
        }

        if tagExists(name: name, excludingID: tag.id, in: tags) {
            return false
        }
        tags[index].name = name
        tags[index].colorHex = colorHex
        return true
    }

    /// Delete a tag and remove it from all recordings.
    /// Returns the deleted tag IDs removed from recordings (empty if tag is protected).
    static func deleteTag(
        _ tag: Tag,
        tags: inout [Tag],
        recordings: inout [RecordingItem]
    ) -> Bool {
        guard !tag.isProtected else { return false }

        let tagId = tag.id
        tags.removeAll { $0.id == tagId }

        for i in recordings.indices {
            let hadTag = recordings[i].tagIDs.contains(tagId)
            recordings[i].tagIDs.removeAll { $0 == tagId }
            if hadTag {
                recordings[i].modifiedAt = Date()
            }
        }
        return true
    }

    /// Merge source tags into a destination tag.
    /// Returns IDs of deleted source tags.
    static func mergeTags(
        sourceTagIDs: Set<UUID>,
        destinationTagID: UUID,
        tags: inout [Tag],
        recordings: inout [RecordingItem]
    ) -> [UUID] {
        guard tag(for: destinationTagID, in: tags) != nil else { return [] }

        // Update recordings
        for i in recordings.indices {
            var newTagIDs = recordings[i].tagIDs
            let hasSourceTag = newTagIDs.contains { sourceTagIDs.contains($0) }
            if hasSourceTag {
                newTagIDs.removeAll { sourceTagIDs.contains($0) }
                if !newTagIDs.contains(destinationTagID) {
                    newTagIDs.append(destinationTagID)
                }
                recordings[i].tagIDs = newTagIDs
                recordings[i].modifiedAt = Date()
            }
        }

        // Delete source tags (except destination, and skip protected)
        var deletedTagIDs: [UUID] = []
        for tagID in sourceTagIDs where tagID != destinationTagID {
            if let t = tag(for: tagID, in: tags), !t.isProtected {
                tags.removeAll { $0.id == tagID }
                deletedTagIDs.append(tagID)
            }
        }

        return deletedTagIDs
    }

    /// Reorder tags by moving from source indices to destination.
    static func moveTags(from source: IndexSet, to destination: Int, tags: inout [Tag]) {
        tags.move(fromOffsets: source, toOffset: destination)
    }

    /// Toggle a tag on a recording. Returns the updated recording.
    static func toggleTag(
        _ tag: Tag,
        on recording: RecordingItem
    ) -> RecordingItem {
        var updated = recording
        if updated.tagIDs.contains(tag.id) {
            updated.tagIDs.removeAll { $0 == tag.id }
        } else {
            updated.tagIDs.append(tag.id)
        }
        return updated
    }

    /// Seed default tags if the tag list is empty.
    static func seedDefaultTagsIfNeeded(tags: inout [Tag]) -> Bool {
        if tags.isEmpty {
            tags = Tag.defaultTags
            return true
        }
        ensureFavoriteTagExists(tags: &tags)
        return false
    }

    /// Ensure the protected favorite tag exists, creating it if missing.
    static func ensureFavoriteTagExists(tags: inout [Tag]) {
        if !tags.contains(where: { $0.id == Tag.favoriteTagID }) {
            let favoriteTag = Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: "#FF6B6B")
            tags.insert(favoriteTag, at: 0)
        }
    }
}
