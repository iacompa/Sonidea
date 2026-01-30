//
//  WatchAppState.swift
//  SonideaWatch Watch App
//
//  Central state for the watchOS companion app.
//

import Foundation
import SwiftUI

@Observable
class WatchAppState {

    // MARK: - Data

    var recordings: [WatchRecordingItem] = []
    var selectedThemeRawValue: String = "system"

    // MARK: - Record Button Position

    var recordButtonPosition: CGPoint?

    // MARK: - Init

    init() {
        loadRecordings()
        loadTheme()
        loadRecordButtonPosition()
    }

    // MARK: - Current Palette

    var currentPalette: WatchThemePalette {
        WatchTheme.palette(for: selectedThemeRawValue)
    }

    // MARK: - Recording Management

    func addRecording(_ recording: WatchRecordingItem) {
        recordings.insert(recording, at: 0)
        saveRecordings()
    }

    func deleteRecording(_ recording: WatchRecordingItem) {
        // Delete file
        try? FileManager.default.removeItem(at: recording.fileURL)
        // Remove from array
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()
    }

    func deleteRecording(at offsets: IndexSet) {
        for index in offsets {
            let recording = recordings[index]
            try? FileManager.default.removeItem(at: recording.fileURL)
        }
        recordings.remove(atOffsets: offsets)
        saveRecordings()
    }

    func markTransferred(_ recording: WatchRecordingItem) {
        guard let index = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        recordings[index].isTransferred = true
        saveRecordings()
    }

    func generateTitle() -> String {
        let prefix = "⌚️ Recording "
        // Also check old prefix for migration
        let oldPrefix = "Watch Rec "
        let maxNumber = recordings.compactMap { item -> Int? in
            if item.title.hasPrefix(prefix) {
                return Int(item.title.dropFirst(prefix.count))
            } else if item.title.hasPrefix(oldPrefix) {
                return Int(item.title.dropFirst(oldPrefix.count))
            }
            return nil
        }.max() ?? 0
        return "\(prefix)\(maxNumber + 1)"
    }

    // MARK: - Theme

    func applyTheme(_ rawValue: String) {
        selectedThemeRawValue = rawValue
        saveTheme()
    }

    // MARK: - Record Button Position

    func persistRecordButtonPosition() {
        guard let pos = recordButtonPosition else {
            UserDefaults.standard.removeObject(forKey: "watchRecordButtonX")
            UserDefaults.standard.removeObject(forKey: "watchRecordButtonY")
            return
        }
        UserDefaults.standard.set(Double(pos.x), forKey: "watchRecordButtonX")
        UserDefaults.standard.set(Double(pos.y), forKey: "watchRecordButtonY")
    }

    func resetRecordButtonPosition() {
        recordButtonPosition = nil
        UserDefaults.standard.removeObject(forKey: "watchRecordButtonX")
        UserDefaults.standard.removeObject(forKey: "watchRecordButtonY")
    }

    private func loadRecordButtonPosition() {
        let x = UserDefaults.standard.double(forKey: "watchRecordButtonX")
        let y = UserDefaults.standard.double(forKey: "watchRecordButtonY")
        if x != 0 || y != 0 {
            recordButtonPosition = CGPoint(x: x, y: y)
        }
    }

    // MARK: - Persistence

    private let recordingsKey = "watchRecordings"
    private let themeKey = "watchTheme"

    private func saveRecordings() {
        guard let data = try? JSONEncoder().encode(recordings) else { return }
        UserDefaults.standard.set(data, forKey: recordingsKey)
    }

    private func loadRecordings() {
        guard let data = UserDefaults.standard.data(forKey: recordingsKey),
              let loaded = try? JSONDecoder().decode([WatchRecordingItem].self, from: data) else { return }
        // Filter out recordings whose files no longer exist
        recordings = loaded.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }
    }

    private func saveTheme() {
        UserDefaults.standard.set(selectedThemeRawValue, forKey: themeKey)
    }

    private func loadTheme() {
        selectedThemeRawValue = UserDefaults.standard.string(forKey: themeKey) ?? "system"
    }
}
