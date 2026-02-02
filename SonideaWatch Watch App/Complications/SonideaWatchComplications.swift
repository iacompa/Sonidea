//
//  SonideaWatchComplications.swift
//  SonideaWatch Watch App
//
//  WidgetKit complications for Apple Watch: accessoryCorner, accessoryCircular, accessoryInline.
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct SonideaComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> SonideaComplicationEntry {
        SonideaComplicationEntry(date: Date())
    }

    func getSnapshot(in context: Context, completion: @escaping (SonideaComplicationEntry) -> Void) {
        completion(SonideaComplicationEntry(date: Date()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SonideaComplicationEntry>) -> Void) {
        let entry = SonideaComplicationEntry(date: Date())
        // Refresh once per hour — complications are mostly static
        let nextUpdate = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct SonideaComplicationEntry: TimelineEntry {
    let date: Date
}

// MARK: - Accessory Corner Complication

struct SonideaAccessoryCornerView: View {
    var body: some View {
        Image(systemName: "mic.fill")
            .font(.title3)
            .widgetLabel("Record")
    }
}

// MARK: - Accessory Circular Complication

struct SonideaAccessoryCircularView: View {
    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            Image(systemName: "mic.fill")
                .font(.system(size: 20))
        }
    }
}

// MARK: - Accessory Inline Complication

struct SonideaAccessoryInlineView: View {
    var body: some View {
        Label("Sonidea", systemImage: "mic.fill")
    }
}

// MARK: - Widget Definition

struct SonideaWatchComplication: Widget {
    let kind: String = "SonideaWatchComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SonideaComplicationProvider()) { entry in
            SonideaAccessoryCircularView()
        }
        .configurationDisplayName("Sonidea")
        .description("Quick access to Sonidea recording.")
        .supportedFamilies([
            .accessoryCorner,
            .accessoryCircular,
            .accessoryInline
        ])
    }
}
