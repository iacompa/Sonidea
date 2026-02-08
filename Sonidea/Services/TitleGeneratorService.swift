//
//  TitleGeneratorService.swift
//  Sonidea
//
//  On-device contextual title generation using Apple Intelligence (iOS 26+) with
//  NaturalLanguage fallback for older devices. Combines transcript analysis with
//  audio classification for intelligent 2-4 word titles.
//

import Foundation
import NaturalLanguage

// Try to import FoundationModels for Apple Intelligence (iOS 26+)
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Audio Context for Naming

/// Audio classification context used for combined naming
struct AudioNamingContext {
    let primaryLabel: String      // Top classifier label (e.g., "acoustic_guitar")
    let confidence: Float         // Classification confidence
    let allLabels: [String]       // All detected labels for context

    init(primaryLabel: String, confidence: Float, allLabels: [String] = []) {
        self.primaryLabel = primaryLabel
        self.confidence = confidence
        self.allLabels = allLabels.isEmpty ? [primaryLabel] : allLabels
    }
}

// MARK: - Title Generator Service

enum TitleGeneratorService {

    // MARK: - Public API

    /// Generate contextual title combining transcript AND audio classification.
    /// This is the primary method that produces the smartest titles.
    /// - Parameters:
    ///   - transcript: The transcribed text (can be empty for instrumental recordings)
    ///   - audioContext: Audio classification result (optional)
    /// - Returns: 2-4 word title, or nil if no meaningful title can be generated
    static func generateTitle(
        from transcript: String?,
        audioContext: AudioNamingContext?
    ) async -> String? {
        let transcriptWords = transcript?.split(separator: " ").count ?? 0
        let hasUsableTranscript = transcriptWords >= 30
        let hasAudioContext = audioContext != nil && audioContext!.confidence >= 0.50

        // Case 1: Both transcript and audio - combine intelligently
        if hasUsableTranscript, let transcript = transcript, let audio = audioContext {
            return await generateCombinedTitle(transcript: transcript, audio: audio)
        }

        // Case 2: Only transcript - use transcript analysis
        if hasUsableTranscript, let transcript = transcript {
            return await generateTitle(from: transcript)
        }

        // Case 3: Only audio classification - use audio-based naming
        if hasAudioContext, let audio = audioContext {
            return generateAudioBasedTitle(audio: audio)
        }

        // Case 4: Neither - return nil
        return nil
    }

