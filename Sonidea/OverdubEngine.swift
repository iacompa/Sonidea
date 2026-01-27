//
//  OverdubEngine.swift
//  Sonidea
//
//  Created by Claude on 1/25/26.
//

import AVFoundation
import Foundation
import Observation

/// Engine state for overdub session
enum OverdubEngineState: Equatable {
    case idle
    case playing          // Playing base (and layers) for reference
    case recording        // Recording a new layer while playing base
    case paused
}

/// Handles simultaneous playback and recording for overdub sessions
@MainActor
@Observable
final class OverdubEngine {
    // MARK: - Observable State

    private(set) var state: OverdubEngineState = .idle
    private(set) var currentPlaybackTime: TimeInterval = 0
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var meterLevel: Float = 0

    /// Volume for base track monitoring (0...1)
    var baseVolume: Float = 1.0 {
        didSet {
            basePlayerNode?.volume = baseVolume
        }
    }

    /// Volume for layer monitoring (0...1)
    var layerVolume: Float = 1.0 {
        didSet {
            for player in layerPlayerNodes {
                player.volume = layerVolume
            }
        }
    }

    /// Whether to monitor previous layers during recording
    var monitorLayers: Bool = true

    // MARK: - Private Audio Components

    private var audioEngine: AVAudioEngine?
    private var basePlayerNode: AVAudioPlayerNode?
    private var layerPlayerNodes: [AVAudioPlayerNode] = []
    private var recordingFile: AVAudioFile?
    private var recordingFileURL: URL?

    private var baseAudioFile: AVAudioFile?
    private var layerAudioFiles: [AVAudioFile] = []
    private var layerOffsets: [TimeInterval] = []

    private var timer: Timer?
    private var recordingStartTime: Date?
    private var playbackStartHostTime: UInt64 = 0
    private(set) var failedLayerIndices: [Int] = []

    /// Thread-safe write failure counter (accessed from audio tap thread)
    private let writeFailureCounter = WriteFailureCounter()

    /// Set by engine when a critical error occurs during recording (e.g. disk full)
    private(set) var recordingError: String?

    // Base recording info
    private var baseDuration: TimeInterval = 0

    // MARK: - Initialization

    init() {}

    // MARK: - Setup

    /// Prepare the engine for overdub with a base track and optional existing layers
    func prepare(
        baseFileURL: URL,
        baseDuration: TimeInterval,
        layerFileURLs: [URL] = [],
        layerOffsets: [TimeInterval] = [],
        quality: RecordingQualityPreset,
        settings: AppSettings
    ) throws {
        // Reset any existing state
        stop()

        // Configure audio session for overdub
        try AudioSessionManager.shared.configureForOverdub(quality: quality, settings: settings)

        // Create audio engine
        let engine = AVAudioEngine()

        // Load base audio file
        let baseFile = try AVAudioFile(forReading: baseFileURL)
        self.baseAudioFile = baseFile
        self.baseDuration = baseDuration

        // Create base player node
        let basePlayer = AVAudioPlayerNode()
        engine.attach(basePlayer)
        self.basePlayerNode = basePlayer

        // Connect base player to main mixer
        let mainMixer = engine.mainMixerNode
        engine.connect(basePlayer, to: mainMixer, format: baseFile.processingFormat)

        // Load layer audio files
        self.layerAudioFiles = []
        self.layerPlayerNodes = []
        self.layerOffsets = layerOffsets
        self.failedLayerIndices = []

        for (index, layerURL) in layerFileURLs.enumerated() {
            do {
                let layerFile = try AVAudioFile(forReading: layerURL)
                layerAudioFiles.append(layerFile)

                let layerPlayer = AVAudioPlayerNode()
                engine.attach(layerPlayer)
                engine.connect(layerPlayer, to: mainMixer, format: layerFile.processingFormat)
                layerPlayerNodes.append(layerPlayer)
            } catch {
                print("⚠️ [OverdubEngine] Failed to load layer \(index): \(error)")
                failedLayerIndices.append(index + 1)
            }
        }

        self.audioEngine = engine
        state = .idle

        print("🎙️ [OverdubEngine] Prepared with base: \(baseFileURL.lastPathComponent), \(layerFileURLs.count) layers")
    }

    // MARK: - Playback Control

