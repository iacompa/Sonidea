//
//  WatchRecorderManager.swift
//  SonideaWatch Watch App
//
//  AVAudioRecorder wrapper for watchOS voice recording.
//

import AVFoundation
import Foundation

@Observable
class WatchRecorderManager: NSObject, AVAudioRecorderDelegate {

    var isRecording = false
    var currentDuration: TimeInterval = 0
    /// Normalized audio level 0.0–1.0 for waveform visualization
    var currentLevel: Float = 0

    private var audioRecorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var timer: Timer?
    private var meterTimer: Timer?
    private var recordingStartTime: Date?

    // MARK: - Start Recording

    func startRecording() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            print("WatchRecorder: Audio session error: \(error)")
            return false
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "watch_\(dateFormatter.string(from: Date())).m4a"
        let url = documentsPath.appendingPathComponent(filename)

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 128000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            recordingURL = url
            isRecording = true
            currentDuration = 0
            currentLevel = 0
            recordingStartTime = Date()
            startTimer()
            startMeterTimer()
            return true
        } catch {
            print("WatchRecorder: Failed to start: \(error)")
            return false
        }
    }

    // MARK: - Stop Recording

    func stopRecording() -> (URL, TimeInterval)? {
        stopTimer()
        stopMeterTimer()
        currentLevel = 0
        guard let recorder = audioRecorder, recorder.isRecording else {
            isRecording = false
            return nil
        }

        let duration = recorder.currentTime
        recorder.stop()
        isRecording = false

        do {
            try AVAudioSession.sharedInstance().setActive(false)
        } catch {
            // Non-fatal
        }

        guard let url = recordingURL else { return nil }
        audioRecorder = nil
        recordingURL = nil
        recordingStartTime = nil
        return (url, duration)
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self, let start = self.recordingStartTime else { return }
            self.currentDuration = Date().timeIntervalSince(start)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Audio Metering

    private func startMeterTimer() {
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let recorder = self.audioRecorder, recorder.isRecording else { return }
            recorder.updateMeters()
            // averagePower returns dB: -160 (silence) to 0 (max)
            let dB = recorder.averagePower(forChannel: 0)
            // Normalize to 0.0–1.0 range with a floor at -50 dB
            let normalized = max(0, (dB + 50) / 50)
            self.currentLevel = normalized
        }
    }

    private func stopMeterTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if !flag {
            print("WatchRecorder: Recording finished unsuccessfully")
        }
        isRecording = false
        stopTimer()
    }
}
