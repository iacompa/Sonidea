//
//  TranscriptSearchResultRow.swift
//  Sonidea
//
//  Display row for transcript search results with highlighted snippet and timestamp.
//  Tapping navigates to the recording and seeks to the matched segment.
//

import SwiftUI

struct TranscriptSearchResultRow: View {
    let result: TranscriptSearchResult
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Recording title + occurrence count
            HStack {
                Text(result.recordingTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(1)

                Spacer()

                Text("\(result.occurrenceCount) match\(result.occurrenceCount == 1 ? "" : "es")")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            // Snippet with highlights (parse <mark> tags)
            highlightedSnippet
                .font(.body)
                .lineLimit(2)
                .foregroundColor(palette.textPrimary)

            // Timestamp
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.caption)
                Text(formatTimestamp(result.startTime))
                    .font(.caption)

                Text("•")
                    .font(.caption)

                Text("Tap to jump")
                    .font(.caption)
                    .foregroundColor(palette.accent)
            }
            .foregroundColor(palette.textSecondary)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    // MARK: - Highlighted Snippet

    /// Parse snippet with <mark> tags and render with highlights
    @ViewBuilder
    private var highlightedSnippet: some View {
        let segments = parseSnippet(result.snippet)

        if segments.isEmpty {
            Text(result.segmentText)
        } else {
            // Build attributed string for highlighting
            Text(buildAttributedSnippet(segments))
        }
    }

    /// Build AttributedString with highlighted segments
    private func buildAttributedSnippet(_ segments: [SnippetSegment]) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            var part = AttributedString(segment.text)
            if segment.isHighlighted {
                part.foregroundColor = .white
                part.backgroundColor = palette.accent
                part.font = .body.bold()
            }
            result.append(part)
        }
        return result
    }

    /// Parse snippet string with <mark> tags into segments
    private func parseSnippet(_ snippet: String) -> [SnippetSegment] {
        var segments: [SnippetSegment] = []
        var remaining = snippet

        while !remaining.isEmpty {
            if let markStart = remaining.range(of: "<mark>") {
                // Add text before <mark>
                let beforeMark = String(remaining[..<markStart.lowerBound])
                if !beforeMark.isEmpty {
                    segments.append(SnippetSegment(text: beforeMark, isHighlighted: false))
                }

                // Find closing </mark>
                remaining = String(remaining[markStart.upperBound...])
                if let markEnd = remaining.range(of: "</mark>") {
                    let highlightedText = String(remaining[..<markEnd.lowerBound])
                    segments.append(SnippetSegment(text: highlightedText, isHighlighted: true))
                    remaining = String(remaining[markEnd.upperBound...])
                } else {
                    // No closing tag - treat rest as regular text
                    segments.append(SnippetSegment(text: remaining, isHighlighted: false))
                    break
                }
            } else {
                // No more <mark> tags
                segments.append(SnippetSegment(text: remaining, isHighlighted: false))
                break
            }
        }

        return segments
    }

    /// Format timestamp for display (e.g., "1:23" or "12:34:56")
    private func formatTimestamp(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(max(0, seconds))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }
}

// MARK: - Snippet Segment

private struct SnippetSegment {
    let text: String
    let isHighlighted: Bool
}

// MARK: - Preview

#Preview {
    VStack(spacing: 0) {
        TranscriptSearchResultRow(result: TranscriptSearchResult(
            id: 1,
            recordingId: UUID(),
            recordingTitle: "Chemistry Lecture",
            startTime: 123.5,
            endTime: 126.0,
            segmentText: "The mitochondria is the powerhouse of the cell",
            snippet: "The <mark>mitochondria</mark> is the powerhouse of the cell",
            relevanceScore: 85.0,
            occurrenceCount: 3,
            recordingCreatedAt: Date()
        ))

        Divider()

        TranscriptSearchResultRow(result: TranscriptSearchResult(
            id: 2,
            recordingId: UUID(),
            recordingTitle: "Team Meeting Notes",
            startTime: 3720.0,
            endTime: 3725.0,
            segmentText: "We need to discuss the project timeline",
            snippet: "We need to discuss the <mark>project</mark> timeline",
            relevanceScore: 72.0,
            occurrenceCount: 1,
            recordingCreatedAt: Date().addingTimeInterval(-86400 * 7)
        ))
    }
    .padding()
}
