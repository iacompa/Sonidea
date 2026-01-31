//
//  ProjectRepository.swift
//  Sonidea
//
//  Pure data operations for projects, extracted from AppState.
//  Operates on inout arrays with no persistence or sync side effects.
//  AppState handles save/sync after each operation.
//

import Foundation

/// Stateless repository for project data operations.
/// All methods take `inout` arrays and return results.
/// Caller (AppState) is responsible for persistence and sync.
enum ProjectRepository {

    // MARK: - Queries

    static func project(for id: UUID?, in projects: [Project]) -> Project? {
        guard let id = id else { return nil }
        return projects.first { $0.id == id }
    }

    /// Get recordings belonging to a project, sorted by version index.
    /// Only returns active (non-trashed) recordings.
    static func recordings(in project: Project, from allRecordings: [RecordingItem]) -> [RecordingItem] {
        allRecordings
            .filter { !$0.isTrashed && $0.projectId == project.id }
            .sorted { $0.versionIndex < $1.versionIndex }
    }

    static func recordingCount(in project: Project, from recordings: [RecordingItem]) -> Int {
        recordings.filter { !$0.isTrashed && $0.projectId == project.id }.count
    }

    static func nextVersionIndex(for project: Project, recordings: [RecordingItem]) -> Int {
        let versions = Self.recordings(in: project, from: recordings)
        return (versions.map { $0.versionIndex }.max() ?? 0) + 1
    }

    static func bestTake(for project: Project, recordings: [RecordingItem]) -> RecordingItem? {
        guard let bestTakeId = project.bestTakeRecordingId else { return nil }
        return recordings.first { $0.id == bestTakeId }
    }

    static func stats(for project: Project, recordings: [RecordingItem]) -> ProjectStats {
        let versions = Self.recordings(in: project, from: recordings)
        let totalDuration = versions.reduce(0) { $0 + $1.duration }
        let dates = versions.map { $0.createdAt }
        return ProjectStats(
            versionCount: versions.count,
            totalDuration: totalDuration,
            oldestVersion: dates.min(),
            newestVersion: dates.max(),
            hasBestTake: project.bestTakeRecordingId != nil
        )
    }

    /// All projects sorted: pinned first, then by updatedAt descending.
    static func sortedProjects(_ projects: [Project]) -> [Project] {
        projects.sorted { a, b in
            if a.pinned != b.pinned { return a.pinned }
            return a.updatedAt > b.updatedAt
        }
    }

    /// Recordings not belonging to any project.
    static func standaloneRecordings(from recordings: [RecordingItem]) -> [RecordingItem] {
        recordings.filter { !$0.isTrashed && $0.projectId == nil }
    }

    // MARK: - Mutations

    /// Create a project from an existing recording (recording becomes V1).
    @discardableResult
    static func createProject(
        from recording: RecordingItem,
        title: String? = nil,
        projects: inout [Project],
        recordings: inout [RecordingItem]
    ) -> Project {
        let project = Project(
            title: title ?? recording.title,
            createdAt: Date(),
            updatedAt: Date()
        )
        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].projectId = project.id
            recordings[index].parentRecordingId = nil
            recordings[index].versionIndex = 1
            recordings[index].modifiedAt = Date()
        }
        projects.insert(project, at: 0)
        return project
    }

    /// Create a new empty project.
    @discardableResult
    static func createProject(
        title: String,
        projects: inout [Project]
    ) -> Project {
        let project = Project(title: title)
        projects.insert(project, at: 0)
        return project
    }

    /// Add a recording as a new version to an existing project.
    static func addVersion(
        recording: RecordingItem,
        to project: Project,
        projects: inout [Project],
        recordings: inout [RecordingItem]
    ) {
        let nextVersion = nextVersionIndex(for: project, recordings: recordings)
        let versions = Self.recordings(in: project, from: recordings)
        let latestVersion = versions.last

        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].projectId = project.id
            recordings[index].parentRecordingId = latestVersion?.id
            recordings[index].versionIndex = nextVersion
            recordings[index].modifiedAt = Date()
        }

        if let projectIndex = projects.firstIndex(where: { $0.id == project.id }) {
            projects[projectIndex].updatedAt = Date()
        }
    }

    /// Remove a recording from its project (makes it standalone).
    static func removeFromProject(
        recording: RecordingItem,
        projects: inout [Project],
        recordings: inout [RecordingItem]
    ) {
        guard let projectId = recording.projectId else { return }

        if let index = recordings.firstIndex(where: { $0.id == recording.id }) {
            recordings[index].projectId = nil
            recordings[index].parentRecordingId = nil
            recordings[index].versionIndex = 1
            recordings[index].modifiedAt = Date()
        }

        if let projectIndex = projects.firstIndex(where: { $0.id == projectId }) {
            projects[projectIndex].updatedAt = Date()
            if projects[projectIndex].bestTakeRecordingId == recording.id {
                projects[projectIndex].bestTakeRecordingId = nil
            }
        }
    }

    /// Set the best take for a project. Returns the updated project if successful.
    static func setBestTake(
        _ recording: RecordingItem,
        for project: Project,
        projects: inout [Project]
    ) -> Project? {
        guard recording.projectId == project.id else { return nil }
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        projects[index].bestTakeRecordingId = recording.id
        projects[index].updatedAt = Date()
        return projects[index]
    }

    /// Clear the best take for a project. Returns the updated project if successful.
    static func clearBestTake(
        for project: Project,
        projects: inout [Project]
    ) -> Project? {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        projects[index].bestTakeRecordingId = nil
        projects[index].updatedAt = Date()
        return projects[index]
    }

    /// Update project properties. Returns the updated project if successful.
    static func updateProject(
        _ project: Project,
        projects: inout [Project]
    ) -> Project? {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        var updated = project
        updated.updatedAt = Date()
        projects[index] = updated
        return updated
    }

    /// Toggle project pin status. Returns the updated project if successful.
    static func toggleProjectPin(
        _ project: Project,
        projects: inout [Project]
    ) -> Project? {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        projects[index].pinned.toggle()
        projects[index].updatedAt = Date()
        return projects[index]
    }

    /// Delete a project (recordings become standalone). Returns the project ID.
    static func deleteProject(
        _ project: Project,
        projects: inout [Project],
        recordings: inout [RecordingItem]
    ) -> UUID {
        let projectId = project.id
        for i in recordings.indices {
            if recordings[i].projectId == projectId {
                recordings[i].projectId = nil
                recordings[i].parentRecordingId = nil
                recordings[i].versionIndex = 1
                recordings[i].modifiedAt = Date()
            }
        }
        projects.removeAll { $0.id == projectId }
        return projectId
    }
}
