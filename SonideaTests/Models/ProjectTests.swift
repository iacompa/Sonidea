//
//  ProjectTests.swift
//  SonideaTests
//
//  Tests for Project model: factory, stats, Codable.
//

import Testing
import Foundation
@testable import Sonidea

struct ProjectTests {

    // MARK: - fromRecording Factory

    @Test func fromRecordingUsesRecordingTitle() {
        let recording = TestFixtures.makeRecording(title: "My Song Idea")
        let project = Project.fromRecording(recording)

        #expect(project.title == "My Song Idea")
        #expect(!project.pinned)
        #expect(project.notes.isEmpty)
        #expect(project.bestTakeRecordingId == nil)
    }

    // MARK: - Codable Round-Trip

    @Test func codableRoundTrip() throws {
        let bestTakeId = UUID()
        let project = TestFixtures.makeProject(
            title: "Beat Project",
            pinned: true,
            notes: "Great progress",
            bestTakeRecordingId: bestTakeId,
            sortOrder: 5
        )

        let data = try JSONEncoder().encode(project)
        let decoded = try JSONDecoder().decode(Project.self, from: data)

        #expect(decoded.id == project.id)
        #expect(decoded.title == "Beat Project")
        #expect(decoded.pinned)
        #expect(decoded.notes == "Great progress")
        #expect(decoded.bestTakeRecordingId == bestTakeId)
        #expect(decoded.sortOrder == 5)
    }

    // MARK: - ProjectStats

    @Test func emptyStats() {
        let stats = ProjectStats.empty
        #expect(stats.versionCount == 0)
        #expect(stats.totalDuration == 0)
        #expect(stats.oldestVersion == nil)
        #expect(stats.newestVersion == nil)
        #expect(!stats.hasBestTake)
    }

    @Test func formattedTotalDuration() {
        let stats = ProjectStats(
            versionCount: 3,
            totalDuration: 185,
            oldestVersion: Date(),
            newestVersion: Date(),
            hasBestTake: true
        )
        #expect(stats.formattedTotalDuration == "3:05")
    }

    @Test func formattedTotalDurationZero() {
        let stats = ProjectStats.empty
        #expect(stats.formattedTotalDuration == "0:00")
    }

    // MARK: - Hashable

    @Test func hashableUsesID() {
        let id = UUID()
        let project1 = TestFixtures.makeProject(id: id, title: "One")
        let project2 = TestFixtures.makeProject(id: id, title: "Two")

        // Same ID should produce same hash
        var hasher1 = Hasher()
        project1.hash(into: &hasher1)

        var hasher2 = Hasher()
        project2.hash(into: &hasher2)

        #expect(hasher1.finalize() == hasher2.finalize())
    }

    // MARK: - Defaults

    @Test func defaultValues() {
        let project = TestFixtures.makeProject()
        #expect(!project.pinned)
        #expect(project.notes.isEmpty)
        #expect(project.bestTakeRecordingId == nil)
        #expect(project.sortOrder == nil)
    }
}
