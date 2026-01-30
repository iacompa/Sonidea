//
//  FileHasherTests.swift
//  SonideaTests
//
//  Tests for FileHasher: SHA-256 hashing of data and files.
//

import Testing
import Foundation
@testable import Sonidea

struct FileHasherTests {

    // MARK: - Data Hashing

    @Test func sha256OfKnownData() {
        let data = "hello world".data(using: .utf8)!
        let hash = FileHasher.sha256Hash(of: data)

        // Known SHA-256 of "hello world"
        #expect(hash == "b94d27b9934d3e08a52e52d7da7dabfac484efe37a5380ee9088f7ace2efcde9")
    }

    @Test func sha256OfEmptyData() {
        let data = Data()
        let hash = FileHasher.sha256Hash(of: data)

        // Known SHA-256 of empty data
        #expect(hash == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    @Test func sha256DifferentDataDifferentHashes() {
        let data1 = "hello".data(using: .utf8)!
        let data2 = "world".data(using: .utf8)!

        let hash1 = FileHasher.sha256Hash(of: data1)
        let hash2 = FileHasher.sha256Hash(of: data2)

        #expect(hash1 != hash2)
    }

    @Test func sha256SameDataSameHash() {
        let data = "deterministic".data(using: .utf8)!
        let hash1 = FileHasher.sha256Hash(of: data)
        let hash2 = FileHasher.sha256Hash(of: data)

        #expect(hash1 == hash2)
    }

    @Test func sha256ReturnsLowercaseHex() {
        let data = "test".data(using: .utf8)!
        let hash = FileHasher.sha256Hash(of: data)

        // Should be all lowercase hex characters
        let validChars = CharacterSet(charactersIn: "0123456789abcdef")
        #expect(hash.unicodeScalars.allSatisfy { validChars.contains($0) })
        #expect(hash.count == 64) // SHA-256 = 32 bytes = 64 hex chars
    }

    // MARK: - File Hashing

    @Test func sha256OfNonexistentFile() async throws {
        let url = URL(fileURLWithPath: "/nonexistent/file.m4a")

        do {
            _ = try await FileHasher.sha256Hash(of: url)
            #expect(Bool(false), "Should have thrown")
        } catch {
            // Expected - file not found
            #expect(error is FileHasherError)
        }
    }

    // MARK: - Verification

    @Test func verifyMatchingHash() async throws {
        // Create a temporary file
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-hash-verify.txt")
        let data = "verify me".data(using: .utf8)!
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let hash = try await FileHasher.sha256Hash(of: tempURL)
        let verified = try await FileHasher.verify(url: tempURL, expectedHash: hash)
        #expect(verified)
    }

    @Test func verifyMismatchedHash() async throws {
        let tempURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test-hash-mismatch.txt")
        let data = "verify me".data(using: .utf8)!
        try data.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let verified = try await FileHasher.verify(url: tempURL, expectedHash: "0000000000000000000000000000000000000000000000000000000000000000")
        #expect(!verified)
    }
}
