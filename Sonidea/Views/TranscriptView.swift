//
//  TranscriptView.swift
//  Sonidea
//
//  Displays a timestamped transcript as flowing tappable word chips.
//  Tapping a word seeks playback to that word's timestamp with haptic feedback.
//  Long-press or context menu provides copy options.
//  The currently-playing word is highlighted with the accent color.
//  When a search query is provided, scrolls to the first matching word.
//

import SwiftUI
import UIKit

struct TranscriptView: View {
    let segments: [TranscriptionSegment]
    let currentTime: TimeInterval
    let onTapSegment: (TimeInterval) -> Void
    var highlightQuery: String? = nil
    /// Optional callback to scroll to a specific segment ID (called on appear with first match)
    var scrollToMatchID: UUID? = nil
    /// Optional search callback when user selects "Search" from context menu
    var onSearch: ((String) -> Void)? = nil

    @Environment(\.themePalette) private var palette
    @Environment(\.layoutDirection) private var layoutDirection

    // Selection state
    @State private var isSelectionMode = false
    @State private var selectedSegmentIDs: Set<UUID> = []
    @State private var selectionStartIndex: Int? = nil
    @State private var showCopiedToast = false

    // Haptic feedback generator (shared instance for performance)
    private static let hapticGenerator = UIImpactFeedbackGenerator(style: .light)

    /// Find the first segment that matches the query
    private var firstMatchID: UUID? {
        guard let query = highlightQuery, !query.isEmpty else { return nil }
        return segments.first { $0.text.localizedCaseInsensitiveContains(query) }?.id
    }

    /// Check if a word matches the search query (case-insensitive)
    private func matchesQuery(_ text: String) -> Bool {
        guard let query = highlightQuery, !query.isEmpty else { return false }
        return text.localizedCaseInsensitiveContains(query)
    }

    /// Get the index of a segment by ID
    private func segmentIndex(for id: UUID) -> Int? {
        segments.firstIndex { $0.id == id }
    }

    /// Get selected text as a string
    private var selectedText: String {
        segments
            .filter { selectedSegmentIDs.contains($0.id) }
            .map { $0.text }
            .joined(separator: " ")
    }

    /// Get text from a segment to the end
    private func textFromSegment(_ segment: TranscriptionSegment) -> String {
        guard let startIndex = segmentIndex(for: segment.id) else { return segment.text }
        return segments[startIndex...]
            .map { $0.text }
            .joined(separator: " ")
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
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 8) {
                    // Header with hint and selection toggle
                    HStack {
                        if isSelectionMode {
                            HStack(spacing: 4) {
                                Image(systemName: "text.cursor")
                                    .font(.caption2)
                                Text("Tap words to select, tap again to deselect")
                                    .font(.caption)
                            }
                            .foregroundColor(palette.accent)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "hand.tap")
                                    .font(.caption2)
                                Text("Tap to play, long-press to copy")
                                    .font(.caption)
                            }
                            .foregroundColor(palette.textSecondary.opacity(0.7))
                        }

                        Spacer()

