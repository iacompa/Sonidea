//
//  TimelineItem.swift
//  Sonidea
//
//  Timeline item model for Journal view - represents recordings and project takes
//  in a unified chronological feed.
//

import Foundation

// MARK: - Timeline Item Type

enum TimelineItemType: Equatable {
    case recording
    case projectTake(projectTitle: String, takeLabel: String)
}

// MARK: - Timeline Item

struct TimelineItem: Identifiable, Equatable {
    let id: UUID
    let type: TimelineItemType
    let title: String
    let timestamp: Date
    let duration: TimeInterval
    let locationLabel: String?
    let tagIDs: [UUID]
    let albumID: UUID?
    let isBestTake: Bool
    let recordingID: UUID
    let projectID: UUID?

    // For navigation
    var isProjectTake: Bool {
        if case .projectTake = type { return true }
        return false
    }

    var projectTitle: String? {
        if case .projectTake(let title, _) = type {
            return title
        }
        return nil
    }

    var takeLabel: String? {
        if case .projectTake(_, let label) = type {
            return label
        }
        return nil
    }
}

// MARK: - Timeline Group (by day)

struct TimelineGroup: Identifiable {
    let id: Date // startOfDay
    let date: Date
    let items: [TimelineItem]

    var displayTitle: String {
        let calendar = Calendar.current
        let now = Date()

        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            // This week - show day name
            return CachedDateFormatter.weekdayName.string(from: date)
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            // This year - show month and day
            return CachedDateFormatter.monthDay.string(from: date)
        } else {
            // Different year - show full date
            return CachedDateFormatter.monthDayYear.string(from: date)
        }
    }
}

// MARK: - Timeline Builder

struct TimelineBuilder {

    /// Build timeline items from recordings and projects
    static func buildTimeline(
        recordings: [RecordingItem],
        projects: [Project]
    ) -> [TimelineItem] {
        var items: [TimelineItem] = []

        // Create a lookup for projects by ID
        let projectLookup = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0) })

        for recording in recordings {
            // Skip trashed recordings
            guard !recording.isTrashed else { continue }

            let type: TimelineItemType
            let isBestTake: Bool

            if let projectId = recording.projectId,
               let project = projectLookup[projectId] {
                // This is a project take
                let takeLabel = "V\(recording.versionIndex)"
                type = .projectTake(projectTitle: project.title, takeLabel: takeLabel)
                isBestTake = project.bestTakeRecordingId == recording.id
            } else {
                // Standalone recording
                type = .recording
                isBestTake = false
            }

            let item = TimelineItem(
                id: recording.id,
                type: type,
                title: recording.title,
                timestamp: recording.createdAt,
                duration: recording.duration,
                locationLabel: recording.locationLabel.isEmpty ? nil : recording.locationLabel,
                tagIDs: recording.tagIDs,
                albumID: recording.albumID,
                isBestTake: isBestTake,
                recordingID: recording.id,
                projectID: recording.projectId
            )

            items.append(item)
        }

        // Sort by timestamp descending (newest first)
        items.sort { $0.timestamp > $1.timestamp }

        return items
    }

    /// Group timeline items by day
    static func groupByDay(_ items: [TimelineItem]) -> [TimelineGroup] {
        let calendar = Calendar.current

        // Group items by start of day
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.timestamp)
        }

        // Convert to TimelineGroup array and sort by date descending
        let groups = grouped.map { (date, items) in
            TimelineGroup(
                id: date,
                date: date,
                items: items.sorted { $0.timestamp > $1.timestamp }
            )
        }

        return groups.sorted { $0.date > $1.date }
    }
}
