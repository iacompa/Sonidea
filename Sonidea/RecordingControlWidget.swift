//
//  RecordingControlWidget.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import WidgetKit
import AppIntents

// MARK: - Control Widget for Lock Screen (iOS 18+)

@available(iOS 18.0, *)
struct RecordingControlWidget: ControlWidget {
    static let kind: String = "com.voicememo.RecordingControl"

    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: Self.kind) {
            ControlWidgetButton(action: StartRecordingIntent()) {
                Label("Record", systemImage: "mic.fill")
            }
        }
        .displayName("Start Recording")
        .description("Tap to start a new voice recording")
    }
}

// MARK: - Widget Bundle

@available(iOS 18.0, *)
struct VoiceMemoProWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingControlWidget()
    }
}
