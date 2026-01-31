//
//  CalendarView.swift
//  Sonidea
//
//  In-app calendar for browsing recordings by date.
//  No EventKit/Apple Calendar integration - fully self-contained.
//

import SwiftUI

// MARK: - Calendar View

struct CalendarView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    @Environment(\.dismiss) private var dismiss

    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date?
    @State private var selectedRecording: RecordingItem?

    private let calendar = Calendar.current
    private let daysOfWeek = ["S", "M", "T", "W", "T", "F", "S"]

    // Recordings grouped by day
    private var recordingsByDay: [Date: [RecordingItem]] {
        Dictionary(grouping: appState.activeRecordings) { recording in
            calendar.startOfDay(for: recording.createdAt)
        }
    }

    // Days in the current month that have recordings
    private var daysWithRecordings: Set<Date> {
        Set(recordingsByDay.keys)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background
                    .ignoresSafeArea()

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
            .navigationTitle("Calendar")
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

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            currentMonth = Date()
                            selectedDate = calendar.startOfDay(for: Date())
                        }
                    } label: {
                        Text("Today")
                            .font(.body)
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
        }
    }

    // MARK: - Month Navigation Header

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

    // MARK: - Days of Week Header

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

    // MARK: - Calendar Grid

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

                // Recording indicator
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

    // MARK: - Day Recordings List

    private func dayRecordingsList(for date: Date) -> some View {
        let recordings = recordingsByDay[calendar.startOfDay(for: date)] ?? []

        return VStack(spacing: 0) {
            // Header
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
                            CalendarRecordingRow(recording: recording)
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
                    .padding(.bottom, 100)
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

    // MARK: - Helpers

    private func daysInMonth() -> [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: currentMonth),
              let firstWeek = calendar.dateInterval(of: .weekOfMonth, for: monthInterval.start) else {
            return []
        }

        var days: [Date?] = []

        // Add padding for days before the first of the month
        let startOfMonth = monthInterval.start
        let weekdayOfFirst = calendar.component(.weekday, from: startOfMonth)
        for _ in 1..<weekdayOfFirst {
            days.append(nil)
        }

        // Add all days in the month
        var date = startOfMonth
        while date < monthInterval.end {
            days.append(date)
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? date
        }

        return days
    }
}

// MARK: - Calendar Recording Row

struct CalendarRecordingRow: View {
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

    private var projectContext: (title: String, take: String)? {
        guard let projectId = recording.projectId,
              let project = appState.project(for: projectId) else {
            return nil
        }
        return (project.title, "V\(recording.versionIndex)")
    }

    private var isBestTake: Bool {
        guard let projectId = recording.projectId,
              let project = appState.project(for: projectId) else {
            return false
        }
        return project.bestTakeRecordingId == recording.id
    }

    var body: some View {
        HStack(spacing: 12) {
            // Time
            Text(formattedTime)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 60, alignment: .leading)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(recording.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)

                    if isBestTake {
                        HStack(spacing: 2) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
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

                    if let context = projectContext {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(palette.textTertiary)

                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                            Text("\(context.title) · \(context.take)")
                                .lineLimit(1)
                        }
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    }

                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(palette.background)
    }
}

// MARK: - Preview

#Preview {
    CalendarView()
        .environment(AppState())
}
