//
//  MixerView.swift
//  Sonidea
//
//  Mixer UI for overdub groups: per-channel volume, pan, mute, solo.
//

import SwiftUI

struct MixerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    @Binding var mixSettings: MixSettings
    let layerCount: Int
    let onBounce: () -> Void
    var isBouncing: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        // Base channel
                        ChannelStripView(
                            label: "Base",
                            channel: $mixSettings.baseChannel,
                            palette: palette
                        )

                        // Layer channels
                        ForEach(0..<layerCount, id: \.self) { i in
                            if i < mixSettings.layerChannels.count {
                                ChannelStripView(
                                    label: "Layer \(i + 1)",
                                    channel: $mixSettings.layerChannels[i],
                                    palette: palette
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                // Master volume + Bounce
                VStack(spacing: 12) {
                    HStack {
                        Text("Master")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(palette.textPrimary)
                        Slider(value: $mixSettings.masterVolume, in: 0...1.5, step: 0.05)
                            .tint(palette.accent)
                        Text(String(format: "%.0f%%", mixSettings.masterVolume * 100))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(palette.textSecondary)
                            .frame(width: 40, alignment: .trailing)
                    }

                    Button {
                        onBounce()
                    } label: {
                        HStack {
                            if isBouncing {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "waveform.badge.plus")
                            }
                            Text(isBouncing ? "Bouncing..." : "Bounce Mix")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundColor(.white)
                        .background(isBouncing ? palette.accent.opacity(0.5) : palette.accent)
                        .cornerRadius(10)
                    }
                    .disabled(isBouncing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(palette.background)
            .navigationTitle("Mixer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Channel Strip

struct ChannelStripView: View {
    let label: String
    @Binding var channel: ChannelMixSettings
    let palette: ThemePalette

    var body: some View {
        VStack(spacing: 8) {
            // Channel label
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)

            // Volume fader (vertical)
            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", channel.volume * 100))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(palette.textSecondary)

                GeometryReader { geo in
                    let height = geo.size.height
                    let normalizedValue = CGFloat(channel.volume / 1.5)
                    let fillHeight = normalizedValue * height

                    ZStack(alignment: .bottom) {
                        // Track
                        RoundedRectangle(cornerRadius: 3)
                            .fill(palette.inputBackground)

                        // Fill
                        RoundedRectangle(cornerRadius: 3)
                            .fill(channel.isMuted ? Color.gray : palette.accent)
                            .frame(height: fillHeight)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = 1.0 - (value.location.y / height)
                                channel.volume = Float(max(0, min(1.5, ratio * 1.5)))
                            }
                    )
                }
                .frame(width: 24, height: 100)
            }

            // Pan knob (simplified as slider)
            VStack(spacing: 2) {
                Text(panLabel)
                    .font(.system(size: 9))
                    .foregroundColor(palette.textSecondary)

                Slider(value: $channel.pan, in: -1...1, step: 0.1)
                    .tint(palette.accent)
                    .frame(width: 60)
            }

            // Mute / Solo buttons
            HStack(spacing: 4) {
                Button {
                    channel.isMuted.toggle()
                } label: {
                    Text("M")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(channel.isMuted ? .white : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(channel.isMuted ? Color.red : palette.inputBackground)
                        .cornerRadius(4)
                }

                Button {
                    channel.isSolo.toggle()
                } label: {
                    Text("S")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(channel.isSolo ? .black : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(channel.isSolo ? Color.yellow : palette.inputBackground)
                        .cornerRadius(4)
                }
            }
        }
        .frame(width: 72)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(palette.cardBackground)
        .cornerRadius(8)
    }

    private var panLabel: String {
        if channel.pan < -0.05 { return "L\(Int(abs(channel.pan) * 100))" }
        if channel.pan > 0.05 { return "R\(Int(channel.pan * 100))" }
        return "C"
    }
}
