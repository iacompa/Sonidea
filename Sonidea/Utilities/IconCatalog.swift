//
//  IconCatalog.swift
//  Sonidea
//
//  Single source of truth for all recording icons.
//  Defines categories, SF Symbols, display names, and SoundAnalysis label mappings.
//

import Foundation

// MARK: - Icon Category

/// Categories for organizing icons in the picker (order matters for display)
enum IconCategory: String, CaseIterable, Identifiable {
    case music = "Music"
    case sounds = "Sounds"
    case voice = "Voice"
    case animals = "Animals"
    case nature = "Nature"
    case vehicles = "Vehicles"
    case other = "Other"

    var id: String { rawValue }

    var displayOrder: Int {
        switch self {
        case .music: return 0
        case .sounds: return 1
        case .voice: return 2
        case .animals: return 3
        case .nature: return 4
        case .vehicles: return 5
        case .other: return 6
        }
    }

    /// Per-category confidence threshold for auto-assigning an icon
    var autoAssignThreshold: Float {
        switch self {
        case .voice: return 0.75
        case .music: return 0.75
        case .animals: return 0.80
        case .nature: return 0.80
        case .vehicles: return 0.80
        case .sounds: return 0.85
        case .other: return 0.85
        }
    }
}

// MARK: - Icon Definition

/// Definition of a single icon with its metadata and classifier label mappings
struct IconDefinition: Identifiable, Hashable {
    let id: String  // Unique identifier (same as sfSymbol for simplicity)
    let sfSymbol: String
    let displayName: String
    let category: IconCategory
    let classifierLabels: Set<String>  // Apple SoundAnalysis labels that map to this icon

    init(sfSymbol: String, displayName: String, category: IconCategory, classifierLabels: [String] = []) {
        self.id = "\(category.rawValue)_\(sfSymbol)"
        self.sfSymbol = sfSymbol
        self.displayName = displayName
        self.category = category
        self.classifierLabels = Set(classifierLabels)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: IconDefinition, rhs: IconDefinition) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Icon Catalog

/// Central catalog of all available icons
struct IconCatalog {

