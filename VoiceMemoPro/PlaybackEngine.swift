//
//  PlaybackEngine.swift
//  VoiceMemoPro
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

    func load(url: URL) {
        stop()
        currentFileURL = url

        do {
            try AudioSessionManager.shared.configureForPlayback()

            audioFile = try AVAudioFile(forReading: url)
            guard let file = audioFile else { return }

            audioSampleRate = file.processingFormat.sampleRate
            audioLengthFrames = file.length
            duration = Double(audioLengthFrames) / audioSampleRate
            currentTime = 0
            seekFrame = 0

            setupAudioEngine(format: file.processingFormat)
        } catch {
            print("Failed to load audio: \(error)")
        }
    }

    func play() {
        guard let engine = audioEngine, let player = playerNode, let file = audioFile else { return }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                print("Failed to start engine: \(error)")
                return
            }
        }

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
        playerNode?.pause()
        isPlaying = false
        stopTimer()
        updateCurrentTime()
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

    // MARK: - Private

    private func setupAudioEngine(format: AVAudioFormat) {
        audioEngine = AVAudioEngine()
        playerNode = AVAudioPlayerNode()
        timePitchNode = AVAudioUnitTimePitch()
        eqNode = AVAudioUnitEQ(numberOfBands: 4)

        guard let engine = audioEngine,
              let player = playerNode,
              let timePitch = timePitchNode,
              let eq = eqNode else { return }

        // Configure time pitch
        timePitch.rate = playbackSpeed

        // Configure EQ bands
        configurEQBands()

        // Attach nodes
        engine.attach(player)
        engine.attach(timePitch)
        engine.attach(eq)

        // Connect: player -> timePitch -> EQ -> mainMixer
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)

        engine.prepare()
    }

    private func configurEQBands() {
        guard let eq = eqNode else { return }

        // Band 0: Low (100 Hz)
        eq.bands[0].filterType = .lowShelf
        eq.bands[0].frequency = EQSettings.lowFrequency
        eq.bands[0].bandwidth = 1.0
        eq.bands[0].bypass = false

        // Band 1: Low-Mid (500 Hz)
        eq.bands[1].filterType = .parametric
        eq.bands[1].frequency = EQSettings.lowMidFrequency
        eq.bands[1].bandwidth = 1.0
        eq.bands[1].bypass = false

        // Band 2: High-Mid (2000 Hz)
        eq.bands[2].filterType = .parametric
        eq.bands[2].frequency = EQSettings.highMidFrequency
        eq.bands[2].bandwidth = 1.0
        eq.bands[2].bypass = false

        // Band 3: High (8000 Hz)
        eq.bands[3].filterType = .highShelf
        eq.bands[3].frequency = EQSettings.highFrequency
        eq.bands[3].bandwidth = 1.0
        eq.bands[3].bypass = false

        applyEQSettings()
    }

    private func applyEQSettings() {
        guard let eq = eqNode else { return }

        eq.bands[0].gain = eqSettings.lowGain
        eq.bands[1].gain = eqSettings.lowMidGain
        eq.bands[2].gain = eqSettings.highMidGain
        eq.bands[3].gain = eqSettings.highGain
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateCurrentTime()
            }
        }
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
