//
//  RecordingEffectsPanel.swift
//  Sonidea
//
//  Settings panel for real-time recording monitoring effects.
//

import SwiftUI

struct RecordingEffectsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @Bindable var effects: RecordingMonitorEffects

    var body: some View {
        NavigationStack {
            List {
                // Enable toggle
                Section {
                    Toggle("Monitor Effects", isOn: $effects.isEnabled)
                        .tint(palette.accent)
                } footer: {
                    Text("Hear your recording through EQ and compression. Effects are for monitoring only — the recording stays clean.")
                }

                if effects.isEnabled {
                    // EQ Section
                    Section {
                        eqSlider(label: "Low (100 Hz)", value: $effects.eqBand0Gain)
                        eqSlider(label: "Low Mid (500 Hz)", value: $effects.eqBand1Gain)
                        eqSlider(label: "High Mid (2 kHz)", value: $effects.eqBand2Gain)
                        eqSlider(label: "High (8 kHz)", value: $effects.eqBand3Gain)
                    } header: {
                        Label("4-Band EQ", systemImage: "slider.horizontal.3")
                    }

                    // Compressor Section
                    Section {
                        Toggle("Compressor", isOn: $effects.compressorEnabled)
                            .tint(palette.accent)

                        if effects.compressorEnabled {
                            HStack {
                                Text("Threshold")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.0f dB", effects.compressorThreshold))
                                    .font(.subheadline)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Slider(value: $effects.compressorThreshold, in: -40...0, step: 1)
                                .tint(palette.accent)

                            HStack {
                                Text("Ratio")
                                    .font(.subheadline)
                                Spacer()
                                Text(String(format: "%.0f:1", effects.compressorRatio))
                                    .font(.subheadline)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Slider(value: $effects.compressorRatio, in: 1...20, step: 0.5)
                                .tint(palette.accent)
                        }
                    } header: {
                        Label("Compressor", systemImage: "waveform.badge.minus")
                    }

                    // Monitor Volume
                    Section {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                            Slider(value: $effects.monitorVolume, in: 0...1.5, step: 0.05)
                                .tint(palette.accent)
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } header: {
                        Text("Monitor Volume")
                    }
                }
            }
            .navigationTitle("Live Effects")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onChange(of: effects.eqBand0Gain) { _, _ in effects.applyEQSettings() }
            .onChange(of: effects.eqBand1Gain) { _, _ in effects.applyEQSettings() }
            .onChange(of: effects.eqBand2Gain) { _, _ in effects.applyEQSettings() }
            .onChange(of: effects.eqBand3Gain) { _, _ in effects.applyEQSettings() }
            .onChange(of: effects.compressorEnabled) { _, _ in effects.applyCompressorSettings() }
            .onChange(of: effects.compressorThreshold) { _, _ in effects.applyCompressorSettings() }
            .onChange(of: effects.compressorRatio) { _, _ in effects.applyCompressorSettings() }
            .onChange(of: effects.monitorVolume) { _, _ in effects.applyMonitorVolume() }
        }
    }

    private func eqSlider(label: String, value: Binding<Float>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.subheadline)
                Spacer()
                Text(String(format: "%+.0f dB", value.wrappedValue))
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundColor(palette.textSecondary)
            }
            Slider(value: value, in: -12...12, step: 0.5)
                .tint(palette.accent)
        }
    }
}