                        // Selection mode toggle
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode.toggle()
                                if !isSelectionMode {
                                    selectedSegmentIDs.removeAll()
                                    selectionStartIndex = nil
                                }
                            }
                            Self.hapticGenerator.impactOccurred()
                        } label: {
                            Image(systemName: isSelectionMode ? "xmark.circle.fill" : "selection.pin.in.out")
                                .font(.subheadline)
                                .foregroundColor(isSelectionMode ? palette.accent : palette.textSecondary)
                        }
                    }

                    // Copy selection button when in selection mode with selections
                    if isSelectionMode && !selectedSegmentIDs.isEmpty {
                        Button {
                            copyToClipboard(selectedText)
                            Self.hapticGenerator.impactOccurred()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "doc.on.doc")
                                    .font(.caption)
                                Text("Copy \(selectedSegmentIDs.count) word\(selectedSegmentIDs.count == 1 ? "" : "s")")
                                    .font(.caption.weight(.medium))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(palette.accent)
                            .clipShape(Capsule())
                        }
                        .transition(.scale.combined(with: .opacity))
                    }

                    FlowLayout(spacing: 4) {
                        ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                            wordChip(for: segment, at: index)
                                .id(segment.id)
                        }
                    }
                }
                .onAppear {
                    // Scroll to first match when view appears
                    if let matchID = scrollToMatchID ?? firstMatchID {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                proxy.scrollTo(matchID, anchor: .center)
                            }
                        }
                    }
                }
                .overlay(alignment: .bottom) {
                    // Copied toast
                    if showCopiedToast {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                            Text("Copied to clipboard")
                        }
                        .font(.caption.weight(.medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.black.opacity(0.75))
                        .clipShape(Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func wordChip(for segment: TranscriptionSegment, at index: Int) -> some View {
        let isCurrent = currentTime >= segment.startTime
            && currentTime < segment.startTime + segment.duration
        let isSearchMatch = matchesQuery(segment.text)
        let isSelected = selectedSegmentIDs.contains(segment.id)

        WordChipView(
            text: segment.text,
            isCurrent: isCurrent,
            isSearchMatch: isSearchMatch,
            isSelected: isSelected,
            isSelectionMode: isSelectionMode,
            palette: palette,
            onTap: {
                if isSelectionMode {
                    handleSelectionTap(segment: segment, at: index)
                } else {
                    // Haptic feedback on tap
                    Self.hapticGenerator.impactOccurred()
                    onTapSegment(segment.startTime)
                }
            },
            onCopyWord: {
                copyToClipboard(segment.text)
            },
            onCopyFromHere: {
                copyToClipboard(textFromSegment(segment))
            },
            onSearch: onSearch != nil ? {
                onSearch?(segment.text)
            } : nil
        )
    }

    private func handleSelectionTap(segment: TranscriptionSegment, at index: Int) {
        Self.hapticGenerator.impactOccurred()

        if selectedSegmentIDs.contains(segment.id) {
            // Deselect
            selectedSegmentIDs.remove(segment.id)
            if selectedSegmentIDs.isEmpty {
                selectionStartIndex = nil
            }
        } else {
            // Select
            if selectionStartIndex == nil {
                // First selection
                selectionStartIndex = index
                selectedSegmentIDs.insert(segment.id)
            } else {
                // Extend selection to include range
                let start = min(selectionStartIndex!, index)
                let end = max(selectionStartIndex!, index)
                for i in start...end {
                    selectedSegmentIDs.insert(segments[i].id)
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        UIPasteboard.general.string = text
        withAnimation(.easeInOut(duration: 0.2)) {
            showCopiedToast = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation(.easeInOut(duration: 0.2)) {
                showCopiedToast = false
            }
        }
    }
}

// MARK: - Word Chip View with Animation

private struct WordChipView: View {
    let text: String
    let isCurrent: Bool
    let isSearchMatch: Bool
    let isSelected: Bool
    let isSelectionMode: Bool
    let palette: ThemePalette

    let onTap: () -> Void
    let onCopyWord: () -> Void
    let onCopyFromHere: () -> Void
    let onSearch: (() -> Void)?

    @State private var isPulsing = false

    private var foregroundColor: Color {
        if isCurrent || isSelected {
            return .white
        } else if isSearchMatch {
            return palette.accent
        } else {
            return palette.textPrimary
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return palette.accent.opacity(0.8)
        } else if isCurrent {
            return palette.accent
        } else if isSearchMatch {
            return palette.accent.opacity(0.15)
        } else {
            return Color.clear
        }
    }

    var body: some View {
        Text(text)
            .font(.subheadline)
            .lineLimit(1)
            .foregroundColor(foregroundColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 1.5)
            )
            .scaleEffect(isPulsing ? 1.1 : 1.0)
            .contentShape(Rectangle())
            .onTapGesture {
                // Trigger pulse animation
                withAnimation(.easeOut(duration: 0.1)) {
                    isPulsing = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(.easeIn(duration: 0.1)) {
                        isPulsing = false
                    }
                }
                onTap()
            }
            .contextMenu {
                Button {
                    onCopyWord()
                } label: {
                    Label("Copy Word", systemImage: "doc.on.doc")
                }

                Button {
                    onCopyFromHere()
                } label: {
                    Label("Copy from Here", systemImage: "text.append")
                }

                if let onSearch = onSearch {
                    Divider()
                    Button {
                        onSearch()
                    } label: {
                        Label("Search", systemImage: "magnifyingglass")
                    }
                }
            }
    }
}
