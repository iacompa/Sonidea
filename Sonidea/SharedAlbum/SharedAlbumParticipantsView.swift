//
//  SharedAlbumParticipantsView.swift
//  Sonidea
//
//  Participant management UI for shared albums.
//  Shows participants with roles, allows admin to change roles and remove participants.
//

import SwiftUI

struct SharedAlbumParticipantsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album

    @State private var participants: [SharedAlbumParticipant] = []
    @State private var isLoading = true
    @State private var selectedParticipant: SharedAlbumParticipant?
    @State private var showRemoveConfirmation = false
    @State private var showRoleSheet = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var sharingController: UICloudSharingController?
    @State private var showSharingSheet = false
    @State private var currentUserId: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading participants...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if participants.isEmpty {
                    emptyStateView
                } else {
                    participantsList
                }
            }
            .background(palette.background)
            .navigationTitle("Participants")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                if album.canManageParticipants {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showShareSheet()
                        } label: {
                            Image(systemName: "person.badge.plus")
                        }
                        .foregroundColor(palette.accent)
                        .accessibilityLabel("Add participant")
                    }
                }
            }
            .sheet(isPresented: $showRoleSheet) {
                if let participant = selectedParticipant {
                    RoleSelectionSheet(
                        participant: participant,
                        onRoleSelected: { role in
                            changeRole(participant: participant, to: role)
                        }
                    )
                    .presentationDetents([.height(300)])
                }
            }
            .alert("Remove Participant?", isPresented: $showRemoveConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Remove", role: .destructive) {
                    if let participant = selectedParticipant {
                        removeParticipant(participant)
                    }
                }
            } message: {
                if let participant = selectedParticipant {
                    Text("\(participant.displayName) will lose access to all recordings in this album.")
                }
            }
            .alert("Error", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showSharingSheet) {
                if let controller = sharingController {
                    CloudSharingSheet(controller: controller)
                        .ignoresSafeArea()
                }
            }
            .onAppear {
                loadParticipants()
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "person.2")
                .font(.system(size: 48))
                .foregroundColor(palette.textTertiary)

            Text("No Participants")
                .font(.headline)
                .foregroundColor(palette.textSecondary)

            Text("Invite others to collaborate on this album")
                .font(.subheadline)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private var participantsList: some View {
        List {
            ForEach(participants) { participant in
                ParticipantRow(
                    participant: participant,
                    isCurrentUser: participant.id == currentUserId,
                    canManage: album.canManageParticipants && participant.role != .admin,
                    onRoleTapped: {
                        selectedParticipant = participant
                        showRoleSheet = true
                    },
                    onRemoveTapped: {
                        selectedParticipant = participant
                        showRemoveConfirmation = true
                    }
                )
            }
        }
        .listStyle(.insetGrouped)
    }

    private func loadParticipants() {
        isLoading = true
        Task {
            let userId = await appState.sharedAlbumManager.getCurrentUserId()
            let fetched = await appState.sharedAlbumManager.fetchParticipants(for: album)
            await MainActor.run {
                currentUserId = userId
                if fetched.isEmpty, let cached = album.participants, !cached.isEmpty {
                    // Use cached participants when CloudKit fetch returns empty
                    participants = cached
                } else {
                    participants = fetched
                }
                isLoading = false
            }
        }
    }

    private func changeRole(participant: SharedAlbumParticipant, to newRole: ParticipantRole) {
        isProcessing = true
        Task {
            do {
                try await appState.sharedAlbumManager.changeParticipantRole(
                    album: album,
                    participantId: participant.id,
                    newRole: newRole
                )

                // Update local state
                await MainActor.run {
                    if let index = participants.firstIndex(where: { $0.id == participant.id }) {
                        participants[index].role = newRole
                    }
                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func removeParticipant(_ participant: SharedAlbumParticipant) {
        isProcessing = true
        Task {
            do {
                try await appState.sharedAlbumManager.removeParticipant(
                    album: album,
                    participantId: participant.id
                )

                // Update local state
                await MainActor.run {
                    participants.removeAll { $0.id == participant.id }

                    // Update album participant count
                    var updatedAlbum = album
                    updatedAlbum.participantCount = participants.count
                    appState.updateSharedAlbum(updatedAlbum)

                    isProcessing = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isProcessing = false
                }
            }
        }
    }

    private func showShareSheet() {
        appState.sharedAlbumManager.prepareSharingController(for: album) { controller in
            DispatchQueue.main.async {
                guard let controller = controller else {
                    errorMessage = "Could not prepare sharing. Please try again."
                    return
                }
                sharingController = controller
                showSharingSheet = true
            }
        }
    }
}

// MARK: - Participant Row

struct ParticipantRow: View {
    @Environment(\.themePalette) private var palette

    let participant: SharedAlbumParticipant
    let isCurrentUser: Bool
    let canManage: Bool
    let onRoleTapped: () -> Void
    let onRemoveTapped: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ParticipantAvatar(
                initials: participant.avatarInitials ?? participant.displayName.prefix(2).uppercased(),
                isAdmin: participant.role == .admin
            )

            // Info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(participant.displayName)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                }

                HStack(spacing: 8) {
                    RoleBadge(role: participant.role)

                    if participant.acceptanceStatus == .pending {
                        Text("Pending")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
            }

            Spacer()

            // Actions
            if canManage {
                Menu {
                    Button {
                        onRoleTapped()
                    } label: {
                        Label("Change Role", systemImage: "person.fill.questionmark")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onRemoveTapped()
                    } label: {
                        Label("Remove", systemImage: "person.fill.xmark")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.title3)
                        .foregroundColor(palette.textSecondary)
                }
                .accessibilityLabel("Participant options")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Participant Avatar

struct ParticipantAvatar: View {
    @Environment(\.themePalette) private var palette

    let initials: String
    let isAdmin: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: isAdmin ? [palette.accent, palette.accent.opacity(0.7)] : [palette.textSecondary, palette.textSecondary.opacity(0.7)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 44, height: 44)

            Text(String(initials.prefix(2)))
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)

            if isAdmin {
                Image(systemName: "crown.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.yellow)
                    .offset(x: 14, y: -14)
            }
        }
    }
}

// MARK: - Role Badge

struct RoleBadge: View {
    @Environment(\.themePalette) private var palette

    let role: ParticipantRole

    var backgroundColor: Color {
        switch role {
        case .admin: return palette.accent
        case .member: return .green
        case .viewer: return palette.textTertiary
        }
    }

    var body: some View {
        Text(role.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(backgroundColor)
            .cornerRadius(4)
            .accessibilityLabel("\(role.displayName) role")
    }
}

// MARK: - Role Selection Sheet

struct RoleSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let participant: SharedAlbumParticipant
    let onRoleSelected: (ParticipantRole) -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Change Role for \(participant.displayName)")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                    .padding(.top)

                VStack(spacing: 12) {
                    ForEach([ParticipantRole.member, ParticipantRole.viewer], id: \.self) { role in
                        Button {
                            onRoleSelected(role)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(role.displayName)
                                        .font(.headline)
                                        .foregroundColor(palette.textPrimary)

                                    Text(role.description)
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()

                                if role == participant.role {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(palette.cardBackground)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(
                                                role == participant.role ? palette.accent : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal)

                Spacer()
            }
            .background(palette.background)
            .navigationTitle("Select Role")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
