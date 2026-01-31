//
//  WatchRecorderManager.swift
//  SonideaWatch Watch App
//
//  AVAudioRecorder wrapper for watchOS voice recording.
//

import AVFoundation
import Foundation
import WatchKit

@MainActor
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
    private var extendedSession: WKExtendedRuntimeSession?
    private var interruptionObserver: NSObjectProtocol?

    // Cleanup handled by stopRecording() which invalidates extendedSession
    // and removes interruptionObserver. No deinit needed since @MainActor
    // properties cannot be accessed from nonisolated deinit.

    /// Cached file timestamp formatter
    private static let fileTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    // MARK: - Start Recording

    func startRecording() -> Bool {
        // --- Microphone permission pre-check ---
        let permissionStatus = AVAudioSession.sharedInstance().recordPermission
        if permissionStatus == .denied {
            #if DEBUG
            print("WatchRecorder: Microphone permission denied")
            #endif
            return false
        }
        // Note: .undetermined is unlikely on watchOS (permission is granted at install via
        // Info.plist), but if it occurs the audio session setup below will trigger the prompt.

        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)
        } catch {
            #if DEBUG
            print("WatchRecorder: Audio session error: \(error)")
            #endif
            return false
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "watch_\(Self.fileTimestamp.string(from: Date())).m4a"
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

            // --- Start extended runtime session for wrist-down protection ---
            let extSession = WKExtendedRuntimeSession()
            extSession.start()
            extendedSession = extSession

            // --- Register audio session interruption observer ---
            if interruptionObserver == nil {
                interruptionObserver = NotificationCenter.default.addObserver(
                    forName: AVAudioSession.interruptionNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] notification in
                    guard let self else { return }
                    guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                          let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

                    if type == .began {
                        // Auto-save on interruption (phone call, Siri, etc.) to prevent data loss
                        Task { @MainActor [weak self] in
                            guard let self, self.isRecording else { return }
                            _ = self.stopRecording()
                        }
                    }
                }
            }

            return true
        } catch {
            #if DEBUG
            print("WatchRecorder: Failed to start: \(error)")
            #endif
            return false
        }
    }

    // MARK: - Stop Recording

    func stopRecording() -> (URL, TimeInterval)? {
        stopTimer()
        stopMeterTimer()
        currentLevel = 0

        // Invalidate extended runtime session
        extendedSession?.invalidate()
        extendedSession = nil

        // Remove interruption observer
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }

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
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
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
            #if DEBUG
            print("WatchRecorder: Recording finished unsuccessfully")
            #endif
        }
        isRecording = false
        stopTimer()
        stopMeterTimer()
        currentLevel = 0
    }
}