    /// Start playing the base track (and layers) for reference
    func play() {
        guard let engine = audioEngine,
              let basePlayer = basePlayerNode,
              let baseFile = baseAudioFile else {
            print("⚠️ [OverdubEngine] Cannot play: engine not prepared")
            return
        }

        do {
            if !engine.isRunning {
                try engine.start()
            }

            // Schedule base track from current position
            let sampleRate = baseFile.processingFormat.sampleRate
            let startFrame = min(AVAudioFramePosition(currentPlaybackTime * sampleRate), baseFile.length)

            // Schedule from startFrame to end
            let remaining = baseFile.length - startFrame
            if remaining > 0 {
                let framesToPlay = AVAudioFrameCount(remaining)
                basePlayer.scheduleSegment(
                    baseFile,
                    startingFrame: startFrame,
                    frameCount: framesToPlay,
                    at: nil
                )
            }

            // Schedule layers with their offsets
            for (index, layerPlayer) in layerPlayerNodes.enumerated() {
                guard index < layerAudioFiles.count else { continue }
                let layerFile = layerAudioFiles[index]
                let offset = index < layerOffsets.count ? layerOffsets[index] : 0

                // Calculate layer start frame accounting for offset
                let layerStartTime = max(0, currentPlaybackTime - offset)
                let layerStartFrame = AVAudioFramePosition(layerStartTime * layerFile.processingFormat.sampleRate)

                if layerStartFrame < layerFile.length {
                    let framesToPlay = AVAudioFrameCount(layerFile.length - layerStartFrame)
                    layerPlayer.scheduleSegment(
                        layerFile,
                        startingFrame: layerStartFrame,
                        frameCount: framesToPlay,
                        at: nil
                    )
                    if monitorLayers {
                        layerPlayer.play()
                    }
                }
            }

            basePlayer.play()
            playbackStartHostTime = mach_absolute_time()
            state = .playing
            startTimer()

        } catch {
            print("❌ [OverdubEngine] Failed to start playback: \(error)")
        }
    }

    /// Pause playback
    func pause() {
        basePlayerNode?.pause()
        for player in layerPlayerNodes {
            player.pause()
        }
        stopTimer()
        state = .paused
    }

    /// Stop playback and reset position
    func stop() {
        stopRecordingInternal()
        basePlayerNode?.stop()
        for player in layerPlayerNodes {
            player.stop()
        }
        audioEngine?.stop()
        AudioSessionManager.shared.deactivate()
        stopTimer()
        currentPlaybackTime = 0
        recordingDuration = 0
        state = .idle
    }

    /// Seek to a specific time
    func seek(to time: TimeInterval) {
        let wasPlaying = state == .playing

        // Stop current playback
        basePlayerNode?.stop()
        for player in layerPlayerNodes {
            player.stop()
        }

        currentPlaybackTime = max(0, min(time, baseDuration))

        if wasPlaying {
            play()
        }
    }

    // MARK: - Recording Control

    /// Start recording a new layer while playing the base.
    /// For Bluetooth: re-activates the session and waits for route stabilization
    /// to avoid error 560226676 (invalid input format during HFP transition).
    func startRecording(outputURL: URL, quality: RecordingQualityPreset) async throws {
        guard let engine = audioEngine else {
            throw OverdubEngineError.engineNotPrepared
        }

        // Check headphones
        guard AudioSessionManager.shared.isHeadphoneMonitoringActive() else {
            throw OverdubEngineError.headphonesRequired
        }

        let session = AVAudioSession.sharedInstance()

        // --- Ensure output directory exists and handle file collisions ---
        let outputDir = outputURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: outputDir.path) {
            try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        }
        var finalURL = outputURL
        if FileManager.default.fileExists(atPath: finalURL.path) {
            // Append UUID to avoid collision
            let stem = finalURL.deletingPathExtension().lastPathComponent
            let ext = finalURL.pathExtension
            finalURL = outputDir.appendingPathComponent("\(stem)_\(UUID().uuidString.prefix(6)).\(ext)")
        }

