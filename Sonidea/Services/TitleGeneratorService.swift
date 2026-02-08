//
//  TitleGeneratorService.swift
//  Sonidea
//
//  On-device contextual title generation using Apple Intelligence (iOS 18+) with
//  NaturalLanguage fallback for older devices. Generates 2-4 word titles.
//

import Foundation
import NaturalLanguage

// Try to import FoundationModels for Apple Intelligence (iOS 18+)
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Title Generator Service

enum TitleGeneratorService {

    // MARK: - Public API

    /// Generate contextual title from transcript using Apple Intelligence if available,
    /// with NaturalLanguage fallback. Returns 2-4 word titles.
    /// Returns nil if transcript is too short (<30 words) or no meaningful title generated.
    static func generateTitle(from transcript: String) async -> String? {
        let words = transcript.split(separator: " ")
        guard words.count >= 30 else { return nil }

        // Try Apple Intelligence first (iOS 18+)
        if let aiTitle = await generateWithAppleIntelligence(transcript) {
            return enforceLength(aiTitle)
        }

        // Fallback to NaturalLanguage-based generation
        if let nlTitle = generateWithNaturalLanguage(transcript) {
            return enforceLength(nlTitle)
        }

        return nil
    }

    /// Synchronous version for backward compatibility (uses NaturalLanguage only)
    static func generateTitle(from transcript: String) -> String? {
        let words = transcript.split(separator: " ")
        guard words.count >= 30 else { return nil }

        if let nlTitle = generateWithNaturalLanguage(transcript) {
            return enforceLength(nlTitle)
        }

        return nil
    }

    // MARK: - Apple Intelligence (iOS 26+)

    private static func generateWithAppleIntelligence(_ transcript: String) async -> String? {
        // FoundationModels framework requires iOS 26+ and Apple Silicon
        // Uses on-device language model for intelligent title generation
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, *) else { return nil }

        do {
            // Create session for on-device language model
            let session = LanguageModelSession()

            // Very strict prompt for short titles
            let prompt = """
            Generate a 2-4 word title for this voice memo. Rules:
            - MAXIMUM 4 words, ideally 2-3
            - No articles (a, an, the)
            - No punctuation except hyphens
            - Capitalize each word
            - Be specific and descriptive

            Examples of good titles:
            - "Guitar Practice"
            - "Chemistry Lecture"
            - "Team Standup"
            - "Song Ideas"
            - "Fast Tempo Jam"
            - "Interview Notes"
            - "Morning Journal"

            Transcript excerpt:
            \(String(transcript.prefix(800)))

            Title:
            """

            let response = try await session.respond(to: prompt)
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
                .replacingOccurrences(of: "Title:", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Validate the response is reasonable
            let wordCount = title.split(separator: " ").count
            if wordCount >= 1 && wordCount <= 5 && title.count <= 40 {
                return title
            }

            return nil
        } catch {
            // Apple Intelligence not available or failed, will fall back to NaturalLanguage
            return nil
        }
        #else
        return nil
        #endif
    }

    // MARK: - NaturalLanguage Fallback

    private static func generateWithNaturalLanguage(_ transcript: String) -> String? {
        // 1. Detect language
        let language = detectLanguage(transcript)

        // 2. Extract named entities (people, places, organizations)
        let entities = extractNamedEntities(transcript, language: language)

        // 3. Extract key nouns with frequency weighting
        let keywords = extractKeywords(transcript, language: language)

        // 4. Detect context type (lecture, meeting, practice, etc.)
        let contextType = detectContextType(transcript)

        // 5. Build short title (2-4 words)
        return buildShortTitle(
            entities: entities,
            keywords: keywords,
            contextType: contextType
        )
    }

    // MARK: - Language Detection

