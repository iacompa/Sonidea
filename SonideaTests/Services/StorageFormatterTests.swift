//
//  StorageFormatterTests.swift
//  SonideaTests
//
//  Tests for StorageFormatter: byte formatting and edge cases.
//

import Testing
import Foundation
@testable import Sonidea

struct StorageFormatterTests {

    @Test func formatZeroBytes() {
        #expect(StorageFormatter.format(0) == "0 B")
    }

    @Test func formatNegativeBytes() {
        #expect(StorageFormatter.format(-1) == "0 B")
    }

    @Test func formatSmallBytes() {
        #expect(StorageFormatter.format(500) == "500 B")
    }

    @Test func formatOneKB() {
        #expect(StorageFormatter.format(1024) == "1.00 KB")
    }

    @Test func formatLargerKB() {
        // 10240 bytes = 10.0 KB
        #expect(StorageFormatter.format(10240) == "10.0 KB")
    }

    @Test func formatOneMB() {
        let oneMB: Int64 = 1024 * 1024
        #expect(StorageFormatter.format(oneMB) == "1.00 MB")
    }

    @Test func formatLargeMB() {
        let largeMB: Int64 = 100 * 1024 * 1024
        #expect(StorageFormatter.format(largeMB) == "100 MB")
    }

    @Test func formatOneGB() {
        let oneGB: Int64 = 1024 * 1024 * 1024
        #expect(StorageFormatter.format(oneGB) == "1.00 GB")
    }

    @Test func formatLargeValue() {
        let tenGB: Int64 = 10 * 1024 * 1024 * 1024
        #expect(StorageFormatter.format(tenGB) == "10.0 GB")
    }

    @Test func formattedFileSizeNonexistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/file.m4a")
        #expect(StorageFormatter.formattedFileSize(at: url) == "\u{2014}")
    }

    @Test func fileSizeNonexistentFile() {
        let url = URL(fileURLWithPath: "/nonexistent/path/file.m4a")
        #expect(StorageFormatter.fileSize(at: url) == nil)
    }
}
