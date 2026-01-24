//
//  FileHasher.swift
//  Sonidea
//
//  Streaming SHA-256 file hashing utility.
//  Uses 64KB chunks to avoid loading entire file into memory.
//

import Foundation
import CryptoKit

// MARK: - File Hasher

actor FileHasher {

    /// Chunk size for streaming hash (64KB)
    private static let chunkSize = 64 * 1024

    /// Compute SHA-256 hash of a file using streaming reads
    /// - Parameter url: File URL to hash
    /// - Returns: Lowercase hex string of the SHA-256 hash
    /// - Throws: FileHasherError if file cannot be read
    static func sha256Hash(of url: URL) async throws -> String {
        return try await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw FileHasherError.fileNotFound(url)
            }

            guard let fileHandle = try? FileHandle(forReadingFrom: url) else {
                throw FileHasherError.cannotOpenFile(url)
            }

            defer {
                try? fileHandle.close()
            }

            var hasher = SHA256()

            while true {
                let chunk = fileHandle.readData(ofLength: chunkSize)
                if chunk.isEmpty {
                    break
                }
                hasher.update(data: chunk)
            }

            let digest = hasher.finalize()
            return digest.hexString
        }.value
    }

    /// Compute SHA-256 hash of Data
    /// - Parameter data: Data to hash
    /// - Returns: Lowercase hex string of the SHA-256 hash
    static func sha256Hash(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.hexString
    }

    /// Verify a file's hash matches an expected value
    /// - Parameters:
    ///   - url: File URL to verify
    ///   - expectedHash: Expected SHA-256 hash (lowercase hex)
    /// - Returns: True if hashes match
    static func verify(url: URL, expectedHash: String) async throws -> Bool {
        let actualHash = try await sha256Hash(of: url)
        return actualHash.lowercased() == expectedHash.lowercased()
    }
}

// MARK: - File Hasher Error

enum FileHasherError: LocalizedError {
    case fileNotFound(URL)
    case cannotOpenFile(URL)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.lastPathComponent)"
        case .cannotOpenFile(let url):
            return "Cannot open file: \(url.lastPathComponent)"
        }
    }
}

// MARK: - Digest Extension

extension Digest {
    /// Convert digest to lowercase hex string
    nonisolated var hexString: String {
        compactMap { String(format: "%02x", $0) }.joined()
    }
}
