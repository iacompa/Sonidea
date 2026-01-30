//
//  SearchService.swift
//  Sonidea
//
//  Stateless search functions extracted from AppState.
//  Pure functions with no state or side effects.
//

import Foundation

/// Stateless search service for recordings, albums, and projects.
enum SearchService {

    /// Search recordings by query text and optional tag filter.
    /// Matches against: title, notes, location, tag names, album name, transcript, project title.
    static func searchRecordings(
        query: String,
        filterTagIDs: Set<UUID> = [],
        recordings: [RecordingItem],
        tags: [Tag],
        albums: [Album],
        projects: [Project]
    ) -> [RecordingItem] {
        var results = recordings

        // Filter by tags if any selected
        if !filterTagIDs.isEmpty {
            results = results.filter { recording in
                !filterTagIDs.isDisjoint(with: Set(recording.tagIDs))
            }
        }

        // Filter by search query
        if !query.isEmpty {
            let lowercasedQuery = query.lowercased()
            results = results.filter { recording in
                // Match title
                if recording.title.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match notes
                if recording.notes.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match location
                if recording.locationLabel.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match tag names
                let recordingTags = tagsForIDs(recording.tagIDs, allTags: tags)
                if recordingTags.contains(where: { $0.name.lowercased().contains(lowercasedQuery) }) {
                    return true
                }
                // Match album name
                if let albumID = recording.albumID,
                   let album = albums.first(where: { $0.id == albumID }),
                   album.name.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match transcript
                if recording.transcript.lowercased().contains(lowercasedQuery) {
                    return true
                }
                // Match project title
                if let projectId = recording.projectId,
                   let project = projects.first(where: { $0.id == projectId }),
                   project.title.lowercased().contains(lowercasedQuery) {
                    return true
                }
                return false
            }
        }

        return results
    }

    /// Search albums by name.
    static func searchAlbums(query: String, albums: [Album]) -> [Album] {
        guard !query.isEmpty else { return albums }
        let lowercasedQuery = query.lowercased()
        return albums.filter { $0.name.lowercased().contains(lowercasedQuery) }
    }

    /// Search projects by title and notes.
    static func searchProjects(query: String, projects: [Project]) -> [Project] {
        guard !query.isEmpty else { return projects }
        let lowercasedQuery = query.lowercased()
        return projects.filter { project in
            if project.title.lowercased().contains(lowercasedQuery) {
                return true
            }
            if project.notes.lowercased().contains(lowercasedQuery) {
                return true
            }
            return false
        }
    }

    // MARK: - Helpers

    /// Resolve tag IDs to Tag objects, preserving order.
    private static func tagsForIDs(_ ids: [UUID], allTags: [Tag]) -> [Tag] {
        ids.compactMap { id in allTags.first { $0.id == id } }
    }
}
