//
//  AudioSessionManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation
import Observation

// NOTE: To enable recording while screen is locked, you MUST enable:
// Target > Signing & Capabilities > Background Modes > "Audio, AirPlay, and Picture in Picture"
// This code provides the audio session support, but the capability must be enabled in Xcode.

@MainActor
@Observable
final class AudioSessionManager {
    static let shared = AudioSessionManager()

    private(set) var isRecordingActive = false
    private(set) var isPlaybackActive = false

    // Observable available inputs - updates on route changes
    private(set) var availableInputs: [AVAudioSessionPortDescription] = []

    // Current effective input
    var currentInput: AVAudioSessionPortDescription? {
        AVAudioSession.sharedInstance().currentRoute.inputs.first
    }

    // Actual sample rate after configuration (may differ from requested)
    private(set) var actualSampleRate: Double = 48000

    var onInterruptionBegan: (() -> Void)?
    var onInterruptionEnded: ((Bool) -> Void)? // Bool = shouldResume
    var onRouteChange: ((AVAudioSession.RouteChangeReason) -> Void)?
    var onMediaServicesReset: (() -> Void)?

    /// Whether a significant route change occurred that requires engine restart
    private(set) var requiresEngineRestart = false

    private init() {
        refreshAvailableInputs()
        setupNotifications()
    }

    // MARK: - Logging & Diagnostics

    /// Log current audio route for debugging
    func logCurrentRoute(context: String = "") {
        #if DEBUG
        let session = AVAudioSession.sharedInstance()
        let route = session.currentRoute

        print("🔊 [AudioSession] Route (\(context)):")
        print("   Inputs:")
        for input in route.inputs {
            print("      - \(input.portName) (\(input.portType.rawValue)) UID: \(input.uid)")
        }
        print("   Outputs:")
        for output in route.outputs {
            print("      - \(output.portName) (\(output.portType.rawValue))")
        }
        print("   Preferred Input: \(session.preferredInput?.portName ?? "None")")
        print("   Available Inputs: \(availableInputs.map { "\($0.portName) (\($0.portType.rawValue))" }.joined(separator: ", "))")
        print("   Sample Rate: \(session.sampleRate) Hz")
        #endif
    }

    /// Get the built-in microphone port from available inputs
    func builtInMicPort() -> AVAudioSessionPortDescription? {
        availableInputs.first { $0.portType == .builtInMic }
    }

    /// Get any Bluetooth HFP input port (for AirPods mic)
    func bluetoothHFPPort() -> AVAudioSessionPortDescription? {
        availableInputs.first { $0.portType == .bluetoothHFP }
    }

    /// Force built-in mic even when Bluetooth is connected
    func forceBuiltInMic() throws {
        guard let builtIn = builtInMicPort() else {
            #if DEBUG
            print("⚠️ [AudioSession] Built-in mic not available")
            #endif
            return
        }
        try AVAudioSession.sharedInstance().setPreferredInput(builtIn)
        #if DEBUG
        print("🎤 [AudioSession] Forced built-in mic: \(builtIn.portName)")
        #endif
    }

    // MARK: - Input Management

    /// Refresh the list of available inputs from AVAudioSession
    func refreshAvailableInputs() {
        availableInputs = AVAudioSession.sharedInstance().availableInputs ?? []
    }

    /// Check if a specific input UID is currently available
    func isInputAvailable(uid: String) -> Bool {
        availableInputs.contains { $0.uid == uid }
    }

    /// Get input description by UID
    func input(for uid: String) -> AVAudioSessionPortDescription? {
        availableInputs.first { $0.uid == uid }
    }

    /// Set preferred input by UID (nil = Automatic)
    func setPreferredInput(uid: String?) throws {
        let session = AVAudioSession.sharedInstance()

        if let uid = uid, let input = input(for: uid) {
            try session.setPreferredInput(input)
        } else {
            // Clear preferred input - system will choose automatically
            try session.setPreferredInput(nil)
        }
    }

