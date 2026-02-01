//
//  ProjectRepositoryTests.swift
//  SonideaTests
//
//  Tests for ProjectRepository: create, versioning, best take, delete, queries.
//

import Testing
import Foundation
@testable import Sonidea

struct ProjectRepositoryTests {

    // MARK: - Queries

    @Test func projectForID() {
        let project = TestFixtures.makeProject(title: "My Project")
        let projects = [project]
        #expect(ProjectRepository.project(for: project.id, in: projects)?.title == "My Project")
    }

    @Test func projectForNilIDReturnsNil() {
        let projects = [TestFixtures.makeProject()]
        #expect(ProjectRepository.project(for: nil, in: projects) == nil)
    }

    @Test func recordingsInProject() {
        let project = TestFixtures.makeProject()
        let recordings = [
            TestFixtures.makeRecording(title: "V1", projectId: project.id, versionIndex: 1),
            TestFixtures.makeRecording(title: "V2", projectId: project.id, versionIndex: 2),
            TestFixtures.makeRecording(title: "Other"),
            TestFixtures.makeRecording(title: "Trashed", trashedAt: Date(), projectId: project.id)
        ]
        let result = ProjectRepository.recordings(in: project, from: recordings)
        #expect(result.count == 2)
        #expect(result[0].title == "V1")
        #expect(result[1].title == "V2")
    }

    @Test func recordingCountInProject() {
        let project = TestFixtures.makeProject()
        let recordings = [
            TestFixtures.makeRecording(projectId: project.id),
            TestFixtures.makeRecording(projectId: project.id),
            TestFixtures.makeRecording()
        ]
        #expect(ProjectRepository.recordingCount(in: project, from: recordings) == 2)
    }

    @Test func nextVersionIndex() {
        let project = TestFixtures.makeProject()
        let recordings = [
            TestFixtures.makeRecording(projectId: project.id, versionIndex: 1),
            TestFixtures.makeRecording(projectId: project.id, versionIndex: 2)
        ]
        #expect(ProjectRepository.nextVersionIndex(for: project, recordings: recordings) == 3)
    }

    @Test func nextVersionIndexEmpty() {
        let project = TestFixtures.makeProject()
        #expect(ProjectRepository.nextVersionIndex(for: project, recordings: []) == 1)
    }

    @Test func bestTake() {
        let recId = UUID()
        let project = TestFixtures.makeProject(bestTakeRecordingId: recId)
        let recordings = [TestFixtures.makeRecording(id: recId, title: "Best")]
        let result = ProjectRepository.bestTake(for: project, recordings: recordings)
        #expect(result?.title == "Best")
    }

    @Test func bestTakeNil() {
        let project = TestFixtures.makeProject()
        #expect(ProjectRepository.bestTake(for: project, recordings: []) == nil)
    }

    @Test func statsComputation() {
        let project = TestFixtures.makeProject()
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let recordings = [
            TestFixtures.makeRecording(createdAt: earlier, duration: 60.0, projectId: project.id),
            TestFixtures.makeRecording(createdAt: now, duration: 120.0, projectId: project.id)
        ]
        let stats = ProjectRepository.stats(for: project, recordings: recordings)
        #expect(stats.versionCount == 2)
        #expect(stats.totalDuration == 180.0)
        #expect(stats.oldestVersion == earlier)
        #expect(stats.newestVersion == now)
    }

    @Test func sortedProjectsPinnedFirst() {
        let pinned = TestFixtures.makeProject(title: "Pinned", pinned: true)
        let recent = TestFixtures.makeProject(title: "Recent", updatedAt: Date())
        let old = TestFixtures.makeProject(title: "Old", updatedAt: Date.distantPast)

        let sorted = ProjectRepository.sortedProjects([old, recent, pinned])
        #expect(sorted[0].title == "Pinned")
        #expect(sorted[1].title == "Recent")
        #expect(sorted[2].title == "Old")
    }

    @Test func standaloneRecordings() {
        let projectId = UUID()
        let recordings = [
            TestFixtures.makeRecording(title: "Standalone"),
            TestFixtures.makeRecording(title: "In Project", projectId: projectId),
            TestFixtures.makeRecording(title: "Trashed Standalone", trashedAt: Date())
        ]
        let result = ProjectRepository.standaloneRecordings(from: recordings)
        #expect(result.count == 1)
        #expect(result[0].title == "Standalone")
    }

    // MARK: - Create

    @Test func createProjectFromRecording() {
        let recording = TestFixtures.makeRecording(title: "My Song")
        var projects: [Project] = []
        var recordings = [recording]

        let project = ProjectRepository.createProject(
            from: recording,
            projects: &projects,
            recordings: &recordings
        )

        #expect(project.title == "My Song")
        #expect(projects.count == 1)
        #expect(recordings[0].projectId == project.id)
        #expect(recordings[0].versionIndex == 1)
    }

