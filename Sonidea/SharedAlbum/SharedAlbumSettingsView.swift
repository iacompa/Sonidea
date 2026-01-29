//
//  SharedAlbumSettingsView.swift
//  Sonidea
//
//  Admin settings panel for shared albums.
//  Controls deletion permissions, trash settings, and location defaults.
//

import SwiftUI

struct SharedAlbumSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album
    @Binding var settings: SharedAlbumSettings

    @State private var localSettings: SharedAlbumSettings = .default
    @State private var isSaving = false
    @State private var showSaveConfirmation = false
    @State private var showShareSheet = false
    @State private var showStopSharingAlert = false
    @State private var showLeaveAlbumAlert = false
    @State private var showCopiedToast = false
    @State private var showParticipantsSheet = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Sharing Management
                Section {
                    // Share link
                    if let shareURL = album.shareURL {
                        Button {
                            UIPasteboard.general.string = shareURL.absoluteString
                            showCopiedToast = true
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()

                            // Auto-dismiss toast
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                showCopiedToast = false
                            }
                        } label: {
                            HStack {
                                Image(systemName: "link")
                                    .foregroundColor(palette.accent)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Copy Invite Link")
                                        .foregroundColor(palette.textPrimary)
                                    Text(shareURL.absoluteString)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                if showCopiedToast {
                                    Text("Copied!")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Image(systemName: "doc.on.doc")
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                        }

                        Button {
                            showShareSheet = true
                        } label: {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundColor(palette.accent)
                                    .frame(width: 24)
                                Text("Share Invite Link")
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }

                    // Manage participants
                    Button {
                        showParticipantsSheet = true
                    } label: {
                        HStack {
                            Image(systemName: "person.2.fill")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Manage Participants")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(album.participantCount)")
                                .foregroundColor(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }

                    // Stop sharing (owner only)
                    if album.isOwner {
                        Button(role: .destructive) {
                            showStopSharingAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "stop.circle.fill")
                                    .foregroundColor(.red)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Stop Sharing")
                                        .foregroundColor(.red)
                                    Text("Remove all participants and make album private")
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                        }
                    }

                    // Leave album (non-owner only)
                    if !album.isOwner {
                        Button(role: .destructive) {
                            showLeaveAlbumAlert = true
                        } label: {
                            HStack {
                                Image(systemName: "rectangle.portrait.and.arrow.right")
                                    .foregroundColor(.red)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Leave Album")
                                        .foregroundColor(.red)
                                    Text("Your recordings will be removed from this album")
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Sharing", systemImage: "person.2")
                } footer: {
                    Text("Share the invite link to add new participants to this album.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Deletion Permissions
                Section {
                    Toggle(isOn: $localSettings.allowMembersToDelete) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow Members to Delete")
                                .foregroundColor(palette.textPrimary)
                            Text("Members can delete their own recordings")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                } header: {
                    Label("Deletion", systemImage: "trash")
                }

                // MARK: - Trash Settings
                Section {
                    Picker("Restore Permission", selection: $localSettings.trashRestorePermission) {
                        ForEach(TrashRestorePermission.allCases, id: \.self) { permission in
                            Text(permission.displayName)
                                .tag(permission)
                        }
                    }

                    Stepper(value: $localSettings.trashRetentionDays, in: 7...30) {
                        HStack {
                            Text("Retention Period")
                            Spacer()
                            Text("\(localSettings.trashRetentionDays) days")
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                } header: {
                    Label("Trash", systemImage: "arrow.uturn.backward")
                } footer: {
                    Text("Items in trash are automatically deleted after the retention period.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Location Settings
                Section {
                    Picker("Default Mode", selection: $localSettings.defaultLocationSharingMode) {
                        ForEach(LocationSharingMode.allCases, id: \.self) { mode in
                            VStack(alignment: .leading) {
                                Text(mode.displayName)
                                if mode != .none {
                                    Text(mode.description)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }
                            }
                            .tag(mode)
                        }
                    }

                    Toggle(isOn: $localSettings.allowMembersToShareLocation) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow Location Sharing")
                                .foregroundColor(palette.textPrimary)
                            Text("Members can share location with recordings")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                } header: {
                    Label("Location", systemImage: "location")
                }

            }
            .navigationTitle("Album Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        saveSettings()
                    }
                    .fontWeight(.semibold)
                    .foregroundColor(palette.accent)
                    .disabled(isSaving)
                }
            }
            .overlay {
                if isSaving {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                }
            }
            .alert("Settings Saved", isPresented: $showSaveConfirmation) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Album settings have been updated.")
            }
            .alert("Stop Sharing?", isPresented: $showStopSharingAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Stop Sharing", role: .destructive) {
                    stopSharing()
                }
            } message: {
                Text("All participants will lose access to this album. Recordings will remain on your device.")
            }
            .alert("Leave Album?", isPresented: $showLeaveAlbumAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Leave Album", role: .destructive) {
                    leaveAlbum()
                }
            } message: {
                Text("Your recordings will be removed from this album. You can be re-invited by the owner.")
            }
            .sheet(isPresented: $showShareSheet) {
                if let shareURL = album.shareURL {
                    ShareSheet(items: [shareURL])
                }
            }
            .sheet(isPresented: $showParticipantsSheet) {
                SharedAlbumParticipantsView(album: album)
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                localSettings = settings
            }
        }
    }

    private func stopSharing() {
        isSaving = true
        Task {
            do {
                try await appState.sharedAlbumManager.stopSharing(album)
                await MainActor.run {
                    appState.removeSharedAlbum(album)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    appState.sharedAlbumManager.error = error.localizedDescription
                }
            }
        }
    }

    private func leaveAlbum() {
        isSaving = true
        Task {
            do {
                try await appState.sharedAlbumManager.leaveSharedAlbum(album)
                await MainActor.run {
                    appState.removeSharedAlbum(album)
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                    appState.sharedAlbumManager.error = error.localizedDescription
                }
            }
        }
    }

    private func saveSettings() {
        isSaving = true
        Task {
            do {
                try await appState.sharedAlbumManager.updateAlbumSettings(
                    album: album,
                    settings: localSettings
                )

                // Write local copy back to the binding on success
                settings = localSettings

                // Update local album state
                var updatedAlbum = album
                updatedAlbum.sharedSettings = localSettings
                appState.updateSharedAlbum(updatedAlbum)

                await MainActor.run {
                    isSaving = false
                    showSaveConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Settings Summary Row (for album detail)

struct SharedAlbumSettingsSummaryRow: View {
    @Environment(\.themePalette) private var palette

    let settings: SharedAlbumSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .foregroundColor(palette.accent)
                Text("Album Settings")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
            }

            HStack(spacing: 16) {
                SettingChip(
                    icon: "trash",
                    text: settings.allowMembersToDelete ? "Members Delete" : "Admin Delete Only"
                )

                SettingChip(
                    icon: "clock",
                    text: "\(settings.trashRetentionDays)d Trash"
                )

                if settings.defaultLocationSharingMode != .none {
                    SettingChip(
                        icon: "location",
                        text: settings.defaultLocationSharingMode.displayName
                    )
                }
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }
}

struct SettingChip: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(palette.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(palette.background)
        .cornerRadius(6)
    }
}
