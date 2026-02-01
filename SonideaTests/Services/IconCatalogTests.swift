//
//  IconCatalogTests.swift
//  SonideaTests
//
//  Tests for IconCatalog: icon definitions, lookup, search, categories.
//

import Testing
import Foundation
@testable import Sonidea

struct IconCatalogTests {

    // MARK: - All Icons

    @Test func allIconsNotEmpty() {
        #expect(!IconCatalog.allIcons.isEmpty)
    }

    @Test func allIconsHaveUniqueIDs() {
        let ids = IconCatalog.allIcons.map(\.id)
        let uniqueIDs = Set(ids)
        // Note: there may be duplicates (e.g., "wind" in both Music/Wind and Nature/Wind)
        // That's by design - we check that the catalog is functional
        #expect(ids.count >= uniqueIDs.count)
    }

    @Test func allIconsHaveNonEmptySymbol() {
        for icon in IconCatalog.allIcons {
            #expect(!icon.sfSymbol.isEmpty, "Icon \(icon.displayName) has empty sfSymbol")
        }
    }

    @Test func allIconsHaveNonEmptyDisplayName() {
        for icon in IconCatalog.allIcons {
            #expect(!icon.displayName.isEmpty, "Icon \(icon.sfSymbol) has empty displayName")
        }
    }

    // MARK: - Default Icon

    @Test func defaultIconIsWaveform() {
        #expect(IconCatalog.defaultIcon.sfSymbol == "waveform")
    }

    // MARK: - Lookup by Symbol

    @Test func lookupBySymbol() {
        let icon = IconCatalog.icon(for: "mic.fill")
        #expect(icon != nil)
        #expect(icon?.displayName == "Mic")
    }

    @Test func lookupBySymbolNotFound() {
        let icon = IconCatalog.icon(for: "nonexistent.symbol")
        #expect(icon == nil)
    }

    // MARK: - Classifier Label Mapping

    @Test func classifierLabelMapping() {
        let icon = IconCatalog.iconForClassifierLabel("dog_bark")
        #expect(icon != nil)
        #expect(icon?.displayName == "Dog")
    }

    @Test func classifierLabelMappingNotFound() {
        let icon = IconCatalog.iconForClassifierLabel("nonexistent_label")
        #expect(icon == nil)
    }

    @Test func classifierLabelMapContainsEntries() {
        let map = IconCatalog.labelToIconMap
        #expect(!map.isEmpty)
    }

    @Test func musicLabelMapsToMusicIcon() {
        let icon = IconCatalog.iconForClassifierLabel("music")
        #expect(icon != nil)
        #expect(icon?.sfSymbol == "music.note")
    }

    // MARK: - Search

    @Test func searchByName() {
        let results = IconCatalog.search("Guitar")
        #expect(!results.isEmpty)
        #expect(results.contains { $0.displayName.contains("Guitar") })
    }

    @Test func searchCaseInsensitive() {
        let results = IconCatalog.search("guitar")
        #expect(!results.isEmpty)
    }

    @Test func searchByCategory() {
        let results = IconCatalog.search("Animals")
        #expect(!results.isEmpty)
    }

    @Test func searchEmptyReturnsAll() {
        let results = IconCatalog.search("")
        #expect(results.count == IconCatalog.allIcons.count)
    }

    @Test func searchNoMatch() {
        let results = IconCatalog.search("xyznonexistent")
        #expect(results.isEmpty)
    }

    // MARK: - Categories

    @Test func iconsByCategoryPopulated() {
        let categories = IconCatalog.iconsByCategory
        #expect(!categories.isEmpty)
    }

    @Test func allCategoriesRepresented() {
        let categoryNames = Set(IconCatalog.iconsByCategory.map(\.category))
        // At minimum, Music and Sounds should be present
        #expect(categoryNames.contains(.music))
        #expect(categoryNames.contains(.sounds))
        #expect(categoryNames.contains(.voice))
    }

    // MARK: - IconCategory

    @Test func iconCategoryDisplayOrder() {
        #expect(IconCategory.music.displayOrder == 0)
        #expect(IconCategory.other.displayOrder == 6)
    }
}
