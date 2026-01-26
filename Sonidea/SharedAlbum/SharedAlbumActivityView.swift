//
//  SharedAlbumActivityView.swift
//  Sonidea
//
//  Activity feed UI for shared albums.
//  Shows chronological list of all album events for trust and transparency.
//

import SwiftUI

struct SharedAlbumActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album

    @State private var events: [SharedAlbumActivityEvent] = []
    @State private var isLoading = true
    @State private var selectedCategory: ActivityCategory = .all

    var filteredEvents: [SharedAlbumActivityEvent] {
        guard selectedCategory != .all else { return events }
        return events.filter { $0.eventType.category == selectedCategory }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category filter
                categoryFilter

                // Events list
                if isLoading {
                    Spacer()
                    ProgressView("Loading activity...")
                    Spacer()
                } else if filteredEvents.isEmpty {
                    emptyStateView
                } else {
                    eventsList
                }
            }
            .background(palette.background)
            .navigationTitle("Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        loadActivity()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .foregroundColor(palette.accent)
                }
            }
            .onAppear {
                loadActivity()
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ActivityCategory.allCases, id: \.self) { category in
                    CategoryChip(
                        category: category,
                        isSelected: selectedCategory == category,
                        count: countForCategory(category)
                    ) {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategory = category
                        }
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
        }
        .background(palette.cardBackground)
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(palette.textTertiary)

            Text("No Activity Yet")
                .font(.headline)
                .foregroundColor(palette.textSecondary)

            Text("Activity will appear here as people use this album")
                .font(.subheadline)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()
        }
    }

    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(groupedEvents, id: \.0) { date, dayEvents in
                    Section {
                        ForEach(dayEvents) { event in
                            ActivityEventRow(event: event)
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                            if event.id != dayEvents.last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }
                    } header: {
                        dateHeader(for: date)
                    }
                }
            }
        }
    }

    private func dateHeader(for date: String) -> some View {
        HStack {
            Text(date)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(palette.textSecondary)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(palette.background)
    }

    private var groupedEvents: [(String, [SharedAlbumActivityEvent])] {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none

        let today = formatter.string(from: Date())
        let yesterday = formatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date()) ?? Date())

        let grouped = Dictionary(grouping: filteredEvents) { event -> String in
            let dateString = formatter.string(from: event.timestamp)
            if dateString == today {
                return "Today"
            } else if dateString == yesterday {
                return "Yesterday"
            }
            return dateString
        }

        return grouped.sorted { $0.value.first?.timestamp ?? Date() > $1.value.first?.timestamp ?? Date() }
    }

    private func countForCategory(_ category: ActivityCategory) -> Int {
        guard category != .all else { return events.count }
        return events.filter { $0.eventType.category == category }.count
    }

    private func loadActivity() {
        isLoading = true
        Task {
            // Use mock data in debug mode
            if appState.isSharedAlbumsDebugMode {
                await MainActor.run {
                    events = appState.debugMockActivityFeed()
                    isLoading = false
                }
            } else {
                let fetched = await appState.sharedAlbumManager.fetchActivityFeed(for: album, limit: 100)
                await MainActor.run {
                    events = fetched
                    isLoading = false
                }
            }
        }
    }
}

// MARK: - Category Chip

struct CategoryChip: View {
    @Environment(\.themePalette) private var palette

    let category: ActivityCategory
    let isSelected: Bool
    let count: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(category.displayName)
                    .font(.subheadline)
                    .fontWeight(isSelected ? .semibold : .regular)

                if count > 0 && !isSelected {
                    Text("\(count)")
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            .foregroundColor(isSelected ? .white : palette.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(isSelected ? Color.blue : palette.background)
            )
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color.clear : palette.textTertiary.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Activity Event Row

struct ActivityEventRow: View {
    @Environment(\.themePalette) private var palette

    let event: SharedAlbumActivityEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(event.eventType.iconColor.opacity(0.15))
                    .frame(width: 36, height: 36)

                Image(systemName: event.eventType.iconName)
                    .font(.system(size: 14))
                    .foregroundColor(event.eventType.iconColor)
            }

            // Content
            VStack(alignment: .leading, spacing: 4) {
                Text(event.displayMessage)
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(event.relativeTime)
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            Spacer()
        }
    }
}

// MARK: - Compact Activity Preview (for album detail)

struct SharedAlbumActivityPreview: View {
    @Environment(\.themePalette) private var palette

    let events: [SharedAlbumActivityEvent]
    let onViewAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(palette.accent)
                Text("Recent Activity")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Button("View All") {
                    onViewAll()
                }
                .font(.subheadline)
                .foregroundColor(palette.accent)
            }

            if events.isEmpty {
                Text("No recent activity")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(events.prefix(3)) { event in
                        HStack(spacing: 8) {
                            Image(systemName: event.eventType.iconName)
                                .font(.caption)
                                .foregroundColor(event.eventType.iconColor)
                                .frame(width: 20)

                            Text(event.displayMessage)
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .lineLimit(1)

                            Spacer()

                            Text(event.relativeTime)
                                .font(.caption2)
                                .foregroundColor(palette.textTertiary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }
}
