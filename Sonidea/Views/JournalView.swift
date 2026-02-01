//
//  JournalView.swift
//  Sonidea
//
//  Chronological timeline view of all recordings and project takes.
//  Provides a "proof trail" for ideas with grouping by day.
//

import SwiftUI

// MARK: - Journal View

struct JournalView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var selectedRecording: RecordingItem?
    @State private var selectedProject: Project?
    @State private var cachedTimelineGroups: [TimelineGroup] = []

    private func recomputeTimelineGroups() {
        let items = TimelineBuilder.buildTimeline(
            recordings: appState.activeRecordings,
            projects: appState.projects
        )
        cachedTimelineGroups = TimelineBuilder.groupByDay(items)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background
                    .ignoresSafeArea()

                if cachedTimelineGroups.isEmpty {
                    emptyStateView
                } else {
                    timelineList
                }
            }
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.medium))
                            .foregroundStyle(palette.textPrimary)
                    }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(project: project)
            }
            .onAppear { recomputeTimelineGroups() }
            .onChange(of: appState.recordingsContentVersion) { _, _ in
                recomputeTimelineGroups()
            }
        }
    }

    // MARK: - Empty State

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 56))
                .foregroundStyle(palette.textTertiary)

            Text("No Recordings Yet")
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            Text("Your recording timeline will appear here as you create recordings.")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: - Timeline List

    private var timelineList: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                ForEach(cachedTimelineGroups) { group in
                    Section {
                        ForEach(group.items) { item in
                            TimelineRowView(
                                item: item,
                                tags: tagsForItem(item),
                                albumName: albumNameForItem(item)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                handleItemTap(item)
                            }

                            if item.id != group.items.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    } header: {
                        sectionHeader(for: group)
                    }
                }
            }
            .padding(.bottom, 100)
        }
        .scrollContentBackground(.hidden)
    }

    // MARK: - Section Header

    private func sectionHeader(for group: TimelineGroup) -> some View {
        HStack {
            Text(group.displayTitle)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .textCase(.uppercase)

            Spacer()

            Text("\(group.items.count)")
                .font(.footnote)
                .foregroundStyle(palette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(palette.background)
    }

    // MARK: - Helpers

    private func tagsForItem(_ item: TimelineItem) -> [Tag] {
        item.tagIDs.compactMap { appState.tag(for: $0) }
    }

    private func albumNameForItem(_ item: TimelineItem) -> String? {
        guard let albumID = item.albumID else { return nil }
        return appState.album(for: albumID)?.name
    }

    private func handleItemTap(_ item: TimelineItem) {
        if let recording = appState.recording(for: item.recordingID) {
            selectedRecording = recording
        }
    }
}

// MARK: - Timeline Row View

struct TimelineRowView: View {
    @Environment(\.themePalette) private var palette

    let item: TimelineItem
    let tags: [Tag]
    let albumName: String?

    private var formattedTime: String {
        CachedDateFormatter.timeOnly.string(from: item.timestamp)
    }

    private var formattedDuration: String {
        let minutes = Int(item.duration) / 60
        let seconds = Int(item.duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack(alignment: .trailing) {
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 50, alignment: .trailing)

            // Timeline indicator
            VStack(spacing: 4) {
                Circle()
                    .fill(item.isBestTake ? Color.yellow : palette.accent)
                    .frame(width: 10, height: 10)
            }

            // Content
            VStack(alignment: .leading, spacing: 6) {
                // Title row
                HStack(alignment: .center, spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    if item.isBestTake {
                        bestTakeBadge
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }

                // Metadata row
                HStack(spacing: 8) {
                    // Duration
                    Label(formattedDuration, systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                    // Project/Take context
                    if case .projectTake(let projectTitle, let takeLabel) = item.type {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)

                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text("\(projectTitle) · \(takeLabel)")
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()
                }

                // Location (if present)
                if let location = item.locationLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "location")
                            .font(.caption2)
                        Text(location)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(palette.textTertiary)
                }

                // Tags and Album
                if !tags.isEmpty || albumName != nil {
                    HStack(spacing: 6) {
                        // Album
                        if let album = albumName {
                            Text(album)
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(palette.textSecondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(palette.chipBackground)
                                .clipShape(Capsule())
                        }

                        // Tags
                        ForEach(tags.prefix(3)) { tag in
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 6, height: 6)
                                Text(tag.name)
                                    .lineLimit(1)
                            }
                            .font(.caption2)
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(palette.chipBackground)
                            .clipShape(Capsule())
                        }

                        if tags.count > 3 {
                            Text("+\(tags.count - 3)")
                                .font(.caption2)
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette.background)
    }

    private var bestTakeBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "star.fill")
                .font(.caption2)
            Text("Best")
                .font(.caption2.weight(.semibold))
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.yellow)
        .clipShape(Capsule())
    }
}

// MARK: - Preview

#Preview {
    JournalView()
        .environment(AppState())
}
