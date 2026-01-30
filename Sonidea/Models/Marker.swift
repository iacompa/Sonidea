//
//  Marker.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/24/26.
//

import Foundation

/// A marker represents a specific point in time within a recording
struct Marker: Identifiable, Codable, Equatable {
    let id: UUID
    var time: TimeInterval
    var label: String?

    init(id: UUID = UUID(), time: TimeInterval, label: String? = nil) {
        self.id = id
        self.time = time
        self.label = label
    }

    /// Adjust marker time by an offset (used after trim/cut operations)
    func adjusted(by offset: TimeInterval) -> Marker {
        Marker(id: id, time: max(0, time + offset), label: label)
    }

    /// Check if marker is within a time range
    func isWithin(start: TimeInterval, end: TimeInterval) -> Bool {
        time >= start && time <= end
    }
}

// MARK: - Marker Array Helpers

extension Array where Element == Marker {
    /// Filter markers to only those within the given range
    func within(start: TimeInterval, end: TimeInterval) -> [Marker] {
        filter { $0.isWithin(start: start, end: end) }
    }

    /// Adjust all markers by subtracting an offset (for trim operations)
    func adjusted(bySubtracting offset: TimeInterval) -> [Marker] {
        map { Marker(id: $0.id, time: Swift.max(0, $0.time - offset), label: $0.label) }
    }

    /// Remove markers outside a duration range and adjust times
    func afterTrim(keepingStart: TimeInterval, keepingEnd: TimeInterval) -> [Marker] {
        filter { $0.time >= keepingStart && $0.time <= keepingEnd }
            .map { Marker(id: $0.id, time: $0.time - keepingStart, label: $0.label) }
    }

    /// Remove markers in a cut range and adjust times for markers after the cut
    func afterCut(removingStart: TimeInterval, removingEnd: TimeInterval) -> [Marker] {
        let cutDuration = removingEnd - removingStart
        return compactMap { marker in
            if marker.time >= removingStart && marker.time <= removingEnd {
                // Marker is in the cut region - remove it
                return nil
            } else if marker.time > removingEnd {
                // Marker is after the cut - shift it back
                return Marker(id: marker.id, time: marker.time - cutDuration, label: marker.label)
            } else {
                // Marker is before the cut - keep as is
                return marker
            }
        }
    }

    /// Remap markers after removing multiple silence ranges
    /// - Parameters:
    ///   - ranges: Array of silence ranges that were removed (sorted by start time)
    ///   - padding: Padding that was applied to each silence cut
    /// - Returns: Markers with adjusted times, removing any that fell within silence regions
    func afterRemovingSilence(ranges: [SilenceRange], padding: TimeInterval) -> [Marker] {
        guard !ranges.isEmpty else { return self }

        return compactMap { marker in
            var adjustedTime = marker.time
            var cumulativeRemoved: TimeInterval = 0

            for silence in ranges {
                // Account for padding on silence boundaries
                let adjustedStart = silence.start + padding
                let adjustedEnd = Swift.max(adjustedStart, silence.end - padding)

                // Skip if padding makes this silence too short to matter
                if adjustedEnd <= adjustedStart {
                    continue
                }

                if marker.time >= adjustedStart && marker.time <= adjustedEnd {
                    // Marker is inside a removed silence region - remove it
                    return nil
                } else if marker.time > adjustedEnd {
                    // Marker is after this silence - accumulate removed duration
                    cumulativeRemoved += (adjustedEnd - adjustedStart)
                }
            }

            // Adjust marker time by total removed duration before it
            adjustedTime = marker.time - cumulativeRemoved
            return Marker(id: marker.id, time: Swift.max(0, adjustedTime), label: marker.label)
        }
    }

    /// Sort markers by time
    var sortedByTime: [Marker] {
        sorted { $0.time < $1.time }
    }
}
