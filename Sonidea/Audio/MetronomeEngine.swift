//
//  MetronomeEngine.swift
//  Sonidea
//
//  Synthesized metronome click track for recording.
//  Click plays through the audio engine's main mixer (speakers)
//  but is NOT captured by the recording tap on the limiter node.
//
//  Audio graph:
//    RECORDING: InputNode -> GainMixer -> Limiter -> [TAP -> File]
//    CLICK:     ClickSourceNode -> MainMixerNode -> Output
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class MetronomeEngine {

    // MARK: - Settings

    var isEnabled: Bool = false
    var bpm: Double = 120 { didSet { bpm = max(40, min(240, bpm)) } }
    var beatsPerBar: Int = 4
    var beatUnit: Int = 4  // 4=quarter, 8=eighth
    var countInBars: Int = 0  // 0=no count-in, 1, or 2
    var volume: Float = 0.7

    // MARK: - Runtime State

    private(set) var isPlaying = false
    private(set) var isCountingIn = false
    private(set) var currentBeat: Int = 0

    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44100
    private var phase: Double = 0
    private var sampleIndex: UInt64 = 0
    private var clickActive = false

    // MARK: - Click Parameters (synthesized)

    private let downbeatFrequency: Float = 1000  // Hz
    private let upbeatFrequency: Float = 800     // Hz
    private let downbeatDuration: Float = 0.015  // 15ms
    private let upbeatDuration: Float = 0.010    // 10ms

    // MARK: - Source Node Factory

    /// Creates an AVAudioSourceNode for the click track.
    /// Attach this to the engine's mainMixerNode (NOT to the recording chain).
    func createSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        self.sampleRate = sampleRate
        self.sampleIndex = 0

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            guard let self else { return noErr }

            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)
            let sr = self.sampleRate
            let currentBPM = self.bpm
            let vol = self.volume
            let clickActive = self.clickActive
            let beatsPerBar = self.beatsPerBar

            guard clickActive, sr > 0, currentBPM > 0 else {
                // Output silence
                for buffer in ablPointer {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for i in 0..<frames { data[i] = 0 }
                }
                return noErr
            }

            let samplesPerBeat = sr * 60.0 / currentBPM

            for buffer in ablPointer {
                guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                for i in 0..<frames {
                    let sampleInBeat = Double(self.sampleIndex + UInt64(i)).truncatingRemainder(dividingBy: samplesPerBeat)
                    let beatIndex = Int(Double(self.sampleIndex + UInt64(i)) / samplesPerBeat) % beatsPerBar

                    let isDownbeat = beatIndex == 0
                    let freq: Float = isDownbeat ? self.downbeatFrequency : self.upbeatFrequency
                    let dur: Float = isDownbeat ? self.downbeatDuration : self.upbeatDuration
                    let durSamples = Double(dur) * sr

                    if sampleInBeat < durSamples {
                        // Sine burst with exponential decay
                        let t = Float(sampleInBeat / sr)
                        let decay = expf(-t * 200) // Fast exponential decay
                        let sample = sinf(2.0 * .pi * freq * t) * decay * vol
                        data[i] = sample
                    } else {
                        data[i] = 0
                    }
                }
            }

            self.sampleIndex += UInt64(frames)
            return noErr
        }

        self.sourceNode = node
        return node
    }

    // MARK: - Playback Control

    func start() {
        sampleIndex = 0
        clickActive = true
        isPlaying = true
    }

    func stop() {
        clickActive = false
        isPlaying = false
        isCountingIn = false
        sampleIndex = 0
    }

    /// Count in for N bars, then call completion when count-in finishes.
    func startCountIn(completion: @escaping () -> Void) {
        guard countInBars > 0 else {
            completion()
            return
        }

        isCountingIn = true
        sampleIndex = 0
        clickActive = true
        isPlaying = true

        let totalBeats = countInBars * beatsPerBar
        let totalDuration = Double(totalBeats) * 60.0 / bpm

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            self?.isCountingIn = false
            completion()
        }
    }

    // MARK: - Tap Tempo

    private var tapTimes: [Date] = []

    /// Call this on each tap to compute BPM from tap intervals.
    func tapTempo() {
        let now = Date()

        // Reset if last tap was >2 seconds ago
        if let last = tapTimes.last, now.timeIntervalSince(last) > 2.0 {
            tapTimes = []
        }

        tapTimes.append(now)

        // Need at least 2 taps
        guard tapTimes.count >= 2 else { return }

        // Keep last 8 taps
        if tapTimes.count > 8 {
            tapTimes = Array(tapTimes.suffix(8))
        }

        // Average interval
        var totalInterval: TimeInterval = 0
        for i in 1..<tapTimes.count {
            totalInterval += tapTimes[i].timeIntervalSince(tapTimes[i - 1])
        }
        let avgInterval = totalInterval / Double(tapTimes.count - 1)

        if avgInterval > 0 {
            bpm = min(240, max(40, 60.0 / avgInterval))
        }
    }
}