    /// Generate contextual title from transcript using Apple Intelligence if available,
    /// with NaturalLanguage fallback. Returns 2-4 word titles.
    /// Returns nil if transcript is too short (<30 words) or no meaningful title generated.
    static func generateTitle(from transcript: String) async -> String? {
        let words = transcript.split(separator: " ")
        guard words.count >= 30 else { return nil }

        // Try Apple Intelligence first (iOS 26+)
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

    // MARK: - Combined Transcript + Audio Title Generation

    /// Generate title using BOTH transcript context AND audio classification
    private static func generateCombinedTitle(transcript: String, audio: AudioNamingContext) async -> String? {
        // Get the audio subject (e.g., "Guitar", "Piano", "Dog")
        guard let audioSubject = audioLabelToSubject[audio.primaryLabel] ?? findSubjectForLabel(audio.primaryLabel) else {
            // No audio mapping - fall back to transcript-only
            return await generateTitle(from: transcript)
        }

        // Detect activity/context from transcript
        let transcriptContext = detectActivityContext(transcript)

        // Check if audio subject matches transcript content
        let loweredTranscript = transcript.lowercased()
        let audioMentioned = audioSubjectMentionedInTranscript(audioSubject, transcript: loweredTranscript)

        // Build combined title
        if let activity = transcriptContext {
            // Transcript has activity context - combine with audio subject
            // e.g., "Guitar Practice", "Piano Lesson", "Drum Session"
            return enforceLength("\(audioSubject) \(activity)")
        } else if audioMentioned {
            // Audio subject mentioned in transcript but no activity detected
            // Try to get more context from transcript keywords
            if let keyword = extractTopKeyword(from: transcript, excluding: audioSubject) {
                return enforceLength("\(audioSubject) \(keyword)")
            }
            return enforceLength("\(audioSubject) Recording")
        } else {
            // Audio and transcript seem unrelated - trust audio for subject, transcript for context
            let language = detectLanguage(transcript)
            let keywords = extractKeywords(transcript, language: language)
            if let keyword = keywords.first {
                return enforceLength("\(audioSubject) \(keyword)")
            }
            return enforceLength("\(audioSubject) Recording")
        }
    }

    /// Generate title from audio classification only (no transcript)
    private static func generateAudioBasedTitle(audio: AudioNamingContext) -> String? {
        guard let subject = audioLabelToSubject[audio.primaryLabel] ?? findSubjectForLabel(audio.primaryLabel) else {
            return nil
        }

        // Check for specific audio contexts based on labels
        let labels = Set(audio.allLabels)

        // Music-specific contexts
        if labels.contains("singing") || labels.contains("choir_singing") {
            if labels.contains(where: { $0.contains("guitar") }) {
                return "Vocal Guitar"
            }
            return "Vocal Recording"
        }

        // Add generic suffix based on category
        let suffix = audioLabelToDefaultSuffix[audio.primaryLabel] ?? "Recording"
        return enforceLength("\(subject) \(suffix)")
    }

    /// Check if audio subject (e.g., "Guitar") is mentioned in transcript
    private static func audioSubjectMentionedInTranscript(_ subject: String, transcript: String) -> Bool {
        let lowered = transcript.lowercased()
        let subjectLower = subject.lowercased()

        // Direct mention
        if lowered.contains(subjectLower) {
            return true
        }

        // Check synonyms
        if let synonyms = subjectSynonyms[subjectLower] {
            return synonyms.contains { lowered.contains($0) }
        }

        return false
    }

    /// Detect activity context from transcript (Practice, Lesson, Session, etc.)
    private static func detectActivityContext(_ transcript: String) -> String? {
        let lowered = transcript.lowercased()

        let activitySignals: [(activity: String, signals: [String])] = [
            ("Practice", ["practice", "practicing", "practise", "practising", "warm up", "warming up", "run through", "work on"]),
            ("Lesson", ["lesson", "teaching", "learning", "tutorial", "instruction", "how to", "showing you"]),
            ("Session", ["session", "jam", "jamming", "recording session", "studio"]),
            ("Rehearsal", ["rehearsal", "rehearse", "rehearsing", "run-through", "sound check"]),
            ("Performance", ["performance", "perform", "performing", "concert", "gig", "show", "recital"]),
            ("Warmup", ["warmup", "warm-up", "warming up", "exercise", "exercises", "drill", "drills"]),
            ("Cover", ["cover", "covering", "cover version", "rendition"]),
            ("Original", ["original", "new song", "wrote", "writing", "composing", "composition"]),
            ("Test", ["test", "testing", "trying out", "checking", "mic check", "sound test"]),
            ("Demo", ["demo", "demonstration", "sample", "example"]),
            ("Ideas", ["idea", "ideas", "brainstorm", "experiment", "experimenting", "trying"]),
        ]

        for (activity, signals) in activitySignals {
            if signals.contains(where: { lowered.contains($0) }) {
                return activity
            }
        }

        return nil
    }

    /// Extract top keyword excluding a specific word
    private static func extractTopKeyword(from transcript: String, excluding: String) -> String? {
        let language = detectLanguage(transcript)
        let keywords = extractKeywords(transcript, language: language)
        let excludedLower = excluding.lowercased()

        return keywords.first { $0.lowercased() != excludedLower }
    }

    // MARK: - Comprehensive Audio Label Mappings

    /// Map SoundAnalysis labels to human-readable subjects for naming
    /// Covers all 300+ Apple classifier labels
    private static let audioLabelToSubject: [String: String] = [
        // MARK: String Instruments
        "acoustic_guitar": "Guitar",
        "electric_guitar": "Guitar",
        "bass_guitar": "Bass",
        "guitar": "Guitar",
        "guitar_strum": "Guitar",
        "guitar_tapping": "Guitar",
        "steel_guitar_slide_guitar": "Slide Guitar",
        "violin_fiddle": "Violin",
        "cello": "Cello",
        "double_bass": "Bass",
        "bowed_string_instrument": "Strings",
        "plucked_string_instrument": "Strings",
        "harp": "Harp",
        "mandolin": "Mandolin",
        "banjo": "Banjo",
        "sitar": "Sitar",
        "zither": "Zither",
        "ukulele": "Ukulele",

        // MARK: Keyboard Instruments
        "piano": "Piano",
        "electric_piano": "Piano",
        "keyboard_musical": "Keyboard",
        "synthesizer": "Synth",
        "organ": "Organ",
        "electronic_organ": "Organ",
        "hammond_organ": "Organ",
        "harpsichord": "Harpsichord",
        "accordion": "Accordion",
        "concertina": "Concertina",

        // MARK: Percussion
        "drum": "Drums",
        "drum_kit": "Drums",
        "bass_drum": "Drums",
        "snare_drum": "Snare",
        "timpani": "Timpani",
        "tabla": "Tabla",
        "cymbal": "Cymbals",
        "hi_hat": "Hi-Hat",
        "tambourine": "Tambourine",
        "mallet_percussion": "Mallets",
        "gong": "Gong",
        "marimba_xylophone": "Marimba",
        "vibraphone": "Vibes",
        "glockenspiel": "Glockenspiel",
        "steelpan": "Steel Pan",
        "rattle_instrument": "Shaker",
        "cowbell": "Cowbell",

        // MARK: Wind Instruments
        "flute": "Flute",
        "oboe": "Oboe",
        "clarinet": "Clarinet",
        "bassoon": "Bassoon",
        "saxophone": "Sax",
        "trumpet": "Trumpet",
        "trombone": "Trombone",
        "french_horn": "French Horn",
        "brass_instrument": "Brass",
        "wind_instrument": "Winds",
        "bagpipes": "Bagpipes",
        "didgeridoo": "Didgeridoo",
        "harmonica": "Harmonica",
        "shofar": "Shofar",

        // MARK: Voice & Vocals
        "singing": "Vocal",
        "choir_singing": "Choir",
        "rapping": "Rap",
        "yodeling": "Yodel",
        "humming": "Humming",
        "whistling": "Whistling",
        "speech": "Voice",
        "talking": "Voice",
        "whispering": "Whisper",
        "narration": "Narration",
        "shout": "Shout",
        "yell": "Yell",
        "screaming": "Scream",
        "battle_cry": "Battle Cry",
        "laughter": "Laughter",
        "giggling": "Giggling",
        "chuckle_chortle": "Chuckle",
        "snicker": "Snicker",
        "belly_laugh": "Laughter",
        "crying_sobbing": "Crying",
        "baby_crying": "Baby",

        // MARK: Body Sounds
        "cough": "Cough",
        "sneeze": "Sneeze",
        "breathing": "Breathing",
        "snoring": "Snoring",
        "gasp": "Gasp",
        "sigh": "Sigh",
        "burp": "Burp",
        "hiccup": "Hiccup",
        "gargling": "Gargling",
        "nose_blowing": "Nose Blow",
        "chewing": "Chewing",
        "slurp": "Slurp",
        "biting": "Biting",

        // MARK: Human Actions
        "applause": "Applause",
        "clapping": "Clapping",
        "cheering": "Cheering",
        "crowd": "Crowd",
        "babble": "Babble",
        "children_shouting": "Children",
        "children_playing": "Children",
        "finger_snapping": "Snap",

        // MARK: Animals - Dogs
        "dog_bark": "Dog",
        "dog_growl": "Dog",
        "dog_whimper": "Dog",
        "dog_bow_wow": "Dog",
        "dog_howl": "Dog",

        // MARK: Animals - Cats
        "cat_meow": "Cat",
        "cat_purr": "Cat",

        // MARK: Animals - Birds
        "bird_chirp_tweet": "Bird",
        "bird_squawk": "Bird",
        "bird_vocalization": "Bird",
        "bird_flapping": "Bird",
        "bird": "Bird",
        "crow_caw": "Crow",
        "pigeon_dove_coo": "Dove",
        "owl_hoot": "Owl",
        "rooster_crow": "Rooster",
        "chicken_cluck": "Chicken",
        "chicken": "Chicken",
        "turkey_gobble": "Turkey",
        "duck_quack": "Duck",
        "goose_honk": "Goose",

        // MARK: Animals - Other
        "cow_moo": "Cow",
        "pig_oink": "Pig",
        "horse_neigh": "Horse",
        "horse_clip_clop": "Horse",
        "frog_croak": "Frog",
        "frog": "Frog",
        "snake_hiss": "Snake",
        "snake_rattle": "Rattlesnake",
        "whale_vocalization": "Whale",
        "lion_roar": "Lion",
        "coyote_howl": "Coyote",
        "elk_bugle": "Elk",

        // MARK: Insects
        "bee_buzz": "Bee",
        "insect": "Insect",
        "fly_buzz": "Fly",
        "mosquito_buzz": "Mosquito",
        "cricket_chirp": "Cricket",

        // MARK: Nature Sounds
        "rain": "Rain",
        "raindrop": "Rain",
        "thunder": "Thunder",
        "thunderstorm": "Storm",
        "wind": "Wind",
        "wind_noise_microphone": "Wind",
        "wind_rustling_leaves": "Wind",
        "fire": "Fire",
        "fire_crackle": "Fire",
        "sea_waves": "Ocean",
        "ocean": "Ocean",
        "stream_burbling": "Stream",
        "waterfall": "Waterfall",
        "underwater_bubbling": "Underwater",

        // MARK: Water Sounds
        "water": "Water",
        "water_tap_faucet": "Faucet",
        "water_pump": "Water Pump",
        "liquid_dripping": "Dripping",
        "liquid_filling_container": "Filling",
        "liquid_pouring": "Pouring",
        "liquid_splashing": "Splash",
        "liquid_sloshing": "Sloshing",
        "liquid_trickle_dribble": "Trickling",
        "toilet_flush": "Toilet",

        // MARK: Vehicles
        "car_horn": "Car Horn",
        "car_passing_by": "Car",
        "engine_starting": "Engine",
        "engine_idling": "Engine",
        "engine_accelerating_revving": "Engine",
        "engine_knocking": "Engine",
        "vehicle_skidding": "Skid",
        "race_car": "Race Car",
        "bus": "Bus",
        "truck": "Truck",
        "motorcycle": "Motorcycle",
        "bicycle": "Bicycle",
        "train": "Train",
        "train_horn": "Train",
        "train_whistle": "Train",
        "train_wheels_squealing": "Train",
        "rail_transport": "Train",
        "subway_metro": "Subway",
        "airplane": "Airplane",
        "aircraft": "Aircraft",
        "helicopter": "Helicopter",
        "boat_water_vehicle": "Boat",
        "motorboat_speedboat": "Speedboat",
        "rowboat_canoe_kayak": "Kayak",

        // MARK: Emergency & Alarms
        "siren": "Siren",
        "police_siren": "Police",
        "fire_engine_siren": "Fire Truck",
        "ambulance_siren": "Ambulance",
        "emergency_vehicle": "Emergency",
        "alarm_clock": "Alarm",
        "clock": "Clock",
        "tick_tock": "Clock",
        "tick": "Ticking",
        "civil_defense_siren": "Siren",
        "smoke_detector": "Smoke Alarm",
        "fire_alarm": "Fire Alarm",

        // MARK: Bells & Chimes
        "bell": "Bell",
        "church_bell": "Church Bell",
        "bicycle_bell": "Bike Bell",
        "door_bell": "Doorbell",
        "wind_chime": "Wind Chime",
        "singing_bowl": "Singing Bowl",
        "telephone_bell_ringing": "Phone",
        "telephone": "Phone",
        "ringtone": "Ringtone",

        // MARK: Impacts & Crashes
        "crash": "Crash",
        "boom": "Boom",
        "thump_thud": "Thump",
        "slap_smack": "Slap",
        "glass_breaking": "Glass Break",
        "fireworks": "Fireworks",
        "firecracker": "Firecracker",
        "gunshot_gunfire": "Gunshot",
        "explosion": "Explosion",
        "artillery_fire": "Artillery",

        // MARK: Tools & Machines
        "power_tool": "Power Tool",
        "drill": "Drill",
        "hammer": "Hammer",
        "saw": "Saw",
        "scissors": "Scissors",
        "cutting": "Cutting",
        "lawn_mower": "Lawn Mower",
        "chainsaw": "Chainsaw",
        "vacuum_cleaner": "Vacuum",
        "blender": "Blender",
        "hair_dryer": "Hair Dryer",
        "electric_shaver": "Shaver",
        "toothbrush": "Toothbrush",
        "mechanical_fan": "Fan",
        "ratchet_and_pawl": "Ratchet",
        "engine": "Engine",
        "microwave_oven": "Microwave",
        "washing_machine": "Washer",
        "dishwasher": "Dishwasher",
        "air_conditioner": "AC",
        "sewing_machine": "Sewing",

        // MARK: Doors & Keys
        "door": "Door",
        "door_slam": "Door Slam",
        "door_sliding": "Sliding Door",
        "door_open_close": "Door",
        "knock": "Knock",
        "keys_jangling": "Keys",

        // MARK: Typing & Clicking
        "tap": "Tap",
        "click": "Click",
        "clicking": "Clicking",
        "typing": "Typing",
        "typing_computer_keyboard": "Typing",
        "keyboard": "Keyboard",

        // MARK: Camera & Office
        "camera": "Camera",
        "printing": "Printing",
        "printer": "Printer",

        // MARK: Music General
        "music": "Music",
        "orchestra": "Orchestra",
        "musical_ensemble": "Ensemble",
        "tuning_fork": "Tuning",

        // MARK: Sports
        "playing_tennis": "Tennis",
        "playing_badminton": "Badminton",
        "basketball_bounce": "Basketball",
        "playing_table_tennis": "Ping Pong",
        "skateboard": "Skateboard",
        "skiing": "Skiing",
        "person_running": "Running",
        "person_walking": "Walking",
        "rope_skipping": "Jump Rope",
    ]

    /// Default suffix when no transcript context is available
    private static let audioLabelToDefaultSuffix: [String: String] = [
        // Music-related get "Recording" or specific suffix
        "acoustic_guitar": "Recording",
        "electric_guitar": "Recording",
        "piano": "Recording",
        "drums": "Recording",
        "singing": "Recording",
        "violin_fiddle": "Recording",

        // Animals get "Audio"
        "dog_bark": "Audio",
        "cat_meow": "Audio",
        "bird": "Audio",

        // Nature gets "Ambience"
        "rain": "Ambience",
        "thunder": "Ambience",
        "wind": "Ambience",
        "ocean": "Ambience",
        "fire": "Ambience",

        // Vehicles get "Sound"
        "car_horn": "Sound",
        "train": "Sound",
        "airplane": "Sound",
    ]

    /// Synonyms for audio subjects (for matching in transcripts)
    private static let subjectSynonyms: [String: [String]] = [
        "guitar": ["acoustic", "electric", "strat", "stratocaster", "les paul", "fender", "gibson", "telecaster", "axe"],
        "piano": ["keys", "keyboard", "grand", "upright", "steinway", "yamaha piano"],
        "drums": ["kit", "drum set", "percussion", "snare", "kick", "cymbals", "hi-hat"],
        "bass": ["bass guitar", "four string", "fender bass"],
        "violin": ["fiddle", "viola"],
        "sax": ["saxophone", "alto sax", "tenor sax", "soprano sax"],
        "trumpet": ["horn", "brass"],
        "vocal": ["voice", "singing", "vocals", "vocalist"],
        "synth": ["synthesizer", "keyboard", "moog", "analog synth"],
    ]

    /// Find subject for labels not in the main dictionary (fuzzy matching)
    private static func findSubjectForLabel(_ label: String) -> String? {
        // Try partial matching
        let labelLower = label.lowercased()

        // Check if label contains a known instrument
        let instruments = ["guitar", "piano", "drum", "bass", "violin", "flute", "trumpet", "sax", "organ", "harp"]
        for instrument in instruments {
            if labelLower.contains(instrument) {
                return instrument.capitalized
            }
        }

        // Check for animal sounds
        let animals = ["dog", "cat", "bird", "horse", "cow", "pig", "frog", "snake", "whale", "lion"]
        for animal in animals {
            if labelLower.contains(animal) {
                return animal.capitalized
            }
        }

        // Check for nature
        if labelLower.contains("rain") || labelLower.contains("water") { return "Water" }
        if labelLower.contains("wind") { return "Wind" }
        if labelLower.contains("thunder") || labelLower.contains("storm") { return "Storm" }
        if labelLower.contains("fire") { return "Fire" }

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

    // MARK: - Duplicate Title Handling

    /// Make a title unique by appending a number if it already exists
    /// - Parameters:
    ///   - title: The proposed title
    ///   - existingTitles: Set of all existing recording titles
    /// - Returns: Unique title (e.g., "Guitar Recording" → "Guitar Recording 2")
    static func makeUnique(_ title: String, existingTitles: Set<String>) -> String {
        // If title doesn't exist, return as-is
        if !existingTitles.contains(title) {
            return title
        }

        // Check for existing numbered versions and find the next number
        // Pattern: "Title", "Title 2", "Title 3", etc.
        var nextNumber = 2
        while existingTitles.contains("\(title) \(nextNumber)") {
            nextNumber += 1
        }

        return "\(title) \(nextNumber)"
    }

    /// Extract base title and number from a potentially numbered title
    /// - Parameter title: Title that may have a number suffix (e.g., "Guitar Recording 3")
    /// - Returns: Tuple of (baseTitle, number?) - number is nil if no suffix
    static func parseNumberedTitle(_ title: String) -> (base: String, number: Int?) {
        // Check if title ends with " N" where N is a number
        let components = title.split(separator: " ")
        guard components.count >= 2,
              let lastComponent = components.last,
              let number = Int(lastComponent),
              number >= 2 else {
            return (title, nil)
        }

        // Reconstruct base title without the number
        let baseComponents = components.dropLast()
        let base = baseComponents.joined(separator: " ")
        return (base, number)
    }
}
