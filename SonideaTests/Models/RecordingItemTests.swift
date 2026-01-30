//
//  RecordingItemTests.swift
//  SonideaTests
//
//  Tests for RecordingItem model: Codable, computed properties, migrations.
//

import Testing
import Foundation
@testable import Sonidea

struct RecordingItemTests {

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let recording = TestFixtures.makeRecording(
            title: "Round Trip Test",
            duration: 123.5,
            notes: "Some notes",
            tagIDs: [UUID(), UUID()],
            albumID: UUID(),
            locationLabel: "Home Studio",
            transcript: "Hello world",
            latitude: 40.7128,
            longitude: -74.0060,
            iconColorHex: "#FF0000",
            iconName: "mic.fill",
            iconSourceRaw: "user",
            versionIndex: 3,
            proofStatusRaw: "proven",
            proofSHA256: "abc123",
            overdubGroupId: UUID(),
            overdubRoleRaw: "base",
            overdubIndex: nil,
            overdubOffsetSeconds: 0.5
        )

        let data = try JSONEncoder().encode(recording)
        let decoded = try JSONDecoder().decode(RecordingItem.self, from: data)

        #expect(decoded.id == recording.id)
        #expect(decoded.fileURL == recording.fileURL)
        #expect(decoded.title == "Round Trip Test")
        #expect(decoded.duration == 123.5)
        #expect(decoded.notes == "Some notes")
        #expect(decoded.tagIDs.count == 2)
        #expect(decoded.albumID == recording.albumID)
        #expect(decoded.locationLabel == "Home Studio")
        #expect(decoded.transcript == "Hello world")
        #expect(decoded.latitude == 40.7128)
        #expect(decoded.longitude == -74.0060)
        #expect(decoded.iconColorHex == "#FF0000")
        #expect(decoded.iconName == "mic.fill")
        #expect(decoded.iconSourceRaw == "user")
        #expect(decoded.versionIndex == 3)
        #expect(decoded.proofStatusRaw == "proven")
        #expect(decoded.proofSHA256 == "abc123")
        #expect(decoded.overdubGroupId == recording.overdubGroupId)
        #expect(decoded.overdubRoleRaw == "base")
        #expect(decoded.overdubOffsetSeconds == 0.5)
    }

    // MARK: - Migration: Missing Fields Decode with Defaults

    @Test func decodeMissingFieldsUsesDefaults() throws {
        // Simulate a minimal JSON from an older schema (no optional fields)
        let id = UUID()
        let url = TestFixtures.dummyFileURL()
        let date = Date()
        let json: [String: Any] = [
            "id": id.uuidString,
            "fileURL": url.absoluteString,
            "createdAt": date.timeIntervalSinceReferenceDate,
            "duration": 30.0,
            "title": "Old Recording",
            "notes": "",
            "tagIDs": [],
            "locationLabel": "",
            "transcript": "",
            "lastPlaybackPosition": 0.0,
            "overdubOffsetSeconds": 0.0,
            "markers": []
        ] as [String: Any]

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(RecordingItem.self, from: data)

        // Fields with defaults should be populated
        #expect(decoded.versionIndex == 1)
        #expect(decoded.projectId == nil)
        #expect(decoded.parentRecordingId == nil)
        #expect(decoded.proofStatusRaw == nil)
        #expect(decoded.overdubGroupId == nil)
        #expect(decoded.overdubRoleRaw == nil)
        #expect(decoded.eqSettings == nil)
        #expect(decoded.iconPredictions == nil)
        #expect(decoded.secondaryIcons == nil)
    }

    // MARK: - Computed Properties

    @Test func isTrashed() {
        let active = TestFixtures.makeRecording(trashedAt: nil)
        #expect(!active.isTrashed)

        let trashed = TestFixtures.makeRecording(trashedAt: Date())
        #expect(trashed.isTrashed)
    }

    @Test func shouldPurgeAfter30Days() {
        // Not trashed - never purge
        let active = TestFixtures.makeRecording(trashedAt: nil)
        #expect(!active.shouldPurge)

        // Trashed today - should not purge
        let recentlyTrashed = TestFixtures.makeRecording(trashedAt: Date())
        #expect(!recentlyTrashed.shouldPurge)

        // Trashed 29 days ago - should not purge
        let almostExpired = TestFixtures.makeRecording(
            trashedAt: Calendar.current.date(byAdding: .day, value: -29, to: Date())
        )
        #expect(!almostExpired.shouldPurge)

        // Trashed 30 days ago - should purge
        let expired = TestFixtures.makeRecording(
            trashedAt: Calendar.current.date(byAdding: .day, value: -30, to: Date())
        )
        #expect(expired.shouldPurge)

        // Trashed 60 days ago - should purge
        let longExpired = TestFixtures.makeRecording(
            trashedAt: Calendar.current.date(byAdding: .day, value: -60, to: Date())
        )
        #expect(longExpired.shouldPurge)
    }

    @Test func formattedDuration() {
        let zero = TestFixtures.makeRecording(duration: 0)
        #expect(zero.formattedDuration == "0:00")

        let short = TestFixtures.makeRecording(duration: 5)
        #expect(short.formattedDuration == "0:05")

        let oneMinute = TestFixtures.makeRecording(duration: 60)
        #expect(oneMinute.formattedDuration == "1:00")

        let mixed = TestFixtures.makeRecording(duration: 125)
        #expect(mixed.formattedDuration == "2:05")
    }

    @Test func belongsToProject() {
        let standalone = TestFixtures.makeRecording(projectId: nil)
        #expect(!standalone.belongsToProject)

        let versioned = TestFixtures.makeRecording(projectId: UUID())
        #expect(versioned.belongsToProject)
    }

    @Test func versionLabel() {
        let v1 = TestFixtures.makeRecording(versionIndex: 1)
        #expect(v1.versionLabel == "V1")

        let v3 = TestFixtures.makeRecording(versionIndex: 3)
        #expect(v3.versionLabel == "V3")
    }

    @Test func overdubRole() {
        let none = TestFixtures.makeRecording(overdubRoleRaw: nil)
        #expect(none.overdubRole == .none)

        let base = TestFixtures.makeRecording(overdubRoleRaw: "base")
        #expect(base.overdubRole == .base)
        #expect(base.isOverdubBase)
        #expect(!base.isOverdubLayer)

        let layer = TestFixtures.makeRecording(overdubRoleRaw: "layer", overdubIndex: 2)
        #expect(layer.overdubRole == .layer)
        #expect(layer.isOverdubLayer)
        #expect(!layer.isOverdubBase)
        #expect(layer.overdubLayerLabel == "Layer 2")
    }

    @Test func displayIconSymbol() {
        let defaultIcon = TestFixtures.makeRecording(iconName: nil)
        #expect(defaultIcon.displayIconSymbol == "waveform")

        let custom = TestFixtures.makeRecording(iconName: "mic.fill")
        #expect(custom.displayIconSymbol == "mic.fill")
    }

    @Test func hasCoordinates() {
        let noCoords = TestFixtures.makeRecording(latitude: nil, longitude: nil)
        #expect(!noCoords.hasCoordinates)

        let partialCoords = TestFixtures.makeRecording(latitude: 40.0, longitude: nil)
        #expect(!partialCoords.hasCoordinates)

        let fullCoords = TestFixtures.makeRecording(latitude: 40.0, longitude: -74.0)
        #expect(fullCoords.hasCoordinates)
        #expect(fullCoords.coordinate != nil)
    }

    @Test func modifiedAtDefaultsToCreatedAt() {
        let date = Date(timeIntervalSince1970: 1000000)
        let recording = TestFixtures.makeRecording(createdAt: date, modifiedAt: nil)
        #expect(recording.modifiedAt == date)
    }

    @Test func modifiedAtUsesExplicitValue() {
        let created = Date(timeIntervalSince1970: 1000000)
        let modified = Date(timeIntervalSince1970: 2000000)
        let recording = TestFixtures.makeRecording(createdAt: created, modifiedAt: modified)
        #expect(recording.modifiedAt == modified)
    }

    @Test func iconSource() {
        let auto = TestFixtures.makeRecording(iconSourceRaw: nil)
        #expect(auto.iconSource == .auto)

        let autoExplicit = TestFixtures.makeRecording(iconSourceRaw: "auto")
        #expect(autoExplicit.iconSource == .auto)

        let user = TestFixtures.makeRecording(iconSourceRaw: "user")
        #expect(user.iconSource == .user)

        let invalid = TestFixtures.makeRecording(iconSourceRaw: "unknown")
        #expect(invalid.iconSource == .auto)
    }
}
