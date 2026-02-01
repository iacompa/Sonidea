//
//  AudioExporterTests.swift
//  SonideaTests
//
//  Tests for ExportFormat enum values and AudioExporter filename generation.
//

import Testing
import Foundation
@testable import Sonidea

struct AudioExporterTests {

    // MARK: - ExportFormat Properties

    @Test func formatDisplayNames() {
        #expect(ExportFormat.original.displayName == "Original")
        #expect(ExportFormat.wav.displayName == "WAV")
        #expect(ExportFormat.m4a.displayName == "M4A (AAC)")
        #expect(ExportFormat.alac.displayName == "ALAC")
    }

    @Test func formatFileExtensions() {
        #expect(ExportFormat.original.fileExtension == "") // sentinel — uses recording's actual extension
        #expect(ExportFormat.wav.fileExtension == "wav")
        #expect(ExportFormat.m4a.fileExtension == "m4a")
        #expect(ExportFormat.alac.fileExtension == "m4a")
    }

    @Test func formatSubtitlesNotEmpty() {
        for format in ExportFormat.allCases {
            #expect(!format.subtitle.isEmpty)
        }
    }

    @Test func formatIconNamesNotEmpty() {
        for format in ExportFormat.allCases {
            #expect(!format.iconName.isEmpty)
        }
    }

    @Test func formatIdentifiable() {
        let ids = ExportFormat.allCases.map { $0.id }
        #expect(Set(ids).count == ExportFormat.allCases.count) // All unique
    }

    @Test func allCasesContainsFourFormats() {
        #expect(ExportFormat.allCases.count == 4)
    }

    // MARK: - Safe Filename Generation

    @Test @MainActor func safeFileNameBasic() {
        let exporter = AudioExporter.shared
        let rec = TestFixtures.makeRecording(title: "My Recording")

        let wavName = exporter.safeFileName(for: rec, format: .wav)
        #expect(wavName == "My Recording.wav")

        let m4aName = exporter.safeFileName(for: rec, format: .m4a)
        #expect(m4aName == "My Recording.m4a")

        let alacName = exporter.safeFileName(for: rec, format: .alac)
        #expect(alacName == "My Recording.m4a")

        let origName = exporter.safeFileName(for: rec, format: .original)
        #expect(origName == "My Recording.m4a")
    }

    @Test @MainActor func safeFileNameDeduplication() {
        let exporter = AudioExporter.shared
        let rec = TestFixtures.makeRecording(title: "Duplicate")
        let existing: Set<String> = ["Duplicate"]

        let name = exporter.safeFileName(for: rec, format: .wav, existingNames: existing)
        #expect(name == "Duplicate (2).wav")
    }

    @Test @MainActor func safeFileNameMultipleCollisions() {
        let exporter = AudioExporter.shared
        let rec = TestFixtures.makeRecording(title: "Test")
        let existing: Set<String> = ["Test", "Test (2)", "Test (3)"]

        let name = exporter.safeFileName(for: rec, format: .m4a, existingNames: existing)
        #expect(name == "Test (4).m4a")
    }

    @Test @MainActor func safeFileNameSpecialCharacters() {
        let exporter = AudioExporter.shared
        let rec = TestFixtures.makeRecording(title: "My/Recording:Test*File")

        let name = exporter.safeFileName(for: rec, format: .wav)
        // Illegal chars should be replaced with dashes
        #expect(!name.contains("/"))
        #expect(!name.contains(":"))
        #expect(!name.contains("*"))
        #expect(name.hasSuffix(".wav"))
    }

    @Test @MainActor func safeFileNameEmptyTitle() {
        let exporter = AudioExporter.shared
        let rec = TestFixtures.makeRecording(title: "")

        let name = exporter.safeFileName(for: rec, format: .wav)
        #expect(name == "Recording.wav")
    }

    @Test @MainActor func safeWAVFileNameDelegatesToSafeFileName() {
        let exporter = AudioExporter.shared
        let rec = TestFixtures.makeRecording(title: "Legacy Test")

        let wavName = exporter.safeWAVFileName(for: rec)
        let genericName = exporter.safeFileName(for: rec, format: .wav)
        #expect(wavName == genericName)
    }
}
