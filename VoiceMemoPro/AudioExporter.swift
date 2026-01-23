//
//  AudioExporter.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation

enum ExportScope: Equatable {
    case all
    case album(Album)
}

struct ExportManifestItem: Codable {
    let id: String
    let title: String
    let createdAt: String
    let duration: Double
    let albumName: String?
    let tagNames: [String]
    let location: String
    let transcriptSnippet: String
    let filename: String
}

struct ExportManifest: Codable {
    let exportDate: String
    let recordingCount: Int
    let recordings: [ExportManifestItem]
}

@MainActor
final class AudioExporter {
    static let shared = AudioExporter()

    private let tempDirectory: URL
    private let wavCacheDirectory: URL
    private let shareDirectory: URL

    private init() {
        let temp = FileManager.default.temporaryDirectory
        tempDirectory = temp.appendingPathComponent("VoiceMemoProExport", isDirectory: true)
        wavCacheDirectory = temp.appendingPathComponent("VoiceMemoProWAVCache", isDirectory: true)
        shareDirectory = temp.appendingPathComponent("VoiceMemoProShare", isDirectory: true)

        // Create directories if needed
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: wavCacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Safe Filename Generation

    /// Generates a safe WAV filename from a recording's title
    /// - Parameters:
    ///   - recording: The recording to generate a filename for
    ///   - existingNames: Set of already-used filenames (without extension) to avoid collisions
    /// - Returns: A safe filename with .wav extension
    func safeWAVFileName(for recording: RecordingItem, existingNames: Set<String> = []) -> String {
        let baseName = sanitizeFilename(recording.title)

        // If base name is unique, use it directly
        if !existingNames.contains(baseName) {
            return "\(baseName).wav"
        }

        // Otherwise, append a counter to make it unique
        var counter = 2
        var uniqueName = "\(baseName) (\(counter))"
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(baseName) (\(counter))"
        }

        return "\(uniqueName).wav"
    }

    /// Sanitizes a string for use as a filename
    /// - Parameter name: The original name (e.g., recording title)
    /// - Returns: A filesystem-safe version of the name
    private func sanitizeFilename(_ name: String) -> String {
        var sanitized = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Fallback if empty
        if sanitized.isEmpty {
            return "Recording"
        }

        // Replace illegal filename characters with dash
        // Illegal: / \ : * ? " < > | and newlines
        let illegalCharacters = CharacterSet(charactersIn: "/\\:*?\"<>|\r\n")
        sanitized = sanitized.components(separatedBy: illegalCharacters).joined(separator: "-")

        // Collapse repeated spaces and dashes
        while sanitized.contains("  ") {
            sanitized = sanitized.replacingOccurrences(of: "  ", with: " ")
        }
        while sanitized.contains("--") {
            sanitized = sanitized.replacingOccurrences(of: "--", with: "-")
        }

        // Trim leading/trailing dashes and spaces
        sanitized = sanitized.trimmingCharacters(in: CharacterSet(charactersIn: "- "))

        // Limit length to 80 characters to avoid filesystem issues
        if sanitized.count > 80 {
            sanitized = String(sanitized.prefix(80)).trimmingCharacters(in: CharacterSet(charactersIn: "- "))
        }

        // Final fallback if somehow empty after sanitization
        if sanitized.isEmpty {
            return "Recording"
        }

        return sanitized
    }

    // MARK: - Single Recording WAV Export

    func exportToWAV(recording: RecordingItem) async throws -> URL {
        // Check cache first (using UUID for internal caching)
        let cachedURL = wavCacheDirectory.appendingPathComponent("\(recording.id.uuidString).wav")
        if !FileManager.default.fileExists(atPath: cachedURL.path) {
            // Convert to WAV and cache
            _ = try await convertToWAV(sourceURL: recording.fileURL, outputURL: cachedURL)
        }

        // Clean up old share files
        cleanShareDirectory()

        // Create a properly named file for sharing
        let shareFilename = safeWAVFileName(for: recording)
        let shareURL = shareDirectory.appendingPathComponent(shareFilename)

        // Remove existing share file if present
        try? FileManager.default.removeItem(at: shareURL)

        // Create a hard link to avoid duplicating the file data
        // If hard link fails (e.g., different volumes), fall back to copy
        do {
            try FileManager.default.linkItem(at: cachedURL, to: shareURL)
        } catch {
            try FileManager.default.copyItem(at: cachedURL, to: shareURL)
        }

        return shareURL
    }

    // MARK: - Bulk Export to ZIP

