//
//  RecorderManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AudioToolbox
import AVFoundation
import CoreLocation
import Foundation
import Observation
import UIKit

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case paused

    var isActive: Bool {
        self != .idle
    }
}

@MainActor
@Observable
final class RecorderManager: NSObject {
    // MARK: - Observable State

    var recordingState: RecordingState = .idle
    var currentDuration: TimeInterval = 0
    var liveMeterSamples: [Float] = []
    var qualityPreset: RecordingQualityPreset = .high
    var metronome = MetronomeEngine()
    var monitorEffects = RecordingMonitorEffects()

    /// User-facing error message (e.g. insufficient disk space). Views can observe this to show alerts.
    private(set) var recordingError: String?

    // Reference to app settings (set by AppState)
    var appSettings: AppSettings = .default

    /// Duration accumulated before current recording segment (for pause/resume)
    private var accumulatedDuration: TimeInterval = 0
    /// Start time of current recording segment
    private var segmentStartTime: Date?
    /// Recording start date (for Live Activity timer)
    private var recordingStartDate: Date?
    /// Current recording ID (for Live Activity)
    private var currentRecordingId: String?

    // Convenience computed properties
    var isRecording: Bool { recordingState == .recording }
    var isPaused: Bool { recordingState == .paused }
    var isActive: Bool { recordingState.isActive }

    // MARK: - AVAudioEngine-based Recording (for Gain + Limiter)

    private var audioEngine: AVAudioEngine?
    private var gainMixerNode: AVAudioMixerNode?
    private var limiterNode: AVAudioUnitEffect?
    private var audioFile: AVAudioFile?
    private var isUsingEngine = false  // Track which recording method is in use
    private var writeErrorCount = 0  // Track buffer write failures during engine recording

    // Legacy AVAudioRecorder (fallback when no gain/limiter needed)
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentFileURL: URL?
    private var wasRecordingBeforeInterruption = false

    /// Guard against double-start during async Bluetooth path
    private var isPreparing = false

    /// Resolved sample rate for engine recording (set when engine output format is created)
    private var resolvedEngineSampleRate: Double?

    /// Serial queue for writing audio buffers to file — keeps I/O off the real-time render thread
    private let fileWriteQueue = DispatchQueue(label: "com.iacompa.sonidea.recorder.filewrite", qos: .userInitiated)

    // Crash recovery: keys for UserDefaults
    private let inProgressRecordingKey = "inProgressRecordingPath"
    private let inProgressMetronomeEnabledKey = "inProgressMetronomeEnabled"
    private let inProgressMonitorEffectsEnabledKey = "inProgressMonitorEffectsEnabled"

    private let maxLiveSamples = 60

    // Location tracking
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentLocationLabel: String = ""

    // Callback for when recording should be stopped and saved (from Live Activity)
    var onStopAndSaveRequested: (() -> Void)?

    // MARK: - Live Gain/Limiter Control

    /// Current input settings (gain + limiter) - can be updated during recording
    var inputSettings: RecordingInputSettings {
        get { appSettings.recordingInputSettings }
        set {
            appSettings.recordingInputSettings = newValue
            applyInputSettings()
        }
    }

