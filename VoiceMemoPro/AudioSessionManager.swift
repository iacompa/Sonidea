//
//  AudioSessionManager.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation

// NOTE: To enable recording while screen is locked, you MUST enable:
// Target > Signing & Capabilities > Background Modes > "Audio, AirPlay, and Picture in Picture"
// This code provides the audio session support, but the capability must be enabled in Xcode.

@MainActor
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private(set) var isRecordingActive = false
    private(set) var isPlaybackActive = false

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)? // Bool = shouldResume
    var onRouteChange: (() -> Void)?

    private init() {
        setupNotifications()
    }

    // MARK: - Session Configuration

    func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()

        var options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetooth
        ]

        // Add A2DP support if available (iOS 10+)
        options.insert(.allowBluetoothA2DP)

        try session.setCategory(.playAndRecord, mode: .default, options: options)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Apply preferred input if set
        applyPreferredInput()

        isRecordingActive = true
    }

    func configureForPlayback() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        isPlaybackActive = true
    }

    func deactivate() {
        let session = AVAudioSession.sharedInstance()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)
        isRecordingActive = false
        isPlaybackActive = false
    }

    // MARK: - Input Selection

    var availableInputs: [AVAudioSessionPortDescription] {
        AVAudioSession.sharedInstance().availableInputs ?? []
    }

    var currentInput: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first
    }

    func setPreferredInput(_ input: AVAudioSessionPortDescription?) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setPreferredInput(input)

        // Persist the input UID
        if let uid = input?.uid {
            UserDefaults.standard.set(uid, forKey: "preferredInputUID")
        } else {
            UserDefaults.standard.removeObject(forKey: "preferredInputUID")
        }
    }

    private func applyPreferredInput() {
        guard let savedUID = UserDefaults.standard.string(forKey: "preferredInputUID") else { return }

        if let matchingInput = availableInputs.first(where: { $0.uid == savedUID }) {
            try? AVAudioSession.sharedInstance().setPreferredInput(matchingInput)
        }
    }

    // MARK: - Notifications

    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleInterruption(notification)
        }

        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleRouteChange(notification)
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        Task { @MainActor in
            switch type {
            case .began:
                onInterruptionBegan?()
            case .ended:
                var shouldResume = false
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    shouldResume = options.contains(.shouldResume)
                }
                onInterruptionEnded?(shouldResume)
            @unknown default:
                break
            }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        Task { @MainActor in
            switch reason {
            case .oldDeviceUnavailable, .newDeviceAvailable:
                onRouteChange?()
            default:
                break
            }
        }
    }
}
