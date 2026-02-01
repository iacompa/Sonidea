//
//  AudioExporter.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import Foundation

enum ExportScope: Equatable {
    case all
    case album(Album)
}

// MARK: - Export Format

enum ExportFormat: String, CaseIterable, Identifiable {
    case original
    case wav
    case m4a
    case alac

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .original: return "Original"
        case .wav: return "WAV"
        case .m4a: return "M4A (AAC)"
        case .alac: return "ALAC"
        }
    }

    var subtitle: String {
        switch self {
        case .original: return "As recorded (smallest file)"
        case .wav: return "16-bit PCM (universal compatibility)"
        case .m4a: return "AAC 256kbps (high quality, compact)"
        case .alac: return "Apple Lossless (lossless, Apple devices)"
        }
    }

    var fileExtension: String {
        switch self {
        case .original: return ""  // sentinel — use recording's actual extension
        case .wav: return "wav"
        case .m4a: return "m4a"
        case .alac: return "m4a"
        }
    }

    var iconName: String {
        switch self {
        case .original: return "doc"
        case .wav: return "waveform"
        case .m4a: return "waveform.path"
        case .alac: return "leaf"
        }
    }
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
        tempDirectory = temp.appendingPathComponent("SonideaExport", isDirectory: true)
        wavCacheDirectory = temp.appendingPathComponent("SonideaWAVCache", isDirectory: true)
        shareDirectory = temp.appendingPathComponent("SonideaShare", isDirectory: true)

        // Create directories if needed
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: wavCacheDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: shareDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Safe Filename Generation

    /// Generates a safe filename for a recording in the given format.
    /// - Parameters:
    ///   - recording: The recording to generate a filename for
    ///   - format: The export format (determines file extension)
    ///   - existingNames: Set of already-used filenames (without extension) to avoid collisions
    /// - Returns: A safe filename with the appropriate extension
    func safeFileName(for recording: RecordingItem, format: ExportFormat, existingNames: Set<String> = []) -> String {
        let baseName = sanitizeFilename(recording.title)
        // For .original, use the recording's actual file extension instead of hardcoded value
        let ext = format == .original ? recording.fileURL.pathExtension : format.fileExtension

        if !existingNames.contains(baseName) {
            return "\(baseName).\(ext)"
        }

        var counter = 2
        var uniqueName = "\(baseName) (\(counter))"
        while existingNames.contains(uniqueName) {
            counter += 1
            uniqueName = "\(baseName) (\(counter))"
        }

        return "\(uniqueName).\(ext)"
    }

    /// Legacy convenience for WAV-only callers.
    func safeWAVFileName(for recording: RecordingItem, existingNames: Set<String> = []) -> String {
        safeFileName(for: recording, format: .wav, existingNames: existingNames)
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

        // Invalidate cache if source file is newer than cached WAV
        var needsConversion = !FileManager.default.fileExists(atPath: cachedURL.path)
        if !needsConversion {
            let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: recording.fileURL.path)
            let cacheAttrs = try? FileManager.default.attributesOfItem(atPath: cachedURL.path)
            let sourceModDate = sourceAttrs?[.modificationDate] as? Date
            let cacheModDate = cacheAttrs?[.modificationDate] as? Date
            if let srcDate = sourceModDate, let cacheDate = cacheModDate, srcDate > cacheDate {
                needsConversion = true
            }
        }

        if needsConversion {
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

    // MARK: - Multi-Format Single Export

    /// Export a recording in the specified format for sharing.
    func export(recording: RecordingItem, format: ExportFormat) async throws -> URL {
        switch format {
        case .wav:
            return try await exportToWAV(recording: recording)
        case .original:
            return try await exportOriginal(recording: recording)
        case .m4a:
            return try await exportToM4A(recording: recording)
        case .alac:
            return try await exportToALAC(recording: recording)
        }
    }

    /// Export the original file as-is (copy to share directory with proper name).
    private func exportOriginal(recording: RecordingItem) async throws -> URL {
        cleanShareDirectory()
        let filename = safeFileName(for: recording, format: .original)
        let shareURL = shareDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: shareURL)

        do {
            try FileManager.default.linkItem(at: recording.fileURL, to: shareURL)
        } catch {
            try FileManager.default.copyItem(at: recording.fileURL, to: shareURL)
        }
        return shareURL
    }

    /// Export as AAC M4A at 256kbps.
    private func exportToM4A(recording: RecordingItem) async throws -> URL {
        let cachedURL = wavCacheDirectory.appendingPathComponent("\(recording.id.uuidString)_aac.m4a")

        var needsConversion = !FileManager.default.fileExists(atPath: cachedURL.path)
        if !needsConversion {
            let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: recording.fileURL.path)
            let cacheAttrs = try? FileManager.default.attributesOfItem(atPath: cachedURL.path)
            if let srcDate = sourceAttrs?[.modificationDate] as? Date,
               let cacheDate = cacheAttrs?[.modificationDate] as? Date,
               srcDate > cacheDate {
                needsConversion = true
            }
        }

        if needsConversion {
            try await convertToM4A(sourceURL: recording.fileURL, outputURL: cachedURL)
        }

        cleanShareDirectory()
        let filename = safeFileName(for: recording, format: .m4a)
        let shareURL = shareDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: shareURL)

        do {
            try FileManager.default.linkItem(at: cachedURL, to: shareURL)
        } catch {
            try FileManager.default.copyItem(at: cachedURL, to: shareURL)
        }
        return shareURL
    }

    /// Export as Apple Lossless (ALAC) M4A.
    private func exportToALAC(recording: RecordingItem) async throws -> URL {
        let cachedURL = wavCacheDirectory.appendingPathComponent("\(recording.id.uuidString)_alac.m4a")

        var needsConversion = !FileManager.default.fileExists(atPath: cachedURL.path)
        if !needsConversion {
            let sourceAttrs = try? FileManager.default.attributesOfItem(atPath: recording.fileURL.path)
            let cacheAttrs = try? FileManager.default.attributesOfItem(atPath: cachedURL.path)
            if let srcDate = sourceAttrs?[.modificationDate] as? Date,
               let cacheDate = cacheAttrs?[.modificationDate] as? Date,
               srcDate > cacheDate {
                needsConversion = true
            }
        }

        if needsConversion {
            try await convertToALAC(sourceURL: recording.fileURL, outputURL: cachedURL)
        }

        cleanShareDirectory()
        let filename = safeFileName(for: recording, format: .alac)
        let shareURL = shareDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: shareURL)

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
        format: ExportFormat = .wav,
        albumLookup: (UUID?) -> Album?,
        tagsLookup: ([UUID]) -> [Tag]
    ) async throws -> URL {
        // Check disk space once before processing all recordings
        let fsAttrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
        if let freeSize = fsAttrs[.systemFreeSize] as? Int64, freeSize < 50_000_000 {
            throw NSError(domain: "AudioExporter", code: 10,
                userInfo: [NSLocalizedDescriptionKey: "Not enough storage space for export. Please free up at least 50MB."])
        }

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

            // Generate unique filename in chosen format
            let exportFilename = safeFileName(for: recording, format: format, existingNames: usedNames)

            // Track this name (without extension) as used
            let actualExt = format == .original ? recording.fileURL.pathExtension : format.fileExtension
            let extLength = actualExt.count + 1 // +1 for the dot
            let nameWithoutExtension = String(exportFilename.dropLast(extLength))
            usedNames.insert(nameWithoutExtension)
            usedNamesByFolder[folderName] = usedNames

            let destination = folder.appendingPathComponent(exportFilename)

            do {
                try await convertFile(sourceURL: recording.fileURL, outputURL: destination, format: format, skipDiskSpaceCheck: true)
            } catch {
                // Skip files that fail to convert
                continue
            }

            // Build manifest item
            let relativePath: String
            if folderName.isEmpty {
                relativePath = exportFilename
            } else {
                relativePath = "\(folderName)/\(exportFilename)"
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
            zipFilename = "Sonidea_AllRecordings.zip"
        case .album(let album):
            zipFilename = "Sonidea_\(sanitizeFilename(album.name)).zip"
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

    private func convertToWAV(sourceURL: URL, outputURL: URL, skipDiskSpaceCheck: Bool = false) async throws -> URL {
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    // Remove existing output file
                    try? FileManager.default.removeItem(at: outputURL)

                    try self.manualConvertToWAV(sourceURL: sourceURL, outputURL: outputURL, skipDiskSpaceCheck: skipDiskSpaceCheck)
                    continuation.resume(returning: outputURL)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func manualConvertToWAV(sourceURL: URL, outputURL: URL, skipDiskSpaceCheck: Bool = false) throws {
        // Check disk space before conversion (skip when caller already verified)
        if !skipDiskSpaceCheck {
            let fsAttrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = fsAttrs[.systemFreeSize] as? Int64, freeSize < 50_000_000 {
                throw NSError(domain: "AudioExporter", code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Not enough storage space for export. Please free up at least 50MB."])
            }
        }

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

        // Allocate output buffer once outside the loop and reuse across iterations
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioExporter", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }

        var position: AVAudioFramePosition = 0
        while position < inputFile.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(inputFile.length - position))
            buffer.frameLength = framesToRead

            try inputFile.read(into: buffer)

            var error: NSError?
            var hasProvidedData = false
            let status = converter.convert(to: outputBuffer, error: &error) { inNumPackets, outStatus in
                if hasProvidedData {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                hasProvidedData = true
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

    // MARK: - M4A (AAC) Conversion

    private func convertToM4A(sourceURL: URL, outputURL: URL, skipDiskSpaceCheck: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try? FileManager.default.removeItem(at: outputURL)
                    try self.manualConvertToAAC(sourceURL: sourceURL, outputURL: outputURL, skipDiskSpaceCheck: skipDiskSpaceCheck)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func manualConvertToAAC(sourceURL: URL, outputURL: URL, skipDiskSpaceCheck: Bool = false) throws {
        // Check disk space before conversion (skip when caller already verified)
        if !skipDiskSpaceCheck {
            let fsAttrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = fsAttrs[.systemFreeSize] as? Int64, freeSize < 50_000_000 {
                throw NSError(domain: "AudioExporter", code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Not enough storage space for export. Please free up at least 50MB."])
            }
        }

        let inputFile = try AVAudioFile(forReading: sourceURL)
        let format = inputFile.processingFormat

        // AAC output: 256kbps
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitRateKey: 256_000
        ]

        guard let outputFormat = AVAudioFormat(settings: outputSettings) else {
            throw NSError(domain: "AudioExporter", code: 10,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create AAC output format"])
        }

        guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
            throw NSError(domain: "AudioExporter", code: 11,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create AAC converter"])
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let bufferSize: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioExporter", code: 12,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }

        // Allocate output buffer once outside the loop and reuse across iterations
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioExporter", code: 13,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }

        var position: AVAudioFramePosition = 0
        while position < inputFile.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(inputFile.length - position))
            inputBuffer.frameLength = framesToRead
            try inputFile.read(into: inputBuffer)

            var error: NSError?
            var hasProvidedData = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if hasProvidedData {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                hasProvidedData = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if status == .error, let error = error { throw error }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
            position += AVAudioFramePosition(framesToRead)
        }
    }

    // MARK: - ALAC Conversion

    private func convertToALAC(sourceURL: URL, outputURL: URL, skipDiskSpaceCheck: Bool = false) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try? FileManager.default.removeItem(at: outputURL)
                    try self.manualConvertToALAC(sourceURL: sourceURL, outputURL: outputURL, skipDiskSpaceCheck: skipDiskSpaceCheck)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func manualConvertToALAC(sourceURL: URL, outputURL: URL, skipDiskSpaceCheck: Bool = false) throws {
        // Check disk space before conversion (skip when caller already verified)
        if !skipDiskSpaceCheck {
            let fsAttrs = try FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory())
            if let freeSize = fsAttrs[.systemFreeSize] as? Int64, freeSize < 50_000_000 {
                throw NSError(domain: "AudioExporter", code: 10,
                    userInfo: [NSLocalizedDescriptionKey: "Not enough storage space for export. Please free up at least 50MB."])
            }
        }

        let inputFile = try AVAudioFile(forReading: sourceURL)
        let format = inputFile.processingFormat

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatAppleLossless,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderBitDepthHintKey: 16
        ]

        guard let outputFormat = AVAudioFormat(settings: outputSettings) else {
            throw NSError(domain: "AudioExporter", code: 20,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create ALAC output format"])
        }

        guard let converter = AVAudioConverter(from: format, to: outputFormat) else {
            throw NSError(domain: "AudioExporter", code: 21,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create ALAC converter"])
        }

        let outputFile = try AVAudioFile(forWriting: outputURL, settings: outputSettings)

        let bufferSize: AVAudioFrameCount = 4096
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioExporter", code: 22,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create input buffer"])
        }

        // Allocate output buffer once outside the loop and reuse across iterations
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: bufferSize) else {
            throw NSError(domain: "AudioExporter", code: 23,
                          userInfo: [NSLocalizedDescriptionKey: "Failed to create output buffer"])
        }

        var position: AVAudioFramePosition = 0
        while position < inputFile.length {
            let framesToRead = min(bufferSize, AVAudioFrameCount(inputFile.length - position))
            inputBuffer.frameLength = framesToRead
            try inputFile.read(into: inputBuffer)

            var error: NSError?
            var hasProvidedData = false
            let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
                if hasProvidedData {
                    outStatus.pointee = .noDataNow
                    return nil
                }
                hasProvidedData = true
                outStatus.pointee = .haveData
                return inputBuffer
            }

            if status == .error, let error = error { throw error }
            if outputBuffer.frameLength > 0 {
                try outputFile.write(from: outputBuffer)
            }
            position += AVAudioFramePosition(framesToRead)
        }
    }

    // MARK: - Bulk Conversion Router

    /// Convert a source file to the given format at the output URL.
    /// - Parameter skipDiskSpaceCheck: When true, skips per-file disk space checks (caller already verified).
    private func convertFile(sourceURL: URL, outputURL: URL, format: ExportFormat, skipDiskSpaceCheck: Bool = false) async throws {
        switch format {
        case .wav:
            _ = try await convertToWAV(sourceURL: sourceURL, outputURL: outputURL, skipDiskSpaceCheck: skipDiskSpaceCheck)
        case .m4a:
            try await convertToM4A(sourceURL: sourceURL, outputURL: outputURL, skipDiskSpaceCheck: skipDiskSpaceCheck)
        case .alac:
            try await convertToALAC(sourceURL: sourceURL, outputURL: outputURL, skipDiskSpaceCheck: skipDiskSpaceCheck)
        case .original:
            try? FileManager.default.removeItem(at: outputURL)
            try FileManager.default.copyItem(at: sourceURL, to: outputURL)
        }
    }

    // MARK: - ZIP Creation

    private func createZIP(from sourceDirectory: URL, to destinationURL: URL) throws {
        let coordinator = NSFileCoordinator()
        var coordinatorError: NSError?
        var copyError: Error?

        coordinator.coordinate(readingItemAt: sourceDirectory, options: .forUploading, error: &coordinatorError) { zipURL in
            do {
                try FileManager.default.copyItem(at: zipURL, to: destinationURL)
            } catch {
                copyError = error
            }
        }

        if let error = coordinatorError {
            throw error
        }

        if let error = copyError {
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
