//
//  WaveformView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var progress: Double = 0
    @Binding var zoomScale: CGFloat

    private let minZoom: CGFloat = 1.0
    private let maxZoom: CGFloat = 10.0
    private let barSpacing: CGFloat = 2
    private let minBarWidth: CGFloat = 2

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { geometry in
            let baseWidth = geometry.size.width
            let zoomedWidth = baseWidth * zoomScale

            ScrollViewReader { scrollProxy in
                ScrollView(.horizontal, showsIndicators: zoomScale > 1) {
                    WaveformCanvas(
                        samples: samples,
                        progress: progress,
                        width: zoomedWidth,
                        height: geometry.size.height,
                        isDarkMode: colorScheme == .dark
                    )
                    .frame(width: zoomedWidth, height: geometry.size.height)
                    .id("waveform")
                }
            }
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = zoomScale * value
                        zoomScale = min(max(newScale, minZoom), maxZoom)
                    }
            )
        }
    }
}

struct WaveformCanvas: View {
    let samples: [Float]
    let progress: Double
    let width: CGFloat
    let height: CGFloat
    let isDarkMode: Bool

    private let barSpacing: CGFloat = 2
    private let cornerRadius: CGFloat = 1.5

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let barCount = samples.count
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = max(2, availableWidth / CGFloat(barCount))

            let progressIndex = Int(progress * Double(barCount))

            let playedColor: Color = isDarkMode ? .white : .accentColor
            let unplayedColor: Color = isDarkMode ? .white.opacity(0.3) : Color(.systemGray3)

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = max(4, CGFloat(sample) * size.height * 0.9)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: cornerRadius)
                    .path(in: rect)

                let isPlayed = index < progressIndex
                let color: Color = isPlayed ? playedColor : unplayedColor

                context.fill(path, with: .color(color))
            }

            // Draw playhead line
            if progress > 0 && progress < 1 {
                let playheadX = CGFloat(progress) * size.width
                let playheadPath = Path { path in
                    path.move(to: CGPoint(x: playheadX, y: 0))
                    path.addLine(to: CGPoint(x: playheadX, y: size.height))
                }
                context.stroke(playheadPath, with: .color(playedColor), lineWidth: 2)
            }
        }
    }
}

// MARK: - Mini Waveform for List Rows

struct MiniWaveformView: View {
    let samples: [Float]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let barCount = samples.count
            let barSpacing: CGFloat = 1
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = max(1, availableWidth / CGFloat(barCount))

            let barColor: Color = colorScheme == .dark ? .white.opacity(0.5) : Color(.systemGray3)

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = max(2, CGFloat(sample) * size.height * 0.85)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: 0.5)
                    .path(in: rect)

                context.fill(path, with: .color(barColor))
            }
        }
    }
}

// MARK: - Live Waveform View for Recording

struct LiveWaveformView: View {
    let samples: [Float]

    var body: some View {
        Canvas { context, size in
            guard !samples.isEmpty else { return }

            let barCount = samples.count
            let barSpacing: CGFloat = 2
            let totalSpacing = barSpacing * CGFloat(barCount - 1)
            let availableWidth = size.width - totalSpacing
            let barWidth = max(2, availableWidth / CGFloat(barCount))

            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * (barWidth + barSpacing)
                let barHeight = max(4, CGFloat(sample) * size.height * 0.9)
                let y = (size.height - barHeight) / 2

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = RoundedRectangle(cornerRadius: 1.5)
                    .path(in: rect)

                // Gradient effect: more recent samples are brighter
                let alpha = 0.3 + (Double(index) / Double(barCount)) * 0.7
                context.fill(path, with: .color(.red.opacity(alpha)))
            }
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 20) {
        // Static waveform
        WaveformView(
            samples: (0..<100).map { _ in Float.random(in: 0.1...1.0) },
            progress: 0.4,
            zoomScale: .constant(1.0)
        )
        .frame(height: 80)

        // Live waveform
        LiveWaveformView(
            samples: (0..<60).map { _ in Float.random(in: 0.1...1.0) }
        )
        .frame(height: 60)

        // Mini waveform
        MiniWaveformView(
            samples: (0..<30).map { _ in Float.random(in: 0.1...1.0) }
        )
        .frame(width: 60, height: 30)
    }
    .padding()
}