    func exportRecordings(
        _ recordings: [RecordingItem],
        scope: ExportScope,
        albumLookup: (UUID?) -> Album?,
        tagsLookup: ([UUID]) -> [Tag]
    ) async throws -> URL {
        // Clean up previous exports
        cleanTempDirectory()

        let exportFolder = tempDirectory.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        var manifestItems: [ExportManifestItem] = []
        let dateFormatter = ISO8601DateFormatter()

        // Track used filenames per folder to ensure uniqueness
        var usedNamesByFolder: [String: Set<String>] = [:]

        for recording in recordings {
            let album = albumLookup(recording.albumID)
            let tags = tagsLookup(recording.tagIDs)

            // Determine folder structure
            let folderName: String
            switch scope {
            case .all:
                if let album = album {
                    folderName = "Albums/\(sanitizeFilename(album.name))"
                } else {
                    folderName = "Unsorted"
                }
            case .album:
                folderName = ""
            }

            let folder: URL
            if folderName.isEmpty {
                folder = exportFolder
            } else {
                folder = exportFolder.appendingPathComponent(folderName, isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            }

            // Get or create the set of used names for this folder
            var usedNames = usedNamesByFolder[folderName] ?? []

            // Generate unique filename
            let wavFilename = safeWAVFileName(for: recording, existingNames: usedNames)

            // Track this name (without extension) as used
            let nameWithoutExtension = String(wavFilename.dropLast(4)) // Remove ".wav"
            usedNames.insert(nameWithoutExtension)
            usedNamesByFolder[folderName] = usedNames

            let wavDestination = folder.appendingPathComponent(wavFilename)

            do {
                _ = try await convertToWAV(sourceURL: recording.fileURL, outputURL: wavDestination)
            } catch {
                // Skip files that fail to convert
                continue
            }

            // Build manifest item
            let relativePath: String
            if folderName.isEmpty {
                relativePath = wavFilename
            } else {
                relativePath = "\(folderName)/\(wavFilename)"
            }

            let transcriptSnippet = String(recording.transcript.prefix(200))

            let item = ExportManifestItem(
                id: recording.id.uuidString,
                title: recording.title,
                createdAt: dateFormatter.string(from: recording.createdAt),
                duration: recording.duration,
                albumName: album?.name,
                tagNames: tags.map { $0.name },
                location: recording.locationLabel,
                transcriptSnippet: transcriptSnippet,
                filename: relativePath
            )
            manifestItems.append(item)
        }

        // Write manifest
        let manifest = ExportManifest(
            exportDate: dateFormatter.string(from: Date()),
            recordingCount: manifestItems.count,
            recordings: manifestItems
        )

        let manifestURL = exportFolder.appendingPathComponent("manifest.json")
        let manifestData = try JSONEncoder().encode(manifest)
        try manifestData.write(to: manifestURL)

        // Create ZIP
        let zipFilename: String
        switch scope {
        case .all:
            zipFilename = "VoiceMemoPro_AllRecordings.zip"
        case .album(let album):
            zipFilename = "VoiceMemoPro_\(sanitizeFilename(album.name)).zip"
        }

        let zipURL = tempDirectory.appendingPathComponent(zipFilename)

        // Remove existing zip if present
        try? FileManager.default.removeItem(at: zipURL)

        // Create ZIP using coordinate write
        try createZIP(from: exportFolder, to: zipURL)

        // Clean up export folder
        try? FileManager.default.removeItem(at: exportFolder)

        return zipURL
    }

    // MARK: - WAV Conversion

    private func convertToWAV(sourceURL: URL, outputURL: URL) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Remove existing output file
                    try? FileManager.default.removeItem(at: outputURL)

                    let asset = AVURLAsset(url: sourceURL)

                    guard let exportSession = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetPassthrough) else {
                        // Fallback: manual conversion
                        try self.manualConvertToWAV(sourceURL: sourceURL, outputURL: outputURL)
                        continuation.resume(returning: outputURL)
                        return
                    }

                    // AVAssetExportSession doesn't support WAV directly, use manual conversion
                    try self.manualConvertToWAV(sourceURL: sourceURL, outputURL: outputURL)
                    continuation.resume(returning: outputURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func manualConvertToWAV(sourceURL: URL, outputURL: URL) throws {
        let inputFile = try AVAudioFile(forReading: sourceURL)
        let format = inputFile.processingFormat
        let frameCount = AVAudioFrameCount(inputFile.length)

        // Create output format (16-bit PCM WAV)
        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: format.sampleRate,
            channels: format.channelCount,
            interleaved: true
        ) else {
            throw NSError(domain: "AudioExporter", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"])
        }

        // Create output file
        let outputFile = try AVAudioFile(
            forWriting: outputURL,
            settings: outputFormat.settings,
            commonFormat: .pcmFormatInt16,
            interleaved: true
        )

        // Read and write in chunks
        let bufferSize: AVAudioFrameCount = 4096
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioExporter", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to create buffer"])
        }

        guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
            throw NSError(domain: "AudioExporter", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"])
        }

        var position: AVAudioFramePosition = 0
        while position < inputFile.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(inputFile.length - position))
            buffer.frameLength = framesToRead

            try inputFile.read(into: buffer)

            guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: framesToRead) else {
                throw NSError(domain: "AudioExporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
            }

            var error: NSError?
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            if status == .error, let error = error {
                throw error
            }

            try outputFile.write(from: outputBuffer)
            position += AVAudioFramePosition(framesToRead)
        }
    }

    // MARK: - ZIP Creation

    private func createZIP(from sourceDirectory: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?

        coordinator.coordinate(readingItemAt: sourceDirectory, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                // Ignore copy errors, the file might already exist
            }
        }

        if let error = coordinatorError {
            throw error
        }

        // Verify ZIP was created
        guard FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw NSError(domain: "AudioExporter", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to create ZIP file"])
        }
    }

    // MARK: - Cleanup Helpers

    private func cleanTempDirectory() {
        let exportFolder = tempDirectory.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.removeItem(at: exportFolder)

        // Remove old ZIP files
        if let contents = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) {
            for url in contents where url.pathExtension == "zip" {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    private func cleanShareDirectory() {
        // Remove all files in share directory (they're just hard links anyway)
        if let contents = try? FileManager.default.contentsOfDirectory(at: shareDirectory, includingPropertiesForKeys: nil) {
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func clearWAVCache() {
        try? FileManager.default.removeItem(at: wavCacheDirectory)
        try? FileManager.default.createDirectory(at: wavCacheDirectory, withIntermediateDirectories: true)
        cleanShareDirectory()
    }
}
