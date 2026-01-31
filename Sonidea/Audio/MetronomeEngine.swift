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
    var bpm: Double = 120 {
        didSet {
            bpm = max(40, min(240, bpm))
            updateRenderParams()
        }
    }
    var beatsPerBar: Int = 4 { didSet { updateRenderParams() } }
    var beatUnit: Int = 4  // 4=quarter, 8=eighth
    var countInBars: Int = 0  // 0=no count-in, 1, or 2
    var volume: Float = 0.7 { didSet { updateRenderParams() } }

    // MARK: - Runtime State

    private(set) var isPlaying = false
    private(set) var isCountingIn = false
    private(set) var currentBeat: Int = 0

    private var sourceNode: AVAudioSourceNode?
    private var sampleRate: Double = 44100
    private var clickActive = false

    /// Shared mutable pointer for the render callback's running sample index.
    /// Allocated once and reused across source node recreations so that
    /// start()/stop() can reset it from the main thread.
    private let renderSampleIndexPtr: UnsafeMutablePointer<UInt64> = {
        let ptr = UnsafeMutablePointer<UInt64>.allocate(capacity: 1)
        ptr.initialize(to: 0)
        return ptr
    }()

    // MARK: - Click Parameters (synthesized)

    private let downbeatFrequency: Float = 1000  // Hz
    private let upbeatFrequency: Float = 800     // Hz
    private let downbeatDuration: Float = 0.015  // 15ms
    private let upbeatDuration: Float = 0.010    // 10ms

    // MARK: - Thread-Safe Render Parameters

    /// Snapshot of parameters read by the audio render callback.
    private struct MetronomeParams {
        var bpm: Double
        var volume: Float
        var clickActive: Bool
        var beatsPerBar: Int
        var sampleRate: Double
    }

    private let paramsLock = NSLock()
    private var renderParams = MetronomeParams(bpm: 120, volume: 0.7, clickActive: false, beatsPerBar: 4, sampleRate: 44100)

    /// Copy current MainActor properties into the lock-protected renderParams.
    private func updateRenderParams() {
        paramsLock.lock()
        renderParams.bpm = bpm
        renderParams.volume = volume
        renderParams.clickActive = clickActive
        renderParams.beatsPerBar = beatsPerBar
        renderParams.sampleRate = sampleRate
        paramsLock.unlock()
    }

    // MARK: - Source Node Factory

    /// Creates an AVAudioSourceNode for the click track.
    /// Attach this to the engine's mainMixerNode (NOT to the recording chain).
    func createSourceNode(sampleRate: Double) -> AVAudioSourceNode {
        self.sampleRate = sampleRate
        renderSampleIndexPtr.pointee = 0
        updateRenderParams()

        let paramsLock = self.paramsLock
        let downbeatFreq = self.downbeatFrequency
        let upbeatFreq = self.upbeatFrequency
        let downbeatDur = self.downbeatDuration
        let upbeatDur = self.upbeatDuration

        // Capture the pointer so the render callback can read/write the running sample index.
        // The pointer is owned by `self` and persists across callbacks and start/stop cycles.
        let sampleIndexPtr = self.renderSampleIndexPtr

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
            let frames = Int(frameCount)

            // SAFETY: If self has been deallocated, the sampleIndexPtr may already be freed.
            // Return silence immediately WITHOUT touching sampleIndexPtr.
            guard let strongSelf = self else {
                for buffer in ablPointer {
                    guard let data = buffer.mData?.assumingMemoryBound(to: Float.self) else { continue }
                    for i in 0..<frames { data[i] = 0 }
                }
                return noErr
            }

            // Read params under lock
            paramsLock.lock()
            let params = strongSelf.renderParams
            paramsLock.unlock()

            let sr = params.sampleRate
            let currentBPM = params.bpm
            let vol = params.volume
            let active = params.clickActive
            let beatsPerBar = params.beatsPerBar

            let currentSampleIndex = sampleIndexPtr.pointee

            guard active, sr > 0, currentBPM > 0 else {
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
                    let sampleInBeat = Double(currentSampleIndex + UInt64(i)).truncatingRemainder(dividingBy: samplesPerBeat)
                    let beatIndex = Int(Double(currentSampleIndex + UInt64(i)) / samplesPerBeat) % beatsPerBar

                    let isDownbeat = beatIndex == 0
                    let freq: Float = isDownbeat ? downbeatFreq : upbeatFreq
                    let dur: Float = isDownbeat ? downbeatDur : upbeatDur
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

            sampleIndexPtr.pointee = currentSampleIndex + UInt64(frames)
            return noErr
        }

        self.sourceNode = node
        return node
    }

    // MARK: - Playback Control

    func start() {
        renderSampleIndexPtr.pointee = 0
        clickActive = true
        isPlaying = true
        updateRenderParams()
    }

    func stop() {
        clickActive = false
        isPlaying = false
        isCountingIn = false
        renderSampleIndexPtr.pointee = 0
        updateRenderParams()
    }

    /// Count in for N bars, then call completion when count-in finishes.
    func startCountIn(completion: @escaping () -> Void) {
        guard countInBars > 0 else {
            completion()
            return
        }

        isCountingIn = true
        renderSampleIndexPtr.pointee = 0
        clickActive = true
        isPlaying = true

        let totalBeats = countInBars * beatsPerBar
        let totalDuration = Double(totalBeats) * 60.0 / bpm

        DispatchQueue.main.asyncAfter(deadline: .now() + totalDuration) { [weak self] in
            self?.isCountingIn = false
            completion()
        }
    }

    // Pointer cleanup: renderSampleIndexPtr is a `let` constant (8 bytes),
    // safe to access from nonisolated deinit. The render callback guards on
    // `[weak self]` returning nil, so the pointer is not touched after dealloc.
    // sourceNode is released automatically when the class is deallocated.
    deinit {
        renderSampleIndexPtr.deinitialize(count: 1)
        renderSampleIndexPtr.deallocate()
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
