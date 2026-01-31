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
    let bounceTitle: String
    let onBounce: () -> Void
    var isBouncing: Bool = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Channel strips + Master fader
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

                        // Master vertical fader
                        masterFaderView
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }

                Divider()

                // Bounce button
                VStack(spacing: 12) {
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
                            VStack(spacing: 2) {
                                Text(isBouncing ? "Bouncing..." : "Bounce Track As:")
                                    .fontWeight(.semibold)
                                if !isBouncing {
                                    Text(bounceTitle)
                                        .font(.caption)
                                        .opacity(0.8)
                                }
                            }
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

    private var masterFaderView: some View {
        VStack(spacing: 8) {
            Text("Master")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)

            VStack(spacing: 2) {
                Text(String(format: "%.0f%%", mixSettings.masterVolume * 100))
                    .font(.system(size: 10))
                    .monospacedDigit()
                    .foregroundColor(palette.textSecondary)

                GeometryReader { geo in
                    let height = geo.size.height
                    let normalizedValue = CGFloat(mixSettings.masterVolume / 1.5)
                    let fillHeight = normalizedValue * height

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(palette.inputBackground)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(palette.accent)
                            .frame(height: fillHeight)
                    }
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let ratio = 1.0 - (value.location.y / height)
                                mixSettings.masterVolume = Float(max(0, min(1.5, ratio * 1.5)))
                            }
                    )
                    .accessibilityLabel("Master volume")
                    .accessibilityValue("\(Int(mixSettings.masterVolume * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: mixSettings.masterVolume = min(1.5, mixSettings.masterVolume + 0.05)
                        case .decrement: mixSettings.masterVolume = max(0, mixSettings.masterVolume - 0.05)
                        @unknown default: break
                        }
                    }
                }
                .frame(width: 28, height: 150)
            }

            // Match channel strip height (pan area)
            VStack(spacing: 2) {
                Text("MST")
                    .font(.system(size: 9))
                    .foregroundColor(palette.textTertiary)
                Color.clear.frame(width: 60, height: 28)
            }

            // Match channel strip height (M/S area)
            Color.clear.frame(height: 22)
        }
        .frame(width: 80)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(palette.cardBackground)
        .cornerRadius(8)
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
                    .accessibilityLabel("\(label) volume")
                    .accessibilityValue("\(Int(channel.volume * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: channel.volume = min(1.5, channel.volume + 0.05)
                        case .decrement: channel.volume = max(0, channel.volume - 0.05)
                        @unknown default: break
                        }
                    }
                }
                .frame(width: 28, height: 150)
            }

            // Pan knob (simplified as slider)
            VStack(spacing: 2) {
                Text(panLabel)
                    .font(.system(size: 9))
                    .foregroundColor(palette.textSecondary)

                Slider(value: $channel.pan, in: -1...1, step: 0.1)
                    .tint(palette.accent)
                    .frame(width: 60)
                    .accessibilityLabel("\(label) pan")
                    .accessibilityValue(panLabel)
            }

            // Mute / Solo buttons
            HStack(spacing: 4) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    channel.isMuted.toggle()
                } label: {
                    Text("M")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(channel.isMuted ? .white : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(channel.isMuted ? Color.red : palette.inputBackground)
                        .cornerRadius(4)
                        .animation(.easeInOut(duration: 0.15), value: channel.isMuted)
                }
                .accessibilityLabel("\(label) mute")
                .accessibilityValue(channel.isMuted ? "on" : "off")

                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    channel.isSolo.toggle()
                } label: {
                    Text("S")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(channel.isSolo ? .black : palette.textSecondary)
                        .frame(width: 26, height: 22)
                        .background(channel.isSolo ? Color.yellow : palette.inputBackground)
                        .cornerRadius(4)
                        .animation(.easeInOut(duration: 0.15), value: channel.isSolo)
                }
                .accessibilityLabel("\(label) solo")
                .accessibilityValue(channel.isSolo ? "on" : "off")
            }

            // Loop toggle
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                channel.isLooped.toggle()
            } label: {
                Image(systemName: channel.isLooped ? "repeat.1" : "repeat")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(channel.isLooped ? .white : palette.textSecondary)
                    .frame(width: 56, height: 22)
                    .background(channel.isLooped ? Color.blue : palette.inputBackground)
                    .cornerRadius(4)
                    .animation(.easeInOut(duration: 0.15), value: channel.isLooped)
            }
            .accessibilityLabel("\(label) loop")
            .accessibilityValue(channel.isLooped ? "on" : "off")
        }
        .frame(width: 80)
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
