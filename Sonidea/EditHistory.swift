//
//  EditHistory.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/24/26.
//

import Foundation

/// A snapshot of the editing state for undo/redo
struct EditSnapshot: Equatable {
    let audioFileURL: URL
    let duration: TimeInterval
    let markers: [Marker]
    let selectionStart: TimeInterval
    let selectionEnd: TimeInterval
    let description: String  // For potential UI display (e.g., "Trim", "Cut", "Add Marker")

    init(
        audioFileURL: URL,
        duration: TimeInterval,
        markers: [Marker],
        selectionStart: TimeInterval,
        selectionEnd: TimeInterval,
        description: String
    ) {
        self.audioFileURL = audioFileURL
        self.duration = duration
        self.markers = markers
        self.selectionStart = selectionStart
        self.selectionEnd = selectionEnd
        self.description = description
    }
}

/// Manages undo/redo history for waveform editing session
@MainActor
@Observable
final class EditHistory {
    private var undoStack: [EditSnapshot] = []
    private var redoStack: [EditSnapshot] = []

    /// Maximum number of undo steps to keep (to limit memory usage)
    private let maxUndoSteps = 20

    /// Whether undo is available
    var canUndo: Bool {
        !undoStack.isEmpty
    }

    /// Whether redo is available
    var canRedo: Bool {
        !redoStack.isEmpty
    }

    /// Description of the action that would be undone
    var undoActionDescription: String? {
        undoStack.last?.description
    }

    /// Description of the action that would be redone
    var redoActionDescription: String? {
        redoStack.last?.description
    }

    /// Push a snapshot onto the undo stack (call before making a change)
    func pushUndo(_ snapshot: EditSnapshot) {
        undoStack.append(snapshot)

        // Trim stack if too large
        if undoStack.count > maxUndoSteps {
            // Clean up old audio files that are no longer reachable
            let removed = undoStack.removeFirst()
            cleanupFileIfOrphaned(removed.audioFileURL)
        }

        // Clear redo stack when new action is performed
        clearRedoStack()
    }

    /// Pop and return the last undo snapshot
    func popUndo() -> EditSnapshot? {
        undoStack.popLast()
    }

    /// Push a snapshot onto the redo stack
    func pushRedo(_ snapshot: EditSnapshot) {
        redoStack.append(snapshot)

        if redoStack.count > maxUndoSteps {
            let removed = redoStack.removeFirst()
            cleanupFileIfOrphaned(removed.audioFileURL)
        }
    }

    /// Pop and return the last redo snapshot
    func popRedo() -> EditSnapshot? {
        redoStack.popLast()
    }

    /// Clear all history (call when exiting edit mode or saving)
    func clear() {
        // Clean up any temporary files in the stacks
        for snapshot in undoStack {
            cleanupFileIfOrphaned(snapshot.audioFileURL)
        }
        for snapshot in redoStack {
            cleanupFileIfOrphaned(snapshot.audioFileURL)
        }

        undoStack.removeAll()
        redoStack.removeAll()
    }

    /// Clear only the redo stack
    private func clearRedoStack() {
        for snapshot in redoStack {
            cleanupFileIfOrphaned(snapshot.audioFileURL)
        }
        redoStack.removeAll()
    }

    /// Check if a file URL is still referenced in the stacks
    private func isFileReferenced(_ url: URL) -> Bool {
        let allSnapshots = undoStack + redoStack
        return allSnapshots.contains { $0.audioFileURL == url }
    }

    /// Clean up a file if it's no longer referenced anywhere
    private func cleanupFileIfOrphaned(_ url: URL) {
        // Don't delete if still in either stack
        if isFileReferenced(url) {
            return
        }

        // Only delete files in the temp/edited directory
        if url.lastPathComponent.contains("_edited_") {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Get the count of available undo steps
    var undoCount: Int {
        undoStack.count
    }

    /// Get the count of available redo steps
    var redoCount: Int {
        redoStack.count
    }
}
