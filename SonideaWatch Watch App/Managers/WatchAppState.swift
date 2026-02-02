//
//  WatchAppState.swift
//  SonideaWatch Watch App
//
//  Central state for the watchOS companion app.
//

import Foundation
import SwiftUI

@MainActor
@Observable
class WatchAppState {

    // MARK: - Data

    var recordings: [WatchRecordingItem] = []
    var selectedThemeRawValue: String = "system"

    /// Number of recordings waiting to be confirmed by the phone
    var pendingTransferCount: Int = 0

    // MARK: - Record Button Position

    var recordButtonPosition: CGPoint?

    // MARK: - Cached Palette

    /// Cached palette — only recomputed when `selectedThemeRawValue` changes.
    private(set) var currentPalette: WatchThemePalette = WatchTheme.palette(for: "system")

    // MARK: - Init

    init() {
        loadRecordings()
        loadTheme()
        // Recompute palette after theme is loaded from UserDefaults
        currentPalette = WatchTheme.palette(for: selectedThemeRawValue)
        loadRecordButtonPosition()
        pendingTransferCount = WatchConnectivityService.shared.pendingTransferCount

        // Handle transfer confirmations from phone
        WatchConnectivityService.shared.onTransferConfirmed = { [weak self] _ in
            self?.pendingTransferCount = WatchConnectivityService.shared.pendingTransferCount
        }
    }

    /// Retry all pending transfers (called when phone becomes reachable)
    func retryPendingTransfers() {
        WatchConnectivityService.shared.retryPendingTransfers(recordings: recordings)
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
        currentPalette = WatchTheme.palette(for: rawValue)
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
        // Build a set of filenames present in the documents directory once,
        // instead of calling fileExists(atPath:) per recording (N syscalls -> 1).
        let docsDir = WatchRecordingItem.documentsDirectory
        let existingFiles: Set<String>
        if let contents = try? FileManager.default.contentsOfDirectory(atPath: docsDir.path) {
            existingFiles = Set(contents)
        } else {
            // If directory listing fails, fall back to keeping all recordings
            existingFiles = Set(loaded.map { $0.fileName })
        }
        let valid = loaded.filter { existingFiles.contains($0.fileName) }
        recordings = valid
        // Re-save to migrate old absolute-URL format to new filename format
        if valid.count != loaded.count || !data.isEmpty {
            saveRecordings()
        }
    }

    private func saveTheme() {
        UserDefaults.standard.set(selectedThemeRawValue, forKey: themeKey)
    }

    private func loadTheme() {
        selectedThemeRawValue = UserDefaults.standard.string(forKey: themeKey) ?? "system"
    }
}