    /// Apply preferred input from settings (if available)
    func applyPreferredInput(from settings: AppSettings) {
        let session = AVAudioSession.sharedInstance()

        guard let preferredUID = settings.preferredInputUID else {
            // Automatic mode - but if Bluetooth is connected and causing issues,
            // we may want to prefer the built-in mic for reliability
            // For now, just clear preferred input and let iOS choose
            do {
                try session.setPreferredInput(nil)
            } catch {
                #if DEBUG
                print("⚠️ [AudioSession] Failed to clear preferred input: \(error.localizedDescription)")
                #endif
            }
            #if DEBUG
            print("🎤 [AudioSession] Input set to Automatic")
            #endif
            return
        }

        if let matchingInput = input(for: preferredUID) {
            do {
                try session.setPreferredInput(matchingInput)
                #if DEBUG
                print("🎤 [AudioSession] Preferred input set to: \(matchingInput.portName) (\(matchingInput.portType.rawValue))")
                #endif
            } catch {
                #if DEBUG
                print("⚠️ [AudioSession] Failed to set preferred input: \(error)")
                #endif
            }
        } else {
            // Preferred input not available
            // If it was built-in mic and we have Bluetooth, try to force built-in
            if let builtIn = builtInMicPort() {
                do {
                    try session.setPreferredInput(builtIn)
                } catch {
                    #if DEBUG
                    print("⚠️ [AudioSession] Failed to set fallback built-in mic input: \(error.localizedDescription)")
                    #endif
                }
                #if DEBUG
                print("🎤 [AudioSession] Fallback to built-in mic: \(builtIn.portName)")
                #endif
            } else {
                do {
                    try session.setPreferredInput(nil)
                } catch {
                    #if DEBUG
                    print("⚠️ [AudioSession] Failed to clear preferred input: \(error.localizedDescription)")
                    #endif
                }
                #if DEBUG
                print("🎤 [AudioSession] Preferred input not available, using automatic")
                #endif
            }
        }
    }

    // MARK: - Session Configuration

    /// Configure audio session for recording with specified quality preset.
    /// For Bluetooth: waits for HFP route stabilization to avoid invalid input format.
    func configureForRecording(quality: RecordingQualityPreset, settings: AppSettings) async throws {
        let session = AVAudioSession.sharedInstance()

        // Remember settings so route-change handler can reapply preferred input
        lastAppliedSettings = settings

        // Use .allowBluetooth (HFP, supports mic) and .allowBluetoothA2DP (output).
        // .playAndRecord with .allowBluetooth will negotiate HFP when input is needed.
        let options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetooth,
            .allowBluetoothA2DP
        ]

        try session.setCategory(.playAndRecord, mode: .default, options: options)

        // Try to set preferred sample rate
        let requestedSampleRate = quality.sampleRate
        do {
            try session.setPreferredSampleRate(requestedSampleRate)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred sample rate: \(error.localizedDescription)")
            #endif
        }

        // Set preferred input channel count from recording mode (mono or stereo)
        do {
            try session.setPreferredInputNumberOfChannels(settings.recordingMode.channelCount)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred input channels: \(error.localizedDescription)")
            #endif
        }

        // Apply preferred input BEFORE activation so the session activates
        // with the correct input already selected.
        applyPreferredInput(from: settings)

        // Activate the session
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Wait for Bluetooth HFP route stabilization if needed.
        // A2DP→HFP transition takes ~200-500ms; without this, inputNode format may be invalid.
        if isBluetoothOutput() || isBluetoothInput() {
            #if DEBUG
            print("🔄 [AudioSession] Bluetooth detected — waiting for HFP route stabilization")
            #endif
            try await Task.sleep(nanoseconds: 500_000_000) // 500ms

            // Reapply preferred input after route stabilization — the HFP
            // transition may have changed available inputs.
            refreshAvailableInputs()
            applyPreferredInput(from: settings)
        }

        // Store actual sample rate
        actualSampleRate = session.sampleRate

        if actualSampleRate != requestedSampleRate {
            #if DEBUG
            print("AudioSession: Requested \(requestedSampleRate)Hz, got \(actualSampleRate)Hz")
            #endif
        }

        // Refresh inputs after activation
        refreshAvailableInputs()

        logCurrentRoute(context: "configureForRecording (async)")

