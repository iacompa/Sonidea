//
//  RecorderManager.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class RecorderManager: NSObject {
    var isRecording = false
    var currentDuration: TimeInterval = 0
    var liveMeterSamples: [Float] = []
    var qualityPreset: RecordingQualityPreset = .better

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentFileURL: URL?
    private var wasRecordingBeforeInterruption = false

    private let maxLiveSamples = 60

    override init() {
        super.init()
        setupInterruptionHandling()
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.isRecording else { return }
                self.wasRecordingBeforeInterruption = true
                self.pauseRecording()
            }
        }

        AudioSessionManager.shared.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor in
                guard let self = self, self.wasRecordingBeforeInterruption else { return }
                self.wasRecordingBeforeInterruption = false
                if shouldResume {
                    self.resumeRecording()
                }
            }
        }

        AudioSessionManager.shared.onRouteChange = { [weak self] in
            Task { @MainActor in
                // Route changed - keep recording stable if possible
                // The recording will continue with whatever input is available
                self?.audioRecorder?.updateMeters()
            }
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        do {
            try AudioSessionManager.shared.configureForRecording()
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }

        let fileURL = generateFileURL()
        currentFileURL = fileURL

        let settings = recordingSettings(for: qualityPreset)

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            isRecording = true
            recordingStartTime = Date()
            currentDuration = 0
            liveMeterSamples = []
            startTimer()
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    func stopRecording() -> RawRecordingData? {
        guard isRecording, let recorder = audioRecorder, let fileURL = currentFileURL else {
            return nil
        }

        recorder.stop()
        stopTimer()

        let duration = currentDuration
        let createdAt = Date()

        isRecording = false
        currentDuration = 0
        recordingStartTime = nil
        audioRecorder = nil
        currentFileURL = nil
        liveMeterSamples = []
        wasRecordingBeforeInterruption = false

        return RawRecordingData(
            fileURL: fileURL,
            createdAt: createdAt,
            duration: duration
        )
    }

    func pauseRecording() {
        audioRecorder?.pause()
        stopTimer()
    }

    func resumeRecording() {
        audioRecorder?.record()
        startTimer()
    }

    // MARK: - Quality Settings

    private func recordingSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        return [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: preset.sampleRate,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: preset.bitRate,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
    }

    // MARK: - Helpers

    private func generateFileURL() -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).m4a"
        return documentsPath.appendingPathComponent(filename)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
                self.updateMeterSamples()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMeterSamples() {
        guard let recorder = audioRecorder, isRecording else { return }

        recorder.updateMeters()

        // Get average power in dB (typically -160 to 0)
        let dB = recorder.averagePower(forChannel: 0)

        // Convert dB to normalized value (0...1)
        // dB ranges from about -60 (silence) to 0 (max)
        // We'll use -50 as practical minimum for better visual range
        let minDB: Float = -50
        let maxDB: Float = 0

        let clampedDB = max(minDB, min(maxDB, dB))
        let normalized = (clampedDB - minDB) / (maxDB - minDB)

        // Add to rolling buffer
        liveMeterSamples.append(normalized)

        // Keep only the most recent samples
        if liveMeterSamples.count > maxLiveSamples {
            liveMeterSamples.removeFirst()
        }
    }
}
