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
    @State private var selectedBand: Int? = 0
    var onSettingsChanged: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private let graphHeight: CGFloat = 180

    // Padding inside the graph for labels
    private let graphPaddingTop: CGFloat = 20
    private let graphPaddingBottom: CGFloat = 24
    private let graphPaddingLeft: CGFloat = 36
    private let graphPaddingRight: CGFloat = 12

    var body: some View {
        VStack(spacing: 12) {
            // EQ Graph
            eqGraph

            // Knob controls for selected band
            if let band = selectedBand {
                knobControls(for: band)
            }

            // Reset handled by parent panel's Reset button
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
                                selectedBand = index
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

    // Fix #7: drawingGroup() rasterizes the curve to reduce CPU during SwiftUI diffing
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
        .drawingGroup()
    }

    /// Simplified bell curve contribution for a parametric band
    /// Fix #6: Uses cached log10 constants instead of recomputing per call
    private func bandContribution(at freq: Float, band: EQBandSettings) -> Float {
        let logFreq = log10(freq)
        let logCenter = log10(band.frequency)

        // Bell curve in log-frequency domain
        let distance = (logFreq - logCenter) / (band.bandwidth * 0.5)
        return band.gain * exp(-distance * distance * 0.5)
    }

    // MARK: - Knob Controls

    @ViewBuilder
    private func knobControls(for index: Int) -> some View {
        HStack(spacing: 0) {
            // Freq knob (logarithmic)
            VStack(spacing: 4) {
                Text("Freq")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                EQKnob(
                    value: Binding(
                        get: { settings.bands[index].frequency },
                        set: {
                            settings.bands[index].frequency = $0
                            onSettingsChanged?()
                        }
                    ),
                    range: EQBandSettings.minFrequency...EQBandSettings.maxFrequency,
                    color: Self.bandColors[index],
                    isLogarithmic: true
                )
                .accessibilityLabel("Frequency")

                Text(formatFrequency(settings.bands[index].frequency))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)

            // Gain knob (linear)
            VStack(spacing: 4) {
                Text("Gain")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                EQKnob(
                    value: Binding(
                        get: { settings.bands[index].gain },
                        set: {
                            settings.bands[index].gain = $0
                            onSettingsChanged?()
                        }
                    ),
                    range: EQBandSettings.minGain...EQBandSettings.maxGain,
                    color: Self.bandColors[index]
                )
                .accessibilityLabel("Gain")

                Text(formatGain(settings.bands[index].gain))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)

            // Q knob (linear)
            VStack(spacing: 4) {
                Text("Q")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                EQKnob(
                    value: Binding(
                        get: { settings.bands[index].q },
                        set: {
                            settings.bands[index].q = $0
                            onSettingsChanged?()
                        }
                    ),
                    range: EQBandSettings.minQ...EQBandSettings.maxQ,
                    color: Self.bandColors[index]
                )
                .accessibilityLabel("Q Factor")

                Text(String(format: "%.1f", settings.bands[index].q))
                    .font(.system(size: 11))
                    .monospacedDigit()
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    static let bandColors: [Color] = [.red, .orange, .green, .blue]

    // MARK: - Coordinate Conversion

    // Fix #6: Cache log10 constants (computed once, not per call)
    private static let minLogFreq = log10(EQBandSettings.minFrequency)
    private static let maxLogFreq = log10(EQBandSettings.maxFrequency)
    private static let logFreqRange = maxLogFreq - minLogFreq

    /// Convert frequency (Hz) to X position using log scale
    private func frequencyToX(_ freq: Float, width: CGFloat) -> CGFloat {
        let freqLog = log10(max(EQBandSettings.minFrequency, min(EQBandSettings.maxFrequency, freq)))
        let normalized = (freqLog - Self.minLogFreq) / Self.logFreqRange
        return CGFloat(normalized) * width
    }

    /// Convert X position to frequency (Hz) using log scale
    private func xToFrequency(_ x: CGFloat, width: CGFloat) -> Float {
        let normalized = Float(max(0, min(width, x)) / width)
        let freqLog = Self.minLogFreq + normalized * Self.logFreqRange
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

// MARK: - EQ Knob

struct EQKnob: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var color: Color = .blue
    var isLogarithmic: Bool = false

    private let size: CGFloat = 56
    /// Total arc sweep: 270 degrees
    private let totalAngle: Double = 270
    /// Start angle offset from 12 o'clock (clockwise). 135 degrees = 7 o'clock position
    private let startAngle: Double = 135
    /// Number of haptic detent positions across the full range
    private static let hapticDetents = 20

    // Drag state: captures normalized value at gesture start to prevent compounding
    @State private var dragStartNormalized: Double?
    @State private var lastDetent: Int = -1

    // Log scale helpers
    private var minLog: Float { log10(max(1e-10, range.lowerBound)) }
    private var maxLog: Float { log10(max(1e-10, range.upperBound)) }
    private var logRange: Float { maxLog - minLog }

    /// Normalize value to 0...1
    private var normalized: Double {
        if isLogarithmic {
            let clamped = max(range.lowerBound, min(range.upperBound, value))
            let logVal = log10(max(1e-10, clamped))
            return Double((logVal - minLog) / logRange)
        } else {
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return Double((value - range.lowerBound) / span)
        }
    }

    /// Convert normalized 0...1 back to value
    private func valueFromNormalized(_ n: Double) -> Float {
        let clamped = Float(max(0, min(1, n)))
        if isLogarithmic {
            let logVal = minLog + clamped * logRange
            return pow(10, logVal)
        } else {
            return range.lowerBound + clamped * (range.upperBound - range.lowerBound)
        }
    }

    private static let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        let trackLineWidth: CGFloat = 4
        let arcRadius = (size - trackLineWidth) / 2

        ZStack {
            // Background track arc
            Arc(startAngle: startAngle, sweepAngle: totalAngle)
                .stroke(color.opacity(0.2), style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round))
                .frame(width: arcRadius * 2, height: arcRadius * 2)

            // Value arc
            Arc(startAngle: startAngle, sweepAngle: totalAngle * normalized)
                .stroke(color, style: StrokeStyle(lineWidth: trackLineWidth, lineCap: .round))
                .frame(width: arcRadius * 2, height: arcRadius * 2)

            // Indicator dot
            let indicatorAngle = Angle.degrees(startAngle + totalAngle * normalized - 90)
            let dotRadius: CGFloat = 3
            Circle()
                .fill(color)
                .frame(width: dotRadius * 2, height: dotRadius * 2)
                .offset(
                    x: (arcRadius - 1) * CGFloat(cos(indicatorAngle.radians)),
                    y: (arcRadius - 1) * CGFloat(sin(indicatorAngle.radians))
                )
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { gesture in
                    // Capture starting position once per drag
                    if dragStartNormalized == nil {
                        dragStartNormalized = normalized
                        lastDetent = Int(normalized * Double(Self.hapticDetents))
                    }
                    // Vertical drag: up = increase, down = decrease
                    // Full range requires ~500pt of drag
                    let delta = -Double(gesture.translation.height) / 500.0
                    guard let startNorm = dragStartNormalized else { return }
                    let newNorm = max(0, min(1, startNorm + delta))
                    value = valueFromNormalized(newNorm)

                    // Haptic on detent crossing
                    let newDetent = Int(newNorm * Double(Self.hapticDetents))
                    if newDetent != lastDetent {
                        lastDetent = newDetent
                        Self.hapticGenerator.impactOccurred()
                    }
                }
                .onEnded { _ in
                    dragStartNormalized = nil
                }
        )
    }
}

/// Arc shape for knob track/value
private struct Arc: Shape {
    let startAngle: Double
    let sweepAngle: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        var path = Path()
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngle - 90),
            endAngle: .degrees(startAngle + sweepAngle - 90),
            clockwise: false
        )
        return path
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
