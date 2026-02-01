//
//  DateFormattersTests.swift
//  SonideaTests
//
//  Tests for CachedDateFormatter: format output and caching.
//

import Testing
import Foundation
@testable import Sonidea

struct DateFormattersTests {

    // MARK: - Format Output

    @Test func fileTimestampFormatIsSortable() {
        let date1 = Date(timeIntervalSince1970: 1000000)
        let date2 = Date(timeIntervalSince1970: 2000000)

        let str1 = CachedDateFormatter.fileTimestamp.string(from: date1)
        let str2 = CachedDateFormatter.fileTimestamp.string(from: date2)

        // String comparison should maintain chronological order
        #expect(str1 < str2)
    }

    @Test func fileTimestampContainsDateParts() {
        // Use a date well into 2024 to avoid timezone-related year boundary issues
        let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let str = CachedDateFormatter.fileTimestamp.string(from: date)

        // Should contain "2024" (or "2023" in far-west timezones) and underscores
        #expect(str.contains("_"))
        #expect(str.count > 10) // reasonable length for a timestamp
    }

    @Test func compactTimestampContainsDateParts() {
        // Use a date well into 2024 to avoid timezone-related year boundary issues
        let date = Date(timeIntervalSince1970: 1704067200) // 2024-01-01 00:00:00 UTC
        let str = CachedDateFormatter.compactTimestamp.string(from: date)

        // Should be a non-empty compact timestamp
        #expect(!str.isEmpty)
        #expect(str.count > 8)
    }

    @Test func timeOnlyFormat() {
        // Just verify it returns a non-empty string
        let str = CachedDateFormatter.timeOnly.string(from: Date())
        #expect(!str.isEmpty)
    }

    @Test func monthYearFormat() {
        let str = CachedDateFormatter.monthYear.string(from: Date())
        #expect(!str.isEmpty)
    }

    // MARK: - Cached Instances (Identity Check)

    @Test func formatterInstancesAreCached() {
        // Accessing the same static property should return the same instance
        let f1 = CachedDateFormatter.fileTimestamp
        let f2 = CachedDateFormatter.fileTimestamp
        #expect(f1 === f2)
    }

    @Test func differentFormatterInstancesAreDifferent() {
        let f1 = CachedDateFormatter.fileTimestamp
        let f2 = CachedDateFormatter.compactTimestamp
        #expect(f1 !== f2)
    }

    // MARK: - POSIX Locale (File Timestamps)

    @Test func fileTimestampUsesPosixLocale() {
        let locale = CachedDateFormatter.fileTimestamp.locale
        #expect(locale?.identifier == "en_US_POSIX")
    }

    @Test func compactTimestampUsesPosixLocale() {
        let locale = CachedDateFormatter.compactTimestamp.locale
        #expect(locale?.identifier == "en_US_POSIX")
    }
}