    /// All icon definitions
    static let allIcons: [IconDefinition] = [
        // MARK: - Music (first)
        IconDefinition(sfSymbol: "music.note", displayName: "Music", category: .music,
                      classifierLabels: ["music", "orchestra", "musical_ensemble"]),
        IconDefinition(sfSymbol: "music.note.list", displayName: "Piano", category: .music,
                      classifierLabels: ["piano", "electric_piano", "keyboard_musical", "synthesizer",
                                        "organ", "electronic_organ", "hammond_organ", "harpsichord"]),
        IconDefinition(sfSymbol: "music.quarternote.3", displayName: "Notes", category: .music),
        IconDefinition(sfSymbol: "cylinder.fill", displayName: "Drums", category: .music,
                      classifierLabels: ["drum", "drum_kit", "bass_drum", "snare_drum", "timpani", "tabla",
                                        "cymbal", "hi_hat", "tambourine", "mallet_percussion", "gong",
                                        "marimba_xylophone", "vibraphone", "glockenspiel", "steelpan",
                                        "rattle_instrument", "cowbell"]),
        IconDefinition(sfSymbol: "music.mic", displayName: "Vocal", category: .music,
                      classifierLabels: ["singing", "choir_singing", "rapping", "yodeling", "humming", "whistling"]),
        IconDefinition(sfSymbol: "tuningfork", displayName: "Tuning", category: .music),
        IconDefinition(sfSymbol: "metronome", displayName: "Metronome", category: .music),
        IconDefinition(sfSymbol: "amplifier", displayName: "Amp", category: .music),
        IconDefinition(sfSymbol: "hifispeaker.fill", displayName: "Speaker", category: .music),
        IconDefinition(sfSymbol: "headphones", displayName: "Headphones", category: .music),
        IconDefinition(sfSymbol: "earpods", displayName: "Earbuds", category: .music),
        IconDefinition(sfSymbol: "radio.fill", displayName: "Radio", category: .music),
        IconDefinition(sfSymbol: "hifispeaker.2.fill", displayName: "Stereo", category: .music),
        // String instruments (includes guitar classifier labels)
        IconDefinition(sfSymbol: "guitars", displayName: "Guitar / Strings", category: .music,
                      classifierLabels: ["acoustic_guitar", "electric_guitar", "bass_guitar", "guitar",
                                        "guitar_strum", "guitar_tapping", "steel_guitar_slide_guitar",
                                        "violin_fiddle", "cello", "double_bass", "bowed_string_instrument",
                                        "plucked_string_instrument", "harp", "mandolin", "banjo", "sitar",
                                        "zither", "ukulele", "accordion", "concertina"]),
        // Wind instruments
        IconDefinition(sfSymbol: "wind", displayName: "Wind", category: .music,
                      classifierLabels: ["flute", "oboe", "clarinet", "bassoon", "saxophone", "trumpet",
                                        "trombone", "french_horn", "brass_instrument", "wind_instrument",
                                        "bagpipes", "didgeridoo", "harmonica", "tuning_fork", "shofar"]),
        IconDefinition(sfSymbol: "waveform.badge.mic", displayName: "Recording", category: .music),

        // MARK: - Sounds (second)
        IconDefinition(sfSymbol: "waveform", displayName: "Waveform", category: .sounds),
        IconDefinition(sfSymbol: "waveform.circle", displayName: "Audio", category: .sounds),
        IconDefinition(sfSymbol: "speaker.wave.2.fill", displayName: "Sound", category: .sounds),
        IconDefinition(sfSymbol: "speaker.wave.3.fill", displayName: "Loud", category: .sounds,
                      classifierLabels: ["shout", "yell", "screaming", "battle_cry"]),
        IconDefinition(sfSymbol: "bell.fill", displayName: "Bell", category: .sounds,
                      classifierLabels: ["bell", "church_bell", "bicycle_bell", "door_bell", "wind_chime",
                                        "singing_bowl", "telephone_bell_ringing"]),
        IconDefinition(sfSymbol: "alarm.fill", displayName: "Alarm", category: .sounds,
                      classifierLabels: ["alarm_clock", "clock", "tick_tock", "tick", "siren",
                                        "civil_defense_siren", "smoke_detector", "fire_alarm"]),
        IconDefinition(sfSymbol: "phone.fill", displayName: "Phone", category: .sounds,
                      classifierLabels: ["telephone", "ringtone"]),
        IconDefinition(sfSymbol: "hand.tap.fill", displayName: "Tap", category: .sounds,
                      classifierLabels: ["knock", "tap", "click", "clicking", "typing",
                                        "typing_computer_keyboard", "keyboard", "finger_snapping"]),
        IconDefinition(sfSymbol: "hand.raised.fill", displayName: "Clap", category: .sounds,
                      classifierLabels: ["applause", "clapping", "cheering"]),
        IconDefinition(sfSymbol: "burst.fill", displayName: "Impact", category: .sounds,
                      classifierLabels: ["crash", "boom", "thump_thud", "slap_smack", "glass_breaking",
                                        "fireworks", "firecracker", "gunshot_gunfire", "explosion", "artillery_fire"]),
        IconDefinition(sfSymbol: "wrench.and.screwdriver.fill", displayName: "Tools", category: .sounds,
                      classifierLabels: ["power_tool", "drill", "hammer", "saw", "scissors", "cutting",
                                        "lawn_mower", "chainsaw", "vacuum_cleaner", "blender",
                                        "hair_dryer", "electric_shaver", "toothbrush"]),
        IconDefinition(sfSymbol: "door.left.hand.open", displayName: "Door", category: .sounds,
                      classifierLabels: ["door", "door_slam", "door_sliding", "door_open_close"]),
        IconDefinition(sfSymbol: "key.fill", displayName: "Keys", category: .sounds,
                      classifierLabels: ["keys_jangling"]),
        IconDefinition(sfSymbol: "camera.fill", displayName: "Camera", category: .sounds,
                      classifierLabels: ["camera"]),
        IconDefinition(sfSymbol: "printer.fill", displayName: "Printer", category: .sounds,
                      classifierLabels: ["printing", "printer"]),
        IconDefinition(sfSymbol: "gearshape.fill", displayName: "Mechanical", category: .sounds,
                      classifierLabels: ["mechanical_fan", "ratchet_and_pawl", "engine",
                                        "microwave_oven", "washing_machine", "dishwasher",
                                        "air_conditioner", "sewing_machine"]),
        IconDefinition(sfSymbol: "megaphone.fill", displayName: "Announcement", category: .sounds,
                      classifierLabels: ["air_horn"]),

        // MARK: - Voice (third)
        IconDefinition(sfSymbol: "mic.fill", displayName: "Mic", category: .voice,
                      classifierLabels: ["speech", "talking"]),
        IconDefinition(sfSymbol: "person.fill", displayName: "Person", category: .voice),
        IconDefinition(sfSymbol: "person.2.fill", displayName: "People", category: .voice,
                      classifierLabels: ["crowd", "babble", "children_shouting", "children_playing"]),
        IconDefinition(sfSymbol: "person.wave.2.fill", displayName: "Greeting", category: .voice),
        IconDefinition(sfSymbol: "bubble.left.fill", displayName: "Speech", category: .voice,
                      classifierLabels: ["whispering", "narration"]),
        IconDefinition(sfSymbol: "bubble.left.and.bubble.right.fill", displayName: "Conversation", category: .voice),
        IconDefinition(sfSymbol: "face.smiling.fill", displayName: "Laughter", category: .voice,
                      classifierLabels: ["laughter", "giggling", "chuckle_chortle", "snicker", "belly_laugh"]),
        IconDefinition(sfSymbol: "face.dashed.fill", displayName: "Crying", category: .voice,
                      classifierLabels: ["crying_sobbing", "baby_crying"]),
        IconDefinition(sfSymbol: "mouth.fill", displayName: "Voice", category: .voice,
                      classifierLabels: ["cough", "sneeze", "breathing", "snoring", "gasp", "sigh", "burp", "hiccup",
                                        "gargling", "nose_blowing", "chewing", "slurp", "biting"]),
        IconDefinition(sfSymbol: "person.crop.circle.fill", displayName: "Portrait", category: .voice),
        IconDefinition(sfSymbol: "theatermasks.fill", displayName: "Performance", category: .voice),
        IconDefinition(sfSymbol: "video.fill", displayName: "Video", category: .voice),
        IconDefinition(sfSymbol: "quote.bubble.fill", displayName: "Quote", category: .voice),

        // MARK: - Animals
        IconDefinition(sfSymbol: "dog.fill", displayName: "Dog", category: .animals,
                      classifierLabels: ["dog_bark", "dog_growl", "dog_whimper", "dog_bow_wow", "dog_howl"]),
        IconDefinition(sfSymbol: "cat.fill", displayName: "Cat", category: .animals,
                      classifierLabels: ["cat_meow", "cat_purr"]),
        IconDefinition(sfSymbol: "hare.fill", displayName: "Rabbit", category: .animals),
        IconDefinition(sfSymbol: "tortoise.fill", displayName: "Turtle", category: .animals),
        IconDefinition(sfSymbol: "bird.fill", displayName: "Bird", category: .animals,
                      classifierLabels: ["bird_chirp_tweet", "bird_squawk", "bird_vocalization", "bird_flapping",
                                        "bird", "crow_caw", "pigeon_dove_coo", "owl_hoot", "rooster_crow",
                                        "chicken_cluck", "chicken", "turkey_gobble", "duck_quack", "goose_honk"]),
        IconDefinition(sfSymbol: "ant.fill", displayName: "Insect", category: .animals,
                      classifierLabels: ["bee_buzz", "insect", "fly_buzz", "mosquito_buzz", "cricket_chirp"]),
        IconDefinition(sfSymbol: "ladybug.fill", displayName: "Bug", category: .animals),
        IconDefinition(sfSymbol: "fish.fill", displayName: "Fish", category: .animals),
        IconDefinition(sfSymbol: "pawprint.fill", displayName: "Animal", category: .animals,
                      classifierLabels: ["cow_moo", "pig_oink", "horse_neigh", "horse_clip_clop",
                                        "frog_croak", "frog", "snake_hiss", "snake_rattle",
                                        "whale_vocalization", "lion_roar", "coyote_howl", "elk_bugle"]),

        // MARK: - Nature
        IconDefinition(sfSymbol: "drop.fill", displayName: "Water", category: .nature,
                      classifierLabels: ["water", "water_tap_faucet", "water_pump", "liquid_dripping",
                                        "liquid_filling_container", "liquid_pouring", "liquid_splashing",
                                        "liquid_sloshing", "liquid_trickle_dribble", "toilet_flush"]),
        IconDefinition(sfSymbol: "cloud.rain.fill", displayName: "Rain", category: .nature,
                      classifierLabels: ["rain", "raindrop"]),
        IconDefinition(sfSymbol: "cloud.bolt.fill", displayName: "Thunder", category: .nature,
                      classifierLabels: ["thunder", "thunderstorm"]),
        IconDefinition(sfSymbol: "wind", displayName: "Wind", category: .nature,
                      classifierLabels: ["wind", "wind_noise_microphone", "wind_rustling_leaves"]),
        IconDefinition(sfSymbol: "flame.fill", displayName: "Fire", category: .nature,
                      classifierLabels: ["fire", "fire_crackle"]),
        IconDefinition(sfSymbol: "leaf.fill", displayName: "Leaf", category: .nature),
        IconDefinition(sfSymbol: "tree.fill", displayName: "Tree", category: .nature),
        IconDefinition(sfSymbol: "mountain.2.fill", displayName: "Mountain", category: .nature),
        IconDefinition(sfSymbol: "water.waves", displayName: "Ocean", category: .nature,
                      classifierLabels: ["sea_waves", "ocean", "stream_burbling", "waterfall", "underwater_bubbling"]),
        IconDefinition(sfSymbol: "sun.max.fill", displayName: "Sun", category: .nature),
        IconDefinition(sfSymbol: "moon.fill", displayName: "Moon", category: .nature),
        IconDefinition(sfSymbol: "sparkles", displayName: "Sparkles", category: .nature),

        // MARK: - Vehicles
        IconDefinition(sfSymbol: "car.fill", displayName: "Car", category: .vehicles,
                      classifierLabels: ["car_horn", "car_passing_by", "engine_starting", "engine_idling",
                                        "engine_accelerating_revving", "engine_knocking",
                                        "vehicle_skidding", "race_car"]),
        IconDefinition(sfSymbol: "bus.fill", displayName: "Bus", category: .vehicles,
                      classifierLabels: ["bus"]),
        IconDefinition(sfSymbol: "truck.box.fill", displayName: "Truck", category: .vehicles,
                      classifierLabels: ["truck"]),
        IconDefinition(sfSymbol: "motorcycle.fill", displayName: "Motorcycle", category: .vehicles,
                      classifierLabels: ["motorcycle"]),
        IconDefinition(sfSymbol: "bicycle", displayName: "Bicycle", category: .vehicles,
                      classifierLabels: ["bicycle"]),
        IconDefinition(sfSymbol: "tram.fill", displayName: "Train", category: .vehicles,
                      classifierLabels: ["train", "train_horn", "train_whistle", "train_wheels_squealing", "rail_transport",
                                        "subway_metro"]),
        IconDefinition(sfSymbol: "airplane", displayName: "Airplane", category: .vehicles,
                      classifierLabels: ["airplane", "aircraft", "helicopter"]),
        IconDefinition(sfSymbol: "ferry.fill", displayName: "Boat", category: .vehicles,
                      classifierLabels: ["boat_water_vehicle", "motorboat_speedboat", "rowboat_canoe_kayak"]),
        IconDefinition(sfSymbol: "fuelpump.fill", displayName: "Fuel", category: .vehicles),
        IconDefinition(sfSymbol: "horn.blast.fill", displayName: "Horn", category: .vehicles,
                      classifierLabels: ["car_horn", "train_horn", "air_horn"]),
        IconDefinition(sfSymbol: "light.beacon.max.fill", displayName: "Siren", category: .vehicles,
                      classifierLabels: ["siren", "police_siren", "fire_engine_siren", "ambulance_siren",
                                        "emergency_vehicle"]),

        // MARK: - Other
        IconDefinition(sfSymbol: "brain.head.profile", displayName: "Idea", category: .other),
        IconDefinition(sfSymbol: "lightbulb.fill", displayName: "Inspiration", category: .other),
        IconDefinition(sfSymbol: "star.fill", displayName: "Star", category: .other),
        IconDefinition(sfSymbol: "heart.fill", displayName: "Heart", category: .other),
        IconDefinition(sfSymbol: "bookmark.fill", displayName: "Bookmark", category: .other),
        IconDefinition(sfSymbol: "flag.fill", displayName: "Flag", category: .other),
        IconDefinition(sfSymbol: "tag.fill", displayName: "Tag", category: .other),
        IconDefinition(sfSymbol: "folder.fill", displayName: "Folder", category: .other),
        IconDefinition(sfSymbol: "doc.fill", displayName: "Document", category: .other),
        IconDefinition(sfSymbol: "note.text", displayName: "Note", category: .other),
        IconDefinition(sfSymbol: "list.bullet", displayName: "List", category: .other),
        IconDefinition(sfSymbol: "checkmark.circle.fill", displayName: "Done", category: .other),
        IconDefinition(sfSymbol: "exclamationmark.triangle.fill", displayName: "Alert", category: .other),
        IconDefinition(sfSymbol: "questionmark.circle.fill", displayName: "Question", category: .other),
        IconDefinition(sfSymbol: "info.circle.fill", displayName: "Info", category: .other),
        IconDefinition(sfSymbol: "mappin.and.ellipse", displayName: "Location", category: .other),
        IconDefinition(sfSymbol: "calendar", displayName: "Calendar", category: .other),
        IconDefinition(sfSymbol: "clock.fill", displayName: "Clock", category: .other),
        IconDefinition(sfSymbol: "stopwatch.fill", displayName: "Timer", category: .other),
        IconDefinition(sfSymbol: "sportscourt.fill", displayName: "Sports", category: .other,
                      classifierLabels: ["playing_tennis", "playing_badminton", "basketball_bounce",
                                        "playing_table_tennis", "skateboard", "skiing",
                                        "person_running", "person_walking", "rope_skipping"]),
    ]

