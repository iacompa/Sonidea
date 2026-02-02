//
//  HomeScreenWidgets.swift
//  SonideaRecordingWidget
//
//  Home screen widgets: QuickRecordWidget (small) and RecentRecordingsWidget (medium).
//

import SwiftUI
import WidgetKit

// MARK: - Timeline Provider

struct HomeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> HomeWidgetEntry {
        HomeWidgetEntry(date: Date(), data: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (HomeWidgetEntry) -> Void) {
        let data = SharedWidgetData.load()
        completion(HomeWidgetEntry(date: Date(), data: data))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<HomeWidgetEntry>) -> Void) {
        let data = SharedWidgetData.load()
        let entry = HomeWidgetEntry(date: Date(), data: data)
        // Refresh every 30 minutes
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }
}

struct HomeWidgetEntry: TimelineEntry {
    let date: Date
    let data: SharedWidgetData?
}

// MARK: - Quick Record Widget (Small)

struct QuickRecordWidgetView: View {
    let entry: HomeWidgetEntry

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "mic.fill")
                .font(.system(size: 32))
                .foregroundStyle(.red)

            Text("Record")
                .font(.caption)
                .fontWeight(.semibold)

            if let count = entry.data?.totalRecordingCount {
                Text("\(count) recordings")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct QuickRecordWidget: Widget {
    let kind: String = "QuickRecordWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            QuickRecordWidgetView(entry: entry)
        }
        .configurationDisplayName("Quick Record")
        .description("Tap to open Sonidea and start recording.")
        .supportedFamilies([.systemSmall])
    }
}

// MARK: - Recent Recordings Widget (Medium)

struct RecentRecordingsWidgetView: View {
    let entry: HomeWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "waveform")
                    .foregroundStyle(Color.accentColor)
                Text("Sonidea")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                if let count = entry.data?.totalRecordingCount {
                    Text("\(count) total")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let recordings = entry.data?.recentRecordings, !recordings.isEmpty {
                ForEach(recordings.prefix(3)) { recording in
                    HStack(spacing: 8) {
                        Image(systemName: recording.iconName ?? "waveform")
                            .font(.system(size: 12))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(recording.title)
                                .font(.caption)
                                .fontWeight(.medium)
                                .lineLimit(1)
                            Text("\(recording.formattedDuration) · \(recording.formattedDate)")
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                }
            } else {
                VStack(spacing: 4) {
                    Spacer()
                    Text("No recordings yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap to start recording")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 4)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct RecentRecordingsWidget: Widget {
    let kind: String = "RecentRecordingsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: HomeWidgetProvider()) { entry in
            RecentRecordingsWidgetView(entry: entry)
        }
        .configurationDisplayName("Recent Recordings")
        .description("View your latest recordings at a glance.")
        .supportedFamilies([.systemMedium])
    }
}
