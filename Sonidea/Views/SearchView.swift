//
// SearchView.swift
// Sonidea
//

import SwiftUI

struct MapPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("Map")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Recording locations will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Search Sheet View
struct SearchSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var searchMode: SearchMode = .default
    @State private var searchScope: SearchScope = .recordings
    @State private var searchQuery = ""
    @State private var debouncedQuery = ""
    @State private var searchTask: Task<Void, Never>?
    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?
    @State private var computedStorageUsed: String = "…"
    @State private var selectedAlbum: Album?
    @State private var selectedProject: Project?

    private var recordingResults: [RecordingItem] {
        appState.searchRecordings(query: debouncedQuery, filterTagIDs: selectedTagIDs)
    }

    private var albumResults: [Album] {
        appState.searchAlbums(query: debouncedQuery)
    }

    private var projectResults: [Project] {
        appState.searchProjects(query: debouncedQuery)
    }

    private var searchPlaceholder: String {
        switch searchScope {
        case .recordings: return "Search recordings..."
        case .projects: return "Search projects..."
        case .albums: return "Search albums..."
        }
    }

    // MARK: - Stats

    private var totalRecordingCount: Int {
        appState.activeRecordings.count
    }

    private var totalStorageUsed: String {
        computedStorageUsed
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                switch searchMode {
                case .default:
                    defaultSearchContent
                case .calendar:
                    calendarSearchContent
                case .timeline:
                    timelineSearchContent
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 4) {
                        // Calendar mode button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchMode = searchMode == .calendar ? .default : .calendar
                            }
                        } label: {
                            Image(systemName: "calendar")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(searchMode == .calendar ? palette.accent : palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(searchMode == .calendar ? palette.accent.opacity(0.15) : Color.clear)
                                .clipShape(Circle())
                        }

                        // Timeline mode button
                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                searchMode = searchMode == .timeline ? .default : .timeline
                            }
                        } label: {
                            Image(systemName: "clock")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(searchMode == .timeline ? palette.accent : palette.textSecondary)
                                .frame(width: 36, height: 36)
                                .background(searchMode == .timeline ? palette.accent.opacity(0.15) : Color.clear)
                                .clipShape(Circle())
                        }
                    }
                }

                ToolbarItem(placement: .principal) {
                    // Title - tapping it returns to default search
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            searchMode = .default
                        }
                    } label: {
                        Text("Search")
                            .font(.headline)
                            .foregroundStyle(searchMode == .default ? palette.accent : palette.textPrimary)
                    }
                    .buttonStyle(.plain)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.accent)
                }
            }
            .iPadSheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(item: $selectedAlbum) { album in
                if album.isShared {
                    SharedAlbumDetailView(album: album)
                } else {
                    AlbumDetailSheet(album: album)
                }
            }
            .sheet(item: $selectedProject) { project in
                ProjectDetailView(project: project)
            }
            .onChange(of: searchScope) { _, _ in
                if searchScope != .recordings { selectedTagIDs.removeAll() }
            }
            .onChange(of: searchQuery) { _, newValue in
                searchTask?.cancel()
                searchTask = Task {
                    try? await Task.sleep(nanoseconds: 300_000_000) // 300ms debounce
                    guard !Task.isCancelled else { return }
                    debouncedQuery = newValue
                }
            }
            .onChange(of: selectedTagIDs) { _, _ in
                // Tag filter changes should apply immediately (no debounce)
                debouncedQuery = searchQuery
            }
        }
        .task {
            let recordings = appState.activeRecordings
            let result = await Task.detached {
                let totalBytes = recordings.reduce(into: Int64(0)) { result, recording in
                    let url = recording.fileURL
                    if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                       let fileSize = attrs[.size] as? Int64 {
                        result += fileSize
                    }
                }
                let formatter = ByteCountFormatter()
                formatter.allowedUnits = [.useKB, .useMB, .useGB]
                formatter.countStyle = .file
                return formatter.string(fromByteCount: totalBytes)
            }.value
            computedStorageUsed = result
        }
    }

    // MARK: - Default Search Content

    private var defaultSearchContent: some View {
        VStack(spacing: 12) {
            // Stats header
            HStack(spacing: 16) {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.caption)
                    Text("\(totalRecordingCount) recordings")
                }

                HStack(spacing: 4) {
                    Image(systemName: "internaldrive")
                        .font(.caption)
                    Text(totalStorageUsed)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Picker("Search Scope", selection: $searchScope) {
                ForEach(SearchScope.allCases, id: \.self) { scope in
                    Text(scope.displayName).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(palette.textSecondary)
                TextField(searchPlaceholder, text: $searchQuery)
                    .foregroundColor(palette.textPrimary)
            }
            .padding(12)
            .background(palette.inputBackground)
            .cornerRadius(10)
            .padding(.horizontal)

            if searchScope == .recordings && !appState.tags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(appState.tags) { tag in
                            TagFilterChip(tag: tag, isSelected: selectedTagIDs.contains(tag.id)) {
                                if selectedTagIDs.contains(tag.id) {
                                    selectedTagIDs.remove(tag.id)
                                } else {
                                    selectedTagIDs.insert(tag.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }

            switch searchScope {
            case .recordings:
                recordingsResultsView
            case .projects:
                projectsResultsView
            case .albums:
                albumsResultsView
            }
        }
        .padding(.top)
    }

    // MARK: - Calendar Search Content

    private var calendarSearchContent: some View {
        SearchCalendarView(searchQuery: debouncedQuery, selectedRecording: $selectedRecording)
    }

    // MARK: - Timeline Search Content

    private var timelineSearchContent: some View {
        SearchTimelineView(searchQuery: debouncedQuery, selectedRecording: $selectedRecording)
    }

    // MARK: - Recordings Results

    @ViewBuilder
    private var recordingsResultsView: some View {
        if recordingResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty && selectedTagIDs.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your recordings")
                        .font(.headline)
                    Text("Search by title, notes, location, tags, or album")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No recordings found")
                        .font(.headline)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(recordingResults) { recording in
                    SearchResultRow(recording: recording)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedRecording = recording }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Albums Results

    @ViewBuilder
    private var albumsResultsView: some View {
        if albumResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your albums")
                        .font(.headline)
                    Text("Find albums by name")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No albums found")
                        .font(.headline)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(albumResults) { album in
                    AlbumSearchRow(album: album)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedAlbum = album }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Projects Results

    @ViewBuilder
    private var projectsResultsView: some View {
        if projectResults.isEmpty {
            Spacer()
            if searchQuery.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("Search your projects")
                        .font(.headline)
                    Text("Find projects by name or notes")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder.badge.questionmark")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No projects found")
                        .font(.headline)
                }
            }
            Spacer()
        } else {
            List {
                ForEach(projectResults) { project in
                    ProjectSearchRow(project: project)
                        .contentShape(Rectangle())
                        .onTapGesture { selectedProject = project }
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }
}

// MARK: - Search Calendar View (Embedded)

struct SearchCalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    let searchQuery: String
    @Binding var selectedRecording: RecordingItem?

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date?

    private let calendar = Calendar.current
    private var daysOfWeek: [String] {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let firstWeekday = Calendar.current.firstWeekday - 1
        return Array(symbols[firstWeekday...]) + Array(symbols[..<firstWeekday])
    }

    private var recordingsByDay: [Date: [RecordingItem]] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let filtered = SearchService.searchRecordings(
            query: trimmed,
            recordings: appState.activeRecordings,
            tags: appState.tags,
            albums: appState.albums,
            projects: appState.projects
        )
        return Dictionary(grouping: filtered) { recording in
            calendar.startOfDay(for: recording.createdAt)
        }
    }

    private var daysWithRecordings: Set<Date> {
        Set(recordingsByDay.keys)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Month navigation
            monthNavigationHeader

            // Days of week header
            daysOfWeekHeader

            // Calendar grid
            calendarGrid

            Divider()
                .padding(.top, 8)

            // Selected day recordings
            if let date = selectedDate {
                dayRecordingsList(for: date)
            } else {
                selectDayPrompt
            }
        }
    }

    private var monthNavigationHeader: some View {
        HStack {
            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
            }

            Spacer()

            Text(monthYearString)
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            Spacer()

            Button {
                withAnimation {
                    currentMonth = calendar.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .frame(width: 44, height: 44)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
    }

    private var monthYearString: String {
        CachedDateFormatter.monthYear.string(from: currentMonth)
    }

    private var daysOfWeekHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(daysOfWeek.enumerated()), id: \.offset) { _, day in
                Text(day)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var calendarGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(days, id: \.self) { date in
                if let date = date {
                    calendarDayCell(for: date)
                } else {
                    Color.clear
                        .frame(height: 44)
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private func calendarDayCell(for date: Date) -> some View {
        let isSelected = selectedDate != nil && calendar.isDate(date, inSameDayAs: selectedDate!)
        let isToday = calendar.isDateInToday(date)
        let hasRecordings = daysWithRecordings.contains(calendar.startOfDay(for: date))
        let recordingCount = recordingsByDay[calendar.startOfDay(for: date)]?.count ?? 0

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedDate = calendar.startOfDay(for: date)
            }
        } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: date))")
                    .font(.body.weight(isToday ? .bold : .regular))
                    .foregroundStyle(
                        isSelected ? Color.white :
                        isToday ? palette.accent :
                        palette.textPrimary
                    )

                if hasRecordings {
                    if recordingCount > 1 {
                        Text("\(recordingCount)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : palette.accent)
                    } else {
                        Circle()
                            .fill(isSelected ? Color.white.opacity(0.9) : palette.accent)
                            .frame(width: 5, height: 5)
                    }
                } else {
                    Color.clear
                        .frame(width: 5, height: 5)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                Group {
                    if isSelected {
                        Circle()
                            .fill(palette.accent)
                    } else if isToday {
                        Circle()
                            .strokeBorder(palette.accent, lineWidth: 1)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }

    private func dayRecordingsList(for date: Date) -> some View {
        let recordings = recordingsByDay[calendar.startOfDay(for: date)] ?? []

        return VStack(spacing: 0) {
            HStack {
                Text(dayHeaderString(for: date))
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Spacer()

                if !recordings.isEmpty {
                    Text("\(recordings.count) recording\(recordings.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            if recordings.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.title)
                        .foregroundStyle(palette.textTertiary)

                    Text("No recordings")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 40)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(recordings.sorted(by: { $0.createdAt > $1.createdAt })) { recording in
                            SearchCalendarRecordingRow(recording: recording)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    selectedRecording = recording
                                }

                            if recording.id != recordings.last?.id {
                                Divider()
                                    .padding(.leading, 16)
                            }
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
    }

    private func dayHeaderString(for date: Date) -> String {
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            return CachedDateFormatter.weekdayMonthDay.string(from: date)
        }
    }

    private var selectDayPrompt: some View {
        VStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.title)
                .foregroundStyle(palette.textTertiary)

            Text("Select a day to view recordings")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        var days: [Date?] = []

        let startOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: startOfMonth)
        for _ in 1..<weekdayOfFirst {
            days.append(nil)
        }

        var date = startOfMonth
        while date < monthInterval.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return days
    }
}

// MARK: - Search Calendar Recording Row

struct SearchCalendarRecordingRow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem

    private var formattedTime: String {
        CachedDateFormatter.timeOnly.string(from: recording.createdAt)
    }

    private var formattedDuration: String {
        let minutes = Int(recording.duration) / 60
        let seconds = Int(recording.duration) % 60
        if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        }
        return "\(seconds)s"
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(formattedTime)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 60, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(recording.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }

                Label(formattedDuration, systemImage: "waveform")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.background)
    }
}

// MARK: - Search Timeline View (Embedded)

struct SearchTimelineView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    let searchQuery: String
    @Binding var selectedRecording: RecordingItem?

    private var timelineGroups: [TimelineGroup] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespaces)
        let filtered = SearchService.searchRecordings(
            query: trimmed,
            recordings: appState.activeRecordings,
            tags: appState.tags,
            albums: appState.albums,
            projects: appState.projects
        )
        let items = TimelineBuilder.buildTimeline(
            recordings: filtered,
            projects: appState.projects
        )
        return TimelineBuilder.groupByDay(items)
    }

    var body: some View {
        if timelineGroups.isEmpty {
            VStack(spacing: 16) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 48))
                    .foregroundStyle(palette.textTertiary)

                Text("No Recordings Yet")
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)

                Text("Your recording timeline will appear here")
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(timelineGroups) { group in
                        Section {
                            ForEach(group.items) { item in
                                SearchTimelineRowView(item: item, tags: tagsForItem(item))
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
                .padding(.bottom, 40)
            }
            .scrollContentBackground(.hidden)
        }
    }

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

    private func tagsForItem(_ item: TimelineItem) -> [Tag] {
        item.tagIDs.compactMap { appState.tag(for: $0) }
    }

    private func handleItemTap(_ item: TimelineItem) {
        if let recording = appState.recording(for: item.recordingID) {
            selectedRecording = recording
        }
    }
}

