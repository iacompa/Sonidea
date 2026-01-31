//
//  OverdubEngine.swift
//  Sonidea
//
//  Created by Claude on 1/25/26.
//

import Accelerate
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

    /// Apply mix settings from the overdub group to player volumes and pans.
    func applyMixSettings(_ settings: MixSettings) {
        let volumes = settings.effectiveVolumes()

        basePlayerNode?.volume = volumes.base
        basePlayerNode?.pan = settings.baseChannel.pan

        for (i, player) in layerPlayerNodes.enumerated() {
            player.volume = i < volumes.layers.count ? volumes.layers[i] : 1.0
            player.pan = i < settings.layerChannels.count ? settings.layerChannels[i].pan : 0.0
        }
    }

    // MARK: - Private Audio Components

    private var audioEngine: AVAudioEngine?
    private var basePlayerNode: AVAudioPlayerNode?
    private var layerPlayerNodes: [AVAudioPlayerNode] = []
    private var recordingFile: AVAudioFile?
    private var recordingFileURL: URL?

    private var baseAudioFile: AVAudioFile?
    private var layerAudioFiles: [AVAudioFile] = []
    private var layerOffsets: [TimeInterval] = []
    private var loopFlags: [Bool] = []  // index 0 = base, 1..N = layers

    /// Pre-loaded PCM buffers for looped tracks (used with .loops scheduling)
    private var baseLoopBuffer: AVAudioPCMBuffer?
    private var layerLoopBuffers: [AVAudioPCMBuffer?] = []

    private var timer: Timer?
    private var recordingStartTime: Date?
    private var playbackStartHostTime: UInt64 = 0
    private var playbackTimeOffset: TimeInterval = 0
    private(set) var failedLayerIndices: [Int] = []

    /// User-visible warning when some layers fail to load
    private(set) var layerWarning: String?

    /// Thread-safe write failure counter (accessed from audio tap thread)
    private let writeFailureCounter = WriteFailureCounter()

    /// Serial queue for writing audio buffers to file — keeps I/O off the real-time render thread
    private let fileWriteQueue = DispatchQueue(label: "com.iacompa.sonidea.overdub.filewrite", qos: .userInitiated)

    /// Set by engine when a critical error occurs during recording (e.g. disk full)
    private(set) var recordingError: String?

    /// Stored input sample rate for recording settings
    private var inputSampleRate: Double = 48000

    /// Frame-accurate recording duration counter (incremented from the write queue)
    private var writtenFrameCount: Int64 = 0

    /// Observer for audio session interruption notifications
    private var interruptionObserver: NSObjectProtocol?

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
        loopFlags: [Bool] = [],
        quality: RecordingQualityPreset,
        settings: AppSettings
    ) throws {
        // Reset any existing state (don't deactivate session since we're about to reconfigure it)
        stop(deactivateSession: false)
        self.loopFlags = loopFlags

        // Configure audio session for overdub
        try AudioSessionManager.shared.configureForOverdub(quality: quality, settings: settings)

        // Create audio engine
        let engine = AVAudioEngine()

        // Load base audio file
        let baseFile = try AVAudioFile(forReading: baseFileURL)
        self.baseAudioFile = baseFile
        self.baseDuration = baseDuration
        let baseSampleRate = baseFile.processingFormat.sampleRate

        // Validate base file duration
        let actualDuration = Double(baseFile.length) / baseFile.processingFormat.sampleRate
        if abs(actualDuration - baseDuration) > 1.0 {
            print("⚠️ [OverdubEngine] Base file duration mismatch: expected \(baseDuration)s, actual \(actualDuration)s. Using actual.")
            self.baseDuration = actualDuration
        }

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

                guard layerFile.processingFormat.sampleRate > 0 else {
                    print("⚠️ [OverdubEngine] Layer \(index) has invalid sample rate, skipping")
                    failedLayerIndices.append(index + 1)
                    continue
                }

                if layerFile.processingFormat.sampleRate != baseSampleRate {
                    print("⚠️ [OverdubEngine] Layer \(index) sample rate (\(layerFile.processingFormat.sampleRate)) differs from base (\(baseSampleRate)). AVAudioEngine will convert automatically.")
                }

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

        // Surface failed layers as a warning
        if !failedLayerIndices.isEmpty {
            let layerNames = failedLayerIndices.map { "Layer \($0)" }.joined(separator: ", ")
            layerWarning = "\(layerNames) could not be loaded and won't play during monitoring."
            print("⚠️ [OverdubEngine] Failed to load: \(layerNames)")
        } else {
            layerWarning = nil
        }

        // Auto-reduce mixer gain to prevent clipping with multiple sources
        let sourceCount = 1 + layerAudioFiles.count // base + layers
        if sourceCount > 1 {
            let headroomGain = 1.0 / sqrt(Float(sourceCount))
            engine.mainMixerNode.outputVolume = headroomGain
            print("🎚️ [OverdubEngine] Auto headroom: \(sourceCount) sources, mixer gain = \(headroomGain)")
        }

        // Pre-load PCM buffers for looped tracks (needed for .loops scheduling)
        baseLoopBuffer = nil
        layerLoopBuffers = Array(repeating: nil, count: layerAudioFiles.count)

        let baseIsLooped = !loopFlags.isEmpty && loopFlags[0]
        if baseIsLooped {
            baseLoopBuffer = loadFullBuffer(from: baseFile)
        }
        for (i, layerFile) in layerAudioFiles.enumerated() {
            let isLooped = (i + 1) < loopFlags.count && loopFlags[i + 1]
            if isLooped {
                layerLoopBuffers[i] = loadFullBuffer(from: layerFile)
            }
        }

        self.audioEngine = engine
        state = .idle

        print("🎙️ [OverdubEngine] Prepared with base: \(baseFileURL.lastPathComponent), \(layerFileURLs.count) layers")
    }

    /// Prepare the engine for preview playback including an unsaved layer
    func prepareForPreview(
        baseFileURL: URL,
        baseDuration: TimeInterval,
        existingLayerURLs: [URL],
        existingLayerOffsets: [TimeInterval],
        previewLayerURL: URL,
        previewLayerOffset: TimeInterval,
        loopFlags: [Bool] = [],
        quality: RecordingQualityPreset,
        settings: AppSettings
    ) throws {
        var allURLs = existingLayerURLs
        allURLs.append(previewLayerURL)
        var allOffsets = existingLayerOffsets
        allOffsets.append(previewLayerOffset)
        // Preview layer (unsaved) is not looped — append false
        var allFlags = loopFlags
        if allFlags.count < allURLs.count + 1 {
            while allFlags.count < allURLs.count + 1 {
                allFlags.append(false)
            }
        }
        try prepare(
            baseFileURL: baseFileURL,
            baseDuration: baseDuration,
            layerFileURLs: allURLs,
            layerOffsets: allOffsets,
            loopFlags: allFlags,
            quality: quality,
            settings: settings
        )
    }

    /// Update the preview layer offset (last layer) and restart playback if active
    func updatePreviewOffset(_ offset: TimeInterval) {
        guard !layerOffsets.isEmpty else { return }
        layerOffsets[layerOffsets.count - 1] = offset
        if state == .playing {
            currentPlaybackTime = 0
            play()
        }
    }

    /// Update offset for a specific layer by index
    func updateLayerOffset(at layerIndex: Int, offset: TimeInterval) {
        guard layerIndex >= 0 && layerIndex < layerOffsets.count else { return }
        layerOffsets[layerIndex] = offset
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

        // Stop player nodes before rescheduling to prevent doubled audio on pause/resume
        basePlayer.stop()
        for player in layerPlayerNodes { player.stop() }

        // Store seek offset so updateTime() can add it to the player-relative time
        playbackTimeOffset = currentPlaybackTime

        do {
            if !engine.isRunning {
                try engine.start()
            }

            // Schedule base track from current position
            let sampleRate = baseFile.processingFormat.sampleRate
            let baseIsLooped = !loopFlags.isEmpty && loopFlags[0]

            if baseIsLooped, let buffer = baseLoopBuffer {
                // For looped base at a seek position, schedule the full buffer with .loops
                // AVAudioPlayerNode will start from the beginning of the buffer
                basePlayer.scheduleBuffer(buffer, at: nil, options: .loops)
            } else {
                let startFrame = min(AVAudioFramePosition(currentPlaybackTime * sampleRate), baseFile.length)
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
            }

            // Schedule layers with their offsets
            for (index, layerPlayer) in layerPlayerNodes.enumerated() {
                guard index < layerAudioFiles.count else { continue }
                let layerFile = layerAudioFiles[index]
                let offset = index < layerOffsets.count ? layerOffsets[index] : 0
                let isLooped = (index + 1) < loopFlags.count && loopFlags[index + 1]

                if isLooped, let buffer = (index < layerLoopBuffers.count ? layerLoopBuffers[index] : nil) {
                    // Looped layer — schedule with .loops
                    if currentPlaybackTime < offset {
                        let delaySec = offset - currentPlaybackTime
                        let delayHostTime = AVAudioTime.hostTime(forSeconds: delaySec)
                        let startTime = AVAudioTime(hostTime: mach_absolute_time() + delayHostTime)
                        layerPlayer.scheduleBuffer(buffer, at: startTime, options: .loops)
                    } else {
                        layerPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
                    }
                    if monitorLayers {
                        layerPlayer.play()
                    }
                } else if currentPlaybackTime < offset {
                    // Playback position is before this layer starts — schedule with a delay
                    let delaySec = offset - currentPlaybackTime
                    let delayHostTime = AVAudioTime.hostTime(forSeconds: delaySec)
                    let startTime = AVAudioTime(hostTime: mach_absolute_time() + delayHostTime)
                    layerPlayer.scheduleFile(layerFile, at: startTime)
                    if monitorLayers {
                        layerPlayer.play()
                    }
                } else {
                    // Playback position is at or past this layer's offset — skip into the layer
                    let layerStartTime = currentPlaybackTime - offset
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
            }

            basePlayer.play()
            playbackStartHostTime = mach_absolute_time()
            state = .playing
            startTimer()

        } catch {
            print("❌ [OverdubEngine] Failed to start playback: \(error)")
            recordingError = "Failed to start playback: \(error.localizedDescription)"
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
    /// - Parameter deactivateSession: Whether to deactivate the audio session. Pass `false` when
    ///   stop is called from prepare() since prepare() will immediately reconfigure the session.
    func stop(deactivateSession: Bool = true) {
        stopRecordingInternal()
        basePlayerNode?.stop()
        for player in layerPlayerNodes {
            player.stop()
        }
        audioEngine?.stop()
        if deactivateSession {
            AudioSessionManager.shared.deactivate()
        }
        stopTimer()
        currentPlaybackTime = 0
        playbackTimeOffset = 0
        recordingDuration = 0
        state = .idle
    }

    /// Seek to a specific time
    func seek(to time: TimeInterval) {
        guard state != .recording else { return }
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

        // Check available disk space (require at least 50MB)
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: documentsURL.path),
           let freeSpace = attrs[.systemFreeSize] as? Int64,
           freeSpace < 50_000_000 {
            throw OverdubEngineError.recordingFailed("Not enough storage space. Please free up at least 50MB to record.")
        }

        // Check microphone permission
        let permissionStatus = AVAudioSession.sharedInstance().recordPermission
        switch permissionStatus {
        case .denied:
            throw OverdubEngineError.recordingFailed("Microphone access denied. Please enable microphone permission in Settings > Privacy > Microphone.")
        case .undetermined:
            let granted = await withCheckedContinuation { continuation in
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
            if !granted {
                throw OverdubEngineError.recordingFailed("Microphone permission is required to record audio.")
            }
        case .granted:
            break
        @unknown default:
            break
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

        // Stop the engine to pick up the new route/format
        // Avoid engine.reset() which detaches all nodes and can cause format mismatches.
        // Instead, stop the engine, create fresh player nodes, and re-attach them.
        if engine.isRunning {
            engine.stop()
        }

        // Create fresh player nodes to avoid stale state from previous runs
        let mainMixer = engine.mainMixerNode

        // Detach old nodes before creating new ones
        if let oldBase = basePlayerNode {
            engine.detach(oldBase)
        }
        for oldLayer in layerPlayerNodes {
            engine.detach(oldLayer)
        }

        // Create and attach fresh base player
        if let baseFile = baseAudioFile {
            let newBasePlayer = AVAudioPlayerNode()
            engine.attach(newBasePlayer)
            engine.connect(newBasePlayer, to: mainMixer, format: baseFile.processingFormat)
            newBasePlayer.volume = baseVolume
            basePlayerNode = newBasePlayer
        }

        // Create and attach fresh layer players
        var newLayerPlayers: [AVAudioPlayerNode] = []
        for (index, layerFile) in layerAudioFiles.enumerated() {
            let newLayerPlayer = AVAudioPlayerNode()
            engine.attach(newLayerPlayer)
            engine.connect(newLayerPlayer, to: mainMixer, format: layerFile.processingFormat)
            newLayerPlayer.volume = layerVolume
            newLayerPlayers.append(newLayerPlayer)
            _ = index // suppress unused warning
        }
        layerPlayerNodes = newLayerPlayers

        // Get input node and validate its format AFTER engine reset
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        inputSampleRate = inputFormat.sampleRate

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
            file = try AVAudioFile(forWriting: finalURL, settings: fileSettings)
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
        writtenFrameCount = 0
        writeFailureCounter.reset()
        recordingError = nil
        let failureCounter = writeFailureCounter  // capture for closure (non-isolated)
        let writeQueue = self.fileWriteQueue
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
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
                    failureCounter.markSuccess()
                    // Track frames written for accurate duration
                    let frames = Int64(copy.frameLength)
                    Task { @MainActor in
                        self?.writtenFrameCount += frames
                    }
                } catch {
                    if failureCounter.increment() {
                        Task { @MainActor in
                            self?.recordingError = "Recording failed: could not write audio data. Your storage may be full."
                            self?.stopRecordingInternal()
                        }
                    }
                }
            }

            // Update meter samples on main thread (uses original buffer — read-only)
            Task { @MainActor in
                self?.updateMeterFromBuffer(buffer)
            }
        }

        // Start engine
        do {
            try engine.start()
        } catch {
            inputNode.removeTap(onBus: 0)
            basePlayerNode = nil
            layerPlayerNodes = []
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

        // Observe audio session interruptions
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }

        print("🎙️ [OverdubEngine] Started recording to: \(finalURL.lastPathComponent)")
    }

    /// Stop recording and return the recorded duration (frame-accurate)
    func stopRecording() -> TimeInterval {
        stopRecordingInternal()
        // Compute duration from actual written frames instead of wall-clock
        let sampleRate = inputSampleRate > 0 ? inputSampleRate : 48000
        let duration = Double(writtenFrameCount) / sampleRate
        recordingDuration = duration
        return duration
    }

    private func stopRecordingInternal() {
        // Remove interruption observer to prevent accumulation across recordings
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }

        // Remove tap (stops new buffers from being enqueued)
        audioEngine?.inputNode.removeTap(onBus: 0)

        // Drain the write queue to ensure all pending buffers are written to disk
        fileWriteQueue.sync {}

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

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

        switch type {
        case .began:
            print("⚠️ [OverdubEngine] Audio interruption began")
            if state == .recording {
                stopRecordingInternal()
                recordingError = "Recording was interrupted (phone call or other audio). Your partial recording was saved."
            }
        case .ended:
            print("ℹ️ [OverdubEngine] Audio interruption ended")
        @unknown default:
            break
        }
    }

    // MARK: - Private Helpers

    private func playBase() {
        guard let basePlayer = basePlayerNode,
              let baseFile = baseAudioFile else { return }

        let baseIsLooped = !loopFlags.isEmpty && loopFlags[0]

        if baseIsLooped, let buffer = baseLoopBuffer {
            basePlayer.scheduleBuffer(buffer, at: nil, options: .loops)
        } else {
            basePlayer.scheduleFile(baseFile, at: nil)
        }

        basePlayer.volume = baseVolume
        basePlayer.play()
    }

    private func playLayers() {
        guard monitorLayers else { return }

        // Stop all layer players before rescheduling to prevent memory leak
        for player in layerPlayerNodes {
            player.stop()
        }

        for (index, layerPlayer) in layerPlayerNodes.enumerated() {
            guard index < layerAudioFiles.count else { continue }
            let layerFile = layerAudioFiles[index]
            let offset = index < layerOffsets.count ? layerOffsets[index] : 0
            let isLooped = (index + 1) < loopFlags.count && loopFlags[index + 1]

            if isLooped, let buffer = (index < layerLoopBuffers.count ? layerLoopBuffers[index] : nil) {
                // Looped layer — schedule buffer with .loops
                if offset > 0 {
                    let hostTimeOffset = AVAudioTime.hostTime(forSeconds: offset)
                    let startTime = AVAudioTime(hostTime: mach_absolute_time() + hostTimeOffset)
                    layerPlayer.scheduleBuffer(buffer, at: startTime, options: .loops)
                } else {
                    layerPlayer.scheduleBuffer(buffer, at: nil, options: .loops)
                }
            } else {
                // Non-looped layer — schedule with offset (existing behavior)
                if offset > 0 {
                    let hostTimeOffset = AVAudioTime.hostTime(forSeconds: offset)
                    let startTime = AVAudioTime(hostTime: mach_absolute_time() + hostTimeOffset)
                    layerPlayer.scheduleFile(layerFile, at: startTime)
                } else if offset < 0 {
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
                        continue
                    }
                } else {
                    layerPlayer.scheduleFile(layerFile, at: nil)
                }
            }

            layerPlayer.volume = layerVolume
            layerPlayer.play()
        }
    }

    /// Load an entire audio file into a PCM buffer for loop scheduling
    private func loadFullBuffer(from file: AVAudioFile) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frameCount) else {
            return nil
        }
        file.framePosition = 0
        do {
            try file.read(into: buffer, frameCount: frameCount)
            return buffer
        } catch {
            print("⚠️ [OverdubEngine] Failed to load loop buffer: \(error)")
            return nil
        }
    }

    private func recordingSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        let sampleRate = inputSampleRate

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
            currentPlaybackTime = playbackTimeOffset + Double(playerTime.sampleTime) / sampleRate
        }
    }

    private func updateMeterFromBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        var rms: Float = 0
        vDSP_rmsqv(channelData[0], 1, &rms, vDSP_Length(frameLength))

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
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        audioEngine = nil
        basePlayerNode = nil
        layerPlayerNodes = []
        baseAudioFile = nil
        layerAudioFiles = []
        recordingFile = nil
        baseLoopBuffer = nil
        layerLoopBuffers = []
        loopFlags = []
    }
}

// MARK: - Errors

// MARK: - Thread-Safe Write Failure Counter

/// Accessed from audio tap thread — must be thread-safe
final class WriteFailureCounter: @unchecked Sendable {
    private var _count = 0
    private let lock = NSLock()
    let maxFailures = 3

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
