//
//  ExportRecordingIntent.swift
//  Sonidea
//
//  Created by Michael Ramos on 2/4/26.
//

import AppIntents
import Foundation
import UniformTypeIdentifiers

// MARK: - Export Format Entity (AppEnum)

/// AppEnum for export format choices in Shortcuts
enum ExportFormatAppEnum: String, AppEnum {
    case wav
    case m4a
    case alac

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        "Export Format"
    }

    static var caseDisplayRepresentations: [ExportFormatAppEnum: DisplayRepresentation] {
        [
            .wav: DisplayRepresentation(title: "WAV", subtitle: "16-bit PCM, universal compatibility"),
            .m4a: DisplayRepresentation(title: "M4A (AAC)", subtitle: "High quality, compact"),
            .alac: DisplayRepresentation(title: "ALAC", subtitle: "Apple Lossless")
        ]
    }

    /// Map to the app's internal ExportFormat enum
    var toExportFormat: ExportFormat {
        switch self {
        case .wav: return .wav
        case .m4a: return .m4a
        case .alac: return .alac
        }
    }
}

// MARK: - Export Recording Intent

/// AppIntent for exporting a recording in the specified format via Shortcuts or Siri.
/// Finds the recording by name (case-insensitive contains match) or uses the most recent.
/// Returns the exported file as an IntentFile.
struct ExportRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Export Recording"
    static var description = IntentDescription("Exports a recording in the specified format")

    /// Does not need to open the app -- runs in background
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Recording Name")
    var recordingName: String?

    @Parameter(title: "Format")
    var format: ExportFormatAppEnum

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        // Load recordings directly from persistence
        let allRecordings = DataSafetyFileOps.load(RecordingItem.self, collection: .recordings)
        let activeRecordings = allRecordings.filter { !$0.isTrashed }

        guard !activeRecordings.isEmpty else {
            throw SonideaIntentError.noRecordingsFound
        }

        // Find the target recording
        let recording: RecordingItem
        if let name = recordingName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let searchName = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let matches = activeRecordings
                .filter { $0.title.lowercased().contains(searchName) }
                .sorted { $0.createdAt > $1.createdAt }

            guard let match = matches.first else {
                throw SonideaIntentError.recordingNotFound(name: name)
            }
            recording = match
        } else {
            guard let mostRecent = activeRecordings.sorted(by: { $0.createdAt > $1.createdAt }).first else {
                throw SonideaIntentError.noRecordingsFound
            }
            recording = mostRecent
        }

        // Verify the audio file exists
        guard FileManager.default.fileExists(atPath: recording.fileURL.path) else {
            throw SonideaIntentError.audioFileNotFound
        }

        // Export the recording
        let exporter = AudioExporter.shared

        do {
            let exportedURL = try await exporter.export(recording: recording, format: format.toExportFormat)

            // Determine UTType for the exported file
            let fileType: UTType
            switch format {
            case .wav:
                fileType = .wav
            case .m4a:
                fileType = .mpeg4Audio
            case .alac:
                fileType = .appleProtectedMPEG4Audio
            }

            // Use file-based IntentFile to avoid loading large files into memory
            let intentFile = IntentFile(fileURL: exportedURL, filename: exportedURL.lastPathComponent, type: fileType)
            return .result(value: intentFile)
        } catch {
            throw SonideaIntentError.exportFailed(message: error.localizedDescription)
        }
    }
}
