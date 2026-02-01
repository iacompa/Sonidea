//
//  SearchService.swift
//  Sonidea
//
//  Stateless search functions extracted from AppState.
//  Pure functions with no state or side effects.
//  Supports both exact substring matching and fuzzy matching
//  with relevance-based ranking.
//

import Foundation

/// Stateless search service for recordings, albums, and projects.
enum SearchService {

    // MARK: - Fuzzy Matching Threshold

    /// Minimum fuzzy score for a result to be included (0.0–1.0).
    private static let fuzzyThreshold: Double = 0.3

    // MARK: - Recording Search

    /// Search recordings by query text and optional tag filter.
    /// Matches against: title, notes, location, tag names, album name, transcript, project title.
    /// Results are ranked by relevance (exact matches first, then fuzzy).
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

        // Filter and rank by search query
        guard !query.isEmpty else { return results }

        let scored: [(RecordingItem, Double)] = results.compactMap { recording in
            let score = recordingScore(recording, query: query, tags: tags, albums: albums, projects: projects)
            guard score >= fuzzyThreshold else { return nil }
            return (recording, score)
        }

        // Sort by score descending, then by creation date descending for ties
        return scored
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.createdAt > rhs.0.createdAt
            }
            .map(\.0)
    }

    /// Search albums by name with fuzzy matching.
    static func searchAlbums(query: String, albums: [Album]) -> [Album] {
        guard !query.isEmpty else { return albums }

        let scored: [(Album, Double)] = albums.compactMap { album in
            let score = fuzzyScore(query: query, target: album.name)
            guard score >= fuzzyThreshold else { return nil }
            return (album, score)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    /// Search projects by title and notes with fuzzy matching.
    static func searchProjects(query: String, projects: [Project]) -> [Project] {
        guard !query.isEmpty else { return projects }

        let scored: [(Project, Double)] = projects.compactMap { project in
            let titleScore = fuzzyScore(query: query, target: project.title)
            let notesScore = fuzzyScore(query: query, target: project.notes)
            let best = max(titleScore, notesScore)
            guard best >= fuzzyThreshold else { return nil }
            return (project, best)
        }

        return scored
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }

    // MARK: - Scoring

    /// Compute the best fuzzy match score for a recording across all searchable fields.
    private static func recordingScore(
        _ recording: RecordingItem,
        query: String,
        tags: [Tag],
        albums: [Album],
        projects: [Project]
    ) -> Double {
        var best: Double = 0

        // Title (highest weight)
        best = max(best, fuzzyScore(query: query, target: recording.title))

        // Notes
        best = max(best, fuzzyScore(query: query, target: recording.notes))

        // Location
        best = max(best, fuzzyScore(query: query, target: recording.locationLabel))

        // Tag names
        let recordingTags = tagsForIDs(recording.tagIDs, allTags: tags)
        for tag in recordingTags {
            best = max(best, fuzzyScore(query: query, target: tag.name))
        }

        // Album name
        if let albumID = recording.albumID,
           let album = albums.first(where: { $0.id == albumID }) {
            best = max(best, fuzzyScore(query: query, target: album.name))
        }

        // Transcript
        best = max(best, fuzzyScore(query: query, target: recording.transcript))

        // Project title
        if let projectId = recording.projectId,
           let project = projects.first(where: { $0.id == projectId }) {
            best = max(best, fuzzyScore(query: query, target: project.title))
        }

        return best
    }

    // MARK: - Fuzzy Matching

    /// Compute a relevance score (0.0–1.0) between a query and a target string.
    /// - 1.0: exact substring match
    /// - 0.9: all query tokens found as substrings
    /// - 0.5–0.85: all tokens matched with small edit distance (typo tolerance)
    /// - 0.3–0.5: partial token matches
    /// - 0.25: character subsequence match
    /// - 0.0: no match
    static func fuzzyScore(query: String, target: String) -> Double {
        guard !query.isEmpty else { return 0 }
        guard !target.isEmpty else { return 0 }

        let q = query.lowercased()
        let t = target.lowercased()

        // 1. Exact substring — best possible match
        if t.contains(q) { return 1.0 }

        // 2. Token-based matching
        let queryTokens = q.split(separator: " ").map(String.init)
        guard !queryTokens.isEmpty else { return 0 }

        // Check if all query tokens appear as substrings in target
        let allTokensExact = queryTokens.allSatisfy { token in t.contains(token) }
        if allTokensExact { return 0.9 }

        // 3. Per-token fuzzy match using Levenshtein distance
        let targetTokens = t.split(separator: " ").map(String.init)
        var matchedCount = 0
        var totalDistance = 0

        for qToken in queryTokens {
            var bestDistance = Int.max
            // Check against each target token
            for tToken in targetTokens {
                let dist = levenshteinDistance(qToken, tToken)
                bestDistance = min(bestDistance, dist)
            }
            // Also check as substring of full target (for compound words)
            if t.contains(qToken) {
                bestDistance = 0
            }
            // Allow edit distance up to 40% of token length (minimum 1)
            let threshold = max(1, qToken.count * 2 / 5)
            if bestDistance <= threshold {
                matchedCount += 1
                totalDistance += bestDistance
            }
        }

        if matchedCount == queryTokens.count {
            // All tokens matched (some with typo tolerance)
            let avgDistance = Double(totalDistance) / Double(matchedCount)
            return max(0.5, 0.85 - avgDistance * 0.1)
        }

        if matchedCount > 0 {
            // Partial token match — score proportional to matched fraction
            return Double(matchedCount) / Double(queryTokens.count) * 0.5
        }

        // 4. Character subsequence match (all chars of query appear in order in target)
        if isSubsequence(q, of: t) {
            return 0.25
        }

        return 0
    }

    // MARK: - String Algorithms

    /// Check if all characters of `query` appear in order within `target`.
    private static func isSubsequence(_ query: String, of target: String) -> Bool {
        var qi = query.startIndex
        var ti = target.startIndex
        while qi < query.endIndex && ti < target.endIndex {
            if query[qi] == target[ti] {
                qi = query.index(after: qi)
            }
            ti = target.index(after: ti)
        }
        return qi == query.endIndex
    }

    /// Levenshtein edit distance between two strings.
    /// Uses O(min(m,n)) space with two-row optimization.
    private static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let a = Array(s1)
        let b = Array(s2)
        let m = a.count
        let n = b.count

        if m == 0 { return n }
        if n == 0 { return m }

        // Ensure b is the shorter string for space optimization
        if m < n { return levenshteinDistance(s2, s1) }

        var prev = Array(0...n)
        var curr = Array(repeating: 0, count: n + 1)

        for i in 1...m {
            curr[0] = i
            for j in 1...n {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }

        return prev[n]
    }

    // MARK: - Helpers

    /// Resolve tag IDs to Tag objects, preserving order.
    private static func tagsForIDs(_ ids: [UUID], allTags: [Tag]) -> [Tag] {
        ids.compactMap { id in allTags.first { $0.id == id } }
    }
}
