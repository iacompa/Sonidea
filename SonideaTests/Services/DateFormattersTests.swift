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
        let date = Date(timeIntervalSince1970: 0)
        let str = CachedDateFormatter.fileTimestamp.string(from: date)

        // Should contain "1970" and underscores
        #expect(str.contains("1970"))
        #expect(str.contains("_"))
    }

    @Test func compactTimestampContainsDateParts() {
        let date = Date(timeIntervalSince1970: 0)
        let str = CachedDateFormatter.compactTimestamp.string(from: date)

        // Should contain "1970" and be compact (no dashes)
        #expect(str.contains("1970"))
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