// MARK: - Search Timeline Row View

struct SearchTimelineRowView: View {
    @Environment(\.themePalette) private var palette

    let item: TimelineItem
    let tags: [Tag]

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
            VStack(alignment: .trailing) {
                Text(formattedTime)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(width: 50, alignment: .trailing)

            VStack(spacing: 4) {
                Circle()
                    .fill(item.isBestTake ? Color.yellow : palette.accent)
                    .frame(width: 10, height: 10)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    if item.isBestTake {
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

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textTertiary)
                }

                HStack(spacing: 8) {
                    Label(formattedDuration, systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)

                    if case .projectTake(let projectTitle, let takeLabel) = item.type {
                        Text("\u{2022}")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)

                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text("\(projectTitle) \u{00B7} \(takeLabel)")
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()
                }

                if !tags.isEmpty {
                    HStack(spacing: 6) {
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
}

// MARK: - Project Search Row

struct ProjectSearchRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.themePalette) var palette
    let project: Project

    private var versionCount: Int {
        appState.recordingCount(in: project)
    }

    private var stats: ProjectStats {
        appState.stats(for: project)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(palette.accent.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundColor(palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(project.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    if project.pinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundColor(palette.textSecondary)
                    }

                    if stats.hasBestTake {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundColor(.yellow)
                    }
                }

                HStack(spacing: 6) {
                    Text("\(versionCount) version\(versionCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    Text("•")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    Text(stats.formattedTotalDuration)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Album Search Row

struct AlbumSearchRow: View {
    @Environment(AppState.self) var appState
    let album: Album

    private var recordingCount: Int {
        appState.recordingCount(in: album)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Image(systemName: album.isShared ? "person.2.fill" : "square.stack.fill")
                    .font(.system(size: 20))
                    .foregroundColor(album.isShared ? .sharedAlbumGold : .primary)
                    .frame(width: 36, height: 36)
                    .background(album.isShared ? Color.sharedAlbumGold.opacity(0.15) : Color(.systemGray4))
                    .cornerRadius(6)

                // Glow effect for shared albums
                if album.isShared {
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.sharedAlbumGold.opacity(0.5), lineWidth: 2)
                        .frame(width: 36, height: 36)
                        .shadow(color: .sharedAlbumGold.opacity(0.3), radius: 4, x: 0, y: 0)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    AlbumTitleView(album: album, font: .body.weight(.medium), showBadge: true)
                        .lineLimit(1)
                }

                HStack(spacing: 4) {
                    Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if album.isShared {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("\(album.participantCount) participant\(album.participantCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.sharedAlbumGold)
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(album.isShared ? .sharedAlbumGold.opacity(0.7) : .secondary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Album Detail Sheet

struct AlbumDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let album: Album

    @State private var selectedTagIDs: Set<UUID> = []
    @State private var selectedRecording: RecordingItem?
    @State private var showLeaveSheet = false
    @State private var showManageSheet = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private var albumRecordings: [RecordingItem] {
        let recordings = appState.recordings(in: album)
        if selectedTagIDs.isEmpty { return recordings }
        return recordings.filter { !selectedTagIDs.isDisjoint(with: Set($0.tagIDs)) }
    }

    /// Reactive lookup so the navigation title updates after rename
    private var currentAlbum: Album {
        appState.albums.first(where: { $0.id == album.id }) ?? album
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                VStack(spacing: 0) {
                    // Shared album banner at top
                    if album.isShared {
                        SharedAlbumBanner(album: album)
                    }

                    VStack(spacing: 16) {
                        if !appState.tags.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(appState.tags) { tag in
                                        TagFilterChip(tag: tag, isSelected: selectedTagIDs.contains(tag.id)) {
                                            if selectedTagIDs.contains(tag.id) {
                                                selectedTagIDs.remove(tag.id)
                                            } else {
                                                selectedTagIDs.insert(tag.id)
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }

                        if albumRecordings.isEmpty {
                            Spacer()
                            VStack(spacing: 12) {
                                Image(systemName: album.isShared ? "person.2.wave.2" : "waveform.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary)
                                Text(selectedTagIDs.isEmpty ? (album.isShared ? "No recordings in this shared album" : "No recordings in this album") : "No recordings match selected tags")
                                    .font(.headline)
                                if album.isShared && selectedTagIDs.isEmpty {
                                    Text("Add recordings to share with collaborators")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                        } else {
                            List {
                                ForEach(albumRecordings) { recording in
                                    SearchResultRow(recording: recording)
                                        .contentShape(Rectangle())
                                        .onTapGesture { selectedRecording = recording }
                                        .listRowBackground(Color.clear)
                                }
                            }
                            .listStyle(.plain)
                            .scrollContentBackground(.hidden)
                        }
                    }
                    .padding(.top)
                }
            }
            .navigationTitle(currentAlbum.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    HStack(spacing: 12) {
                        if album.isShared {
                            Menu {
                                if album.isOwner {
                                    Button {
                                        showManageSheet = true
                                    } label: {
                                        Label("Manage Sharing", systemImage: "person.badge.plus")
                                    }
                                } else {
                                    Button(role: .destructive) {
                                        showLeaveSheet = true
                                    } label: {
                                        Label("Leave Album", systemImage: "person.badge.minus")
                                    }
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                            }
                        }

                        if album.canRename {
                            Button {
                                renameText = currentAlbum.name
                                showRenameAlert = true
                            } label: {
                                Image(systemName: "pencil")
                            }
                        }
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Rename Album", isPresented: $showRenameAlert) {
                TextField("Album name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, trimmed != currentAlbum.name else { return }
                    if appState.renameAlbum(currentAlbum, to: trimmed) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } message: {
                Text("Enter a new name for this album.")
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
            .sheet(isPresented: $showLeaveSheet) {
                LeaveSharedAlbumSheet(album: album)
            }
        }
    }
}

// MARK: - Tag Filter Chip

struct TagFilterChip: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : tag.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tag.color : Color.clear)
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tag.color, lineWidth: 1)
                )
        }
    }
}

// MARK: - Search Result Row

struct SearchResultRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme
    let recording: RecordingItem

    private var recordingTags: [Tag] { appState.tags(for: recording.tagIDs) }
    private var album: Album? { appState.album(for: recording.albumID) }

    var body: some View {
        HStack(spacing: 12) {
            RecordingIconTile(recording: recording, colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(recording.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if let album = album {
                        Text("•").font(.caption).foregroundColor(.secondary)
                        if album.isShared {
                            HStack(spacing: 3) {
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 8))
                                Text(album.name)
                            }
                            .font(.caption)
                            .foregroundColor(.sharedAlbumGold)
                            .lineLimit(1)
                        } else {
                            Text(album.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                if !recordingTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recordingTags.prefix(3)) { tag in
                            TagChipSmall(tag: tag)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 6)
    }
}
