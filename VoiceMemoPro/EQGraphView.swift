//
//  EQGraphView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/23/26.
//

import SwiftUI

// MARK: - EQ Graph View

struct EQGraphView: View {
    @Binding var settings: EQSettings
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    private let bandCount = 4
    private let graphHeight: CGFloat = 120

    var body: some View {
        VStack(spacing: 8) {
            // Graph area
            GeometryReader { geometry in
                let width = geometry.size.width
                let height = geometry.size.height
                let bandWidth = width / CGFloat(bandCount)

                ZStack {
                    // Background grid
                    gridBackground(width: width, height: height)

                    // Center line (0 dB)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: height / 2))
                        path.addLine(to: CGPoint(x: width, y: height / 2))
                    }
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)

                    // Connecting line between points
                    Path { path in
                        for i in 0..<bandCount {
                            let x = bandWidth * CGFloat(i) + bandWidth / 2
                            let y = yPosition(for: settings.gain(for: i), height: height)

                            if i == 0 {
                                path.move(to: CGPoint(x: x, y: y))
                            } else {
                                path.addLine(to: CGPoint(x: x, y: y))
                            }
                        }
                    }
                    .stroke(
                        isEnabled ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.4),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
                    )

                    // Draggable points
                    ForEach(0..<bandCount, id: \.self) { index in
                        let x = bandWidth * CGFloat(index) + bandWidth / 2
                        let y = yPosition(for: settings.gain(for: index), height: height)

                        EQDragPoint(
                            gain: settings.gain(for: index),
                            isEnabled: isEnabled
                        )
                        .position(x: x, y: y)
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    guard isEnabled else { return }
                                    let newGain = gainFromY(value.location.y, height: height)
                                    settings.setGain(newGain, for: index)
                                }
                        )
                    }
                }
            }
            .frame(height: graphHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .opacity(isEnabled ? 1.0 : 0.5)

            // Band labels with dB values
            HStack(spacing: 0) {
                ForEach(0..<bandCount, id: \.self) { index in
                    VStack(spacing: 2) {
                        Text(EQSettings.bandLabels[index])
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)

                        Text(formatGain(settings.gain(for: index)))
                            .font(.caption2)
                            .monospacedDigit()
                            .foregroundColor(isEnabled ? gainColor(settings.gain(for: index)) : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Reset button
            if isEnabled && settings != .flat {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings = .flat
                    }
                } label: {
                    Text("Reset EQ")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - Helpers

    private func gridBackground(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            // Horizontal grid lines at -6dB and +6dB
            let quarterHeight = height / 4

            for i in 1...3 {
                let y = quarterHeight * CGFloat(i)
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: width, y: y))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            }

            // Vertical separator lines
            let bandWidth = width / CGFloat(bandCount)
            for i in 1..<bandCount {
                let x = bandWidth * CGFloat(i)
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: height))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.15)), lineWidth: 0.5)
            }
        }
    }

    private func yPosition(for gain: Float, height: CGFloat) -> CGFloat {
        // Map gain (-12 to +12) to y position (height to 0)
        let normalizedGain = (gain - EQSettings.minGain) / (EQSettings.maxGain - EQSettings.minGain)
        return height - (CGFloat(normalizedGain) * height)
    }

    private func gainFromY(_ y: CGFloat, height: CGFloat) -> Float {
        // Map y position to gain
        let clampedY = max(0, min(height, y))
        let normalizedY = 1.0 - (clampedY / height)
        return EQSettings.minGain + Float(normalizedY) * (EQSettings.maxGain - EQSettings.minGain)
    }

    private func formatGain(_ gain: Float) -> String {
        if gain >= 0 {
            return String(format: "+%.0f", gain)
        } else {
            return String(format: "%.0f", gain)
        }
    }

    private func gainColor(_ gain: Float) -> Color {
        if abs(gain) < 1 {
            return .secondary
        } else if gain > 0 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - EQ Drag Point

struct EQDragPoint: View {
    let gain: Float
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Outer glow
            Circle()
                .fill(isEnabled ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.2))
                .frame(width: 32, height: 32)

            // Inner circle
            Circle()
                .fill(isEnabled ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 20)

            // Center dot
            Circle()
                .fill(colorScheme == .dark ? Color.white : Color.white)
                .frame(width: 8, height: 8)
        }
    }
}

// MARK: - Compact EQ View (for smaller spaces)

struct CompactEQView: View {
    @Binding var settings: EQSettings
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { index in
                VStack(spacing: 4) {
                    Text(EQSettings.bandLabels[index])
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    CompactEQSlider(
                        value: Binding(
                            get: { settings.gain(for: index) },
                            set: { settings.setGain($0, for: index) }
                        ),
                        isEnabled: isEnabled
                    )
                    .frame(height: 80)
                }
            }
        }
    }
}

// MARK: - Compact EQ Slider (vertical)

struct CompactEQSlider: View {
    @Binding var value: Float
    var isEnabled: Bool = true

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let thumbY = yPosition(for: value, height: height)

            ZStack {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(.systemGray5))
                    .frame(width: 8)

                // Center marker
                Rectangle()
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: 12, height: 1)
                    .position(x: geometry.size.width / 2, y: height / 2)

                // Value fill
                VStack {
                    Spacer()
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isEnabled ? Color.accentColor.opacity(0.6) : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: max(0, height / 2 - thumbY))
                }

                // Thumb
                Circle()
                    .fill(isEnabled ? Color.accentColor : Color.secondary)
                    .frame(width: 16, height: 16)
                    .position(x: geometry.size.width / 2, y: thumbY)
                    .gesture(
                        DragGesture()
                            .onChanged { dragValue in
                                guard isEnabled else { return }
                                value = gainFromY(dragValue.location.y, height: height)
                            }
                    )
            }
        }
        .opacity(isEnabled ? 1.0 : 0.5)
    }

    private func yPosition(for gain: Float, height: CGFloat) -> CGFloat {
        let normalizedGain = (gain - EQSettings.minGain) / (EQSettings.maxGain - EQSettings.minGain)
        return height - (CGFloat(normalizedGain) * height)
    }

    private func gainFromY(_ y: CGFloat, height: CGFloat) -> Float {
        let clampedY = max(0, min(height, y))
        let normalizedY = 1.0 - (clampedY / height)
        let gain = EQSettings.minGain + Float(normalizedY) * (EQSettings.maxGain - EQSettings.minGain)
        return max(EQSettings.minGain, min(EQSettings.maxGain, gain))
    }
}

// MARK: - Volume Slider

struct VolumeSliderView: View {
    @Binding var volume: Float
    var isEnabled: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "speaker.fill")
                .font(.caption)
                .foregroundColor(.secondary)

            Slider(value: $volume, in: 0...1)
                .tint(.accentColor)
                .disabled(!isEnabled)

            Image(systemName: "speaker.wave.3.fill")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("\(Int(volume * 100))%")
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
        .opacity(isEnabled ? 1.0 : 0.5)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        EQGraphView(settings: .constant(.flat))
            .padding()

        EQGraphView(
            settings: .constant(EQSettings(
                lowGain: 6,
                lowMidGain: -3,
                highMidGain: 4,
                highGain: 8
            ))
        )
        .padding()

        VolumeSliderView(volume: .constant(0.75))
            .padding()

        CompactEQView(settings: .constant(.flat))
            .padding()
    }
}
