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

    @State private var isSaving = false
    @State private var showSaveConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // MARK: - Deletion Permissions
                Section {
                    Toggle(isOn: $settings.allowMembersToDelete) {
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
                    Picker("Restore Permission", selection: $settings.trashRestorePermission) {
                        ForEach(TrashRestorePermission.allCases, id: \.self) { permission in
                            Text(permission.displayName)
                                .tag(permission)
                        }
                    }

                    Stepper(value: $settings.trashRetentionDays, in: 7...30) {
                        HStack {
                            Text("Retention Period")
                            Spacer()
                            Text("\(settings.trashRetentionDays) days")
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
                    Picker("Default Mode", selection: $settings.defaultLocationSharingMode) {
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

                    Toggle(isOn: $settings.allowMembersToShareLocation) {
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

                // MARK: - Sensitive Content
                Section {
                    Toggle(isOn: $settings.requireSensitiveApproval) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Require Approval")
                                .foregroundColor(palette.textPrimary)
                            Text("Admins must approve sensitive recordings before others can view them")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                } header: {
                    Label("Sensitive Content", systemImage: "eye.slash")
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
        }
    }

    private func saveSettings() {
        isSaving = true
        Task {
            do {
                try await appState.sharedAlbumManager.updateAlbumSettings(
                    album: album,
                    settings: settings
                )

                // Update local album state
                var updatedAlbum = album
                updatedAlbum.sharedSettings = settings
                appState.updateSharedAlbum(updatedAlbum)

                await MainActor.run {
                    isSaving = false
                    showSaveConfirmation = true
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    appState.sharedAlbumManager.error = error.localizedDescription
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
