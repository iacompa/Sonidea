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
    var highlightQuery: String? = nil

    @Environment(\.themePalette) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    /// Check if a word matches the search query (case-insensitive)
    private func matchesQuery(_ text: String) -> Bool {
        guard let query = highlightQuery, !query.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(query)
    }

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
        let isSearchMatch = matchesQuery(segment.text)

        Text(segment.text)
            .font(.subheadline)
            .lineLimit(1)
            .foregroundColor(chipForeground(isCurrent: isCurrent, isSearchMatch: isSearchMatch))
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(chipBackground(isCurrent: isCurrent, isSearchMatch: isSearchMatch))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                onTapSegment(segment.startTime)
            }
    }

    /// Foreground color for word chip based on state
    private func chipForeground(isCurrent: Bool, isSearchMatch: Bool) -> Color {
        if isCurrent {
            return .white
        } else if isSearchMatch {
            return palette.accent
        } else {
            return palette.textPrimary
        }
    }

    /// Background color for word chip based on state
    private func chipBackground(isCurrent: Bool, isSearchMatch: Bool) -> Color {
        if isCurrent {
            return palette.accent
        } else if isSearchMatch {
            return palette.accent.opacity(0.15)
        } else {
            return Color.clear
        }
    }
}
