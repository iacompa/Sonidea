//
//  AudioIconClassifier.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/26/26.
//

import Foundation
import AVFoundation
import SoundAnalysis

// MARK: - Classification Result

/// Result of audio classification for icon selection
struct AudioClassificationResult {
    let icon: PresetIcon
    let confidence: Float
    /// Top predictions that meet the suggestion threshold (max 3, sorted by confidence desc)
    let topPredictions: [IconPrediction]

    init(icon: PresetIcon, confidence: Float, topPredictions: [IconPrediction] = []) {
        self.icon = icon
        self.confidence = confidence
        self.topPredictions = topPredictions
    }

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

// MARK: - Sound Analysis Classifier

/// Classifier using Apple's built-in SoundAnalysis framework
@available(iOS 15.0, *)
final class SoundAnalysisClassifier: AudioIconClassifier {

    /// Maximum duration to analyze (seconds)
    private let maxAnalysisDuration: TimeInterval = 10.0

    /// Check if the built-in classifier is available
    var isModelAvailable: Bool {
        // Apple's built-in classifier is available on iOS 15+
        return true
    }

    func classify(fileURL: URL) async -> AudioClassificationResult? {
        // Verify file exists
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            #if DEBUG
            print("[SoundAnalysisClassifier] File not found: \(fileURL.path)")
            #endif
            return AudioClassificationResult(icon: .waveform, confidence: 0)
        }

        do {
            // Create the built-in sound classifier request
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)

            // Create file analyzer
            let analyzer = try SNAudioFileAnalyzer(url: fileURL)

            // Use observer to collect results
            let observer = ClassificationResultsObserver(maxDuration: maxAnalysisDuration)

            try analyzer.add(request, withObserver: observer)

            // Run analysis in background and wait for completion
            return await withCheckedContinuation { continuation in
                observer.onComplete = { result in
                    continuation.resume(returning: result)
                }

                // Start analysis
                analyzer.analyze()
            }
        } catch {
            #if DEBUG
            print("[SoundAnalysisClassifier] Analysis failed: \(error.localizedDescription)")
            #endif
            return AudioClassificationResult(icon: .waveform, confidence: 0)
        }
    }
}

// MARK: - Classification Results Observer

@available(iOS 15.0, *)
private final class ClassificationResultsObserver: NSObject, SNResultsObserving {

    /// Max duration to analyze before stopping
    private let maxDuration: TimeInterval

    /// Lock protecting all mutable state accessed from SoundAnalysis background callbacks
    private let lock = NSLock()

    /// Track all icon matches with their max confidence (keyed by SF Symbol)
    private var iconConfidences: [String: Float] = [:]

    /// Track if we've logged available classifications (debug, once)
    private static var hasLoggedClassifications = false

    /// Completion callback (guarded by hasDelivered to ensure single invocation)
    var onComplete: ((AudioClassificationResult) -> Void)?

    /// Prevent double delivery (didFailWithError + requestDidComplete can both fire)
    private var hasDelivered = false

    /// Track analyzed time
    private var lastAnalyzedTime: TimeInterval = 0

    init(maxDuration: TimeInterval) {
        self.maxDuration = maxDuration
        super.init()
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }

        // Log available classifications once for debugging (DEBUG only)
        #if DEBUG
        if !Self.hasLoggedClassifications {
            let topLabels = classification.classifications.prefix(15).map { "\($0.identifier): \(String(format: "%.2f", $0.confidence))" }
            print("[SoundAnalysisClassifier] Labels: \(topLabels.joined(separator: ", "))")
            Self.hasLoggedClassifications = true
        }
        #endif

        lock.lock()
        defer { lock.unlock() }

        // Track time progress
        lastAnalyzedTime = classification.timeRange.start.seconds + classification.timeRange.duration.seconds

