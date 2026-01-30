//
//  DateFormatters.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/30/26.
//

import Foundation

/// Cached DateFormatters to avoid repeated allocation.
/// DateFormatter is expensive to create (~50µs each); caching avoids
/// thousands of allocations during list scrolling and date display.
enum CachedDateFormatter {

    // MARK: - Display Formats

    /// "h:mm a" — e.g., "3:45 PM"
    static let timeOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "h:mm a"
        return f
    }()

    /// "MMMM yyyy" — e.g., "January 2026"
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return f
    }()

    /// "EEEE" — e.g., "Monday"
    static let weekdayName: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE"
        return f
    }()

    /// "MMMM d" — e.g., "January 30"
    static let monthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d"
        return f
    }()

    /// "MMMM d, yyyy" — e.g., "January 30, 2026"
    static let monthDayYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMMM d, yyyy"
        return f
    }()

    /// "MMM d" — e.g., "Jan 30"
    static let shortMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f
    }()

    /// "EEEE, MMMM d" — e.g., "Thursday, January 30"
    static let weekdayMonthDay: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMMM d"
        return f
    }()

    /// "EEE d MMM" — e.g., "Thu 30 Jan"
    static let gridDate: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    /// Medium date, short time — e.g., "Jan 30, 2026 at 3:45 PM"
    static let mediumDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Medium date, no time — e.g., "Jan 30, 2026"
    static let mediumDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    // MARK: - File Naming Formats

    /// "yyyy-MM-dd_HH-mm-ss" — for recording filenames
    static let fileTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// "yyyyMMdd_HHmmss" — compact file naming
    static let compactTimestamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd_HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
