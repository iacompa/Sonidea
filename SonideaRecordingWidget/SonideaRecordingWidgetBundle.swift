//
//  SonideaRecordingWidgetBundle.swift
//  SonideaRecordingWidget
//
//  Widget bundle for Sonidea recording Live Activity.
//

import SwiftUI
import WidgetKit

@main
struct SonideaRecordingWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecordingLiveActivityWidget()
        QuickRecordWidget()
        RecentRecordingsWidget()
    }
}
