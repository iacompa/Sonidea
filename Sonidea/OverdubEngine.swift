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
            let startFrame = AVAudioFramePosition(currentPlaybackTime * sampleRate)

            // Schedule from startFrame to end
            let framesToPlay = AVAudioFrameCount(baseFile.length - startFrame)
            if framesToPlay > 0 {
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

    /// Start recording a new layer while playing the base
    func startRecording(outputURL: URL, quality: RecordingQualityPreset) throws {
        guard let engine = audioEngine else {
            throw OverdubEngineError.engineNotPrepared
        }

        // Check headphones
        guard AudioSessionManager.shared.isHeadphoneMonitoringActive() else {
            throw OverdubEngineError.headphonesRequired
        }

        // Get audio session for validation
        let session = AVAudioSession.sharedInstance()

        #if DEBUG
        // Log audio session state for debugging
        print("🎙️ [OverdubEngine] Starting recording - Debug info:")
        print("   Session category: \(session.category.rawValue)")
        print("   Session mode: \(session.mode.rawValue)")
        print("   Session sample rate: \(session.sampleRate)")
        print("   IO buffer duration: \(session.ioBufferDuration)")
        print("   Input channels: \(session.inputNumberOfChannels)")
        print("   Output channels: \(session.outputNumberOfChannels)")
        print("   Route inputs: \(session.currentRoute.inputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        print("   Route outputs: \(session.currentRoute.outputs.map { "\($0.portName) (\($0.portType.rawValue))" })")
        #endif

        // Verify we have a valid input route
        if session.currentRoute.inputs.isEmpty {
            throw OverdubEngineError.recordingFailed("No audio input available. Please check your microphone connection.")
        }

        // Get input node and validate its format
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        #if DEBUG
        print("   Input node format: \(inputFormat)")
        print("   Input format sample rate: \(inputFormat.sampleRate)")
        print("   Input format channels: \(inputFormat.channelCount)")
        #endif

        // Validate input format - error 560226676 occurs when format is invalid
        guard inputFormat.sampleRate > 0 && inputFormat.channelCount > 0 else {
            throw OverdubEngineError.recordingFailed("Invalid audio input format. Sample rate: \(inputFormat.sampleRate), channels: \(inputFormat.channelCount). Try disconnecting and reconnecting your audio device.")
        }

        // Create recording file with validated format
        let settings = recordingSettings(for: quality)

        let file: AVAudioFile
        do {
            file = try AVAudioFile(
                forWriting: outputURL,
                settings: settings,
                commonFormat: inputFormat.commonFormat,
                interleaved: inputFormat.isInterleaved
            )
        } catch {
            #if DEBUG
            print("❌ [OverdubEngine] Failed to create audio file: \(error)")
            if let nsError = error as NSError? {
                print("   Error domain: \(nsError.domain)")
                print("   Error code: \(nsError.code)")
                print("   User info: \(nsError.userInfo)")
            }
            #endif
            throw OverdubEngineError.recordingFailed("Could not create recording file: \(error.localizedDescription)")
        }

        self.recordingFile = file
        self.recordingFileURL = outputURL

        // Install tap on input to record - use the validated input format
        do {
            inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] (buffer: AVAudioPCMBuffer, time: AVAudioTime) in
                do {
                    try file.write(from: buffer)
                } catch {
                    print("❌ [OverdubEngine] Error writing buffer: \(error)")
                }

                // Update meter
                Task { @MainActor in
                    self?.updateMeterFromBuffer(buffer)
                }
            }
        } catch {
            #if DEBUG
            print("❌ [OverdubEngine] Failed to install tap: \(error)")
            #endif
            throw OverdubEngineError.recordingFailed("Could not access microphone: \(error.localizedDescription)")
        }

        // Start engine if not running
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                // Clean up tap before throwing
                inputNode.removeTap(onBus: 0)
                #if DEBUG
                print("❌ [OverdubEngine] Failed to start engine: \(error)")
                if let nsError = error as NSError? {
                    print("   Error domain: \(nsError.domain)")
                    print("   Error code: \(nsError.code)")
                    print("   User info: \(nsError.userInfo)")
                }
                #endif
                throw OverdubEngineError.recordingFailed("Could not start audio engine: \(error.localizedDescription)")
            }
        }

        // Start playback of base and layers
        currentPlaybackTime = 0
        playBase()
        playLayers()

        recordingStartTime = Date()
        state = .recording
        startTimer()

        print("🎙️ [OverdubEngine] Started recording to: \(outputURL.lastPathComponent)")
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
                // Delay start
                let hostTimeOffset = AVAudioTime.hostTime(forSeconds: offset)
                let startTime = AVAudioTime(hostTime: mach_absolute_time() + hostTimeOffset)
                layerPlayer.scheduleFile(layerFile, at: startTime)
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
