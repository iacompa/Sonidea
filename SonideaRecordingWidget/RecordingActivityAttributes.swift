//
//  RecordingActivityAttributes.swift
//  SonideaRecordingWidget
//
//  ActivityKit attributes for Live Activity during recording.
//  This file is duplicated in the widget extension (widgets can't import main app code).
//

import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {

    // Dynamic state that changes during the activity
    public struct ContentState: Codable, Hashable {
        /// Whether recording is currently active (vs paused)
        var isRecording: Bool

        /// The accumulated duration at the time of the last update (for paused state)
        var pausedDuration: TimeInterval?
    }

    /// Unique identifier for this recording session
    var recordingId: String

    /// The date/time when recording started (used for live timer)
    var startDate: Date
}