        // Use IconCatalog to map labels to icons, track max confidence per icon
        for item in classification.classifications {
            let label = item.identifier
            let confidence = Float(item.confidence)

            // Look up icon in catalog by classifier label
            if let matchedIcon = IconCatalog.labelToIconMap[label] {
                let symbol = matchedIcon.sfSymbol
                iconConfidences[symbol] = max(iconConfidences[symbol] ?? 0, confidence)
            }
        }
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        #if DEBUG
        print("[SoundAnalysisClassifier] Request failed: \(error.localizedDescription)")
        #endif
        deliverResult()
    }

    func requestDidComplete(_ request: SNRequest) {
        deliverResult()
    }

    private func deliverResult() {
        lock.lock()
        guard !hasDelivered else {
            lock.unlock()
            return
        }
        hasDelivered = true

        // Snapshot mutable state under the lock, then release before calling onComplete
        let snapshotConfidences = iconConfidences
        lock.unlock()

        // Filter predictions >= threshold and sort by confidence descending
        let threshold = IconPrediction.suggestionThreshold
        let qualifiedPredictions = snapshotConfidences
            .filter { $0.value >= threshold }
            .sorted { $0.value > $1.value }
            .prefix(3)  // Max 3 suggestions
            .map { IconPrediction(iconSymbol: $0.key, confidence: $0.value) }

        // Find best overall match (may be below threshold)
        let bestMatch = snapshotConfidences.max { $0.value < $1.value }

        if let best = bestMatch, best.value > 0 {
            let presetIcon = PresetIcon(rawValue: best.key) ?? .waveform
            let result = AudioClassificationResult(
                icon: presetIcon,
                confidence: best.value,
                topPredictions: Array(qualifiedPredictions)
            )
            #if DEBUG
            print("[SoundAnalysisClassifier] Best: \(best.key) @ \(Int(best.value * 100))%, suggestions: \(qualifiedPredictions.count)")
            #endif
            onComplete?(result)
        } else {
            onComplete?(AudioClassificationResult(icon: .waveform, confidence: 0, topPredictions: []))
        }
    }
}

// MARK: - Fallback Classifier for older iOS

/// Fallback for iOS < 15 where built-in classifier isn't available
final class LegacySoundAnalysisClassifier: AudioIconClassifier {
    var isModelAvailable: Bool { false }

    func classify(fileURL: URL) async -> AudioClassificationResult? {
        return AudioClassificationResult(icon: .waveform, confidence: 0)
    }
}

// MARK: - Audio Icon Classifier Manager

/// Singleton manager for audio classification
final class AudioIconClassifierManager {
    static let shared = AudioIconClassifierManager()

    private let classifier: AudioIconClassifier

    /// Confidence threshold for auto-assignment (0.855 = 85.5%)
    let confidenceThreshold: Float = 0.855

    private init() {
        // Use Apple's built-in SoundAnalysis classifier on iOS 15+
        if #available(iOS 15.0, *) {
            classifier = SoundAnalysisClassifier()
            #if DEBUG
            print("[AudioIconClassifierManager] Using Apple SoundAnalysis classifier")
            #endif
        } else {
            classifier = LegacySoundAnalysisClassifier()
            #if DEBUG
            print("[AudioIconClassifierManager] Using legacy fallback (iOS < 15)")
            #endif
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
            #if DEBUG
            print("[AudioIconClassifierManager] Classification: \(result.icon.displayName) @ \(Int(result.confidence * 100))%")
            #endif
            return result.icon
        } else {
            #if DEBUG
            print("[AudioIconClassifierManager] Below threshold: \(result.icon.displayName) @ \(Int(result.confidence * 100))%")
            #endif
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
            #if DEBUG
            print("[AudioIconClassifierManager] Skipping - user-set icon")
            #endif
            return recording
        }

        // Skip if icon has already been auto-classified (iconSourceRaw is set to "auto")
        if recording.iconSourceRaw == IconSource.auto.rawValue && recording.iconName != nil {
            #if DEBUG
            print("[AudioIconClassifierManager] Skipping - already classified")
            #endif
            return recording
        }

        // Attempt classification - get full result with predictions
        guard let result = await classifier.classify(fileURL: recording.fileURL) else {
            return recording
        }

        var updated = recording

        // Always store top predictions for icon picker suggestions
        if !result.topPredictions.isEmpty {
            updated.iconPredictions = result.topPredictions
        }

        // Only auto-assign icon if confidence meets threshold
        if result.meetsThreshold(confidenceThreshold) {
            updated.iconName = result.icon.rawValue
            updated.iconSource = .auto
            #if DEBUG
            print("[AudioIconClassifierManager] Set icon to \(result.icon.displayName) for: \(recording.title)")
            #endif
        } else {
            #if DEBUG
            print("[AudioIconClassifierManager] Below threshold (\(Int(result.confidence * 100))%), stored \(result.topPredictions.count) suggestions")
            #endif
        }

        return updated
    }
}
