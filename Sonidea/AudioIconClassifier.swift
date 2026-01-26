//
//  AudioIconClassifier.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/26/26.
//

import Foundation
import AVFoundation

// MARK: - Classification Result

/// Result of audio classification for icon selection
struct AudioClassificationResult {
    let icon: PresetIcon
    let confidence: Float

    /// Whether the confidence meets the threshold for auto-assignment
    func meetsThreshold(_ threshold: Float = 0.70) -> Bool {
        confidence >= threshold
    }
}

// MARK: - Audio Icon Classifier Protocol

/// Protocol for audio classification implementations
protocol AudioIconClassifier {
    /// Classify an audio file and return the suggested icon with confidence
    /// - Parameter fileURL: URL to the audio file
    /// - Returns: Classification result, or nil if classification failed
    func classify(fileURL: URL) async -> AudioClassificationResult?
}

// MARK: - Classification Category

/// Categories recognized by the classifier
enum AudioCategory: String, CaseIterable {
    case voice      // Speech, vocals, singing
    case guitar     // Guitar sounds
    case drums      // Drums, percussion
    case keys       // Piano, keyboard, synth
    case other      // Unknown/mixed/unclassified

    /// Map category to preset icon
    var presetIcon: PresetIcon {
        switch self {
        case .voice: return .musicMic   // "music.mic" - Vocal
        case .guitar: return .guitar    // "guitars.fill" - Guitar
        case .drums: return .drum       // "cylinder.fill" - Drums
        case .keys: return .pianokeys   // "pianokeys" - Piano
        case .other: return .waveform   // Default waveform
        }
    }
}

// MARK: - No Model Classifier (Fallback)

/// Fallback classifier that returns default icon
/// Used when SoundAnalysis model is not available
final class NoModelClassifier: AudioIconClassifier {
    func classify(fileURL: URL) async -> AudioClassificationResult? {
        // No model available - return nil to indicate classification not possible
        print("[AudioIconClassifier] No model available, skipping classification")
        return nil
    }
}

// MARK: - Sound Analysis Classifier

/// Classifier using Apple's SoundAnalysis framework
/// This is a scaffold - actual Core ML model integration would go here
final class SoundAnalysisClassifier: AudioIconClassifier {

    /// Check if the classification model is available
    var isModelAvailable: Bool {
        // TODO: Check if Core ML model bundle exists
        // For now, return false to use fallback
        return false
    }

    func classify(fileURL: URL) async -> AudioClassificationResult? {
        guard isModelAvailable else {
            print("[SoundAnalysisClassifier] Model not available")
            return nil
        }

        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            print("[SoundAnalysisClassifier] File not found: \(fileURL.path)")
            return nil
        }

        // TODO: Implement actual SoundAnalysis classification
        // 1. Load Core ML model
        // 2. Create SNAudioFileAnalyzer with the audio file
        // 3. Add classification request with model
        // 4. Analyze and collect results
        // 5. Map top classification to AudioCategory
        // 6. Return result with confidence

        // Placeholder: return nil until model is integrated
        print("[SoundAnalysisClassifier] Classification not yet implemented")
        return nil
    }
}

// MARK: - Audio Icon Classifier Manager

/// Singleton manager for audio classification
final class AudioIconClassifierManager {
    static let shared = AudioIconClassifierManager()

    private let classifier: AudioIconClassifier

    /// Confidence threshold for auto-assignment (0.70 = 70%)
    let confidenceThreshold: Float = 0.70

    private init() {
        // Use SoundAnalysis if available, otherwise fallback
        let soundAnalysis = SoundAnalysisClassifier()
        if soundAnalysis.isModelAvailable {
            classifier = soundAnalysis
        } else {
            classifier = NoModelClassifier()
        }
    }

    /// Classify an audio file and return suggested icon if confidence meets threshold
    /// - Parameter fileURL: URL to the audio file
    /// - Returns: Suggested PresetIcon, or nil if classification failed or below threshold
    func classifyForIcon(fileURL: URL) async -> PresetIcon? {
        guard let result = await classifier.classify(fileURL: fileURL) else {
            return nil
        }

        if result.meetsThreshold(confidenceThreshold) {
            print("[AudioIconClassifierManager] Classification: \(result.icon.displayName) @ \(Int(result.confidence * 100))%")
            return result.icon
        } else {
            print("[AudioIconClassifierManager] Below threshold: \(result.icon.displayName) @ \(Int(result.confidence * 100))%")
            return nil
        }
    }

    /// Classify and update a recording's icon if it hasn't been user-set
    /// - Parameters:
    ///   - recording: The recording to classify
    ///   - autoSelectEnabled: Whether auto-select is enabled in settings
    /// - Returns: Updated recording if icon was changed, original otherwise
    func classifyAndUpdateIfNeeded(recording: RecordingItem, autoSelectEnabled: Bool) async -> RecordingItem {
        // Skip if auto-select is disabled
        guard autoSelectEnabled else {
            return recording
        }

        // Skip if user has already set an icon (iconSource == .user)
        if recording.iconSource == .user {
            print("[AudioIconClassifierManager] Skipping - user-set icon")
            return recording
        }

        // Skip if icon has already been auto-classified (iconSourceRaw is set to "auto")
        if recording.iconSourceRaw == IconSource.auto.rawValue && recording.iconName != nil {
            print("[AudioIconClassifierManager] Skipping - already classified")
            return recording
        }

        // Attempt classification
        guard let suggestedIcon = await classifyForIcon(fileURL: recording.fileURL) else {
            return recording
        }

        // Update recording with classified icon
        var updated = recording
        updated.iconName = suggestedIcon.rawValue
        updated.iconSource = .auto

        print("[AudioIconClassifierManager] Set icon to \(suggestedIcon.displayName) for: \(recording.title)")
        return updated
    }
}
