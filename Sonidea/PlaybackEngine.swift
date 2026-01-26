//
//  PlaybackEngine.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackEngine {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0
    var playbackSpeed: Float = 1.0
    var eqSettings: EQSettings = .flat

    /// Error state for UI to display
    var loadError: PlaybackError?

    /// Whether the engine is ready to play
    var isLoaded: Bool {
        audioFile != nil && audioEngine != nil && playerNode != nil
    }

    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var eqNode: AVAudioUnitEQ?
    private var audioFile: AVAudioFile?
    private var timer: Timer?

    private var seekFrame: AVAudioFramePosition = 0
    private var audioSampleRate: Double = 44100
    private var audioLengthFrames: AVAudioFramePosition = 0

    private var currentFileURL: URL?

    init() {}

    // MARK: - Public API

    /// Load audio file for playback with error reporting
    func load(url: URL) {
        stop()
        loadError = nil
        currentFileURL = url

        // Log file info for debugging
        AudioDebug.logFileInfo(url: url, context: "PlaybackEngine.load")

        // Verify file exists and is valid
        let status = AudioDebug.verifyAudioFile(url: url)
        guard status.isValid else {
            let errorMsg = status.errorMessage ?? "Unknown error"
            print("❌ [PlaybackEngine] File verification failed: \(errorMsg)")

            switch status {
            case .notFound:
                loadError = .fileNotFound(url)
            case .audioError(let error):
                loadError = .cannotOpenFile(url, error)
            default:
                loadError = .cannotOpenFile(url, NSError(domain: "PlaybackEngine", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg]))
            }
            return
        }

        // Configure audio session
        do {
            try AudioSessionManager.shared.configureForPlayback()
            AudioDebug.logSessionState(context: "PlaybackEngine.load - after session config")
        } catch {
            AudioDebug.logError(error, context: "PlaybackEngine.load - session config")
            loadError = .audioSessionFailed(error)
            return
        }

        // Open audio file
        do {
            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else {
                loadError = .cannotOpenFile(url, NSError(domain: "PlaybackEngine", code: -2, userInfo: [NSLocalizedDescriptionKey: "AVAudioFile returned nil"]))
                return
            }

            audioSampleRate = file.processingFormat.sampleRate
            audioLengthFrames = file.length
            duration = Double(audioLengthFrames) / audioSampleRate
            currentTime = 0
            seekFrame = 0

            print("✅ [PlaybackEngine] Audio file loaded: duration=\(duration)s, sampleRate=\(audioSampleRate)")

            setupAudioEngine(format: file.processingFormat)
        } catch {
            AudioDebug.logError(error, context: "PlaybackEngine.load - open file")
            loadError = .cannotOpenFile(url, error)
            return
        }
    }

    func play() {
        guard let engine = audioEngine, let player = playerNode, let file = audioFile else {
            print("⚠️ [PlaybackEngine] play() called but engine not ready")
            return
        }

        if !engine.isRunning {
            do {
                try engine.start()
                AudioDebug.logSessionState(context: "PlaybackEngine.play - engine started")
            } catch {
                AudioDebug.logError(error, context: "PlaybackEngine.play - engine start")
                loadError = .engineStartFailed(error)
                return
            }
        }

        // CRITICAL: Stop player first to clear any previously scheduled segments
        // This prevents segment accumulation when pause/play is cycled, which causes
        // playhead drift (UI shows 100% while audio continues from queued segments)
        player.stop()

        // Schedule from current seek position
        let frameCount = AVAudioFrameCount(audioLengthFrames - seekFrame)
        guard frameCount > 0 else {
            // Already at end, restart from beginning
            seekFrame = 0
            currentTime = 0
            let fullFrameCount = AVAudioFrameCount(audioLengthFrames)
            player.scheduleSegment(file, startingFrame: 0, frameCount: fullFrameCount, at: nil)
            player.play()
            isPlaying = true
            startTimer()
            return
        }

        player.scheduleSegment(file, startingFrame: seekFrame, frameCount: frameCount, at: nil) { [weak self] in
            Task { @MainActor in
                self?.handlePlaybackFinished()
            }
        }

        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        // Update current time first to capture accurate position
        updateCurrentTime()

        // Save current position to seekFrame so play() resumes from here
        seekFrame = AVAudioFramePosition(currentTime * audioSampleRate)

        playerNode?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil
        eqNode = nil
        audioFile = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        seekFrame = 0
        stopTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        let wasPlaying = isPlaying

        if wasPlaying {
            playerNode?.stop()
        }

        let newFrame = AVAudioFramePosition(time * audioSampleRate)
        seekFrame = max(0, min(newFrame, audioLengthFrames))
        currentTime = Double(seekFrame) / audioSampleRate

        if wasPlaying {
            play()
        }
    }

    func skip(seconds: TimeInterval) {
        let newTime = max(0, min(duration, currentTime + seconds))
        seek(to: newTime)
    }

    /// Clear any load error (call after user dismisses error alert)
    func clearError() {
        loadError = nil
    }

    // MARK: - Speed Control

    func setSpeed(_ speed: Float) {
        playbackSpeed = max(0.5, min(2.0, speed))
        timePitchNode?.rate = playbackSpeed
    }

    // MARK: - EQ Control

    func setEQ(_ settings: EQSettings) {
        eqSettings = settings
        applyEQSettings()
    }

    /// Update a single band's settings in real-time
    func updateBand(_ index: Int, frequency: Float? = nil, gain: Float? = nil, q: Float? = nil) {
        guard index >= 0 && index < 4 else { return }

        if let freq = frequency {
            eqSettings.bands[index].frequency = max(EQBandSettings.minFrequency, min(EQBandSettings.maxFrequency, freq))
        }
        if let g = gain {
            eqSettings.bands[index].gain = max(EQBandSettings.minGain, min(EQBandSettings.maxGain, g))
        }
        if let qVal = q {
            eqSettings.bands[index].q = max(EQBandSettings.minQ, min(EQBandSettings.maxQ, qVal))
        }

        applyBandSettings(index)
    }

    // MARK: - Private

    private func setupAudioEngine(format: AVAudioFormat) {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitchNode = AVAudioUnitTimePitch()
        eqNode = AVAudioUnitEQ(numberOfBands: 4)

        guard let engine = audioEngine,
              let player = playerNode,
              let timePitch = timePitchNode,
              let eq = eqNode else {
            print("⚠️ [PlaybackEngine] Failed to create audio nodes")
            return
        }

        // Configure time pitch
        timePitch.rate = playbackSpeed

        // Configure all EQ bands as parametric
        configureEQBands()

        // Attach nodes
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(eq)

        // Connect: player -> timePitch -> EQ -> mainMixer
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        engine.prepare()
        print("✅ [PlaybackEngine] Audio engine setup complete")
    }

    private func configureEQBands() {
        guard let eq = eqNode else { return }

        // Configure all 4 bands as parametric filters
        for i in 0..<4 {
            eq.bands[i].filterType = .parametric
            eq.bands[i].bypass = false
        }

        applyEQSettings()
    }

    private func applyEQSettings() {
        guard let eq = eqNode else { return }

        for i in 0..<4 {
            let band = eqSettings.bands[i]
            eq.bands[i].frequency = band.frequency
            eq.bands[i].gain = band.gain
            eq.bands[i].bandwidth = band.bandwidth
        }
    }

    private func applyBandSettings(_ index: Int) {
        guard let eq = eqNode, index >= 0 && index < 4 else { return }

        let band = eqSettings.bands[index]
        eq.bands[index].frequency = band.frequency
        eq.bands[index].gain = band.gain
        eq.bands[index].bandwidth = band.bandwidth
    }

    private func startTimer() {
        // Use .common mode so timer continues during scroll tracking
        let newTimer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateCurrentTime() {
        guard let player = playerNode,
              let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else {
            return
        }

        let currentFrame = seekFrame + playerTime.sampleTime
        currentTime = Double(currentFrame) / audioSampleRate

        // Clamp to duration
        if currentTime >= duration {
            currentTime = duration
        }
    }

    private func handlePlaybackFinished() {
        isPlaying = false
        currentTime = 0
        seekFrame = 0
        stopTimer()
    }
}
