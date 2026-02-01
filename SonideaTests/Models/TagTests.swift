//
//  TagTests.swift
//  SonideaTests
//
//  Tests for Tag model: protected tags, defaults, Codable, Color extension.
//

import Testing
import Foundation
import SwiftUI
@testable import Sonidea

// Disambiguate Sonidea.Tag from Testing.Tag
private typealias Tag = Sonidea.Tag

struct TagTests {

    // MARK: - Favorite Tag ID Stability

    @Test func favoriteTagIDIsStable() {
        let expected = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        #expect(Tag.favoriteTagID == expected)
    }

    // MARK: - Protected Tag

    @Test func favoriteTagIsProtected() {
        let favorite = Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: "#FF6B6B")
        #expect(favorite.isProtected)
    }

    @Test func regularTagIsNotProtected() {
        let tag = TestFixtures.makeTag(name: "beatbox")
        #expect(!tag.isProtected)
    }

    // MARK: - Default Tags

    @Test func defaultTagsContainsFavorite() {
        let hasFavorite = Tag.defaultTags.contains { $0.id == Tag.favoriteTagID }
        #expect(hasFavorite)
    }

    @Test func defaultTagsHaveUniqueIDs() {
        let ids = Tag.defaultTags.map(\.id)
        let uniqueIDs = Set(ids)
        #expect(ids.count == uniqueIDs.count)
    }

    @Test func defaultTagsHaveNonEmptyNames() {
        for tag in Tag.defaultTags {
            #expect(!tag.name.isEmpty)
        }
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let tag = TestFixtures.makeTag(name: "melody", colorHex: "#9B59B6")
        let data = try JSONEncoder().encode(tag)
        let decoded = try JSONDecoder().decode(Tag.self, from: data)

        #expect(decoded.id == tag.id)
        #expect(decoded.name == "melody")
        #expect(decoded.colorHex == "#9B59B6")
    }

    // MARK: - Color(hex:) Extension

    @Test func colorFromValidHex() {
        let color = Color(hex: "#FF0000")
        #expect(color != nil)
    }

    @Test func colorFromValidHexWithoutHash() {
        let color = Color(hex: "00FF00")
        #expect(color != nil)
    }

    @Test func colorFromInvalidHex() {
        let color = Color(hex: "not-a-hex")
        #expect(color == nil)
    }

    @Test func colorFromEmptyString() {
        let color = Color(hex: "")
        #expect(color == nil)
    }

    // MARK: - Equatable / Hashable

    @Test func equalityByAllFields() {
        let id = UUID()
        let tag1 = Tag(id: id, name: "test", colorHex: "#000000")
        let tag2 = Tag(id: id, name: "test", colorHex: "#000000")
        #expect(tag1 == tag2)
    }

    @Test func inequalityOnDifferentName() {
        let id = UUID()
        let tag1 = Tag(id: id, name: "one", colorHex: "#000000")
        let tag2 = Tag(id: id, name: "two", colorHex: "#000000")
        #expect(tag1 != tag2)
    }
}
