//
//  EQGraphView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/23/26.
//

import SwiftUI

// MARK: - Parametric EQ Graph View

struct ParametricEQView: View {
    @Binding var settings: EQSettings
    @State private var selectedBand: Int? = nil
    var onSettingsChanged: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private let graphHeight: CGFloat = 180

    // Padding inside the graph for labels
    private let graphPaddingTop: CGFloat = 20
    private let graphPaddingBottom: CGFloat = 24
    private let graphPaddingLeft: CGFloat = 36
    private let graphPaddingRight: CGFloat = 12

    var body: some View {
        VStack(spacing: 16) {
            // EQ Graph
            eqGraph

            // Band controls (when a band is selected)
            if let band = selectedBand {
                bandControls(for: band)
            } else {
                // Hint text when no band selected
                Text("Tap a point to adjust its settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Reset button
            if !settings.isFlat {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        settings.reset()
                        onSettingsChanged?()
                    }
                } label: {
                    Label("Reset EQ", systemImage: "arrow.counterclockwise")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
            }
        }
    }

    // MARK: - EQ Graph

    private var eqGraph: some View {
        GeometryReader { geometry in
            let fullWidth = geometry.size.width
            let fullHeight = geometry.size.height

            // Inner graph area (excluding label padding)
            let graphWidth = fullWidth - graphPaddingLeft - graphPaddingRight
            let graphHeight = fullHeight - graphPaddingTop - graphPaddingBottom

            ZStack {
                // Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color(.systemGray6) : Color(.systemGray6))

                // Labels (outside the graph area)
                dBLabels(fullHeight: fullHeight, graphHeight: graphHeight)
                frequencyLabels(fullWidth: fullWidth, fullHeight: fullHeight, graphWidth: graphWidth)

                // Graph content area
                ZStack {
                    // Grid
                    gridLines(width: graphWidth, height: graphHeight)

                    // Center line (0 dB)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: graphHeight / 2))
                        path.addLine(to: CGPoint(x: graphWidth, y: graphHeight / 2))
                    }
                    .stroke(Color.secondary.opacity(0.5), lineWidth: 1)

                    // Frequency response curve (approximate)
                    frequencyResponseCurve(width: graphWidth, height: graphHeight)

                    // Band points
                    ForEach(0..<4, id: \.self) { index in
                        let band = settings.bands[index]
                        let x = frequencyToX(band.frequency, width: graphWidth)
                        let y = gainToY(band.gain, height: graphHeight)

                        EQBandPoint(
                            isSelected: selectedBand == index,
                            bandIndex: index,
                            colorScheme: colorScheme
                        )
                        .position(x: x, y: y)
                        .accessibilityLabel("EQ band \(index + 1)")
                        .accessibilityValue("Frequency \(Int(band.frequency)) Hz, Gain \(String(format: "%.1f", band.gain)) dB")
                        .gesture(
                            DragGesture()
                                .onChanged { value in
                                    selectedBand = index
                                    // Update frequency (X) and gain (Y)
                                    let newFreq = xToFrequency(value.location.x, width: graphWidth)
                                    let newGain = yToGain(value.location.y, height: graphHeight)
                                    settings.bands[index].frequency = newFreq
                                    settings.bands[index].gain = newGain
                                    onSettingsChanged?()
                                }
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selectedBand = selectedBand == index ? nil : index
                            }
                        }
                    }
                }
                .frame(width: graphWidth, height: graphHeight)
                .offset(x: (graphPaddingLeft - graphPaddingRight) / 2, y: (graphPaddingTop - graphPaddingBottom) / 2)
            }
        }
        .frame(height: graphHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - dB Labels (left side)

    private func dBLabels(fullHeight: CGFloat, graphHeight: CGFloat) -> some View {
        let centerY = fullHeight / 2

        return ZStack {
            // +12 dB
            Text("+12")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: 18, y: graphPaddingTop)

            // 0 dB
            Text("0")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: 12, y: centerY)

            // -12 dB
            Text("-12")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: 18, y: fullHeight - graphPaddingBottom)
        }
    }

    // MARK: - Frequency Labels (bottom)

    private func frequencyLabels(fullWidth: CGFloat, fullHeight: CGFloat, graphWidth: CGFloat) -> some View {
        let labelY = fullHeight - 8

        return ZStack {
            // 100 Hz
            Text("100")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: graphPaddingLeft + frequencyToX(100, width: graphWidth), y: labelY)

            // 1k Hz
            Text("1k")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: graphPaddingLeft + frequencyToX(1000, width: graphWidth), y: labelY)

            // 10k Hz
            Text("10k")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .position(x: graphPaddingLeft + frequencyToX(10000, width: graphWidth), y: labelY)
        }
    }

    // MARK: - Grid Lines

    private func gridLines(width: CGFloat, height: CGFloat) -> some View {
        Canvas { context, size in
            // Horizontal lines at +6, 0, -6 dB
            let gainLines: [Float] = [6, 0, -6]
            for gain in gainLines {
                let y = gainToY(gain, height: height)
                let path = Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: width, y: y))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            }

            // Vertical lines at key frequencies (100, 1k, 10k)
            let freqLines: [Float] = [100, 1000, 10000]
            for freq in freqLines {
                let x = frequencyToX(freq, width: width)
                let path = Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: height))
                }
                context.stroke(path, with: .color(.secondary.opacity(0.2)), lineWidth: 0.5)
            }
        }
    }

    // MARK: - Frequency Response Curve

    private func frequencyResponseCurve(width: CGFloat, height: CGFloat) -> some View {
        Path { path in
            let steps = 100
            for i in 0...steps {
                let x = width * CGFloat(i) / CGFloat(steps)
                let freq = xToFrequency(x, width: width)

                // Sum contributions from all bands (simplified approximation)
                var totalGain: Float = 0
                for band in settings.bands {
                    totalGain += bandContribution(at: freq, band: band)
                }

                let y = gainToY(totalGain, height: height)

                if i == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }
        }
        .stroke(
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            ),
            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
        )
    }

    /// Simplified bell curve contribution for a parametric band
    private func bandContribution(at freq: Float, band: EQBandSettings) -> Float {
        let logFreq = log10(freq)
        let logCenter = log10(band.frequency)
        let bandwidth = band.bandwidth

        // Bell curve in log-frequency domain
        let distance = (logFreq - logCenter) / (bandwidth * 0.5)
        let contribution = band.gain * exp(-distance * distance * 0.5)

        return contribution
    }

    // MARK: - Band Controls

    @ViewBuilder
    private func bandControls(for index: Int) -> some View {
        let band = settings.bands[index]

        VStack(spacing: 12) {
            // Band name
            Text(EQSettings.bandLabels[index])
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)

            // Frequency control
            VStack(spacing: 4) {
                HStack {
                    Text("Freq")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatFrequency(band.frequency))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }

                LogSlider(
                    value: Binding(
                        get: { band.frequency },
                        set: {
                            settings.bands[index].frequency = $0
                            onSettingsChanged?()
                        }
                    ),
                    range: EQBandSettings.minFrequency...EQBandSettings.maxFrequency
                )
            }

            // Gain control
            VStack(spacing: 4) {
                HStack {
                    Text("Gain")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(formatGain(band.gain))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(gainColor(band.gain))
                }

                Slider(
                    value: Binding(
                        get: { band.gain },
                        set: {
                            settings.bands[index].gain = $0
                            onSettingsChanged?()
                        }
                    ),
                    in: EQBandSettings.minGain...EQBandSettings.maxGain
                )
                .tint(.accentColor)
            }

            // Q control
            VStack(spacing: 4) {
                HStack {
                    Text("Q")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(String(format: "%.1f", band.q))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }

                Slider(
                    value: Binding(
                        get: { band.q },
                        set: {
                            settings.bands[index].q = $0
                            onSettingsChanged?()
                        }
                    ),
                    in: EQBandSettings.minQ...EQBandSettings.maxQ
                )
                .tint(.orange)
            }
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    // MARK: - Coordinate Conversion

    /// Convert frequency (Hz) to X position using log scale
    private func frequencyToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let minLog = log10(EQBandSettings.minFrequency)
        let maxLog = log10(EQBandSettings.maxFrequency)
        let freqLog = log10(max(EQBandSettings.minFrequency, min(EQBandSettings.maxFrequency, freq)))
        let normalized = (freqLog - minLog) / (maxLog - minLog)
        return CGFloat(normalized) * width
    }

    /// Convert X position to frequency (Hz) using log scale
    private func xToFrequency(_ x: CGFloat, width: CGFloat) -> Float {
        let minLog = log10(EQBandSettings.minFrequency)
        let maxLog = log10(EQBandSettings.maxFrequency)
        let normalized = Float(max(0, min(width, x)) / width)
        let freqLog = minLog + normalized * (maxLog - minLog)
        return pow(10, freqLog)
    }

    /// Convert gain (dB) to Y position
    private func gainToY(_ gain: Float, height: CGFloat) -> CGFloat {
        let normalized = (gain - EQBandSettings.minGain) / (EQBandSettings.maxGain - EQBandSettings.minGain)
        return height - (CGFloat(normalized) * height)
    }

    /// Convert Y position to gain (dB)
    private func yToGain(_ y: CGFloat, height: CGFloat) -> Float {
        let clampedY = max(0, min(height, y))
        let normalized = 1.0 - Float(clampedY / height)
        return EQBandSettings.minGain + normalized * (EQBandSettings.maxGain - EQBandSettings.minGain)
    }

    // MARK: - Formatting

    private func formatFrequency(_ freq: Float) -> String {
        if freq >= 1000 {
            return String(format: "%.1fk Hz", freq / 1000)
        } else {
            return String(format: "%.0f Hz", freq)
        }
    }

    private func formatGain(_ gain: Float) -> String {
        if gain >= 0 {
            return String(format: "+%.1f dB", gain)
        } else {
            return String(format: "%.1f dB", gain)
        }
    }

    private func gainColor(_ gain: Float) -> Color {
        if abs(gain) < 0.5 {
            return .secondary
        } else if gain > 0 {
            return .orange
        } else {
            return .blue
        }
    }
}

