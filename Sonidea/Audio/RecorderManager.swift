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

    // Legacy AVAudioRecorder (fallback when no gain/limiter needed)
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentFileURL: URL?
    private var wasRecordingBeforeInterruption = false

    /// Guard against double-start during async Bluetooth path
    private var isPreparing = false

    /// Resolved sample rate for engine recording (set when engine output format is created)
    private var resolvedEngineSampleRate: Double?

    // Crash recovery: key for UserDefaults
    private let inProgressRecordingKey = "inProgressRecordingPath"

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
        let gainLinear = pow(10, inputSettings.gainDb / 20.0)
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
                // Bypass by setting threshold to 0 dB with large headroom
                AudioUnitSetParameter(audioUnit, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, 0, 0)
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

                print("🔄 [RecorderManager] Route change detected, recording: \(self.recordingState.isActive), engine: \(self.isUsingEngine)")

                // If we're recording with the engine and a device changed, we need to restart
                if self.recordingState.isActive && self.isUsingEngine {
                    if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                        print("🔄 [RecorderManager] Bluetooth device changed - restarting engine...")
                        self.handleEngineRouteChange()
                    }
                } else if self.recordingState.isActive && !self.isUsingEngine {
                    // AVAudioRecorder may also need attention on route changes
                    // Force a reconfiguration of the audio session to ensure input is valid
                    if reason == .newDeviceAvailable || reason == .oldDeviceUnavailable {
                        print("🔄 [RecorderManager] Bluetooth device changed - reconfiguring session...")
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

    // MARK: - Recording Control

    func startRecording() {
        guard recordingState == .idle, !isPreparing else { return }

        isPreparing = true

        // Prevent screen sleep if enabled
        if appSettings.preventSleepWhileRecording {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let isBluetooth = AudioSessionManager.shared.isBluetoothOutput()

        if isBluetooth {
            // Bluetooth needs async route stabilization
            Task { @MainActor in
                do {
                    try await AudioSessionManager.shared.configureForRecording(
                        quality: qualityPreset,
                        settings: appSettings
                    )
                } catch {
                    print("Failed to set up audio session: \(error)")
                    self.isPreparing = false
                    return
                }
                self.continueStartRecording()
            }
        } else {
            // Wired/built-in: synchronous path (no wait needed)
            do {
                try AudioSessionManager.shared.configureForRecording(
                    quality: qualityPreset,
                    settings: appSettings
                ) as Void
            } catch {
                print("Failed to set up audio session: \(error)")
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
        let needsEngine = !inputSettings.isDefault
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
            print("Failed to start recording: \(error)")
        }
    }

    /// Start recording using AVAudioEngine with gain and limiter nodes
    private func startEngineRecording(fileURL: URL) {
        do {
            // Create audio engine
            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            // Log input format for debugging
            print("🎙️ [RecorderManager] Engine input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch, \(inputFormat.commonFormat.rawValue)")

            // Verify input format is valid
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                print("❌ [RecorderManager] Invalid input format - falling back to simple recording")
                isUsingEngine = false
                startSimpleRecording(fileURL: fileURL)
                return
            }

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
            engine.connect(inputNode, to: gainMixer, format: inputFormat)
            engine.connect(gainMixer, to: limiter, format: inputFormat)

            // Use limiter's actual output format for tap (avoids sample rate mismatch that causes 0-frame files)
            let tapFormat = limiter.outputFormat(forBus: 0)
            resolvedEngineSampleRate = tapFormat.sampleRate
            print("🎙️ [RecorderManager] Tap format: \(tapFormat.sampleRate)Hz, \(tapFormat.channelCount)ch")

            // Create output audio file matching tap format
            let file = try AVAudioFile(
                forWriting: fileURL,
                settings: engineFileSettings(for: qualityPreset),
                commonFormat: tapFormat.commonFormat,
                interleaved: tapFormat.isInterleaved
            )

            // Install tap on limiter output to write to file (using native format, no conversion)
            limiter.installTap(onBus: 0, bufferSize: 4096, format: tapFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                do {
                    try file.write(from: buffer)
                } catch {
                    print("❌ [RecorderManager] Error writing audio buffer: \(error)")
                }

                // Update meter samples on main thread
                Task { @MainActor in
                    self?.updateMeterFromBuffer(buffer)
                }
            }

            // Store references
            self.audioEngine = engine
            self.gainMixerNode = gainMixer
            self.limiterNode = limiter
            self.audioFile = file

            // Apply current input settings
            applyInputSettings()

            // Start the engine
            try engine.start()

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

            print("🎙️ [RecorderManager] Started engine recording with gain: \(inputSettings.gainDb) dB, limiter: \(inputSettings.limiterEnabled ? "ON" : "OFF")")
        } catch {
            print("❌ [RecorderManager] Failed to start engine recording: \(error)")
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
    private func engineFileSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        let effectiveSampleRate = resolvedEngineSampleRate ?? AudioSessionManager.shared.actualSampleRate
        let channels = appSettings.recordingMode.channelCount

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

    /// Update meter samples from audio buffer (for engine recording)
    private func updateMeterFromBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        // Calculate RMS level
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Detect if we're getting silence (potential Bluetooth routing issue)
        if rms < 0.0001 {
            consecutiveSilentBuffers += 1
            if consecutiveSilentBuffers == silentBufferWarningThreshold {
                print("⚠️ [RecorderManager] WARNING: \(silentBufferWarningThreshold) consecutive silent buffers detected - possible input routing issue!")
                AudioSessionManager.shared.logCurrentRoute(context: "silent buffer warning")
            }
        } else {
            if consecutiveSilentBuffers >= silentBufferWarningThreshold {
                print("✅ [RecorderManager] Audio input recovered after \(consecutiveSilentBuffers) silent buffers")
            }
            consecutiveSilentBuffers = 0
        }

        // Convert to dB and normalize
        let dB = 20 * log10(max(rms, 0.000001))
        let minDB: Float = -50
        let maxDB: Float = 0
        let clampedDB = max(minDB, min(maxDB, dB))
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
            print("⚠️ [RecorderManager] stopRecording called but no active recording")
            return nil
        }

        // Verify we have either engine or recorder
        guard isUsingEngine ? (audioEngine != nil) : (audioRecorder != nil) else {
            print("⚠️ [RecorderManager] stopRecording called but no recorder/engine available")
            return nil
        }

        print("🎙️ [RecorderManager] Stopping recording: \(fileURL.lastPathComponent)")

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
                    print("✅ [RecorderManager] File verified: \(size) bytes")
                }
            } catch {
                print("⚠️ [RecorderManager] Error checking file attributes: \(error.localizedDescription)")
            }
        }

        if !fileVerified {
            print("❌ [RecorderManager] File verification failed")
            AudioDebug.logFileInfo(url: fileURL, context: "RecorderManager.stopRecording - verification failed")
        }

        // Get actual duration from the audio file, not wall clock time
        // Wall clock accumulation can differ from actual audio frames due to buffer latency
        // Fall back to wall clock if file reports 0 (e.g. simulator with no mic input)
        let duration: TimeInterval
        if fileVerified {
            do {
                let audioFile = try AVAudioFile(forReading: fileURL)
                let actualDuration = Double(audioFile.length) / audioFile.processingFormat.sampleRate
                print("✅ [RecorderManager] Actual file duration: \(actualDuration)s (wall clock was: \(accumulatedDuration)s)")
                // Use file duration if valid, otherwise fall back to wall clock
                duration = actualDuration > 0.1 ? actualDuration : accumulatedDuration
            } catch {
                print("⚠️ [RecorderManager] Could not read file for duration, using wall clock: \(error.localizedDescription)")
                duration = accumulatedDuration
            }
        } else {
            duration = accumulatedDuration
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

        // Log final file info for debugging
        AudioDebug.logFileInfo(url: fileURL, context: "RecorderManager.stopRecording - final")

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
        // Remove tap from limiter
        limiterNode?.removeTap(onBus: 0)

        // Stop the engine
        audioEngine?.stop()

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
            } catch {
                print("❌ [RecorderManager] Failed to resume engine: \(error)")
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
            print("⚠️ [RecorderManager] Cannot handle route change - invalid state")
            return
        }

        // Save current accumulated duration
        if let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }

        print("🔄 [RecorderManager] Stopping engine for route change...")

        // Stop the current engine (but keep the file open)
        limiterNode?.removeTap(onBus: 0)
        engine.stop()

        // Small delay to let the audio system settle after route change
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.restartEngineAfterRouteChange()
        }
    }

    /// Restart the engine after a route change
    private func restartEngineAfterRouteChange() {
        guard let engine = audioEngine,
              let gainMixer = gainMixerNode,
              let limiter = limiterNode else {
            print("❌ [RecorderManager] Cannot restart engine - missing components")
            return
        }

        do {
            // Reconfigure audio session to ensure correct input
            try AudioSessionManager.shared.configureForRecording(
                quality: qualityPreset,
                settings: appSettings
            )

            let inputNode = engine.inputNode
            let inputFormat = inputNode.outputFormat(forBus: 0)

            print("🔄 [RecorderManager] New input format: \(inputFormat.sampleRate)Hz, \(inputFormat.channelCount)ch")

            // Verify input format is valid (non-zero sample rate)
            guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
                print("❌ [RecorderManager] Invalid input format after route change")
                return
            }

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
                print("🔄 [RecorderManager] Sample rate changed (\(previousSampleRate) -> \(newOutputFormat.sampleRate)), creating new segment: \(segmentURL.lastPathComponent)")
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
                print("❌ [RecorderManager] No audio file available after route change")
                return
            }

            // Reconnect nodes with new format
            engine.disconnectNodeInput(gainMixer)
            engine.connect(inputNode, to: gainMixer, format: inputFormat)

            // Reinstall tap on limiter
            limiter.installTap(onBus: 0, bufferSize: 4096, format: newOutputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                do {
                    try activeFile.write(from: buffer)
                } catch {
                    print("❌ [RecorderManager] Error writing audio buffer: \(error)")
                }

                Task { @MainActor in
                    self?.updateMeterFromBuffer(buffer)
                }
            }

            // Restart the engine
            try engine.start()

            // Resume timing
            segmentStartTime = Date()
            print("✅ [RecorderManager] Engine restarted successfully after route change")

        } catch {
            print("❌ [RecorderManager] Failed to restart engine: \(error)")
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
            print("⚠️ [RecorderManager] Failed to reconfigure session: \(error)")
        }

        // Resume recording
        recorder.record()
        segmentStartTime = Date()

        print("✅ [RecorderManager] Recorder resumed after route change")
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
        currentLocation = nil
        currentLocationLabel = ""
    }

    // MARK: - Crash Recovery

    private func markRecordingInProgress(_ fileURL: URL) {
        UserDefaults.standard.set(fileURL.path, forKey: inProgressRecordingKey)
    }

    private func clearInProgressRecording() {
        UserDefaults.standard.removeObject(forKey: inProgressRecordingKey)
    }

    /// Check for and recover any in-progress recording from a crash
    /// Returns the file URL if a recoverable recording exists
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

    // MARK: - Helpers

    private func generateFileURL(for preset: RecordingQualityPreset) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).\(preset.fileExtension)"
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
        print("Location error: \(error.localizedDescription)")
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
