//
//  ProjectDetailView.swift
//  Sonidea
//
//  Project detail view showing all versions/takes and project metadata.
//

import SwiftUI

struct ProjectDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var editedTitle: String
    @State private var editedNotes: String
    @State private var currentProject: Project

    @State private var showAddVersionSheet = false
    @State private var showDeleteConfirmation = false
    @State private var selectedRecording: RecordingItem?

    init(project: Project) {
        _editedTitle = State(initialValue: project.title)
        _editedNotes = State(initialValue: project.notes)
        _currentProject = State(initialValue: project)
    }

    private var versions: [RecordingItem] {
        appState.recordings(in: currentProject)
    }

    private var stats: ProjectStats {
        appState.stats(for: currentProject)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        statsSection
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 1)
                        versionsSection
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 1)
                        metadataSection
                        Rectangle()
                            .fill(palette.separator)
                            .frame(height: 1)
                        dangerZone
                    }
                    .padding()
                }
            }
            .navigationTitle("Project")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        currentProject.pinned.toggle()
                        appState.toggleProjectPin(currentProject)
                    } label: {
                        Image(systemName: currentProject.pinned ? "pin.fill" : "pin")
                            .foregroundColor(currentProject.pinned ? palette.accent : palette.textSecondary)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        saveChanges()
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAddVersionSheet) {
                AddVersionSheet(project: currentProject)
            }
            .sheet(item: $selectedRecording) { recording in
                // Pass isOpenedFromProject: true to prevent navigation loop
                RecordingDetailView(recording: recording, isOpenedFromProject: true)
                    .environment(appState)
            }
            .alert("Delete Project?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    appState.deleteProject(currentProject)
                    dismiss()
                }
            } message: {
                Text("This will remove the project but keep all recordings as standalone items.")
            }
            .onAppear {
                refreshProject()
            }
            .onChange(of: selectedRecording) { _, newValue in
                // Refresh project when sheet is dismissed (recording is nil again)
                if newValue == nil {
                    refreshProject()
                }
            }
        }
    }

    // MARK: - Stats Section

    private var statsSection: some View {
        VStack(spacing: 16) {
            // Project icon and title
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "folder.fill")
                        .font(.system(size: 28))
                        .foregroundColor(palette.accent)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(currentProject.title)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(2)

                    Text("\(stats.versionCount) version\(stats.versionCount == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()
            }

            // Stats grid
            HStack(spacing: 12) {
                StatBadge(
                    icon: "clock",
                    value: stats.formattedTotalDuration,
                    label: "Total",
                    palette: palette
                )

                if stats.hasBestTake {
                    StatBadge(
                        icon: "star.fill",
                        value: "Set",
                        label: "Best Take",
                        palette: palette,
                        iconColor: .yellow
                    )
                }

                if let newest = stats.newestVersion {
                    StatBadge(
                        icon: "calendar",
                        value: formatShortDate(newest),
                        label: "Latest",
                        palette: palette
                    )
                }
            }
        }
    }

    // MARK: - Versions Section

    private var versionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Versions")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    showAddVersionSheet = true
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text("Add")
                    }
                    .font(.caption)
                    .foregroundColor(palette.accent)
                }
            }

            // Hint for Best Take discovery
            if !versions.isEmpty {
                Text("Tip: Press and hold a take to set Best Take.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if versions.isEmpty {
                emptyVersionsView
                    .padding(.top, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(versions) { recording in
                        VersionRow(
                            recording: recording,
                            isBestTake: currentProject.bestTakeRecordingId == recording.id,
                            palette: palette,
                            onTap: {
                                selectedRecording = recording
                            },
                            onSetBestTake: {
                                if currentProject.bestTakeRecordingId == recording.id {
                                    appState.clearBestTake(for: currentProject)
                                } else {
                                    appState.setBestTake(recording, for: currentProject)
                                }
                                refreshProject()
                            },
                            onRemoveFromProject: {
                                appState.removeFromProject(recording: recording)
                                refreshProject()
                            }
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private var emptyVersionsView: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.badge.plus")
                .font(.system(size: 40))
                .foregroundColor(palette.textSecondary.opacity(0.5))

            Text("No versions yet")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)

            Button {
                showAddVersionSheet = true
            } label: {
                Text("Add First Version")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(palette.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(palette.inputBackground)
        .cornerRadius(12)
    }

    // MARK: - Metadata Section

    private var metadataSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Title
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)
                TextField("Project title", text: $editedTitle)
                    .textFieldStyle(.plain)
                    .foregroundColor(palette.textPrimary)
                    .padding(12)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
            }

            // Notes
            VStack(alignment: .leading, spacing: 8) {
                Text("Notes")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)
                TextEditor(text: $editedNotes)
                    .scrollContentBackground(.hidden)
                    .foregroundColor(palette.textPrimary)
                    .padding(8)
                    .frame(minHeight: 100)
                    .background(palette.inputBackground)
                    .cornerRadius(8)
            }

            // Dates
            VStack(alignment: .leading, spacing: 8) {
                Text("Info")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .textCase(.uppercase)

                VStack(spacing: 0) {
                    InfoRow(label: "Created", value: currentProject.formattedCreatedDate, palette: palette)
                    Rectangle().fill(palette.separator).frame(height: 1)
                    InfoRow(label: "Updated", value: currentProject.formattedUpdatedDate, palette: palette)
                }
                .background(palette.inputBackground)
                .cornerRadius(8)
            }
        }
    }

    // MARK: - Danger Zone

    private var dangerZone: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Danger Zone")
                .font(.caption)
                .foregroundColor(.red.opacity(0.8))
                .textCase(.uppercase)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                HStack {
                    Image(systemName: "trash")
                    Text("Delete Project")
                }
                .font(.subheadline)
                .foregroundColor(.red)
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(Color.red.opacity(0.1))
                .cornerRadius(8)
            }

            Text("Recordings will be kept as standalone items.")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
    }

    // MARK: - Helpers

    private func refreshProject() {
        if let updated = appState.project(for: currentProject.id) {
            currentProject = updated
        }
    }

    private func saveChanges() {
        var updated = currentProject
        updated.title = editedTitle.isEmpty ? currentProject.title : editedTitle
        updated.notes = editedNotes
        appState.updateProject(updated)
    }

    private func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - Version Row

