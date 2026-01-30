//
//  AudioEditToolsPanel.swift
//  Sonidea
//
//  Panel for advanced audio editing tools: Fade, Normalize, Noise Gate.
//

import SwiftUI

struct AudioEditToolsPanel: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var isProcessing: Bool

    let onFade: (TimeInterval, TimeInterval, FadeCurve) -> Void
    let onNormalize: (Float) -> Void
    let onNoiseGate: (Float) -> Void

    @State private var fadeInDuration: Double = 0.5
    @State private var fadeOutDuration: Double = 0.5
    @State private var fadeCurve: FadeCurve = .sCurve
    @State private var normalizeTarget: Float = -0.3
    @State private var gateThreshold: Float = -40

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Fade
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Label("Fade In", systemImage: "arrow.up.right")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1fs", fadeInDuration))
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $fadeInDuration, in: 0...5, step: 0.1)
                            .tint(palette.accent)

                        HStack {
                            Label("Fade Out", systemImage: "arrow.down.right")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1fs", fadeOutDuration))
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $fadeOutDuration, in: 0...5, step: 0.1)
                            .tint(palette.accent)

                        Picker("Curve", selection: $fadeCurve) {
                            ForEach(FadeCurve.allCases) { curve in
                                Text(curve.displayName).tag(curve)
                            }
                        }
                        .pickerStyle(.segmented)

                        Button {
                            dismiss()
                            onFade(fadeInDuration, fadeOutDuration, fadeCurve)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Apply Fade", systemImage: "waveform.path.ecg")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing || (fadeInDuration == 0 && fadeOutDuration == 0))
                    }
                } header: {
                    Label("Fade In / Out", systemImage: "waveform.path.ecg")
                }

                // MARK: - Normalize
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Target Peak")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.1f dB", normalizeTarget))
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $normalizeTarget, in: -6...0, step: 0.1)
                            .tint(palette.accent)
                        Text("Adjusts volume so the loudest peak reaches the target level.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

                        Button {
                            dismiss()
                            onNormalize(normalizeTarget)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Normalize", systemImage: "speaker.wave.3")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }
                } header: {
                    Label("Normalize", systemImage: "speaker.wave.3")
                }

                // MARK: - Noise Gate
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Threshold")
                                .font(.subheadline)
                            Spacer()
                            Text(String(format: "%.0f dB", gateThreshold))
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                        }
                        Slider(value: $gateThreshold, in: -60...(-10), step: 1)
                            .tint(palette.accent)
                        Text("Silences audio below the threshold. Useful for removing background noise between phrases.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

                        Button {
                            dismiss()
                            onNoiseGate(gateThreshold)
                        } label: {
                            HStack {
                                Spacer()
                                Label("Apply Gate", systemImage: "waveform.badge.minus")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                        .disabled(isProcessing)
                    }
                } header: {
                    Label("Noise Gate", systemImage: "waveform.badge.minus")
                }
            }
            .navigationTitle("Audio Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