        isRecordingActive = true
    }

    /// Synchronous variant for non-Bluetooth paths (backwards compatibility)
    func configureForRecording(quality: RecordingQualityPreset, settings: AppSettings) throws {
        let session = AVAudioSession.sharedInstance()

        // Remember settings so route-change handler can reapply preferred input
        lastAppliedSettings = settings

        let options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetooth,
            .allowBluetoothA2DP
        ]

        try session.setCategory(.playAndRecord, mode: .default, options: options)
        do {
            try session.setPreferredSampleRate(quality.sampleRate)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred sample rate: \(error.localizedDescription)")
            #endif
        }
        // Set preferred input channel count from recording mode (mono or stereo)
        do {
            try session.setPreferredInputNumberOfChannels(settings.recordingMode.channelCount)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred input channels: \(error.localizedDescription)")
            #endif
        }

        // Apply preferred input BEFORE activation so the session activates
        // with the correct input already selected.
        applyPreferredInput(from: settings)

        try session.setActive(true, options: .notifyOthersOnDeactivation)

        actualSampleRate = session.sampleRate

        // Reapply preferred input after activation — activation may have
        // changed the route, especially with wired headphones.
        applyPreferredInput(from: settings)
        refreshAvailableInputs()
        logCurrentRoute(context: "configureForRecording (sync)")
        isRecordingActive = true
    }

    /// Legacy method for backwards compatibility
    func configureForRecording() throws {
        let session = AVAudioSession.sharedInstance()

        let options: AVAudioSession.CategoryOptions = [
            .defaultToSpeaker,
            .allowBluetooth,
            .allowBluetoothA2DP
        ]

        try session.setCategory(.playAndRecord, mode: .default, options: options)

        // Force mono input - we only record mono for best quality on mobile devices
        do {
            try session.setPreferredInputNumberOfChannels(1)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred input channels: \(error.localizedDescription)")
            #endif
        }

        try session.setActive(true, options: .notifyOthersOnDeactivation)

        actualSampleRate = session.sampleRate
        refreshAvailableInputs()

        isRecordingActive = true
    }

    func configureForPlayback() throws {
        if isRecordingActive {
            // Don't change category while recording - .playAndRecord already supports playback
            isPlaybackActive = true
            return
        }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true, options: .notifyOthersOnDeactivation)
        isPlaybackActive = true
    }

    func deactivatePlayback() {
        isPlaybackActive = false
        if !isRecordingActive {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                #if DEBUG
                print("⚠️ [AudioSession] Failed to deactivate after playback: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func deactivateRecording() {
        isRecordingActive = false
        if !isPlaybackActive {
            let session = AVAudioSession.sharedInstance()
            do {
                try session.setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                #if DEBUG
                print("⚠️ [AudioSession] Failed to deactivate after recording: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func deactivate() {
        deactivatePlayback()
        deactivateRecording()
    }

    // MARK: - Input Icons

    /// Get SF Symbol icon name for input port type
    static func icon(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "iphone"
        case .headsetMic:
            return "headphones"
        case .bluetoothHFP, .bluetoothA2DP, .bluetoothLE:
            return "airpodspro"
        case .usbAudio:
            return "cable.connector"
        case .carAudio:
            return "car"
        default:
            return "mic.fill"
        }
    }

    /// Get human-readable port type name
    static func portTypeName(for portType: AVAudioSession.Port) -> String {
        switch portType {
        case .builtInMic:
            return "Built-in"
        case .headsetMic:
            return "Headset"
        case .bluetoothHFP:
            return "Bluetooth"
        case .bluetoothA2DP:
            return "Bluetooth A2DP"
        case .bluetoothLE:
            return "Bluetooth LE"
        case .usbAudio:
            return "USB Audio"
        case .carAudio:
            return "CarPlay"
        default:
            return "External"
        }
    }

    // MARK: - Headphone Detection (for Overdub)

    /// Check if headphone monitoring is active (required for overdub to prevent feedback)
    /// Returns true if outputs include headphones, headset, USB audio, or bluetooth audio
    func isHeadphoneMonitoringActive() -> Bool {
        #if targetEnvironment(simulator)
        return true // Allow overdub on simulator for testing/screenshots
        #else
        let session = AVAudioSession.sharedInstance()
        let outputs = session.currentRoute.outputs

        for output in outputs {
            switch output.portType {
            case .headphones, .headsetMic:
                return true
            case .usbAudio:
                // USB audio interface typically has headphone monitoring
                return true
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                // Allow bluetooth headphones for overdub
                return true
            default:
                continue
            }
        }

        return false
        #endif
    }

    /// Check if the current output route is Bluetooth (AirPods, BT headphones, etc.)
    func isBluetoothOutput() -> Bool {
        let session = AVAudioSession.sharedInstance()
        for output in session.currentRoute.outputs {
            switch output.portType {
            case .bluetoothA2DP, .bluetoothHFP, .bluetoothLE:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Check if the current input route is Bluetooth (AirPods mic, BT headset mic, etc.)
    func isBluetoothInput() -> Bool {
        let session = AVAudioSession.sharedInstance()
        for input in session.currentRoute.inputs {
            switch input.portType {
            case .bluetoothHFP, .bluetoothLE:
                return true
            default:
                continue
            }
        }
        return false
    }

    /// Check if a wired headset mic is connected
    func isWiredHeadsetInput() -> Bool {
        let session = AVAudioSession.sharedInstance()
        for input in session.currentRoute.inputs {
            if input.portType == .headsetMic {
                return true
            }
        }
        return false
    }

    /// Get the current output type name for display
    func currentOutputName() -> String {
        let session = AVAudioSession.sharedInstance()
        if let output = session.currentRoute.outputs.first {
            return output.portName
        }
        return "Speaker"
    }

    /// Configure audio session specifically for overdub (playback + recording simultaneously)
    /// Uses lower latency settings than standard recording
    func configureForOverdub(quality: RecordingQualityPreset, settings: AppSettings) throws {
        let session = AVAudioSession.sharedInstance()

        // IMPORTANT: For overdub (simultaneous record + playback), we CANNOT use A2DP.
        // A2DP is output-only (no microphone). We must use HFP for Bluetooth which supports
        // both input and output. Use .allowBluetooth (enables HFP) but NOT .allowBluetoothA2DP.
        let options: AVAudioSession.CategoryOptions = [
            .allowBluetooth  // Enables HFP profile which supports mic + output
            // Note: Do NOT include .allowBluetoothA2DP - it's output-only and will fail recording
            // Note: Do NOT include .defaultToSpeaker - overdub requires headphones
        ]

        #if DEBUG
        print("🔧 [AudioSession] Configuring for overdub")
        print("   Category: playAndRecord")
        print("   Options: allowBluetooth (HFP for mic support)")
        #endif

        // Use playAndRecord for simultaneous playback and recording
        try session.setCategory(.playAndRecord, mode: .default, options: options)

        // Request lower latency for overdub
        let requestedSampleRate = quality.sampleRate
        do {
            try session.setPreferredSampleRate(requestedSampleRate)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred sample rate for overdub: \(error.localizedDescription)")
            #endif
        }
        do {
            try session.setPreferredIOBufferDuration(0.005) // 5ms buffer for low latency
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred IO buffer duration: \(error.localizedDescription)")
            #endif
        }

        // Force mono input - we only record mono for best quality on mobile devices
        do {
            try session.setPreferredInputNumberOfChannels(1)
        } catch {
            #if DEBUG
            print("⚠️ [AudioSession] Failed to set preferred input channels for overdub: \(error.localizedDescription)")
            #endif
        }

        // Activate the session
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Store actual sample rate
        actualSampleRate = session.sampleRate

        #if DEBUG
        print("   Actual sample rate: \(session.sampleRate) Hz")
        print("   IO buffer duration: \(session.ioBufferDuration) sec")
        logCurrentRoute(context: "configureForOverdub")
        #endif

        // Verify we have a valid input route
        let currentInputs = session.currentRoute.inputs
        if currentInputs.isEmpty {
            #if DEBUG
            print("⚠️ [AudioSession] No input route available after overdub configuration")
            #endif
        } else {
            #if DEBUG
            for input in currentInputs {
                print("   Input available: \(input.portName) (\(input.portType.rawValue))")
            }
            #endif
        }

        // Apply preferred input (prefer built-in mic for overdub unless user has external)
        applyPreferredInput(from: settings)

        // Refresh inputs after activation
        refreshAvailableInputs()

        isRecordingActive = true
        isPlaybackActive = true
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

        // Handle media services reset (rare but critical - e.g., system audio crash recovery)
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMediaServicesReset()
        }
    }

    private func handleMediaServicesReset() {
        // Reset internal state - audio engine and session need to be rebuilt
        isRecordingActive = false
        isPlaybackActive = false

        Task { @MainActor in
            refreshAvailableInputs()
            onMediaServicesReset?()
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

    /// Settings reference for reapplying preferred input on route changes.
    /// Set by `configureForRecording` so that route-change handler can reapply.
    private var lastAppliedSettings: AppSettings?

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        Task { @MainActor in
            // Always refresh available inputs on route change
            refreshAvailableInputs()

            // Log route change for debugging
            let reasonStr: String
            switch reason {
            case .unknown: reasonStr = "unknown"
            case .newDeviceAvailable: reasonStr = "newDeviceAvailable"
            case .oldDeviceUnavailable: reasonStr = "oldDeviceUnavailable"
            case .categoryChange: reasonStr = "categoryChange"
            case .override: reasonStr = "override"
            case .wakeFromSleep: reasonStr = "wakeFromSleep"
            case .noSuitableRouteForCategory: reasonStr = "noSuitableRouteForCategory"
            case .routeConfigurationChange: reasonStr = "routeConfigurationChange"
            @unknown default: reasonStr = "unknown(\(reasonValue))"
            }
            #if DEBUG
            print("🔄 [AudioSession] Route changed: \(reasonStr)")
            #endif
            logCurrentRoute(context: "after route change")

            // Reapply preferred input whenever a device is added or removed,
            // so the user's mic-source selection is honoured after plug/unplug.
            if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                if let settings = lastAppliedSettings {
                    applyPreferredInput(from: settings)
                }
            }

            // Determine if this requires engine restart (device changes typically do)
            switch reason {
            case .newDeviceAvailable, .oldDeviceUnavailable:
                // Device connected/disconnected - engine input may be invalid
                requiresEngineRestart = true
                onRouteChange?(reason)
            case .categoryChange, .override, .routeConfigurationChange:
                onRouteChange?(reason)
            default:
                break
            }
        }
    }

    /// Clear the engine restart flag after handling
    func clearEngineRestartFlag() {
        requiresEngineRestart = false
    }
}
