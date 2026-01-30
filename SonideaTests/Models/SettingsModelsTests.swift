//
//  SettingsModelsTests.swift
//  SonideaTests
//
//  Tests for SettingsModels: quality presets, recording modes, EQ, migrations.
//

import Testing
import Foundation
@testable import Sonidea

struct SettingsModelsTests {

    // MARK: - RecordingQualityPreset Migration

    @Test func qualityPresetMigrationFromGood() throws {
        let json = "\"good\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingQualityPreset.self, from: data)
        #expect(decoded == .standard)
    }

    @Test func qualityPresetMigrationFromBetter() throws {
        let json = "\"better\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingQualityPreset.self, from: data)
        #expect(decoded == .high)
    }

    @Test func qualityPresetMigrationFromBest() throws {
        let json = "\"best\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingQualityPreset.self, from: data)
        #expect(decoded == .high)
    }

    @Test func qualityPresetCurrentValuesDecodeCorrectly() throws {
        for preset in RecordingQualityPreset.allCases {
            let json = "\"\(preset.rawValue)\""
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(RecordingQualityPreset.self, from: data)
            #expect(decoded == preset)
        }
    }

    @Test func qualityPresetUnknownValueDefaultsToHigh() throws {
        let json = "\"ultra\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingQualityPreset.self, from: data)
        #expect(decoded == .high)
    }

    // MARK: - Recording Quality Properties

    @Test func qualityPresetFileExtensions() {
        #expect(RecordingQualityPreset.standard.fileExtension == "m4a")
        #expect(RecordingQualityPreset.high.fileExtension == "m4a")
        #expect(RecordingQualityPreset.lossless.fileExtension == "m4a")
        #expect(RecordingQualityPreset.wav.fileExtension == "wav")
    }

    @Test func qualityPresetIsLossless() {
        #expect(!RecordingQualityPreset.standard.isLossless)
        #expect(!RecordingQualityPreset.high.isLossless)
        #expect(RecordingQualityPreset.lossless.isLossless)
        #expect(RecordingQualityPreset.wav.isLossless)
    }

    @Test func qualityPresetSampleRates() {
        #expect(RecordingQualityPreset.standard.sampleRate == 44100)
        #expect(RecordingQualityPreset.high.sampleRate == 48000)
        #expect(RecordingQualityPreset.lossless.sampleRate == 48000)
        #expect(RecordingQualityPreset.wav.sampleRate == 48000)
    }

    // MARK: - RecordingMode Migration

    @Test func recordingModeMigrationFromDualMono() throws {
        let json = "\"dualMono\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingMode.self, from: data)
        #expect(decoded == .stereo)
    }

    @Test func recordingModeMigrationFromSpatial() throws {
        let json = "\"spatial\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingMode.self, from: data)
        #expect(decoded == .stereo)
    }

    @Test func recordingModeCurrentValuesDecodeCorrectly() throws {
        for mode in RecordingMode.allCases {
            let json = "\"\(mode.rawValue)\""
            let data = json.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(RecordingMode.self, from: data)
            #expect(decoded == mode)
        }
    }

    @Test func recordingModeUnknownDefaultsToMono() throws {
        let json = "\"binaural\""
        let data = json.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(RecordingMode.self, from: data)
        #expect(decoded == .mono)
    }

    @Test func recordingModeChannelCounts() {
        #expect(RecordingMode.mono.channelCount == 1)
        #expect(RecordingMode.stereo.channelCount == 2)
    }

    // MARK: - EQ Settings

    @Test func flatEQIsFlat() {
        let eq = EQSettings.flat
        #expect(eq.isFlat)
        #expect(eq.bands.count == 4)
    }

    @Test func nonFlatEQIsNotFlat() {
        var eq = EQSettings.flat
        eq.bands[0] = EQBandSettings(frequency: 100, gain: 6.0, q: 1.0)
        #expect(!eq.isFlat)
    }

    @Test func eqReset() {
        var eq = EQSettings.flat
        eq.bands[0] = EQBandSettings(frequency: 200, gain: 12.0, q: 2.0)
        eq.bands[1] = EQBandSettings(frequency: 500, gain: -6.0, q: 0.5)

        eq.reset()
        #expect(eq.isFlat)
        #expect(eq.bands.count == 4)
    }