// MARK: - EQ Band Point

struct EQBandPoint: View {
    let isSelected: Bool
    let bandIndex: Int
    let colorScheme: ColorScheme

    private var bandColor: Color {
        switch bandIndex {
        case 0: return .red
        case 1: return .orange
        case 2: return .green
        case 3: return .blue
        default: return .purple
        }
    }

    var body: some View {
        ZStack {
            // Selection ring
            if isSelected {
                Circle()
                    .stroke(bandColor, lineWidth: 2)
                    .frame(width: 36, height: 36)
            }

            // Outer glow
            Circle()
                .fill(bandColor.opacity(0.3))
                .frame(width: 28, height: 28)

            // Inner circle
            Circle()
                .fill(bandColor)
                .frame(width: 18, height: 18)

            // Band number
            Text("\(bandIndex + 1)")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
    }
}

// MARK: - Logarithmic Slider

struct LogSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>

    private var normalizedValue: Float {
        let minLog = log10(range.lowerBound)
        let maxLog = log10(range.upperBound)
        let valueLog = log10(max(range.lowerBound, value))
        return (valueLog - minLog) / (maxLog - minLog)
    }

    private func valueFromNormalized(_ normalized: Float) -> Float {
        let minLog = log10(range.lowerBound)
        let maxLog = log10(range.upperBound)
        let valueLog = minLog + normalized * (maxLog - minLog)
        return pow(10, valueLog)
    }

    var body: some View {
        Slider(
            value: Binding(
                get: { normalizedValue },
                set: { value = valueFromNormalized($0) }
            ),
            in: 0...1
        )
        .tint(.purple)
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 24) {
        ParametricEQView(settings: .constant(.flat))
            .padding()

        ParametricEQView(
            settings: .constant(EQSettings(bands: [
                EQBandSettings(frequency: 80, gain: 6, q: 1.5),
                EQBandSettings(frequency: 500, gain: -3, q: 1.0),
                EQBandSettings(frequency: 2500, gain: 4, q: 2.0),
                EQBandSettings(frequency: 10000, gain: 8, q: 0.7)
            ]))
        )
        .padding()
    }
}
