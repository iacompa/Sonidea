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

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentFileURL: URL?

    private let maxLiveSamples = 60

    override init() {
        super.init()
    }

    func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: .defaultToSpeaker)
            try session.setActive(true)
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }

        let fileURL = generateFileURL()
        currentFileURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

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

        return RawRecordingData(
            fileURL: fileURL,
            createdAt: createdAt,
            duration: duration
        )
    }

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
