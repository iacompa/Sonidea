//
//  TranscriptView.swift
//  Sonidea
//
//  Displays a timestamped transcript as flowing tappable word chips.
//  Tapping a word seeks playback to that word's timestamp.
//  The currently-playing word is highlighted with the accent color.
//

import SwiftUI

struct TranscriptView: View {
    let segments: [TranscriptionSegment]
    let currentTime: TimeInterval
    let onTapSegment: (TimeInterval) -> Void

    @Environment(\.themePalette) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    var body: some View {
        if segments.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "text.word.spacing")
                    .font(.title3)
                    .foregroundColor(palette.textSecondary.opacity(0.6))
                Text("Tap Transcribe to generate a word-level transcript")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else {
            FlowLayout(spacing: 4) {
                ForEach(segments) { segment in
                    wordChip(for: segment)
                }
            }
        }
    }

    @ViewBuilder
    private func wordChip(for segment: TranscriptionSegment) -> some View {
        let isCurrent = currentTime >= segment.startTime
            && currentTime < segment.startTime + segment.duration

        Text(segment.text)
            .font(.subheadline)
            .lineLimit(1)
            .foregroundColor(isCurrent ? .white : palette.textPrimary)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isCurrent ? palette.accent : Color.clear)
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTapSegment(segment.startTime)
            }
    }
}
