//
//  MetronomeSettingsView.swift
//  Sonidea
//
//  Settings for the metronome during recording. Requires headphones.
//

import SwiftUI

struct MetronomeSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette
    @Bindable var metronome: MetronomeEngine

    var body: some View {
        NavigationStack {
            List {
                // Enable toggle
                Section {
                    Toggle("Metronome", isOn: $metronome.isEnabled)
                        .tint(palette.accent)
                } footer: {
                    Text("When enabled, a metronome plays through your headphones while recording. Requires headphones (wired or Bluetooth). The click is not captured in the recording.")
                }

                if metronome.isEnabled {
                    // BPM
                    Section {
                        HStack {
                            Text("BPM")
                                .font(.subheadline)
                            Spacer()
                            Text("\(Int(metronome.bpm))")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(palette.accent)
                        }

                        Slider(value: $metronome.bpm, in: 40...240, step: 1)
                            .tint(palette.accent)
                            .accessibilityLabel("BPM")

                        // Tap tempo
                        Button {
                            metronome.tapTempo()
                        } label: {
                            HStack {
                                Spacer()
                                Label("Tap Tempo", systemImage: "hand.tap")
                                    .fontWeight(.medium)
                                Spacer()
                            }
                        }
                    } header: {
                        Text("Tempo")
                    }

                    // Time signature
                    Section {
                        Picker("Beats per bar", selection: $metronome.beatsPerBar) {
                            ForEach([2, 3, 4, 5, 6, 7, 8], id: \.self) { beats in
                                Text("\(beats)").tag(beats)
                            }
                        }

                        Picker("Beat unit", selection: $metronome.beatUnit) {
                            Text("Quarter").tag(4)
                            Text("Eighth").tag(8)
                        }
                    } header: {
                        Text("Time Signature")
                    }

                    // Count-in
                    Section {
                        Picker("Count-in", selection: $metronome.countInBars) {
                            Text("None").tag(0)
                            Text("1 Bar").tag(1)
                            Text("2 Bars").tag(2)
                        }
                    } header: {
                        Text("Count-In")
                    } footer: {
                        Text("Play click for the selected number of bars before recording starts.")
                    }

                    // Volume
                    Section {
                        HStack {
                            Image(systemName: "speaker.fill")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                            Slider(value: $metronome.volume, in: 0.1...1.0, step: 0.05)
                                .tint(palette.accent)
                                .accessibilityLabel("Volume")
                            Image(systemName: "speaker.wave.3.fill")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    } header: {
                        Text("Volume")
                    }
                }
            }
            .navigationTitle("Metronome")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
