//
//  RecordingMonitorEffects.swift
//  Sonidea
//
//  Monitoring-only effects chain for recording.
//  Audio is heard through EQ + compressor while recording,
//  but the recording file captures clean audio from the limiter tap.
//
//  Audio graph:
//    RECORDING: InputNode -> GainMixer -> Limiter -> [TAP -> File]  (clean)
//    MONITOR:   Limiter -> MonitorMixer -> MonitorEQ -> MonitorCompressor -> MainMixerNode -> Output
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class RecordingMonitorEffects {

    // MARK: - Settings

    var isEnabled: Bool = false

    // EQ (4-band parametric, matching PlaybackEngine pattern)
    var eqBand0Gain: Float = 0  // Low shelf (100 Hz)
    var eqBand1Gain: Float = 0  // Low mid (500 Hz)
    var eqBand2Gain: Float = 0  // High mid (2000 Hz)
    var eqBand3Gain: Float = 0  // High shelf (8000 Hz)

    // Compressor
    var compressorEnabled: Bool = false
    var compressorThreshold: Float = -20  // dB
    var compressorRatio: Float = 4.0      // 1:1 to 20:1

    // Monitor volume
    var monitorVolume: Float = 1.0

    // MARK: - Audio Nodes

    private(set) var monitorMixer: AVAudioMixerNode?
    private(set) var eqNode: AVAudioUnitEQ?
    private(set) var compressorNode: AVAudioUnitEffect?

    // MARK: - Node Creation

    /// Create and return the monitoring nodes. Caller attaches them to the engine.
    func createNodes() -> (mixer: AVAudioMixerNode, eq: AVAudioUnitEQ, compressor: AVAudioUnitEffect) {
        let mixer = AVAudioMixerNode()
        mixer.outputVolume = monitorVolume

        // 4-band parametric EQ (same as PlaybackEngine)
        let eq = AVAudioUnitEQ(numberOfBands: 4)
        configureBands(eq)

        // Dynamics processor configured as compressor
        let compDesc = AudioComponentDescription(
            componentType: kAudioUnitType_Effect,
            componentSubType: kAudioUnitSubType_DynamicsProcessor,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        let compressor = AVAudioUnitEffect(audioComponentDescription: compDesc)

        self.monitorMixer = mixer
        self.eqNode = eq
        self.compressorNode = compressor

        applyEQSettings()
        applyCompressorSettings()

        return (mixer: mixer, eq: eq, compressor: compressor)
    }

    // MARK: - Apply Settings

    func applyEQSettings() {
        guard let eq = eqNode else { return }
        let gains = [eqBand0Gain, eqBand1Gain, eqBand2Gain, eqBand3Gain]
        for i in 0..<min(4, eq.bands.count) {
            eq.bands[i].gain = gains[i]
        }
    }

    func applyCompressorSettings() {
        guard let comp = compressorNode else { return }
        let au = comp.audioUnit
        if compressorEnabled {
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, compressorThreshold, 0)
            // Map ratio to headroom: ratio 1 = headroom 40 (no compression), ratio 20 = headroom 1 (heavy)
            let headroom = Float(40.0 / max(compressorRatio, 1.0))
            AudioUnitSetParameter(au, kDynamicsProcessorParam_HeadRoom, kAudioUnitScope_Global, 0, headroom, 0)
            // Attack 10ms, release 100ms
            AudioUnitSetParameter(au, kDynamicsProcessorParam_AttackTime, kAudioUnitScope_Global, 0, 0.01, 0)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_ReleaseTime, kAudioUnitScope_Global, 0, 0.1, 0)
        } else {
            // Bypass: set threshold to 0 (no compression)
            AudioUnitSetParameter(au, kDynamicsProcessorParam_Threshold, kAudioUnitScope_Global, 0, 0, 0)
        }
    }

    func applyMonitorVolume() {
        monitorMixer?.outputVolume = monitorVolume
    }

    // MARK: - Cleanup

    func teardown() {
        monitorMixer = nil
        eqNode = nil
        compressorNode = nil
    }

    // MARK: - Private

    private func configureBands(_ eq: AVAudioUnitEQ) {
        guard eq.bands.count >= 4 else { return }

        let band0 = eq.bands[0]
        band0.filterType = .lowShelf
        band0.frequency = 100
        band0.bandwidth = 1.0
        band0.bypass = false

        let band1 = eq.bands[1]
        band1.filterType = .parametric
        band1.frequency = 500
        band1.bandwidth = 1.0
        band1.bypass = false

        let band2 = eq.bands[2]
        band2.filterType = .parametric
        band2.frequency = 2000
        band2.bandwidth = 1.0
        band2.bypass = false

        let band3 = eq.bands[3]
        band3.filterType = .highShelf
        band3.frequency = 8000
        band3.bandwidth = 1.0
        band3.bypass = false
    }
}