    @Test func eqDefaultFrequencies() {
        let eq = EQSettings.flat
        #expect(eq.bands[0].frequency == 100)
        #expect(eq.bands[1].frequency == 400)
        #expect(eq.bands[2].frequency == 2000)
        #expect(eq.bands[3].frequency == 8000)
    }

    @Test func eqBandSettingsClamping() {
        // Frequency clamping
        let lowFreq = EQBandSettings(frequency: 5, gain: 0, q: 1.0)
        #expect(lowFreq.frequency == EQBandSettings.minFrequency)

        let highFreq = EQBandSettings(frequency: 30000, gain: 0, q: 1.0)
        #expect(highFreq.frequency == EQBandSettings.maxFrequency)

        // Gain clamping
        let lowGain = EQBandSettings(frequency: 100, gain: -20, q: 1.0)
        #expect(lowGain.gain == EQBandSettings.minGain)

        let highGain = EQBandSettings(frequency: 100, gain: 20, q: 1.0)
        #expect(highGain.gain == EQBandSettings.maxGain)

        // Q clamping
        let lowQ = EQBandSettings(frequency: 100, gain: 0, q: 0.1)
        #expect(lowQ.q == EQBandSettings.minQ)

        let highQ = EQBandSettings(frequency: 100, gain: 0, q: 20.0)
        #expect(highQ.q == EQBandSettings.maxQ)
    }

    @Test func bandwidthFromQFormula() {
        // Q=1 should give a specific bandwidth value
        let bw = EQBandSettings.bandwidthFromQ(1.0)
        #expect(bw > 0)

        // Higher Q = narrower bandwidth
        let narrowBw = EQBandSettings.bandwidthFromQ(5.0)
        let wideBw = EQBandSettings.bandwidthFromQ(0.5)
        #expect(narrowBw < wideBw)
    }

    @Test func bandwidthPropertyMatchesStaticMethod() {
        let band = EQBandSettings(frequency: 1000, gain: 0, q: 2.0)
        let staticBw = EQBandSettings.bandwidthFromQ(2.0)
        #expect(abs(band.bandwidth - staticBw) < 0.001)
    }

    @Test func eqInitWithWrongBandCountFallsToFlat() {
        let eq = EQSettings(bands: [
            EQBandSettings(frequency: 100, gain: 6.0, q: 1.0)
        ])
        // Should fall back to flat when not exactly 4 bands
        #expect(eq.bands.count == 4)
        #expect(eq.isFlat)
    }

    // MARK: - RecordingInputSettings

    @Test func defaultInputSettings() {
        let settings = RecordingInputSettings.default
        #expect(settings.gainDb == 0)
        #expect(!settings.limiterEnabled)
        #expect(settings.limiterCeilingDb == -1)
        #expect(settings.isDefault)
    }

    @Test func inputSettingsNotDefaultWithGain() {
        var settings = RecordingInputSettings.default
        settings.gainDb = 3.0
        #expect(!settings.isDefault)
    }

    @Test func inputSettingsNotDefaultWithLimiter() {
        var settings = RecordingInputSettings.default
        settings.limiterEnabled = true
        #expect(!settings.isDefault)
    }

    @Test func gainDisplayString() {
        var settings = RecordingInputSettings.default
        settings.gainDb = 3.0
        #expect(settings.gainDisplayString == "+3.0 dB")

        settings.gainDb = -2.5
        #expect(settings.gainDisplayString == "-2.5 dB")

        settings.gainDb = 0
        #expect(settings.gainDisplayString == "0 dB")
    }

    // MARK: - AppSettings

    @Test func appSettingsDefaults() {
        let settings = AppSettings.default
        #expect(settings.recordingQuality == .high)
        #expect(settings.recordingMode == .mono)
        #expect(!settings.autoTranscribe)
        #expect(settings.skipInterval == .fifteen)
        #expect(settings.playbackSpeed == 1.0)
        #expect(!settings.iCloudSyncEnabled)
        #expect(settings.autoSelectIcon)
        #expect(settings.preventSleepWhileRecording)
    }

    // MARK: - SilenceSkipSettings

    @Test func silenceSkipDefaults() {
        let settings = SilenceSkipSettings.default
        #expect(!settings.enabled)
        #expect(settings.threshold == -55)
        #expect(settings.minDuration == 0.5)
    }
}
