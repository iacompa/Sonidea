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

    private var audioRecorder: AVAudioRecorder?
    private var recordingStartTime: Date?
    private var timer: Timer?
    private var currentFileURL: URL?

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
            audioRecorder?.record()
            isRecording = true
            recordingStartTime = Date()
            currentDuration = 0
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
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let startTime = self.recordingStartTime else { return }
                self.currentDuration = Date().timeIntervalSince(startTime)
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}