        // --- Re-activate session to ensure Bluetooth HFP route is stable ---
        // When switching from A2DP to HFP, iOS needs time to negotiate the route.
        // Re-setting the category + activating forces the route transition now.
        let isBluetooth = AudioSessionManager.shared.isBluetoothOutput()
        if isBluetooth {
            #if DEBUG
            print("🔄 [OverdubEngine] Bluetooth detected — re-activating session for HFP route")
            #endif
            try session.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth])
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            // Poll for valid input format with timeout (HFP negotiation can take 200-1500ms)
            var routeReady = false
            for attempt in 1...6 {
                try await Task.sleep(nanoseconds: 300_000_000) // 300ms per attempt
                let inputs = session.currentRoute.inputs
                if !inputs.isEmpty {
                    routeReady = true
                    #if DEBUG
                    print("✅ [OverdubEngine] Bluetooth route ready after attempt \(attempt)")
                    #endif
                    break
                }
                #if DEBUG
                print("⏳ [OverdubEngine] Bluetooth route not ready, attempt \(attempt)/6")
                #endif
            }
            if !routeReady {
                throw OverdubEngineError.recordingFailed("Bluetooth audio route did not stabilize. Try disconnecting and reconnecting your Bluetooth device, or use wired headphones.")
            }
        }

        #if DEBUG
        print("🎙️ [OverdubEngine] Starting recording - Debug info:")
        print("   Session category: \(session.category.rawValue)")
        print("   Session sample rate: \(session.sampleRate)")
        print("   Route inputs: \(session.currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        print("   Route outputs: \(session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        #endif

        // Verify we have a valid input route
        if session.currentRoute.inputs.isEmpty {
            if isBluetooth {
                throw OverdubEngineError.recordingFailed("Can't record with this Bluetooth device — it doesn't support microphone input. Try using wired headphones or AirPods.")
            }
            throw OverdubEngineError.recordingFailed("No audio input available. Please check your microphone connection.")
        }

        // Stop and reset the engine to pick up the new route/format
        // This is critical for Bluetooth: the input node format is stale until the engine restarts.
        if engine.isRunning {
            engine.stop()
        }
        engine.reset()

        // Re-attach and re-connect player nodes (engine.reset() detaches all nodes)
        let mainMixer = engine.mainMixerNode
        if let basePlayer = basePlayerNode, let baseFile = baseAudioFile {
            engine.attach(basePlayer)
            engine.connect(basePlayer, to: mainMixer, format: baseFile.processingFormat)
        }
        for (index, layerPlayer) in layerPlayerNodes.enumerated() {
            guard index < layerAudioFiles.count else { continue }
            let layerFile = layerAudioFiles[index]
            engine.attach(layerPlayer)
            engine.connect(layerPlayer, to: mainMixer, format: layerFile.processingFormat)
        }

        // Get input node and validate its format AFTER engine reset
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        #if DEBUG
        print("   Input format after reset: sr=\(inputFormat.sampleRate) ch=\(inputFormat.channelCount)")
        #endif

        // Validate input format
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            if isBluetooth {
                throw OverdubEngineError.recordingFailed("Can't start recording with this Bluetooth route. Try disconnecting Bluetooth or use wired headphones.")
            }
            throw OverdubEngineError.recordingFailed("Invalid audio input format. Try disconnecting and reconnecting your audio device.")
        }

        // Create recording file with validated format
        let fileSettings = recordingSettings(for: quality)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: finalURL,
                settings: fileSettings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
        } catch {
            #if DEBUG
            print("❌ [OverdubEngine] Failed to create audio file: \(error)")
            if let nsError = error as NSError? {
                print("   Error domain: \(nsError.domain), code: \(nsError.code)")
            }
            #endif
            throw OverdubEngineError.recordingFailed("Could not create recording file: \(error.localizedDescription)")
        }

        self.recordingFile = file
        self.recordingFileURL = finalURL

        // Install tap on input to record
        writeFailureCounter.reset()
        recordingError = nil
        let failureCounter = writeFailureCounter  // capture for closure (non-isolated)
        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
            do {
                try file.write(from: buffer)
                failureCounter.markSuccess()
            } catch {
                if failureCounter.increment() {
                    Task { @MainActor in
                        self?.recordingError = "Recording failed: could not write audio data. Your storage may be full."
                        self?.stopRecordingInternal()
                    }
                    return
                }
            }

            Task { @MainActor in
                self?.updateMeterFromBuffer(buffer)
            }
        }

        // Start engine
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            #if DEBUG
            print("❌ [OverdubEngine] Failed to start engine: \(error)")
            #endif
            throw OverdubEngineError.recordingFailed("Could not start audio engine: \(error.localizedDescription)")
        }

        // Start playback of base and layers
        currentPlaybackTime = 0
        playBase()
        playLayers()

        recordingStartTime = Date()
        state = .recording
        startTimer()

        print("🎙️ [OverdubEngine] Started recording to: \(finalURL.lastPathComponent)")
    }

    /// Stop recording and return the recorded duration
    func stopRecording() -> TimeInterval {
        let duration = recordingDuration
        stopRecordingInternal()
        return duration
    }

    private func stopRecordingInternal() {
        // Remove tap
        audioEngine?.inputNode.removeTap(onBus: 0)

        // Close recording file
        recordingFile = nil
        recordingStartTime = nil

        // Stop playback
        basePlayerNode?.stop()
        for player in layerPlayerNodes {
            player.stop()
        }

        stopTimer()

        if state == .recording {
            state = .idle
        }
    }

    // MARK: - Private Helpers

    private func playBase() {
        guard let basePlayer = basePlayerNode,
              let baseFile = baseAudioFile else { return }

        basePlayer.scheduleFile(baseFile, at: nil)
        basePlayer.volume = baseVolume
        basePlayer.play()
    }

    private func playLayers() {
        guard monitorLayers else { return }

        for (index, layerPlayer) in layerPlayerNodes.enumerated() {
            guard index < layerAudioFiles.count else { continue }
            let layerFile = layerAudioFiles[index]
            let offset = index < layerOffsets.count ? layerOffsets[index] : 0

            // Schedule with offset
            if offset > 0 {
                // Positive offset: delay the layer start
                let hostTimeOffset = AVAudioTime.hostTime(forSeconds: offset)
                let startTime = AVAudioTime(hostTime: mach_absolute_time() + hostTimeOffset)
                layerPlayer.scheduleFile(layerFile, at: startTime)
            } else if offset < 0 {
                // Negative offset: skip into the layer (start playback from later in the file)
                let skipSeconds = -offset
                let sampleRate = layerFile.processingFormat.sampleRate
                let skipFrames = AVAudioFramePosition(skipSeconds * sampleRate)
                let remainingFrames = AVAudioFrameCount(layerFile.length - skipFrames)
                if skipFrames < layerFile.length && remainingFrames > 0 {
                    layerPlayer.scheduleSegment(
                        layerFile,
                        startingFrame: skipFrames,
                        frameCount: remainingFrames,
                        at: nil
                    )
                } else {
                    // Offset exceeds layer length — skip this layer
                    continue
                }
            } else {
                layerPlayer.scheduleFile(layerFile, at: nil)
            }

            layerPlayer.volume = layerVolume
            layerPlayer.play()
        }
    }

    private func recordingSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        let sampleRate = AudioSessionManager.shared.actualSampleRate

        switch preset {
        case .standard:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: min(sampleRate, 44100),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
        case .high:
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: min(sampleRate, 48000),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 256000,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        case .lossless:
            return [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: min(sampleRate, 48000),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitDepthHintKey: 16,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        case .wav:
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: min(sampleRate, 48000),
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        }
    }

    private func startTimer() {
        // Use .common mode so timer continues during scroll tracking
        let newTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateTime()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateTime() {
        if state == .recording, let startTime = recordingStartTime {
            recordingDuration = Date().timeIntervalSince(startTime)
            currentPlaybackTime = recordingDuration
        } else if state == .playing, let basePlayer = basePlayerNode,
                  let nodeTime = basePlayer.lastRenderTime,
                  let playerTime = basePlayer.playerTime(forNodeTime: nodeTime) {
            let sampleRate = baseAudioFile?.processingFormat.sampleRate ?? 48000
            currentPlaybackTime = Double(playerTime.sampleTime) / sampleRate
        }
    }

    private func updateMeterFromBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[0][i]
            sum += sample * sample
        }
        let rms = sqrt(sum / Float(frameLength))

        // Convert to normalized level (0...1)
        let dB = 20 * log10(max(rms, 0.000001))
        let minDB: Float = -50
        let maxDB: Float = 0
        let clampedDB = max(minDB, min(maxDB, dB))
        meterLevel = (clampedDB - minDB) / (maxDB - minDB)
    }

    // MARK: - Cleanup

    func cleanup() {
        stop()
        audioEngine = nil
        basePlayerNode = nil
        layerPlayerNodes = []
        baseAudioFile = nil
        layerAudioFiles = []
        recordingFile = nil
    }
}

// MARK: - Errors

// MARK: - Thread-Safe Write Failure Counter

/// Accessed from audio tap thread — must be thread-safe
final class WriteFailureCounter: @unchecked Sendable {
    private var _count = 0
    private let lock = NSLock()
    let maxFailures = 10

    func reset() {
        lock.lock()
        _count = 0
        lock.unlock()
    }

    /// Increments and returns true if max failures reached
    func increment() -> Bool {
        lock.lock()
        _count += 1
        let exceeded = _count >= maxFailures
        lock.unlock()
        return exceeded
    }

    func markSuccess() {
        lock.lock()
        _count = 0
        lock.unlock()
    }
}

enum OverdubEngineError: Error, LocalizedError {
    case engineNotPrepared
    case headphonesRequired
    case noInputAvailable
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .engineNotPrepared:
            return "Audio engine not prepared. Please try again."
        case .headphonesRequired:
            return "Headphones are required for recording over a track to prevent feedback."
        case .noInputAvailable:
            return "No microphone input available. If using Bluetooth headphones, ensure they support hands-free calling (HFP). Some Bluetooth audio devices only support playback."
        case .recordingFailed(let reason):
            return reason
        }
    }
}
