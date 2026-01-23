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

    init(recording: RecordingItem) {
        _editedTitle = State(initialValue: recording.title)
        _editedNotes = State(initialValue: recording.notes)
        _editedLocationLabel = State(initialValue: recording.locationLabel)
        _currentRecording = State(initialValue: recording)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        playbackSection
                        Divider().background(Color.gray.opacity(0.3))
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
        .preferredColorScheme(.dark)
    }

    // MARK: - Playback Section

    private var playbackSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "waveform")
                .font(.system(size: 60))
                .foregroundColor(.white.opacity(0.3))
                .padding(.vertical, 20)

            HStack {
                Text(formatTime(playback.currentTime))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .monospacedDigit()
                Spacer()
                Text(formatTime(playback.duration))
                    .font(.caption)
                    .foregroundColor(.gray)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 4)
                        .cornerRadius(2)
                    Rectangle()
                        .fill(Color.white)
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
                    .foregroundColor(.white)
            }

            Text(currentRecording.formattedDate)
                .font(.caption)
                .foregroundColor(.gray)
        }
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                TextField("Recording title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }

            // Album
            VStack(alignment: .leading, spacing: 8) {
                Text("Album")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)

                Button {
                    showChooseAlbum = true
                } label: {
                    HStack {
                        if let album = appState.album(for: currentRecording.albumID) {
                            Text(album.name)
                                .foregroundColor(.white)
                        } else {
                            Text("None")
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundColor(.gray)
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
                        .foregroundColor(.gray)
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
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                TextField("Enter location", text: $editedLocationLabel)
                    .textFieldStyle(.plain)
                    .padding(12)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(.gray)
                    .textCase(.uppercase)
                TextEditor(text: $editedNotes)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(Color(.systemGray6))
                    .cornerRadius(8)
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Helpers

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
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        ForEach(appState.tags) { tag in
                            HStack {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 24, height: 24)
                                Text(tag.name)
                                    .foregroundColor(.white)
                                Spacer()
                            }
                            .listRowBackground(Color(.systemGray6))
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
                                .foregroundColor(.white)
                            ColorPicker("", selection: $newTagColor, supportsOpacity: false)
                                .labelsHidden()
                        }
                        .listRowBackground(Color(.systemGray6))

                        Button("Create Tag") {
                            guard !newTagName.isEmpty else { return }
                            appState.createTag(name: newTagName, colorHex: newTagColor.toHex())
                            newTagName = ""
                            newTagColor = .blue
                        }
                        .disabled(newTagName.isEmpty)
                        .listRowBackground(Color(.systemGray6))
                    } header: {
                        Text("New Tag")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Manage Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
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
            ZStack {
                Color.black.ignoresSafeArea()

                List {
                    Section {
                        Button {
                            recording = appState.setAlbum(nil, for: recording)
                            dismiss()
                        } label: {
                            HStack {
                                Text("None")
                                    .foregroundColor(.white)
                                Spacer()
                                if recording.albumID == nil {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                        .listRowBackground(Color(.systemGray6))

                        ForEach(appState.albums) { album in
                            Button {
                                recording = appState.setAlbum(album, for: recording)
                                dismiss()
                            } label: {
                                HStack {
                                    Text(album.name)
                                        .foregroundColor(.white)
                                    Spacer()
                                    if recording.albumID == album.id {
                                        Image(systemName: "checkmark")
                                            .foregroundColor(.blue)
                                    }
                                }
                            }
                            .listRowBackground(Color(.systemGray6))
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
                                .foregroundColor(.white)
                        }
                        .listRowBackground(Color(.systemGray6))

                        Button("Create Album") {
                            guard !newAlbumName.isEmpty else { return }
                            let album = appState.createAlbum(name: newAlbumName)
                            recording = appState.setAlbum(album, for: recording)
                            newAlbumName = ""
                            dismiss()
                        }
                        .disabled(newAlbumName.isEmpty)
                        .listRowBackground(Color(.systemGray6))
                    } header: {
                        Text("New Album")
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Choose Album")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
