//
//  AudioDebug.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/24/26.
//

import AVFoundation
import Foundation

/// Debug helper for audio file and session diagnostics
enum AudioDebug {

    // MARK: - File Diagnostics

    /// Log detailed file information
    static func logFileInfo(url: URL, context: String) {
        print("🎵 [\(context)] File diagnostics:")
        print("   URL: \(url.path)")

        let fileManager = FileManager.default
        let exists = fileManager.fileExists(atPath: url.path)
        print("   Exists: \(exists)")

        if exists {
            do {
                let attrs = try fileManager.attributesOfItem(atPath: url.path)
                if let size = attrs[.size] as? Int64 {
                    print("   Size: \(size) bytes (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))")
                }
                if let created = attrs[.creationDate] as? Date {
                    print("   Created: \(created)")
                }
                if let modified = attrs[.modificationDate] as? Date {
                    print("   Modified: \(modified)")
                }
            } catch {
                print("   ❌ Error getting attributes: \(error.localizedDescription)")
            }

            // Check if file is readable
            let isReadable = fileManager.isReadableFile(atPath: url.path)
            print("   Readable: \(isReadable)")

            // Try to get audio file info
            do {
                let audioFile = try AVAudioFile(forReading: url)
                print("   ✅ AVAudioFile opened successfully")
                print("   Duration: \(Double(audioFile.length) / audioFile.processingFormat.sampleRate) seconds")
                print("   Sample rate: \(audioFile.processingFormat.sampleRate)")
                print("   Channels: \(audioFile.processingFormat.channelCount)")
            } catch {
                print("   ❌ AVAudioFile error: \(error.localizedDescription)")
            }
        } else {
            print("   ❌ File does not exist!")

            // Check parent directory
            let parentDir = url.deletingLastPathComponent()
            let parentExists = fileManager.fileExists(atPath: parentDir.path)
            print("   Parent directory exists: \(parentExists)")
            print("   Parent directory: \(parentDir.path)")
        }
    }

    /// Verify a file exists and has valid audio content
    static func verifyAudioFile(url: URL) -> AudioFileStatus {
        let fileManager = FileManager.default

        // Check existence
        guard fileManager.fileExists(atPath: url.path) else {
            return .notFound
        }

        // Check size
        do {
            let attrs = try fileManager.attributesOfItem(atPath: url.path)
            guard let size = attrs[.size] as? Int64, size > 0 else {
                return .empty
            }

            // Minimum valid audio file size (header + some data)
            if size < 100 {
                return .tooSmall(size)
            }
        } catch {
            return .attributeError(error)
        }

        // Check if readable as audio
        do {
            let audioFile = try AVAudioFile(forReading: url)
            let duration = Double(audioFile.length) / audioFile.processingFormat.sampleRate

            if duration <= 0 {
                return .zeroDuration
            }

            return .valid(duration: duration)
        } catch {
            return .audioError(error)
        }
    }

    // MARK: - Session Diagnostics

    /// Log current audio session state
    static func logSessionState(context: String) {
        let session = AVAudioSession.sharedInstance()

        print("🔊 [\(context)] Audio session state:")
        print("   Category: \(session.category.rawValue)")
        print("   Mode: \(session.mode.rawValue)")
        print("   Sample rate: \(session.sampleRate)")
        print("   Is active: \(session.isOtherAudioPlaying ? "other audio playing" : "available")")

        // Current route
        let route = session.currentRoute
        print("   Inputs: \(route.inputs.map { $0.portName }.joined(separator: ", "))")
        print("   Outputs: \(route.outputs.map { $0.portName }.joined(separator: ", "))")
    }

    /// Log error with context
    static func logError(_ error: Error, context: String) {
        print("❌ [\(context)] Error: \(error.localizedDescription)")
        if let nsError = error as NSError? {
            print("   Domain: \(nsError.domain)")
            print("   Code: \(nsError.code)")
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                print("   Underlying: \(underlying.localizedDescription)")
            }
        }
    }
}

// MARK: - Audio File Status

enum AudioFileStatus {
    case valid(duration: TimeInterval)
    case notFound
    case empty
    case tooSmall(Int64)
    case zeroDuration
    case attributeError(Error)
    case audioError(Error)

    var isValid: Bool {
        if case .valid = self { return true }
        return false
    }

    var errorMessage: String? {
        switch self {
        case .valid:
            return nil
        case .notFound:
            return "Recording file not found. It may have been deleted."
        case .empty:
            return "Recording file is empty."
        case .tooSmall(let size):
            return "Recording file is too small (\(size) bytes)."
        case .zeroDuration:
            return "Recording has zero duration."
        case .attributeError(let error):
            return "Cannot read recording: \(error.localizedDescription)"
        case .audioError(let error):
            return "Cannot open recording: \(error.localizedDescription)"
        }
    }
}

// MARK: - Playback Error

enum PlaybackError: LocalizedError {
    case fileNotFound(URL)
    case cannotOpenFile(URL, Error)
    case audioSessionFailed(Error)
    case engineStartFailed(Error)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "Recording file not found: \(url.lastPathComponent)"
        case .cannotOpenFile(_, let error):
            return "Cannot open recording: \(error.localizedDescription)"
        case .audioSessionFailed(let error):
            return "Audio system error: \(error.localizedDescription)"
        case .engineStartFailed(let error):
            return "Playback failed to start: \(error.localizedDescription)"
        }
    }
}