    /// Apply current input settings to the audio engine (live update)
    private func applyInputSettings() {
        guard isUsingEngine else { return }

        // Apply gain: convert dB to linear
        // dB = 20 * log10(linear), so linear = 10^(dB/20)
        let clampedGainDb = max(-6.0, min(6.0, inputSettings.gainDb))
        let gainLinear = pow(10, clampedGainDb / 20.0)
        gainMixerNode?.outputVolume = gainLinear

        // Apply limiter settings via AudioUnit parameters
        if let limiter = limiterNode {
            let audioUnit = limiter.audioUnit
            if inputSettings.limiterEnabled {
                // Configure dynamics processor as a limiter
                // kDynamicsProcessorParam_Threshold: dB level above which compression starts
                // kDynamicsProcessorParam_HeadRoom: dB above threshold before hard limiting
                // kDynamicsProcessorParam_ExpansionRatio: 1.0 = no expansion
                // kDynamicsProcessorParam_AttackTime: seconds
                // kDynamicsProcessorParam_ReleaseTime: seconds
                // kDynamicsProcessorParam_CompressionAmount: read-only output

                let threshold = inputSettings.limiterCeilingDb
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, threshold, 0)
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 0.1, 0)
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_ExpansionRatio, kAudioUnitScope_Global, 0, 1.0, 0)
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.001, 0)
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.05, 0)
            } else {
                // Bypass by setting threshold to +40 dB so the limiter never engages
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, 40, 0)
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, 40, 0)
            }
        }
    }

    override init() {
        super.init()
        setupInterruptionHandling()
        setupLocationManager()
        setupIntentNotificationHandling()
    }

    // MARK: - Intent Notification Handling

    private func setupIntentNotificationHandling() {
        // Handle stop recording request from Live Activity
        NotificationCenter.default.addObserver(
            forName: .stopRecordingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onStopAndSaveRequested?()
            }
        }

        // Handle pause request from Live Activity
        NotificationCenter.default.addObserver(
            forName: .pauseRecordingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseRecording()
            }
        }

        // Handle resume request from Live Activity
        NotificationCenter.default.addObserver(
            forName: .resumeRecordingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeRecording()
            }
        }
    }

    /// Check and consume pending stop recording request (from Live Activity intent when app was backgrounded)
    func consumePendingStopRequest() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: StopRecordingIntent.pendingStopKey)
        if pending {
            UserDefaults.standard.set(false, forKey: StopRecordingIntent.pendingStopKey)
            return true
        }
        return false
    }

    // MARK: - Location Setup

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    private func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            // Permission denied or restricted
            currentLocation = nil
            currentLocationLabel = ""
        }
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.recordingState == .recording else { return }
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

        AudioSessionManager.shared.onRouteChange = { [weak self] reason in
            Task { @MainActor in
                guard let self = self else { return }

                #if DEBUG
                print("🔄 [RecorderManager] Route change detected, recording: \(self.recordingState.isActive), engine: \(self.isUsingEngine)")
                #endif

                // If we're recording with the engine and a device changed, we need to restart
                if self.recordingState.isActive && self.isUsingEngine {
                    if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                        #if DEBUG
                        print("🔄 [RecorderManager] Audio device changed - restarting engine...")
                        #endif
                        self.handleEngineRouteChange()
                    }
                } else if self.recordingState.isActive && !self.isUsingEngine {
                    // AVAudioRecorder may also need attention on route changes
                    // Force a reconfiguration of the audio session to ensure input is valid
                    if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                        #if DEBUG
                        print("🔄 [RecorderManager] Audio device changed - reconfiguring session...")
                        #endif
                        self.handleRecorderRouteChange()
                    }
                }

                AudioSessionManager.shared.clearEngineRestartFlag()
            }
        }

        // Handle rare media services reset (system audio crash recovery)
        // Safely finalize any in-progress recording to prevent data loss
        AudioSessionManager.shared.onMediaServicesReset = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.recordingState.isActive else { return }
                // Stop recording immediately - audio system is being rebuilt
                // This saves whatever was recorded up to this point
                _ = self.stopRecording()
            }
        }
    }

    // MARK: - Disk Space Check

    /// Minimum free disk space required to start recording (50 MB)
    private static let minimumFreeDiskSpace: Int64 = 50 * 1024 * 1024

    /// Returns true if there is sufficient disk space to begin recording.
    private func hasSufficientDiskSpace() -> Bool {
        do {
            let attrs = try FileManager.default.attributesOfFileSystem(
                forPath: NSHomeDirectory()
            )
            if let freeSize = attrs[.systemFreeSize] as? Int64 {
                return freeSize >= Self.minimumFreeDiskSpace
            }
        } catch {
            #if DEBUG
            print("⚠️ [RecorderManager] Could not check disk space: \(error.localizedDescription)")
            #endif
        }
        // If the check fails, allow recording to proceed rather than blocking
        return true
    }

    // MARK: - Recording Control

    func startRecording() {
        guard recordingState == .idle, !isPreparing else { return }

        // Pre-flight: ensure microphone permission before starting
        let permissionStatus = AVAudioApplication.shared.recordPermission
        switch permissionStatus {
        case .denied:
            recordingError = "Microphone access denied. Please enable microphone permission in Settings > Privacy > Microphone."
            return
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    if granted {
                        self?.startRecording()
                    } else {
                        self?.recordingError = "Microphone permission is required to record audio."
                    }
                }
            }
            return
        case .granted:
            break
        @unknown default:
            break
        }

        // Pre-flight: ensure enough disk space before starting
        if !hasSufficientDiskSpace() {
            let message = "Not enough storage to start recording. Please free up at least 50 MB and try again."
            #if DEBUG
            print("⚠️ [RecorderManager] \(message)")
            #endif
            recordingError = message
            return
        }
        recordingError = nil

        isPreparing = true

        // Prevent screen sleep if enabled
        if appSettings.preventSleepWhileRecording {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let isBluetooth = AudioSessionManager.shared.isBluetoothOutput()
            || AudioSessionManager.shared.isBluetoothInput()

        if isBluetooth {
            // Bluetooth needs async route stabilization (A2DP -> HFP transition)
            Task { @MainActor in
                do {
                    try await AudioSessionManager.shared.configureForRecording(
                        quality: qualityPreset,
                        settings: appSettings
                    )
                } catch {
                    #if DEBUG
                    print("Failed to set up audio session: \(error)")
                    #endif
                    self.isPreparing = false
                    return
                }
                self.continueStartRecording()
            }
        } else {
            // Wired/built-in: synchronous path
            do {
                try AudioSessionManager.shared.configureForRecording(
                    quality: qualityPreset,
                    settings: appSettings
                ) as Void
            } catch {
                #if DEBUG
                print("Failed to set up audio session: \(error)")
                #endif
                isPreparing = false
                return
            }
            continueStartRecording()
        }
    }

    private func continueStartRecording() {
        isPreparing = false
        // Request location at start of recording
        requestLocationIfNeeded()

        let fileURL = generateFileURL(for: qualityPreset)
        currentFileURL = fileURL

        // Decide which recording method to use:
        // Use AVAudioEngine if gain/limiter are active, otherwise use AVAudioRecorder (simpler)
        let needsEngine = !inputSettings.isDefault || metronome.isEnabled || monitorEffects.isEnabled
        isUsingEngine = needsEngine

        if needsEngine {
            startEngineRecording(fileURL: fileURL)
        } else {
            startSimpleRecording(fileURL: fileURL)
        }
    }

    /// Start recording using AVAudioRecorder (no gain/limiter processing)
    private func startSimpleRecording(fileURL: URL) {
        let settings = recordingSettings(for: qualityPreset)

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            recordingState = .recording
            let startDate = Date()
            segmentStartTime = startDate
            recordingStartDate = startDate
            accumulatedDuration = 0
            currentDuration = 0
            liveMeterSamples = []
            startTimer()

            // Track in-progress recording for crash recovery
            markRecordingInProgress(fileURL)

            // Start Live Activity
            currentRecordingId = UUID().uuidString
            RecordingLiveActivityManager.shared.startActivity(
                recordingId: currentRecordingId!,
                startDate: startDate
            )
        } catch {
            #if DEBUG
            print("Failed to start recording: \(error)")
            #endif
        }
    }

    /// Build an AVAudioFormat that matches the hardware input (sample rate + channel count).
    /// Falls back to the inputNode's outputFormat if the hardware format is unavailable.
    private static func hardwareInputFormat(for engine: AVAudioEngine) -> AVAudioFormat? {
        let inputNode = engine.inputNode

        // 1. Try the hardware format (reflects the actual mic, including headset mics)
        let hwFormat = inputNode.inputFormat(forBus: 0)
        if hwFormat.sampleRate > 0 && hwFormat.channelCount > 0 {
            // Build an explicit Float32 non-interleaved format with the hardware's
            // sample rate and channel count.  This avoids carrying over any unexpected
            // common-format from the hardware descriptor.
            if let fmt = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: hwFormat.sampleRate,
                channels: hwFormat.channelCount,
                interleaved: false
            ) {
                return fmt
            }
        }

        // 2. Fallback: the output side of the input node (may already be correct)
        let outFmt = inputNode.outputFormat(forBus: 0)
        if outFmt.sampleRate > 0 && outFmt.channelCount > 0 {
            return outFmt
        }

        return nil
    }

    /// Start recording using AVAudioEngine with gain and limiter nodes
    private func startEngineRecording(fileURL: URL) {
        do {
            // Create audio engine
            let engine = AVAudioEngine()

            // Obtain the true hardware input format.
            // Using inputNode.inputFormat(forBus:0) instead of outputFormat(forBus:0)
            // ensures we get the format the connected mic actually delivers —
            // critical for wired headset mics and Bluetooth HFP mics whose sample
            // rate / channel count differ from the built-in mic.
            guard let inputFormat = Self.hardwareInputFormat(for: engine) else {
                #if DEBUG
                print("❌ [RecorderManager] Could not determine a valid input format - falling back to simple recording")
                #endif
                isUsingEngine = false
                startSimpleRecording(fileURL: fileURL)
                return
            }

            let inputNode = engine.inputNode

            // Log input format for debugging
            #if DEBUG
            print("🎙️ [RecorderManager] Engine input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, \(inputFormat.commonFormat.rawValue)")
            print("🎙️ [RecorderManager] Hardware input format: \(inputNode.inputFormat(forBus: 0))")
            print("🎙️ [RecorderManager] InputNode output format: \(inputNode.outputFormat(forBus: 0))")
            #endif

            // Create gain mixer node
            let gainMixer = AVAudioMixerNode()
            engine.attach(gainMixer)

            // Create limiter node (dynamics processor configured as limiter)
            let limiterDesc = AudioComponentDescription(
                componentType: kAudioUnitType_Effect,
                componentSubType: kAudioUnitSubType_DynamicsProcessor,
                componentManufacturer: kAudioUnitManufacturer_Apple,
                componentFlags: 0,
                componentFlagsMask: 0
            )
            let limiter = AVAudioUnitEffect(audioComponentDescription: limiterDesc)
            engine.attach(limiter)

            // Connect: Input → Gain Mixer → Limiter
            // Use the hardware-derived format for all connections in the recording chain.
            engine.connect(inputNode, to: gainMixer, format: inputFormat)
            engine.connect(gainMixer, to: limiter, format: inputFormat)

            // Use limiter's actual output format for tap — this reflects the format
            // after the full connection chain has been resolved by the engine.
            let tapFormat = limiter.outputFormat(forBus: 0)
            // If the limiter output is invalid (can happen rarely), fall back to inputFormat
            let effectiveTapFormat = (tapFormat.sampleRate > 0 && tapFormat.channelCount > 0) ? tapFormat : inputFormat
            resolvedEngineSampleRate = effectiveTapFormat.sampleRate
            #if DEBUG
            print("🎙️ [RecorderManager] Tap format: \(effectiveTapFormat.sampleRate)Hz, \(effectiveTapFormat.channelCount)ch")
            #endif

            // Reset write error counter
            writeErrorCount = 0

            // Create output audio file matching tap format
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: engineFileSettings(for: qualityPreset),
                commonFormat: effectiveTapFormat.commonFormat,
                interleaved: effectiveTapFormat.isInterleaved
            )

            // Install tap on limiter output to write to file (using native format, no conversion)
            // File I/O is dispatched to a serial queue to avoid blocking the real-time render thread
            let writeQueue = self.fileWriteQueue
            limiter.installTap(onBus: 0, bufferSize: 4096, format: effectiveTapFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                // Copy buffer for off-thread writing (tap may reuse the buffer)
                guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
                copy.frameLength = buffer.frameLength
                if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                    let channelCount = Int(buffer.format.channelCount)
                    let frameCount = Int(buffer.frameLength)
                    for ch in 0..<channelCount {
                        memcpy(dst[ch], src[ch], frameCount * MemoryLayout<Float>.size)
                    }
                }

                writeQueue.async { [weak self] in
                    do {
                        try file.write(from: copy)
                    } catch {
                        self?.writeErrorCount += 1
                        #if DEBUG
                        print("❌ [RecorderManager] Error writing audio buffer: \(error)")
                        #endif
                    }
                }

                // Compute peak on audio thread (buffer may be recycled before MainActor runs)
                let channelCount = Int(buffer.format.channelCount)
                let frameLength = Int(buffer.frameLength)
                var peak: Float = 0
                if let channelData = buffer.floatChannelData, frameLength > 0 {
                    for ch in 0..<channelCount {
                        for i in 0..<frameLength {
                            let absSample = abs(channelData[ch][i])
                            if absSample > peak { peak = absSample }
                        }
                    }
                }
                Task { @MainActor in
                    self?.updateMeterWithPeak(peak)
                }
            }

            // Store references
            self.audioEngine = engine
            self.gainMixerNode = gainMixer
            self.limiterNode = limiter
            self.audioFile = file

            // Apply current input settings
            applyInputSettings()

            // Attach metronome click source to main mixer (NOT to recording chain)
            // Click goes: ClickSourceNode -> MainMixerNode -> Output (speaker/headphones)
            // Recording tap is on LimiterNode, so click is not captured.
            if metronome.isEnabled {
                let clickNode = metronome.createSourceNode(sampleRate: inputFormat.sampleRate)
                engine.attach(clickNode)
                let monoFormat = AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: inputFormat.sampleRate,
                    channels: 1,
                    interleaved: false
                )!
                engine.connect(clickNode, to: engine.mainMixerNode, format: monoFormat)
                #if DEBUG
                print("🎵 [RecorderManager] Metronome click node attached to mainMixerNode")
                #endif
            }

            // Attach monitoring effects chain (hear effects, record clean)
            // Chain: Limiter -> MonitorMixer -> MonitorEQ -> MonitorCompressor -> MainMixerNode
            if monitorEffects.isEnabled {
                let nodes = monitorEffects.createNodes()
                engine.attach(nodes.mixer)
                engine.attach(nodes.eq)
                engine.attach(nodes.compressor)
                engine.connect(limiter, to: nodes.mixer, format: effectiveTapFormat)
                engine.connect(nodes.mixer, to: nodes.eq, format: effectiveTapFormat)
                engine.connect(nodes.eq, to: nodes.compressor, format: effectiveTapFormat)
                engine.connect(nodes.compressor, to: engine.mainMixerNode, format: effectiveTapFormat)
            } else {
                // Complete the engine graph even without monitoring effects.
                // Connect limiter → silent mixer → mainMixerNode so the engine
                // properly pulls audio through the recording chain (needed for
                // the tap to reliably receive buffers). Volume 0 prevents feedback.
                let silentMixer = AVAudioMixerNode()
                engine.attach(silentMixer)
                silentMixer.outputVolume = 0
                engine.connect(limiter, to: silentMixer, format: effectiveTapFormat)
                engine.connect(silentMixer, to: engine.mainMixerNode, format: effectiveTapFormat)
            }

            // Start the engine
            try engine.start()

            // Start metronome if enabled
            if metronome.isEnabled {
                metronome.start()
            }

            recordingState = .recording
            let startDate = Date()
            segmentStartTime = startDate
            recordingStartDate = startDate
            accumulatedDuration = 0
            currentDuration = 0
            liveMeterSamples = []
            startTimer()

            // Track in-progress recording for crash recovery
            markRecordingInProgress(fileURL)

            // Start Live Activity
            currentRecordingId = UUID().uuidString
            RecordingLiveActivityManager.shared.startActivity(
                recordingId: currentRecordingId!,
                startDate: startDate
            )

            #if DEBUG
            print("🎙️ [RecorderManager] Started engine recording with gain: \(inputSettings.gainDb) dB, limiter: \(inputSettings.limiterEnabled ? "ON" : "OFF")")
            #endif
        } catch {
            #if DEBUG
            print("❌ [RecorderManager] Failed to start engine recording: \(error)")
            #endif
            // Fallback to simple recording
            isUsingEngine = false
            startSimpleRecording(fileURL: fileURL)
        }
    }

    /// Get output format for engine recording
    private func engineOutputFormat(for preset: RecordingQualityPreset, inputFormat: AVAudioFormat) -> AVAudioFormat {
        let sampleRate = min(Double(inputFormat.sampleRate), preset.sampleRate)
        resolvedEngineSampleRate = sampleRate
        let channels = AVAudioChannelCount(appSettings.recordingMode.channelCount)
        // If input only has 1 channel, cap at mono regardless of setting
        let effectiveChannels = min(channels, inputFormat.channelCount)
        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: effectiveChannels,
            interleaved: false
        ) ?? inputFormat
    }

    /// Get file settings for engine recording
    /// Uses resolvedEngineSampleRate (set by engineOutputFormat) to ensure consistency
    /// Caps channel count to input device capability to avoid requesting stereo from a mono mic
    private func engineFileSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        let effectiveSampleRate = resolvedEngineSampleRate ?? AudioSessionManager.shared.actualSampleRate
        let requestedChannels = appSettings.recordingMode.channelCount
        let inputChannels = Int(audioEngine?.inputNode.inputFormat(forBus: 0).channelCount ?? 1)
        let channels = min(requestedChannels, max(inputChannels, 1))

        switch preset {
        case .standard:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: effectiveSampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128000 * channels,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        case .high:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: effectiveSampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 256000 * channels,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        case .lossless:
            return [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: effectiveSampleRate,
                AVNumberOfChannelsKey: channels,
                AVEncoderBitDepthHintKey: 16,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: effectiveSampleRate,
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        }
    }

    /// Track consecutive silent buffers for debugging
    private var consecutiveSilentBuffers = 0
    private let silentBufferWarningThreshold = 20

    /// Smoothed peak level for meter display (peak with decay)
    private var smoothedPeakLevel: Float = 0
    /// Decay rate per buffer callback (~93% retention gives ~300ms decay at 44.1kHz/4096 buffer)
    private let peakDecayFactor: Float = 0.93

    /// Update meter from a pre-computed peak value (called from audio tap with peak computed on audio thread)
    private func updateMeterWithPeak(_ peak: Float) {
        // Detect if we're getting silence (potential Bluetooth routing issue)
        if peak < 0.0001 {
            consecutiveSilentBuffers += 1
            if consecutiveSilentBuffers == silentBufferWarningThreshold {
                #if DEBUG
                print("⚠️ [RecorderManager] WARNING: \(silentBufferWarningThreshold) consecutive silent buffers detected - possible input routing issue!")
                #endif
                AudioSessionManager.shared.logCurrentRoute(context: "silent buffer warning")
            }
        } else {
            if consecutiveSilentBuffers >= silentBufferWarningThreshold {
                #if DEBUG
                print("✅ [RecorderManager] Audio input recovered after \(consecutiveSilentBuffers) silent buffers")
                #endif
            }
            consecutiveSilentBuffers = 0
        }

        // Peak hold with decay: rise instantly, fall slowly
        if peak >= smoothedPeakLevel {
            smoothedPeakLevel = peak
        } else {
            smoothedPeakLevel = smoothedPeakLevel * peakDecayFactor
        }

        // Convert peak amplitude to dB: dB = 20 * log10(amplitude)
        // Use -60 dB as the floor (amplitude ~0.001) for professional meter range
        let amplitude = max(smoothedPeakLevel, 1e-6)  // avoid log10(0)
        let dB = 20 * log10(amplitude)
        let minDB: Float = -60
        let maxDB: Float = 0
        let clampedDB = max(minDB, min(maxDB, dB))
        // Linear mapping of dB to 0..1 (the view handles perceptual scaling)
        let normalized = (clampedDB - minDB) / (maxDB - minDB)

        // Update samples on main actor
        liveMeterSamples.append(normalized)
        if liveMeterSamples.count > maxLiveSamples {
            liveMeterSamples.removeFirst()
        }
    }

    /// Stop recording and return raw data for saving
    func stopRecording() -> RawRecordingData? {
        guard recordingState.isActive, let fileURL = currentFileURL else {
            #if DEBUG
            print("⚠️ [RecorderManager] stopRecording called but no active recording")
            #endif
            return nil
        }

        // Verify we have either engine or recorder
        guard isUsingEngine ? (audioEngine != nil) : (audioRecorder != nil) else {
            #if DEBUG
            print("⚠️ [RecorderManager] stopRecording called but no recorder/engine available")
            #endif
            return nil
        }

        #if DEBUG
        print("🎙️ [RecorderManager] Stopping recording: \(fileURL.lastPathComponent)")
        #endif

        // Update duration one final time if recording (not paused)
        if recordingState == .recording, let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }

        // Stop based on which method is in use
        // CRITICAL: Nil out recorder BEFORE reading the file for duration.
        // On real devices, AVAudioRecorder holds a file handle that prevents
        // AVAudioFile(forReading:) from getting accurate frame counts.
        if isUsingEngine {
            stopEngineRecording()
        } else {
            audioRecorder?.stop()
            audioRecorder = nil  // Release file handle so AVAudioFile can read it accurately
        }
        stopTimer()

        // CRITICAL: Verify the file was written successfully
        // AVAudioRecorder.stop() is synchronous but file system may lag
        let fileManager = FileManager.default
        var fileVerified = false

        // Check file existence synchronously (quick check, no blocking sleep)
        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
                if let size = attrs[.size] as? Int64, size > 100 {
                    fileVerified = true
                    #if DEBUG
                    print("✅ [RecorderManager] File verified: \(size) bytes")
                    #endif
                }
            } catch {
                #if DEBUG
                print("⚠️ [RecorderManager] Error checking file attributes: \(error.localizedDescription)")
                #endif
            }
        }

        if !fileVerified {
            #if DEBUG
            print("❌ [RecorderManager] File verification failed (write errors: \(writeErrorCount))")
            #endif
            AudioDebug.logFileInfo(url: fileURL, context: "RecorderManager.stopRecording - verification failed")
        }

        if writeErrorCount > 0 {
            #if DEBUG
            print("⚠️ [RecorderManager] \(writeErrorCount) buffer write errors occurred during recording")
            #endif
        }

        // Use wall clock duration for instant stop response.
        // Wall clock is what the user sees during recording and is accurate enough.
        let duration: TimeInterval = accumulatedDuration

        // Discard very short recordings (< 0.3s) — user likely tapped stop immediately.
        // Clean up the file and return nil so the caller silently discards.
        if duration < 0.3 {
            #if DEBUG
            print("ℹ️ [RecorderManager] Recording too short (\(String(format: "%.2f", duration))s), discarding")
            #endif
            try? FileManager.default.removeItem(at: fileURL)
            resetState()
            clearInProgressRecording()
            AudioSessionManager.shared.deactivateRecording()
            RecordingLiveActivityManager.shared.endActivity()
            return nil
        }

        let createdAt = Date()

        // Capture location data
        let latitude = currentLocation?.coordinate.latitude
        let longitude = currentLocation?.coordinate.longitude
        let locationLabel = currentLocationLabel

        // End Live Activity
        RecordingLiveActivityManager.shared.endActivity()

        resetState()
        clearInProgressRecording()

        // Deactivate audio session when recording is done
        AudioSessionManager.shared.deactivateRecording()

        // Move non-critical I/O to background to keep stop instant
        let capturedURL = fileURL
        DispatchQueue.global(qos: .utility).async {
            AudioDebug.logFileInfo(url: capturedURL, context: "RecorderManager.stopRecording - final")
            Self.protectAudioFile(at: capturedURL)
        }

        return RawRecordingData(
            fileURL: fileURL,
            createdAt: createdAt,
            duration: duration,
            latitude: latitude,
            longitude: longitude,
            locationLabel: locationLabel
        )
    }

    /// Stop the AVAudioEngine recording
    private func stopEngineRecording() {
        // Stop metronome and monitor effects
        metronome.stop()
        monitorEffects.teardown()

        // Remove tap from limiter (stops new buffers from being enqueued)
        limiterNode?.removeTap(onBus: 0)

        // Stop the engine
        audioEngine?.stop()

        // Drain the write queue to ensure all pending buffers are written to disk
        fileWriteQueue.sync {}

        // Close the audio file (implicit on dealloc, but good to be explicit)
        audioFile = nil
    }

    /// Pause recording safely - flushes audio buffer to prevent data loss
    func pauseRecording() {
        guard recordingState == .recording else { return }

        // Verify we have either engine or recorder
        guard isUsingEngine ? (audioEngine != nil) : (audioRecorder != nil) else { return }

        // Accumulate duration from this segment
        if let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }
        segmentStartTime = nil

        // Pause based on which method is in use
        if isUsingEngine {
            // AVAudioEngine doesn't have a true pause, so we stop it
            // Note: This means pause/resume with engine creates a new segment
            audioEngine?.pause()
            // Drain the file write queue to ensure all pending audio data is flushed to disk
            fileWriteQueue.sync {}
        } else {
            // Pause the recorder - this flushes the audio buffer to disk
            audioRecorder?.pause()
        }

        stopTimer()
        recordingState = .paused

        // Update Live Activity to show paused state
        RecordingLiveActivityManager.shared.updateActivity(
            isRecording: false,
            pausedDuration: accumulatedDuration
        )
    }

    /// Resume recording after pause
    func resumeRecording() {
        guard recordingState == .paused else { return }

        // Verify we have either engine or recorder
        guard isUsingEngine ? (audioEngine != nil) : (audioRecorder != nil) else { return }

        // Resume based on which method is in use
        if isUsingEngine {
            do {
                try audioEngine?.start()
                // Restart metronome if it was enabled
                if metronome.isEnabled {
                    metronome.start()
                }
            } catch {
                #if DEBUG
                print("❌ [RecorderManager] Failed to resume engine: \(error)")
                #endif
                return
            }
        } else {
            audioRecorder?.record()
        }

        segmentStartTime = Date()
        recordingState = .recording
        startTimer()

        // Update Live Activity to show recording state
        RecordingLiveActivityManager.shared.updateActivity(
            isRecording: true,
            pausedDuration: nil
        )
    }

    // MARK: - Route Change Handling

    /// Handle route change when using AVAudioEngine (Bluetooth connect/disconnect)
    /// This restarts the engine with the new input configuration
    private func handleEngineRouteChange() {
        guard let engine = audioEngine,
              let fileURL = currentFileURL,
              recordingState == .recording else {
            #if DEBUG
            print("⚠️ [RecorderManager] Cannot handle route change - invalid state")
            #endif
            return
        }

        // Save current accumulated duration
        if let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }

        #if DEBUG
        print("🔄 [RecorderManager] Stopping engine for route change...")
        #endif

        // Stop the current engine (but keep the file open)
        limiterNode?.removeTap(onBus: 0)
        engine.stop()

        // Allow the audio system to settle after route change.
        // Bluetooth HFP transitions can take 200-500ms; wired headsets ~100-200ms.
        let delay: Double = AudioSessionManager.shared.isBluetoothOutput()
            || AudioSessionManager.shared.isBluetoothInput() ? 0.5 : 0.3
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.restartEngineAfterRouteChange()
        }
    }

    /// Restart the engine after a route change
    private func restartEngineAfterRouteChange() {
        guard let engine = audioEngine,
              let gainMixer = gainMixerNode,
              let limiter = limiterNode else {
            #if DEBUG
            print("❌ [RecorderManager] Cannot restart engine - missing components")
            #endif
            return
        }

        do {
            // Reconfigure audio session to ensure correct input
            try AudioSessionManager.shared.configureForRecording(
                quality: qualityPreset,
                settings: appSettings
            )

            // Use the hardware input format — same approach as startEngineRecording
            guard let inputFormat = Self.hardwareInputFormat(for: engine) else {
                #if DEBUG
                print("❌ [RecorderManager] Invalid input format after route change")
                #endif
                return
            }

            #if DEBUG
            print("🔄 [RecorderManager] New input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")
            #endif

            // Check if sample rate changed - if so, we need a new file
            let newOutputFormat = engineOutputFormat(for: qualityPreset, inputFormat: inputFormat)
            let previousSampleRate = audioFile?.processingFormat.sampleRate ?? 0

            var activeFile: AVAudioFile
            if newOutputFormat.sampleRate != previousSampleRate, let fileURL = currentFileURL {
                // Sample rate changed: close old file and create a new segment file
                // to avoid writing mismatched-format buffers to the old file
                audioFile = nil
                let segmentURL = fileURL.deletingPathExtension()
                    .appendingPathExtension("seg\(Int(Date().timeIntervalSince1970))")
                    .appendingPathExtension(fileURL.pathExtension)
                #if DEBUG
                print("🔄 [RecorderManager] Sample rate changed (\(previousSampleRate) -> \(newOutputFormat.sampleRate)), creating new segment: \(segmentURL.lastPathComponent)")
                #endif
                let newFile = try AVAudioFile(
                    forWriting: segmentURL,
                    settings: engineFileSettings(for: qualityPreset),
                    commonFormat: newOutputFormat.commonFormat,
                    interleaved: newOutputFormat.isInterleaved
                )
                audioFile = newFile
                activeFile = newFile
            } else if let file = audioFile {
                // Same sample rate - reuse existing file
                activeFile = file
            } else {
                #if DEBUG
                print("❌ [RecorderManager] No audio file available after route change")
                #endif
                return
            }

            // Disconnect ALL nodes in the recording chain so we can reconnect
            // with the new format — prevents format mismatches between nodes.
            engine.disconnectNodeInput(gainMixer)
            engine.disconnectNodeInput(limiter)

            // Reconnect full chain: Input → Gain Mixer → Limiter
            let inputNode = engine.inputNode
            engine.connect(inputNode, to: gainMixer, format: inputFormat)
            engine.connect(gainMixer, to: limiter, format: inputFormat)

            // Determine effective tap format after reconnection
            let tapFmt = limiter.outputFormat(forBus: 0)
            let effectiveTapFormat = (tapFmt.sampleRate > 0 && tapFmt.channelCount > 0) ? tapFmt : inputFormat

            // Reinstall tap on limiter — dispatch file write off the real-time thread
            let writeQueue = self.fileWriteQueue
            limiter.installTap(onBus: 0, bufferSize: 4096, format: effectiveTapFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                // Copy buffer for off-thread writing (tap may reuse the buffer)
                guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
                copy.frameLength = buffer.frameLength
                if let src = buffer.floatChannelData, let dst = copy.floatChannelData {
                    let channelCount = Int(buffer.format.channelCount)
                    let frameCount = Int(buffer.frameLength)
                    for ch in 0..<channelCount {
                        memcpy(dst[ch], src[ch], frameCount * MemoryLayout<Float>.size)
                    }
                }

                writeQueue.async {
                    do {
                        try activeFile.write(from: copy)
                    } catch {
                        #if DEBUG
                        print("❌ [RecorderManager] Error writing audio buffer: \(error)")
                        #endif
                    }
                }

                // Compute peak on audio thread (buffer may be recycled before MainActor runs)
                let chCount = Int(buffer.format.channelCount)
                let fLen = Int(buffer.frameLength)
                var peak: Float = 0
                if let chData = buffer.floatChannelData, fLen > 0 {
                    for ch in 0..<chCount {
                        for i in 0..<fLen {
                            let absSample = abs(chData[ch][i])
                            if absSample > peak { peak = absSample }
                        }
                    }
                }
                Task { @MainActor in
                    self?.updateMeterWithPeak(peak)
                }
            }

            // Reconnect monitoring effects if active
            if monitorEffects.isEnabled {
                let nodes = monitorEffects.createNodes()
                // Check if nodes are already attached; if not, attach them
                if nodes.mixer.engine == nil { engine.attach(nodes.mixer) }
                if nodes.eq.engine == nil { engine.attach(nodes.eq) }
                if nodes.compressor.engine == nil { engine.attach(nodes.compressor) }
                engine.connect(limiter, to: nodes.mixer, format: effectiveTapFormat)
                engine.connect(nodes.mixer, to: nodes.eq, format: effectiveTapFormat)
                engine.connect(nodes.eq, to: nodes.compressor, format: effectiveTapFormat)
                engine.connect(nodes.compressor, to: engine.mainMixerNode, format: effectiveTapFormat)
            }

            // Restart the engine
            try engine.start()

            // Resume timing
            segmentStartTime = Date()
            #if DEBUG
            print("✅ [RecorderManager] Engine restarted successfully after route change")
            #endif

        } catch {
            #if DEBUG
            print("❌ [RecorderManager] Failed to restart engine: \(error)")
            #endif
        }
    }

    /// Handle route change when using AVAudioRecorder
    private func handleRecorderRouteChange() {
        guard let recorder = audioRecorder, recordingState == .recording else {
            return
        }

        // AVAudioRecorder is more resilient to route changes, but we should
        // reconfigure the session to ensure the correct input is used

        // Save current duration
        if let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }

        // Pause briefly
        recorder.pause()

        // Reconfigure session
        do {
            try AudioSessionManager.shared.configureForRecording(
                quality: qualityPreset,
                settings: appSettings
            )
        } catch {
            #if DEBUG
            print("⚠️ [RecorderManager] Failed to reconfigure session: \(error)")
            #endif
        }

        // Resume recording
        recorder.record()
        segmentStartTime = Date()

        #if DEBUG
        print("✅ [RecorderManager] Recorder resumed after route change")
        #endif
    }

    /// Discard the current recording without saving
    func discardRecording() {
        guard recordingState.isActive, let fileURL = currentFileURL else { return }

        // Stop based on which method is in use
        if isUsingEngine {
            stopEngineRecording()
        } else {
            audioRecorder?.stop()
        }
        stopTimer()

        // Delete the audio file
        try? FileManager.default.removeItem(at: fileURL)

        // End Live Activity
        RecordingLiveActivityManager.shared.endActivity()

        resetState()
        clearInProgressRecording()

        // Deactivate audio session when discarding
        AudioSessionManager.shared.deactivateRecording()
    }

    /// Reset all recording state
    private func resetState() {
        recordingState = .idle
        // Re-enable screen sleep
        UIApplication.shared.isIdleTimerDisabled = false
        isPreparing = false
        currentDuration = 0
        accumulatedDuration = 0
        segmentStartTime = nil
        recordingStartDate = nil
        currentRecordingId = nil

        // Clear AVAudioRecorder
        audioRecorder = nil

        // Clear AVAudioEngine components
        audioEngine = nil
        gainMixerNode = nil
        limiterNode = nil
        audioFile = nil
        isUsingEngine = false
        resolvedEngineSampleRate = nil

        currentFileURL = nil
        liveMeterSamples = []
        wasRecordingBeforeInterruption = false
        consecutiveSilentBuffers = 0
        smoothedPeakLevel = 0
        currentLocation = nil
        currentLocationLabel = ""
    }

    // MARK: - Crash Recovery

    private func markRecordingInProgress(_ fileURL: URL) {
        UserDefaults.standard.set(fileURL.path, forKey: inProgressRecordingKey)
        UserDefaults.standard.set(metronome.isEnabled, forKey: inProgressMetronomeEnabledKey)
        UserDefaults.standard.set(monitorEffects.isEnabled, forKey: inProgressMonitorEffectsEnabledKey)
    }

    private func clearInProgressRecording() {
        UserDefaults.standard.removeObject(forKey: inProgressRecordingKey)
        UserDefaults.standard.removeObject(forKey: inProgressMetronomeEnabledKey)
        UserDefaults.standard.removeObject(forKey: inProgressMonitorEffectsEnabledKey)
    }

    /// Check for and recover any in-progress recording from a crash
    /// Returns the file URL if a recoverable recording exists
    /// Also restores metronome and monitoring effects enabled state
    func checkForRecoverableRecording() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: inProgressRecordingKey) else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: path)

        // Verify the file exists and has content
        guard FileManager.default.fileExists(atPath: path) else {
            clearInProgressRecording()
            return nil
        }

        // Check file has meaningful content (> 1KB)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int,
           size > 1024 {
            // Restore metronome and monitoring effects state
            metronome.isEnabled = UserDefaults.standard.bool(forKey: inProgressMetronomeEnabledKey)
            monitorEffects.isEnabled = UserDefaults.standard.bool(forKey: inProgressMonitorEffectsEnabledKey)
            return fileURL
        }

        // File too small, likely corrupted
        try? FileManager.default.removeItem(at: fileURL)
        clearInProgressRecording()
        return nil
    }

    /// Clear the recoverable recording marker without recovering
    func dismissRecoverableRecording() {
        if let path = UserDefaults.standard.string(forKey: inProgressRecordingKey) {
            try? FileManager.default.removeItem(atPath: path)
        }
        clearInProgressRecording()
    }

    // MARK: - Quality Settings

    private func recordingSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        // Use actual sample rate from audio session (may differ from requested)
        let effectiveSampleRate = AudioSessionManager.shared.actualSampleRate
        let channels = appSettings.recordingMode.channelCount

        switch preset {
        case .standard:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: min(effectiveSampleRate, 44100),
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 128000 * channels,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

        case .high:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: min(effectiveSampleRate, 48000),
                AVNumberOfChannelsKey: channels,
                AVEncoderBitRateKey: 256000 * channels,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]

        case .lossless:
            return [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: min(effectiveSampleRate, 48000),
                AVNumberOfChannelsKey: channels,
                AVEncoderBitDepthHintKey: 16,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]

        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: min(effectiveSampleRate, 48000),
                AVNumberOfChannelsKey: channels,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        }
    }

    // MARK: - Audio File Protection

    /// Protect an audio file after recording: set file protection attributes
    /// and ensure iCloud backup inclusion.
    static func protectAudioFile(at url: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }

        // Set file protection to complete until first user authentication
        // This ensures the file is encrypted at rest but accessible after unlock
        do {
            try fm.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        } catch {
            #if DEBUG
            print("⚠️ [RecorderManager] Failed to set file protection: \(error.localizedDescription)")
            #endif
        }

        // Ensure file is included in iCloud backup (not excluded)
        var fileURL = url
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = false
        do {
            try fileURL.setResourceValues(resourceValues)
        } catch {
            #if DEBUG
            print("⚠️ [RecorderManager] Failed to set backup inclusion: \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Helpers

    private func generateFileURL(for preset: RecordingQualityPreset) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let filename = "recording_\(CachedDateFormatter.fileTimestamp.string(from: Date())).\(preset.fileExtension)"
        return documentsPath.appendingPathComponent(filename)
    }

    /// Legacy method for backwards compatibility
    private func generateFileURL() -> URL {
        generateFileURL(for: qualityPreset)
    }

    private func startTimer() {
        // Use .common mode so timer continues during scroll tracking
        let newTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.recordingState == .recording else { return }

                // Calculate total duration: accumulated + current segment
                if let startTime = self.segmentStartTime {
                    self.currentDuration = self.accumulatedDuration + Date().timeIntervalSince(startTime)
                }
                self.updateMeterSamples()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMeterSamples() {
        guard let recorder = audioRecorder, recordingState == .recording else { return }

        recorder.updateMeters()

        // Use peak power (not average) for responsive, accurate peak metering.
        // peakPower returns the peak sample value in dB for the most recent buffer.
        let dB = recorder.peakPower(forChannel: 0)

        // Map dB to normalized value (0...1) with -60 dB floor for professional range.
        // AVAudioRecorder returns -160 dB for silence; we clamp to -60 dB.
        let minDB: Float = -60
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

// MARK: - CLLocationManagerDelegate

extension RecorderManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location

            // Reverse geocode to get a label
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    // Build a location label from placemark
                    var labelParts: [String] = []
                    if let name = placemark.name {
                        labelParts.append(name)
                    }
                    if let locality = placemark.locality {
                        labelParts.append(locality)
                    }
                    self.currentLocationLabel = labelParts.joined(separator: ", ")
                }
            } catch {
                // Use coordinates as fallback label
                self.currentLocationLabel = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.recordingState.isActive {
                    manager.requestLocation()
                }
            }
        }
    }
}