private struct VersionRow: View {
    let recording: RecordingItem
    let isBestTake: Bool
    let palette: ThemePalette
    let onTap: () -> Void
    let onSetBestTake: () -> Void
    let onRemoveFromProject: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Version badge
                Text(recording.versionLabel)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(isBestTake ? .yellow : palette.textSecondary)
                    .frame(width: 32)

                // Recording info
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(recording.title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)

                        if isBestTake {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.yellow)
                        }
                    }

                    Text("\(recording.formattedDuration) \u{2022} \(recording.formattedDate)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
            .padding(12)
            .background(palette.inputBackground)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                onSetBestTake()
            } label: {
                Label(
                    isBestTake ? "Remove Best Take" : "Set as Best Take",
                    systemImage: isBestTake ? "star.slash" : "star.fill"
                )
            }

            Divider()

            Button(role: .destructive) {
                onRemoveFromProject()
            } label: {
                Label("Remove from Project", systemImage: "folder.badge.minus")
            }
        }
    }
}

// MARK: - Stat Badge

private struct StatBadge: View {
    let icon: String
    let value: String
    let label: String
    let palette: ThemePalette
    var iconColor: Color? = nil

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(iconColor ?? palette.textSecondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(palette.textPrimary)
            Text(label)
                .font(.caption2)
                .foregroundColor(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(palette.inputBackground)
        .cornerRadius(8)
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String
    let palette: ThemePalette

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
        }
        .padding(12)
    }
}

// MARK: - Add Version Sheet

struct AddVersionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let project: Project

    @State private var searchQuery = ""

    private var eligibleRecordings: [RecordingItem] {
        // Only show standalone recordings (not already in a project)
        let standalone = appState.standaloneRecordings

        if searchQuery.isEmpty {
            return standalone
        }

        let lowercased = searchQuery.lowercased()
        return standalone.filter {
            $0.title.lowercased().contains(lowercased) ||
            $0.notes.lowercased().contains(lowercased)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                palette.background.ignoresSafeArea()

                if appState.standaloneRecordings.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(eligibleRecordings) { recording in
                            Button {
                                appState.addVersion(recording: recording, to: project)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "waveform")
                                        .foregroundColor(palette.textSecondary)
                                        .frame(width: 24)

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(recording.title)
                                            .font(.subheadline)
                                            .foregroundColor(palette.textPrimary)
                                        Text("\(recording.formattedDuration) \u{2022} \(recording.formattedDate)")
                                            .font(.caption)
                                            .foregroundColor(palette.textSecondary)
                                    }

                                    Spacer()

                                    Image(systemName: "plus.circle")
                                        .foregroundColor(palette.accent)
                                }
                            }
                        }
                    }
                    .searchable(text: $searchQuery, prompt: "Search recordings")
                }
            }
            .navigationTitle("Add Version")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(palette.textSecondary.opacity(0.5))

            Text("No Standalone Recordings")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text("All recordings are already part of projects. Record a new take to add it here.")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}
