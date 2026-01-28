//
//  SettingsModels.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation

// MARK: - Recording Quality Preset

enum RecordingQualityPreset: String, CaseIterable, Identifiable, Codable {
    case standard   // AAC, 44.1kHz, ~128kbps
    case high       // AAC, 48kHz, ~256kbps
    case lossless   // ALAC, 48kHz (fallback to AAC if unsupported)
    case wav        // PCM WAV, 48kHz, 16-bit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return "Standard"
        case .high: return "High"
        case .lossless: return "Lossless"
        case .wav: return "WAV"
        }
    }

    var description: String {
        switch self {
        case .standard: return "AAC 44.1 kHz · Smaller files"
        case .high: return "AAC 48 kHz · Balanced quality"
        case .lossless: return "ALAC 48 kHz · Studio quality"
        case .wav: return "PCM 48 kHz · Uncompressed"
        }
    }

    var sampleRate: Double {
        switch self {
        case .standard: return 44100
        case .high, .lossless, .wav: return 48000
        }
    }

    var bitRate: Int {
        switch self {
        case .standard: return 128000
        case .high: return 256000
        case .lossless, .wav: return 0 // Not applicable for lossless/WAV
        }
    }

    var fileExtension: String {
        switch self {
        case .standard, .high, .lossless: return "m4a"
        case .wav: return "wav"
        }
    }

    var formatID: AudioFormatID {
        switch self {
        case .standard, .high: return kAudioFormatMPEG4AAC
        case .lossless: return kAudioFormatAppleLossless
        case .wav: return kAudioFormatLinearPCM
        }
    }

    var isLossless: Bool {
        switch self {
        case .lossless, .wav: return true
        case .standard, .high: return false
        }
    }

    // Migration from old presets
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)

        // Handle migration from old values
        switch rawValue {
        case "good": self = .standard
        case "better": self = .high
        case "best": self = .high
        default:
            self = RecordingQualityPreset(rawValue: rawValue) ?? .high
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
    var threshold: Float = -55  // dB threshold (-60 to -20)
    var minDuration: Double = 0.5  // minimum silence duration to skip (seconds)

    static let `default` = SilenceSkipSettings()
}

// MARK: - Recording Input Settings (Gain + Limiter)

struct RecordingInputSettings: Codable, Equatable {
    /// Input gain in dB (-6 to +6)
    var gainDb: Float = 0

    /// Whether the limiter is enabled
    var limiterEnabled: Bool = false

    /// Limiter ceiling in dB (0, -1, -2, -3, -4, -5, -6)
    var limiterCeilingDb: Float = -1

    // Gain range
    static let minGainDb: Float = -6
    static let maxGainDb: Float = 6
    static let gainStep: Float = 0.5

    // Limiter ceiling options
    static let ceilingOptions: [Float] = [0, -1, -2, -3, -4, -5, -6]

    static let `default` = RecordingInputSettings()

    /// Check if settings are at default values
    var isDefault: Bool {
        abs(gainDb) < 0.1 && !limiterEnabled
    }

    /// Format gain for display with sign
    var gainDisplayString: String {
        if gainDb > 0 {
            return String(format: "+%.1f dB", gainDb)
        } else if gainDb < 0 {
            return String(format: "%.1f dB", gainDb)
        } else {
            return "0 dB"
        }
    }

    /// Format ceiling for display
    var ceilingDisplayString: String {
        if limiterCeilingDb == 0 {
            return "0 dB"
        } else {
            return String(format: "%.0f dB", limiterCeilingDb)
        }
    }

    /// Summary string for banner display (only non-defaults)
    var summaryString: String? {
        var parts: [String] = []

        if abs(gainDb) >= 0.1 {
            parts.append("Gain \(gainDisplayString)")
        }

        if limiterEnabled {
            parts.append("Limiter \(ceilingDisplayString)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - App Settings (persisted)

struct AppSettings: Codable {
    var recordingQuality: RecordingQualityPreset = .high
    var transcriptionLanguage: TranscriptionLanguage = .system
    var autoTranscribe: Bool = false
    var skipInterval: SkipInterval = .fifteen
    var playbackSpeed: Float = 1.0
    var silenceSkipSettings: SilenceSkipSettings = .default
    var iCloudSyncEnabled: Bool = false

    // Audio input preference (nil = Automatic)
    var preferredInputUID: String? = nil

    // Recording input controls (gain + limiter)
    var recordingInputSettings: RecordingInputSettings = .default

    // Move hint tracking
    var hasShownMoveHint: Bool = false
    var hasEverMovedRecordButton: Bool = false
    var lastMoveHintShownAt: Date? = nil

    // Auto icon detection (classify audio type post-save)
    var autoSelectIcon: Bool = true

    static let `default` = AppSettings()
}