    /// Icons grouped by category (for picker UI)
    static let iconsByCategory: [(category: IconCategory, icons: [IconDefinition])] = {
        let grouped = Dictionary(grouping: allIcons) { $0.category }
        return IconCategory.allCases
            .sorted { $0.displayOrder < $1.displayOrder }
            .compactMap { category in
                guard let icons = grouped[category], !icons.isEmpty else { return nil }
                return (category: category, icons: icons)
            }
    }()

    /// Lookup icon by SF Symbol name
    static func icon(for sfSymbol: String) -> IconDefinition? {
        allIcons.first { $0.sfSymbol == sfSymbol }
    }

    /// Look up the category for a given SF Symbol name
    static func category(for sfSymbol: String) -> IconCategory? {
        allIcons.first { $0.sfSymbol == sfSymbol }?.category
    }

    /// Find best matching icon for a classifier label
    static func iconForClassifierLabel(_ label: String) -> IconDefinition? {
        allIcons.first { $0.classifierLabels.contains(label) }
    }

    /// Get all classifier labels and their corresponding icons
    static var labelToIconMap: [String: IconDefinition] = {
        var map: [String: IconDefinition] = [:]
        for icon in allIcons {
            for label in icon.classifierLabels {
                map[label] = icon
            }
        }
        return map
    }()

    /// Default icon (waveform)
    static let defaultIcon = allIcons.first { $0.sfSymbol == "waveform" }!

    /// Search icons by name (case-insensitive)
    static func search(_ query: String) -> [IconDefinition] {
        guard !query.isEmpty else { return allIcons }
        let lowercased = query.lowercased()
        return allIcons.filter { icon in
            icon.displayName.lowercased().contains(lowercased) ||
            icon.category.rawValue.lowercased().contains(lowercased)
        }
    }
}
