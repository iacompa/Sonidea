//
//  RecordingsListView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct RecordingsListView: View {
    @Environment(AppState.self) var appState
    @State private var selectedRecording: RecordingItem?

    var body: some View {
        Group {
            if appState.recordings.isEmpty {
                emptyState
            } else {
                recordingsList
            }
        }
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.gray)
            Text("No Recordings")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)
            Text("Tap the red button to start recording")
                .font(.subheadline)
                .foregroundColor(.gray)
        }
    }

    private var recordingsList: some View {
        List {
            ForEach(appState.recordings) { recording in
                RecordingRow(recording: recording)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        selectedRecording = recording
                    }
                    .listRowBackground(Color.clear)
            }
            .onDelete { offsets in
                appState.deleteRecordings(at: offsets)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }
}

struct RecordingRow: View {
    @Environment(AppState.self) var appState
    let recording: RecordingItem

    private var recordingTags: [Tag] {
        appState.tags(for: recording.tagIDs)
    }

    private var album: Album? {
        appState.album(for: recording.albumID)
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 24))
                .foregroundColor(.white)
                .frame(width: 44, height: 44)
                .background(Color.gray.opacity(0.3))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.gray)

                    if let album = album {
                        Text("•")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Text(album.name)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                // Tag chips (show up to 2)
                if !recordingTags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(recordingTags.prefix(2)) { tag in
                            TagChipSmall(tag: tag)
                        }
                        if recordingTags.count > 2 {
                            Text("+\(recordingTags.count - 2)")
                                .font(.caption2)
                                .foregroundColor(.gray)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.gray)
        }
        .padding(.vertical, 8)
    }
}

struct TagChipSmall: View {
    let tag: Tag

    var body: some View {
        Text(tag.name)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tag.color.opacity(0.8))
            .cornerRadius(4)
    }
}
