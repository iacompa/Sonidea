//
//  RecordingDetailView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI

struct RecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @State private var playback = PlaybackManager()

    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var editedLocationLabel: String
    @State private var currentRecording: RecordingItem

    @State private var showManageTags = false
    @State private var showChooseAlbum = false

    @State private var waveformSamples: [Float] = []
    @State private var zoomScale: CGFloat = 1.0
    @State private var isLoadingWaveform = true

    init(recording: RecordingItem) {
        _editedTitle = State(initialValue: recording.title)
        _editedNotes = State(initialValue: recording.notes)
        _editedLocationLabel = State(initialValue: recording.locationLabel)
        _currentRecording = State(initialValue: recording)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        playbackSection
                        Divider()
                        metadataSection
                    }
                    .padding()
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveChanges()
                        playback.stop()
                        dismiss()
                    }
                }
            }
            .onAppear {
                playback.load(url: currentRecording.fileURL)
                loadWaveform()
            }
            .onDisappear {
                playback.stop()
            }
            .sheet(isPresented: $showManageTags) {
                ManageTagsSheet()
            }
            .sheet(isPresented: $showChooseAlbum) {
                ChooseAlbumSheet(recording: $currentRecording)
            }
        }
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Waveform
            ZStack {
                if isLoadingWaveform {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .primary))
                        .frame(height: 100)
                } else if waveformSamples.isEmpty {
                    Image(systemName: "waveform")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                        .frame(height: 100)
                } else {
                    WaveformView(
                        samples: waveformSamples,
                        progress: playbackProgress,
                        zoomScale: $zoomScale
                    )
                    .frame(height: 100)
                }
            }
            .padding(.vertical, 10)

            // Zoom indicator
            if zoomScale > 1.01 {
                HStack {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(Int(zoomScale * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        withAnimation {
                            zoomScale = 1.0
                        }
                    } label: {
                        Text("Reset")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }

            HStack {
                Text(formatTime(playback.currentTime))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(playback.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(height: 4)
                        .cornerRadius(2)
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(width: progressWidth(in: geometry.size.width), height: 4)
                        .cornerRadius(2)
                }
            }
            .frame(height: 4)

            Button {
                playback.togglePlayPause()
            } label: {
                Image(systemName: playback.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 56))
                    .foregroundColor(.accentColor)
            }

            Text(currentRecording.formattedDate)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextField("Recording title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            // Album
            VStack(alignment: .leading, spacing: 8) {
                Text("Album")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Button {
                    showChooseAlbum = true
                } label: {
                    HStack {
                        if let album = appState.album(for: currentRecording.albumID) {
                            Text(album.name)
                                .foregroundColor(.primary)
                        } else {
                            Text("None")
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                }
            }

            // Tags
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tags")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button("Manage") {
                        showManageTags = true
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }

                FlowLayout(spacing: 8) {
                    ForEach(appState.tags) { tag in
                        TagChipSelectable(
                            tag: tag,
                            isSelected: currentRecording.tagIDs.contains(tag.id)
                        ) {
                            currentRecording = appState.toggleTag(tag, for: currentRecording)
                        }
                    }
                }
            }

            // Location
            VStack(alignment: .leading, spacing: 8) {
                Text("Location")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextField("Enter location", text: $editedLocationLabel)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                TextEditor(text: $editedNotes)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
            }
        }
    }

    // MARK: - Helpers

    private var playbackProgress: Double {
        guard playback.duration > 0 else { return 0 }
        return min(1, max(0, playback.currentTime / playback.duration))
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard playback.duration > 0 else { return 0 }
        return totalWidth * (playback.currentTime / playback.duration)
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func saveChanges() {
        var updated = currentRecording
        updated.title = editedTitle.isEmpty ? currentRecording.title : editedTitle
        updated.notes = editedNotes
        updated.locationLabel = editedLocationLabel
        appState.updateRecording(updated)
    }

    private func loadWaveform() {
        isLoadingWaveform = true
        Task {
            let samples = await WaveformSampler.shared.samples(
                for: currentRecording.fileURL,
                targetSampleCount: 150
            )
            await MainActor.run {
                waveformSamples = samples
                isLoadingWaveform = false
            }
        }
    }
}

// MARK: - Tag Chip Selectable

struct TagChipSelectable: View {
    let tag: Tag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(tag.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : tag.color)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? tag.color : tag.color.opacity(0.2))
                .cornerRadius(16)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(tag.color, lineWidth: isSelected ? 0 : 1)
                )
        }
    }
}

// MARK: - Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(proposal: proposal, subviews: subviews)
        for (index, frame) in result.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: .unspecified)
        }
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, frames: [CGRect]) {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var frames: [CGRect] = []

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            frames.append(CGRect(x: currentX, y: currentY, width: size.width, height: size.height))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
        }

        let totalHeight = currentY + lineHeight
        return (CGSize(width: maxWidth, height: totalHeight), frames)
    }
}

// MARK: - Manage Tags Sheet

struct ManageTagsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var newTagName = ""
    @State private var newTagColor = Color.blue

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(appState.tags) { tag in
                        HStack {
                            Circle()
                                .fill(tag.color)
                                .frame(width: 24, height: 24)
                            Text(tag.name)
                            Spacer()
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            appState.deleteTag(appState.tags[index])
                        }
                    }
                } header: {
                    Text("Existing Tags")
                }

                Section {
                    HStack {
                        TextField("Tag name", text: $newTagName)
                        ColorPicker("", selection: $newTagColor, supportsOpacity: false)
                            .labelsHidden()
                    }

                    Button("Create Tag") {
                        guard !newTagName.isEmpty else { return }
                        appState.createTag(name: newTagName, colorHex: newTagColor.toHex())
                        newTagName = ""
                        newTagColor = .blue
                    }
                    .disabled(newTagName.isEmpty)
                } header: {
                    Text("New Tag")
                }
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Choose Album Sheet

struct ChooseAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Binding var recording: RecordingItem

    @State private var newAlbumName = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        recording = appState.setAlbum(nil, for: recording)
                        dismiss()
                    } label: {
                        HStack {
                            Text("None")
                            Spacer()
                            if recording.albumID == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }

                    ForEach(appState.albums) { album in
                        Button {
                            recording = appState.setAlbum(album, for: recording)
                            dismiss()
                        } label: {
                            HStack {
                                Text(album.name)
                                Spacer()
                                if recording.albumID == album.id {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            appState.deleteAlbum(appState.albums[index])
                        }
                    }
                } header: {
                    Text("Albums")
                }

                Section {
                    HStack {
                        TextField("Album name", text: $newAlbumName)
                    }

                    Button("Create Album") {
                        guard !newAlbumName.isEmpty else { return }
                        let album = appState.createAlbum(name: newAlbumName)
                        recording = appState.setAlbum(album, for: recording)
                        newAlbumName = ""
                        dismiss()
                    }
                    .disabled(newAlbumName.isEmpty)
                } header: {
                    Text("New Album")
                }
            }
            .navigationTitle("Choose Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
