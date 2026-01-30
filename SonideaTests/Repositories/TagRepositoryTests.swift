//
//  TagRepositoryTests.swift
//  SonideaTests
//
//  Tests for TagRepository: create, update, delete, merge, toggle, seed.
//

import Testing
import Foundation
@testable import Sonidea

struct TagRepositoryTests {

    // MARK: - Create

    @Test func createTagSucceeds() {
        var tags: [Tag] = []
        let tag = TagRepository.createTag(name: "melody", colorHex: "#9B59B6", tags: &tags)

        #expect(tag != nil)
        #expect(tags.count == 1)
        #expect(tags[0].name == "melody")
    }

    @Test func createDuplicateTagFails() {
        var tags = [TestFixtures.makeTag(name: "melody")]
        let result = TagRepository.createTag(name: "MELODY", colorHex: "#000000", tags: &tags)

        #expect(result == nil)
        #expect(tags.count == 1)
    }

    // MARK: - Update

    @Test func updateTagNameAndColor() {
        var tags = [TestFixtures.makeTag(name: "old", colorHex: "#000000")]
        let tag = tags[0]

        let result = TagRepository.updateTag(tag, name: "new", colorHex: "#FFFFFF", tags: &tags)
        #expect(result)
        #expect(tags[0].name == "new")
        #expect(tags[0].colorHex == "#FFFFFF")
    }

    @Test func updateProtectedTagOnlyRecolors() {
        var tags = [Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: "#FF6B6B")]
        let protectedTag = tags[0]

        let result = TagRepository.updateTag(protectedTag, name: "renamed", colorHex: "#00FF00", tags: &tags)
        #expect(result)
        #expect(tags[0].name == "favorite") // Name unchanged
        #expect(tags[0].colorHex == "#00FF00") // Color changed
    }

    @Test func updateToDuplicateNameFails() {
        var tags = [
            TestFixtures.makeTag(name: "one"),
            TestFixtures.makeTag(name: "two")
        ]

        let result = TagRepository.updateTag(tags[1], name: "one", colorHex: "#000000", tags: &tags)
        #expect(!result)
        #expect(tags[1].name == "two")
    }

    // MARK: - Delete

    @Test func deleteTagSucceeds() {
        let tag = TestFixtures.makeTag(name: "deleteme")
        var tags = [tag]
        var recordings = [TestFixtures.makeRecording(tagIDs: [tag.id])]

        let result = TagRepository.deleteTag(tag, tags: &tags, recordings: &recordings)
        #expect(result)
        #expect(tags.isEmpty)
        #expect(recordings[0].tagIDs.isEmpty)
    }

    @Test func deleteProtectedTagFails() {
        let favoriteTag = Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: "#FF6B6B")
        var tags = [favoriteTag]
        var recordings: [RecordingItem] = []

        let result = TagRepository.deleteTag(favoriteTag, tags: &tags, recordings: &recordings)
        #expect(!result)
        #expect(tags.count == 1)
    }

    @Test func deleteTagRemovesFromRecordings() {
        let tag = TestFixtures.makeTag(name: "remove")
        let otherTag = TestFixtures.makeTag(name: "keep")
        var tags = [tag, otherTag]
        var recordings = [
            TestFixtures.makeRecording(tagIDs: [tag.id, otherTag.id]),
            TestFixtures.makeRecording(tagIDs: [tag.id]),
            TestFixtures.makeRecording(tagIDs: [otherTag.id])
        ]

        _ = TagRepository.deleteTag(tag, tags: &tags, recordings: &recordings)

        #expect(recordings[0].tagIDs == [otherTag.id])
        #expect(recordings[1].tagIDs.isEmpty)
        #expect(recordings[2].tagIDs == [otherTag.id])
    }

    // MARK: - Merge

    @Test func mergeTagsUpdatesRecordings() {
        let source = TestFixtures.makeTag(name: "source")
        let dest = TestFixtures.makeTag(name: "dest")
        var tags = [source, dest]
        var recordings = [TestFixtures.makeRecording(tagIDs: [source.id])]

        let deleted = TagRepository.mergeTags(
            sourceTagIDs: [source.id],
            destinationTagID: dest.id,
            tags: &tags,
            recordings: &recordings
        )

        #expect(deleted.count == 1)
        #expect(tags.count == 1) // Source removed
        #expect(recordings[0].tagIDs.contains(dest.id))
        #expect(!recordings[0].tagIDs.contains(source.id))
    }

    // MARK: - Toggle

    @Test func toggleTagAdds() {
        let tag = TestFixtures.makeTag()
        let recording = TestFixtures.makeRecording(tagIDs: [])

        let updated = TagRepository.toggleTag(tag, on: recording)
        #expect(updated.tagIDs.contains(tag.id))
    }

    @Test func toggleTagRemoves() {
        let tag = TestFixtures.makeTag()
        let recording = TestFixtures.makeRecording(tagIDs: [tag.id])

        let updated = TagRepository.toggleTag(tag, on: recording)
        #expect(!updated.tagIDs.contains(tag.id))
    }

    // MARK: - Seed Defaults

    @Test func seedDefaultTagsWhenEmpty() {
        var tags: [Tag] = []
        let didSeed = TagRepository.seedDefaultTagsIfNeeded(tags: &tags)

        #expect(didSeed)
        #expect(!tags.isEmpty)
        #expect(tags.contains(where: { $0.id == Tag.favoriteTagID }))
    }

    @Test func seedDefaultTagsDoesNotOverwrite() {
        let customTag = TestFixtures.makeTag(name: "custom")
        var tags = [customTag]
        let didSeed = TagRepository.seedDefaultTagsIfNeeded(tags: &tags)

        #expect(!didSeed)
        #expect(tags.contains(where: { $0.name == "custom" }))
    }

    // MARK: - Ensure Favorite

    @Test func ensureFavoriteCreatesIfMissing() {
        var tags = [TestFixtures.makeTag(name: "other")]
        TagRepository.ensureFavoriteTagExists(tags: &tags)

        #expect(tags.contains(where: { $0.id == Tag.favoriteTagID }))
        #expect(tags.count == 2)
    }

    @Test func ensureFavoriteDoesNotDuplicate() {
        var tags = [Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: "#FF6B6B")]
        TagRepository.ensureFavoriteTagExists(tags: &tags)

        #expect(tags.count == 1)
    }

    // MARK: - Queries

    @Test func tagExistsCaseInsensitive() {
        let tags = [TestFixtures.makeTag(name: "Melody")]
        #expect(TagRepository.tagExists(name: "melody", in: tags))
        #expect(TagRepository.tagExists(name: "MELODY", in: tags))
    }

    @Test func tagExistsExcludingID() {
        let tag = TestFixtures.makeTag(name: "Melody")
        let tags = [tag]
        #expect(!TagRepository.tagExists(name: "melody", excludingID: tag.id, in: tags))
    }

    @Test func isFavorite() {
        let fav = TestFixtures.makeRecording(tagIDs: [Tag.favoriteTagID])
        #expect(TagRepository.isFavorite(fav))

        let notFav = TestFixtures.makeRecording(tagIDs: [])
        #expect(!TagRepository.isFavorite(notFav))
    }
}