    private static func detectLanguage(_ text: String) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? .english
    }

    // MARK: - Named Entity Extraction

    private static func extractNamedEntities(_ text: String, language: NLLanguage) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        var entities: [String] = []
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameType, options: [.omitWhitespace]) { tag, tokenRange in
            if let tag = tag, [.personalName, .placeName, .organizationName].contains(tag) {
                let entity = String(text[tokenRange])
                // Only add if it's a meaningful entity (not too short)
                if entity.count >= 2 && !entities.contains(entity) {
                    entities.append(entity)
                }
            }
            return entities.count < 3  // Only need top 3
        }

        return entities
    }

    // MARK: - Keyword Extraction

    private static func extractKeywords(_ text: String, language: NLLanguage) -> [String] {
        let tagger = NLTagger(tagSchemes: [.nameTypeOrLexicalClass])
        tagger.string = text
        tagger.setLanguage(language, range: text.startIndex..<text.endIndex)

        var termFreq: [String: Int] = [:]
        let range = text.startIndex..<text.endIndex

        tagger.enumerateTags(in: range, unit: .word, scheme: .nameTypeOrLexicalClass, options: [.omitWhitespace, .omitPunctuation]) { tag, tokenRange in
            guard let tag = tag else { return true }
            let word = String(text[tokenRange]).lowercased()

            // Weight by part of speech - prefer nouns
            if tag == .noun && word.count > 3 && !isStopWord(word) {
                termFreq[word, default: 0] += 2
            } else if tag == .adjective && word.count > 3 && !isStopWord(word) {
                termFreq[word, default: 0] += 1
            }
            return true
        }

        // Return top 3 by frequency, capitalized
        return termFreq.sorted { $0.value > $1.value }
            .prefix(3)
            .map { $0.key.capitalized }
    }

    // MARK: - Context Detection

    private static func detectContextType(_ text: String) -> String? {
        let lowered = text.lowercased()

        // Map of context types to their signal words
        let contextSignals: [(type: String, signals: [String])] = [
            ("Lecture", ["lecture", "professor", "chapter", "exam", "homework", "class", "student", "university", "college", "course", "syllabus"]),
            ("Meeting", ["meeting", "agenda", "roadmap", "quarterly", "stakeholder", "action items", "deadline", "standup", "scrum", "sprint"]),
            ("Practice", ["practice", "chord", "scale", "tempo", "metronome", "guitar", "piano", "drums", "bass", "violin", "rehearsal"]),
            ("Interview", ["interview", "candidate", "position", "resume", "hiring", "qualifications"]),
            ("Podcast", ["episode", "podcast", "listeners", "welcome back", "tune in", "subscribe"]),
            ("Ideas", ["idea", "brainstorm", "what if", "concept", "maybe we could"]),
            ("Journal", ["today i", "feeling", "dear diary", "reflecting on"]),
            ("Song", ["verse", "chorus", "bridge", "lyrics", "hook", "melody line"]),
            ("Notes", ["note to self", "remember to", "don't forget", "todo", "reminder"])
        ]

        for (contextType, signals) in contextSignals {
            if signals.contains(where: { lowered.contains($0) }) {
                return contextType
            }
        }

        return nil
    }

    // MARK: - Title Building (Short: 2-4 words)

    private static func buildShortTitle(
        entities: [String],
        keywords: [String],
        contextType: String?
    ) -> String? {

        // Priority 1: Context + Keyword (2 words)
        // Example: "Chemistry Lecture", "Guitar Practice"
        if let context = contextType, let keyword = keywords.first {
            // Put the more specific word first
            if context == "Practice" || context == "Lecture" || context == "Meeting" {
                return "\(keyword) \(context)"
            }
            return "\(context) \(keyword)"
        }

        // Priority 2: Just context type if distinctive
        if let context = contextType, ["Interview", "Podcast", "Journal"].contains(context) {
            if let keyword = keywords.first {
                return "\(keyword) \(context)"
            }
            return context
        }

        // Priority 3: Top 2 keywords
        // Example: "Chemistry Biology"
        if keywords.count >= 2 {
            return "\(keywords[0]) \(keywords[1])"
        }

        // Priority 4: Entity + keyword
        // Example: "Smith Chemistry"
        if let entity = entities.first, let keyword = keywords.first {
            return "\(entity) \(keyword)"
        }

        // Priority 5: Single keyword
        if let keyword = keywords.first {
            return keyword
        }

        // Priority 6: Entity only
        if let entity = entities.first {
            return entity
        }

        return nil
    }

    // MARK: - Length Enforcement

    /// Ensure title is 2-4 words and fits on screen
    private static func enforceLength(_ title: String) -> String {
        var words = title.split(separator: " ").map(String.init)

        // Remove articles if present
        let articles = ["a", "an", "the", "A", "An", "The"]
        words = words.filter { !articles.contains($0) }

        // Limit to 4 words
        if words.count > 4 {
            words = Array(words.prefix(4))
        }

        let result = words.joined(separator: " ")

        // Truncate if still too long (40 chars max for display)
        if result.count > 40 {
            return String(result.prefix(37)) + "..."
        }

        return result
    }

    // MARK: - Stop Words

    private static let stopWords: Set<String> = [
        // Articles & Prepositions
        "the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for",
        "of", "with", "by", "from", "up", "about", "into", "through", "during",
        // Verbs (common)
        "is", "are", "was", "were", "be", "been", "being", "have", "has", "had",
        "do", "does", "did", "will", "would", "could", "should", "may", "might",
        "must", "can",
        // Pronouns
        "this", "that", "these", "those", "i", "you", "he", "she",
        "it", "we", "they", "what", "which", "who", "when", "where", "why", "how",
        // Filler words (common in speech)
        "just", "like", "going", "know", "think", "want", "need", "okay", "yeah",
        "actually", "really", "very", "also", "something", "anything", "nothing",
        "um", "uh", "so", "well", "right", "now", "then", "there", "here",
        "thing", "things", "stuff", "kind", "sort", "basically", "literally",
        "probably", "maybe", "definitely", "certainly", "anyway", "anyways",
        "got", "get", "make", "made", "take", "took", "come", "came", "go", "went"
    ]

    private static func isStopWord(_ word: String) -> Bool {
        stopWords.contains(word.lowercased())
    }
}
