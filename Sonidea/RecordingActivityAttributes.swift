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

    /// Whether there is currently an active Live Activity
    var hasActiveActivity: Bool {
        currentActivity != nil
    }

    /// Start a Live Activity for recording
    /// Call this ONLY when recording has successfully started
    func startActivity(recordingId: String, startDate: Date) {
        guard #available(iOS 16.1, *) else { return }
        guard isSupported else {
            print("📱 [LiveActivity] Not supported on this device")
            return
        }

        // End any existing activity first
        endActivityImmediately()

        let attributes = RecordingActivityAttributes(
            recordingId: recordingId,
            startDate: startDate
        )

        let initialState = RecordingActivityAttributes.ContentState(
            isRecording: true,
            pausedDuration: nil
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: initialState, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            print("✅ [LiveActivity] Started for recording: \(recordingId)")
        } catch {
            print("❌ [LiveActivity] Failed to start: \(error.localizedDescription)")
        }
    }

    /// Update the Live Activity state (e.g., when paused/resumed)
    func updateActivity(isRecording: Bool, pausedDuration: TimeInterval? = nil) {
        guard #available(iOS 16.1, *) else { return }
        guard let activity = currentActivity else {
            print("⚠️ [LiveActivity] No active activity to update")
            return
        }

        let updatedState = RecordingActivityAttributes.ContentState(
            isRecording: isRecording,
            pausedDuration: pausedDuration
        )

        Task {
            await activity.update(.init(state: updatedState, staleDate: nil))
            print("🔄 [LiveActivity] Updated: isRecording=\(isRecording), pausedDuration=\(pausedDuration ?? 0)")
        }
    }

    /// End the current Live Activity immediately
    func endActivity() {
        endActivityImmediately()
    }

    /// End activity with immediate dismissal (no lingering)
    private func endActivityImmediately() {
        guard #available(iOS 16.1, *) else { return }

        if let activity = currentActivity {
            let finalState = RecordingActivityAttributes.ContentState(
                isRecording: false,
                pausedDuration: nil
            )

            Task {
                await activity.end(
                    .init(state: finalState, staleDate: nil),
                    dismissalPolicy: .immediate
                )
                print("🛑 [LiveActivity] Ended current activity")
            }
        }

        currentActivity = nil
    }

    /// End ALL recording Live Activities (cleanup on app launch)
    /// Call this on app startup to clear any stuck activities
    func endAllActivities() {
        guard #available(iOS 16.1, *) else { return }

        let activities = Activity<RecordingActivityAttributes>.activities
        let count = activities.count

        if count > 0 {
            print("🧹 [LiveActivity] Cleaning up \(count) stuck activit\(count == 1 ? "y" : "ies")")
        }

        Task {
            for activity in activities {
                await activity.end(
                    .init(
                        state: RecordingActivityAttributes.ContentState(
                            isRecording: false,
                            pausedDuration: nil
                        ),
                        staleDate: nil
                    ),
                    dismissalPolicy: .immediate
                )
            }
        }

        currentActivity = nil
    }

    /// Cleanup stale activities if no recording is in progress
    /// Call this on app launch after checking recording state
    func cleanupIfNotRecording(isCurrentlyRecording: Bool) {
        guard !isCurrentlyRecording else { return }

        endAllActivities()
    }
}
