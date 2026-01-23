//
//  SettingsModels.swift
//  VoiceMemoPro
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

// MARK: - EQ Settings

struct EQSettings: Codable, Equatable {
    var lowGain: Float = 0       // -12 to +12 dB
    var lowMidGain: Float = 0
    var highMidGain: Float = 0
    var highGain: Float = 0

    static let flat = EQSettings()

    // Fixed center frequencies for 4-band EQ
    static let lowFrequency: Float = 100
    static let lowMidFrequency: Float = 500
    static let highMidFrequency: Float = 2000
    static let highFrequency: Float = 8000
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
    var eqSettings: EQSettings = .flat
    var silenceSkipSettings: SilenceSkipSettings = .default

    static let `default` = AppSettings()
}
