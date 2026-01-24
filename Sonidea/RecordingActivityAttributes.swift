//
//  RecordingActivityAttributes.swift
//  Sonidea
//
//  ActivityKit attributes for Live Activity during recording.
//  Shared between main app and widget extension.
//

import ActivityKit
import Foundation

struct RecordingActivityAttributes: ActivityAttributes {

    // Static attributes that don't change during the activity
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

    /// Display title
    var title: String
}

// MARK: - Live Activity Manager

@MainActor
final class RecordingLiveActivityManager {
    static let shared = RecordingLiveActivityManager()

    private var currentActivity: Activity<RecordingActivityAttributes>?

    private init() {}

    /// Check if Live Activities are supported on this device/OS
    var isSupported: Bool {
        if #available(iOS 16.1, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    /// Start a Live Activity for recording
    func startActivity(recordingId: String, startDate: Date) {
        guard #available(iOS 16.1, *) else { return }
        guard isSupported else { return }

        // End any existing activity first
        endActivity()

        let attributes = RecordingActivityAttributes(
            recordingId: recordingId,
            startDate: startDate,
            title: "Recording"
        )

        let initialState = RecordingActivityAttributes.ContentState(
            isRecording: true,
            pausedDuration: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                contentState: initialState,
                pushType: nil
            )
            currentActivity = activity
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }

    /// Update the Live Activity state (e.g., when paused/resumed)
    func updateActivity(isRecording: Bool, pausedDuration: TimeInterval? = nil) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = currentActivity else { return }

        let updatedState = RecordingActivityAttributes.ContentState(
            isRecording: isRecording,
            pausedDuration: pausedDuration
        )

        Task {
            await activity.update(using: updatedState)
        }
    }

    /// End the Live Activity
    func endActivity() {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = currentActivity else { return }

        let finalState = RecordingActivityAttributes.ContentState(
            isRecording: false,
            pausedDuration: nil
        )

        Task {
            await activity.end(using: finalState, dismissalPolicy: .immediate)
        }

        currentActivity = nil
    }

    /// End all recording activities (cleanup)
    func endAllActivities() {
        guard #available(iOS 16.1, *) else { return }

        Task {
            for activity in Activity<RecordingActivityAttributes>.activities {
                await activity.end(dismissalPolicy: .immediate)
            }
        }

        currentActivity = nil
    }
}
