//
//  SettingsModels.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation

// MARK: - Recording Quality Preset

enum RecordingQualityPreset: String, CaseIterable, Identifiable, Codable {
    case good
    case better
    case best

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .good: return "Good"
        case .better: return "Better"
        case .best: return "Best"
        }
    }

    var description: String {
        switch self {
        case .good: return "22 kHz, smaller files"
        case .better: return "44.1 kHz, balanced"
        case .best: return "48 kHz, highest quality"
        }
    }

    var sampleRate: Double {
        switch self {
        case .good: return 22050
        case .better: return 44100
        case .best: return 48000
        }
    }

    var bitRate: Int {
        switch self {
        case .good: return 64000
        case .better: return 128000
        case .best: return 192000
        }
    }
}

// MARK: - Transcription Language

enum TranscriptionLanguage: String, CaseIterable, Identifiable, Codable {
    case system
    case english = "en-US"
    case spanish = "es-ES"
    case portuguese = "pt-BR"
    case french = "fr-FR"
    case italian = "it-IT"
    case mandarin = "zh-CN"
    case cantonese = "zh-HK"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System/Auto"
        case .english: return "English"
        case .spanish: return "Spanish"
        case .portuguese: return "Portuguese"
        case .french: return "French"
        case .italian: return "Italian"
        case .mandarin: return "Mandarin (Simplified)"
        case .cantonese: return "Cantonese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }

    var locale: Locale? {
        switch self {
        case .system: return nil
        default: return Locale(identifier: rawValue)
        }
    }
}

// MARK: - Skip Interval

enum SkipInterval: Int, CaseIterable, Identifiable, Codable {
    case five = 5
    case ten = 10
    case fifteen = 15

    var id: Int { rawValue }

    var displayName: String {
        "\(rawValue)s"
    }
}

// MARK: - Parametric EQ Band Settings

struct EQBandSettings: Codable, Equatable {
    var frequency: Float  // Hz (20 - 20000)
    var gain: Float       // dB (-12 to +12)
    var q: Float          // Q factor (0.3 to 10.0)

    // Gain range
    static let minGain: Float = -12
    static let maxGain: Float = 12

    // Frequency range
    static let minFrequency: Float = 20
    static let maxFrequency: Float = 20000

    // Q range (user-facing)
    static let minQ: Float = 0.3
    static let maxQ: Float = 10.0

    /// Convert user-facing Q to AVAudioUnitEQ bandwidth (octaves)
    /// Formula: bandwidth = 2 * asinh(1 / (2 * Q)) / ln(2)
    /// This is the standard conversion from Q to bandwidth in octaves
    var bandwidth: Float {
        // bandwidth (octaves) = 2 * asinh(1/(2*Q)) / ln(2)
        let clampedQ = max(0.1, q) // Avoid division issues
        return 2 * asinh(1 / (2 * clampedQ)) / log(2)
    }

    /// Create bandwidth from Q for AVAudioUnitEQ
    static func bandwidthFromQ(_ q: Float) -> Float {
        let clampedQ = max(0.1, q)
        return 2 * asinh(1 / (2 * clampedQ)) / log(2)
    }

    init(frequency: Float, gain: Float = 0, q: Float = 1.0) {
        self.frequency = max(Self.minFrequency, min(Self.maxFrequency, frequency))
        self.gain = max(Self.minGain, min(Self.maxGain, gain))
        self.q = max(Self.minQ, min(Self.maxQ, q))
    }
}

// MARK: - Full EQ Settings (4 bands)

struct EQSettings: Codable, Equatable {
    var bands: [EQBandSettings]

    // Default frequencies for 4-band parametric EQ
    static let defaultFrequencies: [Float] = [100, 400, 2000, 8000]

    // Band labels
    static let bandLabels = ["Low", "Low-Mid", "High-Mid", "High"]

    static let flat = EQSettings(bands: [
        EQBandSettings(frequency: 100, gain: 0, q: 1.0),
        EQBandSettings(frequency: 400, gain: 0, q: 1.0),
        EQBandSettings(frequency: 2000, gain: 0, q: 1.0),
        EQBandSettings(frequency: 8000, gain: 0, q: 1.0)
    ])

    init(bands: [EQBandSettings]) {
        // Ensure we always have exactly 4 bands
        if bands.count == 4 {
            self.bands = bands
        } else {
            self.bands = Self.flat.bands
        }
    }

    init() {
        self.bands = Self.flat.bands
    }

    // Check if EQ is flat (all gains at 0)
    var isFlat: Bool {
        bands.allSatisfy { abs($0.gain) < 0.1 }
    }

    // Reset to flat
    mutating func reset() {
        bands = [
            EQBandSettings(frequency: 100, gain: 0, q: 1.0),
            EQBandSettings(frequency: 400, gain: 0, q: 1.0),
            EQBandSettings(frequency: 2000, gain: 0, q: 1.0),
            EQBandSettings(frequency: 8000, gain: 0, q: 1.0)
        ]
    }
}

// MARK: - Silence Skip Settings

struct SilenceSkipSettings: Codable, Equatable {
    var enabled: Bool = false
    var threshold: Float = -40  // dB threshold (-60 to -20)
    var minDuration: Double = 0.5  // minimum silence duration to skip (seconds)

    static let `default` = SilenceSkipSettings()
}

// MARK: - App Settings (persisted)

struct AppSettings: Codable {
    var recordingQuality: RecordingQualityPreset = .better
    var transcriptionLanguage: TranscriptionLanguage = .system
    var autoTranscribe: Bool = false
    var skipInterval: SkipInterval = .fifteen
    var playbackSpeed: Float = 1.0
    var silenceSkipSettings: SilenceSkipSettings = .default

    static let `default` = AppSettings()
}
