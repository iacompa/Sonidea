//
//  TranscriptSearchService.swift
//  Sonidea
//
//  SQLite FTS5 full-text search for transcripts with fuzzy matching, improved ranking,
//  and incremental indexing for performance at scale.
//

import Foundation
import SQLite3
import os

// MARK: - Search Result Model

struct TranscriptSearchResult: Identifiable {
    let id: Int64
    let recordingId: UUID
    let recordingTitle: String
    let startTime: TimeInterval
    let endTime: TimeInterval
    let segmentText: String
    /// Snippet with <mark> tags around matched words
    let snippet: String
    /// Combined relevance score (higher = more relevant)
    let relevanceScore: Double
    /// Number of matches in this recording
    let occurrenceCount: Int
    /// Recording creation date (for display)
    let recordingCreatedAt: Date
}

// MARK: - Service

actor TranscriptSearchService {
    static let shared = TranscriptSearchService()

    private static let logger = Logger(subsystem: "com.iacompa.sonidea", category: "TranscriptSearch")

    private var db: OpaquePointer?
    private let dbPath: String

    /// Cache of recording metadata for search results
    private var recordingCache: [UUID: RecordingMeta] = [:]

    /// Track last index rebuild for incremental updates (persisted to survive app restarts)
    private var lastFullRebuildDate: Date? {
        get { UserDefaults.standard.object(forKey: "TranscriptSearchLastRebuild") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "TranscriptSearchLastRebuild") }
    }

    /// Track indexed recording IDs and their modified dates
    private var indexedRecordings: [UUID: Date] = [:]

    private struct RecordingMeta {
        let title: String
        let createdAt: Date
    }

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        self.dbPath = appSupport.appendingPathComponent("transcripts.db").path
    }

    // MARK: - Database Setup

    /// Initialize database and FTS5 tables
    func setup() throws {
        guard db == nil else { return }

        var dbPointer: OpaquePointer?
        let result = sqlite3_open(dbPath, &dbPointer)

        guard result == SQLITE_OK, let dbPointer = dbPointer else {
            let errorMessage = String(cString: sqlite3_errmsg(dbPointer))
            Self.logger.error("Failed to open database: \(errorMessage)")
            throw TranscriptSearchError.databaseOpenFailed(errorMessage)
        }

        db = dbPointer

        // Enable WAL mode for better concurrent performance
        try executeSQL("PRAGMA journal_mode = WAL;")
        try executeSQL("PRAGMA synchronous = NORMAL;")

        // Create content table with additional metadata
        let createContentTableSQL = """
        CREATE TABLE IF NOT EXISTS transcripts_segments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            recordingId TEXT NOT NULL,
            segmentIndex INTEGER NOT NULL,
            startTime REAL NOT NULL,
            endTime REAL NOT NULL,
            text TEXT NOT NULL,
            confidence REAL,
            soundex TEXT,
            UNIQUE(recordingId, segmentIndex)
        );
        """

        try executeSQL(createContentTableSQL)

        // Create FTS5 virtual table with trigram tokenizer for fuzzy matching
        // Using trigram tokenizer allows partial word matching and typo tolerance
        let createFTSTableSQL = """
        CREATE VIRTUAL TABLE IF NOT EXISTS transcripts_fts USING fts5(
            recordingId UNINDEXED,
            startTime UNINDEXED,
            endTime UNINDEXED,
            text,
            content = 'transcripts_segments',
            content_rowid = 'id',
            tokenize = 'porter unicode61'
        );
        """

        try executeSQL(createFTSTableSQL)

        // Create trigram table for fuzzy matching
        let createTrigramTableSQL = """
        CREATE TABLE IF NOT EXISTS transcripts_trigrams (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            segmentId INTEGER NOT NULL,
            trigram TEXT NOT NULL,
            FOREIGN KEY(segmentId) REFERENCES transcripts_segments(id) ON DELETE CASCADE
        );
        """

        try executeSQL(createTrigramTableSQL)

        // Migration: Drop ALL old triggers to ensure fresh creation with correct FTS5 external content syntax
        // The old triggers used "DELETE FROM transcripts_fts WHERE rowid = old.id" which doesn't work
        // for external content FTS5 tables. Must use special 'delete' INSERT command.
        try executeSQL("DROP TRIGGER IF EXISTS transcripts_ai;")
        try executeSQL("DROP TRIGGER IF EXISTS transcripts_ad;")
        try executeSQL("DROP TRIGGER IF EXISTS transcripts_au;")

        // Create sync triggers for external content FTS5 table
        // FTS5 external content tables require special INSERT syntax for delete operations:
        // INSERT INTO fts_table(fts_table, rowid, ...) VALUES('delete', old.id, old.columns...)
        let createInsertTriggerSQL = """
        CREATE TRIGGER transcripts_ai AFTER INSERT ON transcripts_segments BEGIN
            INSERT INTO transcripts_fts(rowid, recordingId, startTime, endTime, text)
            VALUES(new.id, new.recordingId, new.startTime, new.endTime, new.text);
        END;
        """

        try executeSQL(createInsertTriggerSQL)

        // For external content FTS5, deletion requires special 'delete' command
        let createDeleteTriggerSQL = """
        CREATE TRIGGER transcripts_ad AFTER DELETE ON transcripts_segments BEGIN
            INSERT INTO transcripts_fts(transcripts_fts, rowid, recordingId, startTime, endTime, text)
            VALUES('delete', old.id, old.recordingId, old.startTime, old.endTime, old.text);
            DELETE FROM transcripts_trigrams WHERE segmentId = old.id;
        END;
        """

        try executeSQL(createDeleteTriggerSQL)

        let createUpdateTriggerSQL = """
        CREATE TRIGGER transcripts_au AFTER UPDATE ON transcripts_segments BEGIN
            INSERT INTO transcripts_fts(transcripts_fts, rowid, recordingId, startTime, endTime, text)
            VALUES('delete', old.id, old.recordingId, old.startTime, old.endTime, old.text);
            DELETE FROM transcripts_trigrams WHERE segmentId = old.id;
            INSERT INTO transcripts_fts(rowid, recordingId, startTime, endTime, text)
            VALUES(new.id, new.recordingId, new.startTime, new.endTime, new.text);
        END;
        """

        try executeSQL(createUpdateTriggerSQL)

        // Create performance indexes
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_segments_recording ON transcripts_segments(recordingId);")
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_trigrams_trigram ON transcripts_trigrams(trigram);")
        try executeSQL("CREATE INDEX IF NOT EXISTS idx_trigrams_segment ON transcripts_trigrams(segmentId);")

        // Note: FTS rebuild is handled by rebuildIndex() on first launch, not here
        // This prevents double-rebuild which can cause stale FTS entries

        Self.logger.info("TranscriptSearchService database initialized")
    }

    // MARK: - Indexing

    /// Index segments after transcription completes
    func indexTranscript(recordingId: UUID, segments: [TranscriptionSegment], title: String, createdAt: Date) throws {
        try ensureDatabase()

        guard !segments.isEmpty else {
            Self.logger.warning("indexTranscript called with empty segments for \(recordingId.uuidString.prefix(8))")
            return
        }

        let recordingIdStr = recordingId.uuidString

        // Store metadata for search results
        recordingCache[recordingId] = RecordingMeta(title: title, createdAt: createdAt)
        indexedRecordings[recordingId] = Date()

        Self.logger.info("Indexing \(segments.count) segments for recording \(recordingId.uuidString.prefix(8)), first segment: '\(segments.first?.text ?? "nil")'")

        // Begin transaction for better performance
        try executeSQL("BEGIN TRANSACTION;")

        defer {
            // Commit or rollback
            try? executeSQL("COMMIT;")
        }

        // Insert segments
        let insertSQL = """
        INSERT OR REPLACE INTO transcripts_segments (recordingId, segmentIndex, startTime, endTime, text, confidence, soundex)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw TranscriptSearchError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for (index, segment) in segments.enumerated() {
            sqlite3_reset(statement)

            let soundexCode = soundex(segment.text)

            sqlite3_bind_text(statement, 1, recordingIdStr, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(statement, 2, Int32(index))
            sqlite3_bind_double(statement, 3, segment.startTime)
            sqlite3_bind_double(statement, 4, segment.startTime + segment.duration)
            sqlite3_bind_text(statement, 5, segment.text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_double(statement, 6, Double(segment.confidence))
            sqlite3_bind_text(statement, 7, soundexCode, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TranscriptSearchError.insertFailed(lastErrorMessage)
            }

            // Get the inserted row ID for trigrams
            let rowId = sqlite3_last_insert_rowid(db)

            // Insert trigrams for fuzzy matching
            try insertTrigrams(for: segment.text, segmentId: rowId)
        }

        Self.logger.info("Indexed \(segments.count) segments for recording \(recordingId.uuidString.prefix(8))")
    }

    /// Insert trigrams for a text segment
    private func insertTrigrams(for text: String, segmentId: Int64) throws {
        let trigrams = generateTrigrams(text)
        guard !trigrams.isEmpty else { return }

        let insertSQL = "INSERT INTO transcripts_trigrams (segmentId, trigram) VALUES (?, ?);"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw TranscriptSearchError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        for trigram in trigrams {
            sqlite3_reset(statement)
            sqlite3_bind_int64(statement, 1, segmentId)
            sqlite3_bind_text(statement, 2, trigram, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            _ = sqlite3_step(statement)  // Best effort - don't fail on trigram insert
        }
    }

    /// Generate trigrams from text for fuzzy matching
    private func generateTrigrams(_ text: String) -> Set<String> {
        let normalized = text.lowercased().filter { $0.isLetter || $0.isWhitespace }
        let words = normalized.split(separator: " ")

        var trigrams = Set<String>()

        for word in words where word.count >= 3 {
            let chars = Array(word)
            for i in 0...(chars.count - 3) {
                let trigram = String(chars[i..<(i + 3)])
                trigrams.insert(trigram)
            }
        }

        return trigrams
    }

    /// Compute Soundex code for phonetic matching
    private func soundex(_ text: String) -> String {
        let words = text.lowercased().split(separator: " ")
        return words.prefix(3).map { soundexWord(String($0)) }.joined(separator: " ")
    }

    private func soundexWord(_ word: String) -> String {
        guard !word.isEmpty else { return "" }

        let chars = Array(word.uppercased())
        var result = [chars[0]]

        let soundexMap: [Character: Character] = [
            "B": "1", "F": "1", "P": "1", "V": "1",
            "C": "2", "G": "2", "J": "2", "K": "2", "Q": "2", "S": "2", "X": "2", "Z": "2",
            "D": "3", "T": "3",
            "L": "4",
            "M": "5", "N": "5",
            "R": "6"
        ]

        var lastCode: Character = "0"
        for char in chars.dropFirst() {
            if let code = soundexMap[char], code != lastCode {
                result.append(code)
                lastCode = code
            } else if !soundexMap.keys.contains(char) {
                lastCode = "0"
            }
            if result.count >= 4 { break }
        }

        while result.count < 4 {
            result.append("0")
        }

        return String(result)
    }

    /// Update segments when transcript is edited/re-generated
    func reindexTranscript(recordingId: UUID, segments: [TranscriptionSegment], title: String, createdAt: Date) throws {
        try removeTranscript(recordingId: recordingId)
        try indexTranscript(recordingId: recordingId, segments: segments, title: title, createdAt: createdAt)
    }

    /// Delete when recording is trashed/deleted
    func removeTranscript(recordingId: UUID) throws {
        try ensureDatabase()

        let deleteSQL = "DELETE FROM transcripts_segments WHERE recordingId = ?;"

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, deleteSQL, -1, &statement, nil) == SQLITE_OK else {
            throw TranscriptSearchError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, recordingId.uuidString, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw TranscriptSearchError.deleteFailed(lastErrorMessage)
        }

        recordingCache.removeValue(forKey: recordingId)
        indexedRecordings.removeValue(forKey: recordingId)

        Self.logger.info("Removed transcript for recording \(recordingId.uuidString.prefix(8))")
    }

    // MARK: - Search

    /// Search with fuzzy matching, improved ranking, and typo tolerance
    func search(query: String, limit: Int = 50) throws -> [TranscriptSearchResult] {
        try ensureDatabase()

        let trimmedQuery = query.trimmingCharacters(in: .whitespaces)
        guard !trimmedQuery.isEmpty else { return [] }

        // Try exact FTS5 search first
        var results = try searchFTS(query: trimmedQuery, limit: limit)

        // If few results, try fuzzy search with trigrams
        if results.count < 5 {
            let fuzzyResults = try searchFuzzy(query: trimmedQuery, limit: limit - results.count)
            // Merge results, avoiding duplicates
            let existingIds = Set(results.map { $0.id })
            for fuzzyResult in fuzzyResults where !existingIds.contains(fuzzyResult.id) {
                results.append(fuzzyResult)
            }
        }

        // Deduplicate by recordingId, keeping highest-scoring segment per recording
        var bestByRecording: [UUID: TranscriptSearchResult] = [:]
        for result in results {
            if let existing = bestByRecording[result.recordingId] {
                if result.relevanceScore > existing.relevanceScore {
                    bestByRecording[result.recordingId] = result
                }
            } else {
                bestByRecording[result.recordingId] = result
            }
        }

        var dedupedResults = Array(bestByRecording.values)

        // Sort by combined relevance score (higher = better)
        dedupedResults.sort { $0.relevanceScore > $1.relevanceScore }

        Self.logger.info("Search '\(trimmedQuery)' returned \(dedupedResults.count) results (from \(results.count) segments)")
        return Array(dedupedResults.prefix(limit))
    }

    /// Standard FTS5 search with BM25 ranking
    private func searchFTS(query: String, limit: Int) throws -> [TranscriptSearchResult] {
        // Build FTS5 query with prefix matching and OR for typo variants
        let ftsQuery = buildFTSQuery(from: query)
        Self.logger.info("FTS query: \(ftsQuery)")

        // Search with BM25 ranking
        // Note: For FTS5 with external content, we query the FTS table first, then join with content
        // Using GROUP BY ts.id to prevent duplicate results from stale FTS entries
        let searchSQL = """
        SELECT
            ts.id,
            ts.recordingId,
            ts.startTime,
            ts.endTime,
            ts.text,
            snippet(transcripts_fts, 3, '<mark>', '</mark>', '...', 15) AS snippet,
            bm25(transcripts_fts) AS bm25_score
        FROM transcripts_fts
        JOIN transcripts_segments ts ON transcripts_fts.rowid = ts.id
        WHERE transcripts_fts MATCH ?
        GROUP BY ts.id
        ORDER BY bm25_score
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK else {
            Self.logger.error("Search prepare failed: \(self.lastErrorMessage)")
            throw TranscriptSearchError.prepareFailed(lastErrorMessage)
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_text(statement, 1, ftsQuery, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int(statement, 2, Int32(limit * 2))  // Fetch more for post-ranking

        let results = try extractResults(from: statement, isFuzzy: false)
        Self.logger.info("FTS search returned \(results.count) results")
        return results
    }

    /// Fuzzy search using trigram similarity for typo tolerance
    private func searchFuzzy(query: String, limit: Int) throws -> [TranscriptSearchResult] {
        let queryTrigrams = generateTrigrams(query)
        guard !queryTrigrams.isEmpty else { return [] }

        // Find segments with matching trigrams
        let placeholders = queryTrigrams.map { _ in "?" }.joined(separator: ", ")

        let searchSQL = """
        SELECT
            ts.id,
            ts.recordingId,
            ts.startTime,
            ts.endTime,
            ts.text,
            ts.text AS snippet,
            COUNT(DISTINCT t.trigram) AS match_count,
            (SELECT COUNT(*) FROM transcripts_segments s2 WHERE s2.recordingId = ts.recordingId) AS occurrence_count
        FROM transcripts_trigrams t
        JOIN transcripts_segments ts ON t.segmentId = ts.id
        WHERE t.trigram IN (\(placeholders))
        GROUP BY ts.id
        HAVING match_count >= ?
        ORDER BY match_count DESC
        LIMIT ?;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, searchSQL, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var paramIndex: Int32 = 1
        for trigram in queryTrigrams {
            sqlite3_bind_text(statement, paramIndex, trigram, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            paramIndex += 1
        }

        // Require at least 30% trigram match
        let minMatches = max(1, Int32(Double(queryTrigrams.count) * 0.3))
        sqlite3_bind_int(statement, paramIndex, minMatches)
        paramIndex += 1
        sqlite3_bind_int(statement, paramIndex, Int32(limit))

        return try extractResults(from: statement, isFuzzy: true)
    }

    /// Extract results from a prepared statement
    private func extractResults(from statement: OpaquePointer?, isFuzzy: Bool) throws -> [TranscriptSearchResult] {
        var results: [TranscriptSearchResult] = []
        let now = Date()

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)

            guard let recordingIdCStr = sqlite3_column_text(statement, 1) else { continue }
            let recordingIdStr = String(cString: recordingIdCStr)
            guard let recordingId = UUID(uuidString: recordingIdStr) else { continue }

            let startTime = sqlite3_column_double(statement, 2)
            let endTime = sqlite3_column_double(statement, 3)

            let segmentText: String
            if let textCStr = sqlite3_column_text(statement, 4) {
                segmentText = String(cString: textCStr)
            } else {
                segmentText = ""
            }

            let snippet: String
            if let snippetCStr = sqlite3_column_text(statement, 5) {
                snippet = String(cString: snippetCStr)
            } else {
                snippet = segmentText
            }

            let rawScore = sqlite3_column_double(statement, 6)
            // For fuzzy search, column 7 is match_count; for FTS search, we default to 1
            let occurrenceCount = isFuzzy ? Int(sqlite3_column_int(statement, 7)) : 1

            // Look up cached metadata
            let meta = recordingCache[recordingId]
            let recordingTitle = meta?.title ?? "Recording"
            let createdAt = meta?.createdAt ?? Date.distantPast

            // Calculate combined relevance score
            let relevanceScore = calculateRelevance(
                bm25Score: isFuzzy ? 0 : rawScore,
                fuzzyMatchCount: isFuzzy ? Int(rawScore) : 0,
                occurrenceCount: occurrenceCount,
                createdAt: createdAt,
                now: now
            )

            let result = TranscriptSearchResult(
                id: id,
                recordingId: recordingId,
                recordingTitle: recordingTitle,
                startTime: startTime,
                endTime: endTime,
                segmentText: segmentText,
                snippet: isFuzzy ? highlightFuzzyMatch(segmentText) : snippet,
                relevanceScore: relevanceScore,
                occurrenceCount: occurrenceCount,
                recordingCreatedAt: createdAt
            )

            results.append(result)
        }

        return results
    }

    /// Calculate combined relevance score
    /// Higher score = more relevant
    private func calculateRelevance(
        bm25Score: Double,
        fuzzyMatchCount: Int,
        occurrenceCount: Int,
        createdAt: Date,
        now: Date
    ) -> Double {
        // BM25 is negative (lower = better), normalize to 0-100
        // Typical BM25 scores range from -25 (very relevant) to 0 (less relevant)
        let bm25Normalized = max(0, 100 + (bm25Score * 4))

        // Fuzzy match score (0-50 based on trigram matches)
        let fuzzyScore = Double(fuzzyMatchCount) * 10

        // Recency boost: recordings from last 7 days get boost, decays over time
        let daysSinceCreation = now.timeIntervalSince(createdAt) / 86400
        let recencyBoost: Double
        if daysSinceCreation < 1 {
            recencyBoost = 30  // Today
        } else if daysSinceCreation < 7 {
            recencyBoost = 20  // This week
        } else if daysSinceCreation < 30 {
            recencyBoost = 10  // This month
        } else {
            recencyBoost = 0
        }

        // Occurrence boost (small, logarithmic to prevent domination)
        let occurrenceBoost = min(15, log(Double(occurrenceCount + 1)) * 5)

        return bm25Normalized + fuzzyScore + recencyBoost + occurrenceBoost
    }

    /// Add basic highlighting to fuzzy match results
    private func highlightFuzzyMatch(_ text: String) -> String {
        // For fuzzy results, we don't have exact match positions
        // Just return the text as-is (could be enhanced later)
        return text
    }

    // MARK: - Incremental Index Rebuild

    /// Rebuild index incrementally - only index new/modified recordings
    func rebuildIndex(from recordings: [RecordingItem]) throws {
        try ensureDatabase()

        // One-time migration to fix stale FTS entries (v2 schema fix)
        let migrationKey = "TranscriptSearchFTSMigrationV2"
        if !UserDefaults.standard.bool(forKey: migrationKey) {
            Self.logger.info("Running one-time FTS migration to fix stale entries")
            try fullRebuild(from: recordings)
            lastFullRebuildDate = Date()
            UserDefaults.standard.set(true, forKey: migrationKey)
            return
        }

        // First time: full rebuild
        if lastFullRebuildDate == nil {
            try fullRebuild(from: recordings)
            lastFullRebuildDate = Date()
            return
        }

        // Incremental: only process changed recordings
        var newCount = 0
        var updatedCount = 0
        var removedCount = 0

        let currentRecordingIds = Set(recordings.map { $0.id })

        // Remove recordings no longer in the list
        for indexedId in indexedRecordings.keys where !currentRecordingIds.contains(indexedId) {
            try? removeTranscript(recordingId: indexedId)
            removedCount += 1
        }

        // Add/update recordings
        for recording in recordings {
            guard let segments = recording.transcriptionSegments, !segments.isEmpty else { continue }

            let existingIndexDate = indexedRecordings[recording.id]

            if existingIndexDate == nil {
                // New recording
                try indexTranscript(
                    recordingId: recording.id,
                    segments: segments,
                    title: recording.title,
                    createdAt: recording.createdAt
                )
                newCount += 1
            } else if recording.modifiedAt > existingIndexDate! {
                // Modified recording
                try reindexTranscript(
                    recordingId: recording.id,
                    segments: segments,
                    title: recording.title,
                    createdAt: recording.createdAt
                )
                updatedCount += 1
            } else {
                // Just update the title cache in case it changed
                recordingCache[recording.id] = RecordingMeta(title: recording.title, createdAt: recording.createdAt)
            }
        }

        // Optimize database periodically (every 100 changes)
        if newCount + updatedCount + removedCount > 100 {
            try? optimizeDatabase()
        }

        Self.logger.info("Incremental rebuild: +\(newCount) new, ~\(updatedCount) updated, -\(removedCount) removed")
    }

    /// Full index rebuild (used on first launch or when needed)
    private func fullRebuild(from recordings: [RecordingItem]) throws {
        // Clear existing data first - DELETE triggers will clean up FTS entries
        // This is more reliable than 'delete-all' for external content FTS tables
        try executeSQL("DELETE FROM transcripts_segments;")
        try executeSQL("DELETE FROM transcripts_trigrams;")

        // Also explicitly clear any orphaned FTS entries (belt and suspenders)
        do {
            try executeSQL("INSERT INTO transcripts_fts(transcripts_fts) VALUES('delete-all');")
        } catch {
            Self.logger.warning("FTS delete-all failed (may be expected if triggers already cleaned up): \(error.localizedDescription)")
        }
        recordingCache.removeAll()
        indexedRecordings.removeAll()

        // Re-index all recordings with segments
        var indexedCount = 0
        for recording in recordings where recording.transcriptionSegments != nil {
            guard let segments = recording.transcriptionSegments, !segments.isEmpty else { continue }
            try indexTranscript(
                recordingId: recording.id,
                segments: segments,
                title: recording.title,
                createdAt: recording.createdAt
            )
            indexedCount += 1
        }

        // Optimize after full rebuild
        try? optimizeDatabase()

        Self.logger.info("Full rebuild completed with \(indexedCount) recordings")
    }

    /// Optimize database for better query performance
    private func optimizeDatabase() throws {
        try executeSQL("INSERT INTO transcripts_fts(transcripts_fts) VALUES('optimize');")
        try executeSQL("ANALYZE;")
        Self.logger.info("Database optimized")
    }

    /// Update cached recording title
    func updateRecordingTitle(recordingId: UUID, title: String) {
        if var meta = recordingCache[recordingId] {
            recordingCache[recordingId] = RecordingMeta(title: title, createdAt: meta.createdAt)
        }
    }

    // MARK: - Private Helpers

    private func ensureDatabase() throws {
        if db == nil {
            try setup()
        }
    }

    private func executeSQL(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

        if result != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
            sqlite3_free(errorMessage)
            throw TranscriptSearchError.executionFailed(message)
        }
    }

    private var lastErrorMessage: String {
        if let db = db {
            return String(cString: sqlite3_errmsg(db))
        }
        return "Database not open"
    }

    /// Build FTS5 query from user input with typo variants
    private func buildFTSQuery(from input: String) -> String {
        let words = input.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }

        var queryParts: [String] = []

        for word in words {
            let escaped = word.replacingOccurrences(of: "\"", with: "\"\"")

            // Generate typo variants for each word
            var variants = ["\"\(escaped)\"*"]  // Original with prefix matching

            // Add common typo variants for words 4+ characters
            if word.count >= 4 {
                // Missing letter variants
                for i in 0..<word.count {
                    var chars = Array(word)
                    chars.remove(at: i)
                    let variant = String(chars)
                    if variant.count >= 3 {
                        variants.append("\"\(variant)\"*")
                    }
                }

                // Swapped adjacent letters
                for i in 0..<(word.count - 1) {
                    var chars = Array(word)
                    chars.swapAt(i, i + 1)
                    let variant = String(chars)
                    variants.append("\"\(variant)\"*")
                }
            }

            // Limit variants to prevent query explosion
            let limitedVariants = Array(variants.prefix(5))
            queryParts.append("(\(limitedVariants.joined(separator: " OR ")))")
        }

        return queryParts.joined(separator: " AND ")
    }
}

// MARK: - Errors

enum TranscriptSearchError: Error, LocalizedError {
    case databaseOpenFailed(String)
    case prepareFailed(String)
    case insertFailed(String)
    case deleteFailed(String)
    case executionFailed(String)

    var errorDescription: String? {
        switch self {
        case .databaseOpenFailed(let msg):
            return "Failed to open transcript database: \(msg)"
        case .prepareFailed(let msg):
            return "Failed to prepare SQL statement: \(msg)"
        case .insertFailed(let msg):
            return "Failed to insert transcript: \(msg)"
        case .deleteFailed(let msg):
            return "Failed to delete transcript: \(msg)"
        case .executionFailed(let msg):
            return "SQL execution failed: \(msg)"
        }
    }
}