    @Test func createProjectWithCustomTitle() {
        let recording = TestFixtures.makeRecording(title: "Original")
        var projects: [Project] = []
        var recordings = [recording]

        let project = ProjectRepository.createProject(
            from: recording,
            title: "Custom Title",
            projects: &projects,
            recordings: &recordings
        )

        #expect(project.title == "Custom Title")
    }

    @Test func createEmptyProject() {
        var projects: [Project] = []
        let project = ProjectRepository.createProject(title: "Empty Project", projects: &projects)
        #expect(project.title == "Empty Project")
        #expect(projects.count == 1)
    }

    // MARK: - Add Version

    @Test func addVersionIncrementsIndex() {
        let project = TestFixtures.makeProject()
        let v1 = TestFixtures.makeRecording(title: "V1", projectId: project.id, versionIndex: 1)
        let newRec = TestFixtures.makeRecording(title: "V2")
        var projects = [project]
        var recordings = [v1, newRec]

        ProjectRepository.addVersion(
            recording: newRec,
            to: project,
            projects: &projects,
            recordings: &recordings
        )

        #expect(recordings[1].projectId == project.id)
        #expect(recordings[1].versionIndex == 2)
        #expect(recordings[1].parentRecordingId == v1.id)
    }

    // MARK: - Remove From Project

    @Test func removeFromProjectClearsMetadata() {
        let project = TestFixtures.makeProject()
        let recording = TestFixtures.makeRecording(projectId: project.id, versionIndex: 2)
        var projects = [project]
        var recordings = [recording]

        ProjectRepository.removeFromProject(
            recording: recording,
            projects: &projects,
            recordings: &recordings
        )

        #expect(recordings[0].projectId == nil)
        #expect(recordings[0].versionIndex == 1)
    }

    @Test func removeFromProjectClearsBestTake() {
        let recording = TestFixtures.makeRecording()
        let project = TestFixtures.makeProject(bestTakeRecordingId: recording.id)
        var projects = [project]
        var recordings = [TestFixtures.makeRecording(id: recording.id, projectId: project.id)]

        ProjectRepository.removeFromProject(
            recording: recordings[0],
            projects: &projects,
            recordings: &recordings
        )

        #expect(projects[0].bestTakeRecordingId == nil)
    }

    // MARK: - Best Take

    @Test func setBestTake() {
        let project = TestFixtures.makeProject()
        let recording = TestFixtures.makeRecording(projectId: project.id)
        var projects = [project]

        let updated = ProjectRepository.setBestTake(recording, for: project, projects: &projects)
        #expect(updated?.bestTakeRecordingId == recording.id)
    }

    @Test func setBestTakeWrongProject() {
        let project = TestFixtures.makeProject()
        let recording = TestFixtures.makeRecording() // No projectId
        var projects = [project]

        let updated = ProjectRepository.setBestTake(recording, for: project, projects: &projects)
        #expect(updated == nil)
    }

    @Test func clearBestTake() {
        let recId = UUID()
        let project = TestFixtures.makeProject(bestTakeRecordingId: recId)
        var projects = [project]

        let updated = ProjectRepository.clearBestTake(for: project, projects: &projects)
        #expect(updated?.bestTakeRecordingId == nil)
    }

    // MARK: - Update & Pin

    @Test func updateProject() {
        var project = TestFixtures.makeProject(title: "Old")
        var projects = [project]
        project.notes = "Updated notes"

        let updated = ProjectRepository.updateProject(project, projects: &projects)
        #expect(updated?.notes == "Updated notes")
    }

    @Test func toggleProjectPin() {
        let project = TestFixtures.makeProject(pinned: false)
        var projects = [project]

        let updated = ProjectRepository.toggleProjectPin(project, projects: &projects)
        #expect(updated?.pinned == true)
    }

    // MARK: - Delete

    @Test func deleteProjectReleasesRecordings() {
        let project = TestFixtures.makeProject()
        var projects = [project]
        var recordings = [
            TestFixtures.makeRecording(projectId: project.id, versionIndex: 2),
            TestFixtures.makeRecording(title: "Other")
        ]

        let deletedId = ProjectRepository.deleteProject(project, projects: &projects, recordings: &recordings)
        #expect(deletedId == project.id)
        #expect(projects.isEmpty)
        #expect(recordings[0].projectId == nil)
        #expect(recordings[0].versionIndex == 1)
        #expect(recordings[1].title == "Other") // Unchanged
    }
}
