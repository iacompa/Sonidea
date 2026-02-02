//
//  WatchStartRecordingIntent.swift
//  SonideaWatch Watch App
//
//  AppIntent to start recording from a watch complication.
//

import AppIntents

struct WatchStartRecordingIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Recording"
    static var description = IntentDescription("Start a new voice recording on Apple Watch")
    static var openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        // Set a flag that WatchContentView reads on appear to auto-start recording
        UserDefaults.standard.set(true, forKey: "pendingStartRecording")
        return .result()
    }
}
