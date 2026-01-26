//
//  SharedAlbumViews.swift
//  Sonidea
//
//  UI components for Shared Albums feature.
//

import SwiftUI
import CloudKit

// MARK: - Create Shared Album Flow

struct CreateSharedAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var albumName = ""
    @State private var showSafetyGate = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "person.2.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.blue, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                .padding(.top, 20)

                // Title and description
                VStack(spacing: 8) {
                    Text("Create Shared Album")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("Share recordings with friends, collaborators, or bandmates. Everyone can add and listen.")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Album name input
                VStack(alignment: .leading, spacing: 8) {
                    Text("Album Name")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    TextField("My Shared Album", text: $albumName)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 24)

                // Error message
                if let error = errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Spacer()

                // Continue button
                Button {
                    if albumName.trimmingCharacters(in: .whitespaces).isEmpty {
                        errorMessage = "Please enter an album name"
                    } else {
                        showSafetyGate = true
                    }
                } label: {
                    HStack {
                        Text("Continue")
                        Image(systemName: "arrow.right")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(albumName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }
            }
            .sheet(isPresented: $showSafetyGate) {
                SharedAlbumSafetyGateSheet(
                    albumName: albumName,
                    onConfirm: {
                        createSharedAlbum()
                    }
                )
            }
        }
    }

    private func createSharedAlbum() {
        isCreating = true
        Task {
            do {
                let album = try await appState.sharedAlbumManager.createSharedAlbum(name: albumName.trimmingCharacters(in: .whitespaces))
                appState.addSharedAlbum(album)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

// MARK: - Safety Gate Modal

struct SharedAlbumSafetyGateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let albumName: String
    let onConfirm: () -> Void

    @State private var understandsAddDelete = false
    @State private var trustsParticipants = false

    private var canContinue: Bool {
        understandsAddDelete && trustsParticipants
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.2))
                            .frame(width: 72, height: 72)

                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 20)

                    // Title
                    Text("Before You Share")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    // Warning bullets
                    VStack(alignment: .leading, spacing: 16) {
                        SafetyBulletRow(
                            icon: "person.2.fill",
                            text: "Anyone in this shared album can add and delete recordings."
                        )

                        SafetyBulletRow(
                            icon: "hand.raised.fill",
                            text: "Only share with people you trust."
                        )

                        SafetyBulletRow(
                            icon: "eye.fill",
                            text: "Recordings added here are visible to all participants."
                        )

                        SafetyBulletRow(
                            icon: "trash.fill",
                            text: "If someone deletes a recording, it may be removed for everyone."
                        )
                    }
                    .padding(.horizontal, 24)

                    Divider()
                        .padding(.horizontal, 24)

                    // Acknowledgment checkboxes
                    VStack(spacing: 16) {
                        AcknowledgmentRow(
                            isChecked: $understandsAddDelete,
                            text: "I understand participants can add/delete recordings"
                        )

                        AcknowledgmentRow(
                            isChecked: $trustsParticipants,
                            text: "I will only share with people I trust"
                        )
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 40)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            dismiss()
                            onConfirm()
                        } label: {
                            Text("Create \"\(albumName)\"")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(canContinue ? Color.blue : Color.gray)
                                .cornerRadius(12)
                        }
                        .disabled(!canContinue)

                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(palette.textSecondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled()  // Force user to make a choice
        }
    }
}

// MARK: - Safety Bullet Row

struct SafetyBulletRow: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(.orange)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Acknowledgment Row

struct AcknowledgmentRow: View {
    @Environment(\.themePalette) private var palette

    @Binding var isChecked: Bool
    let text: String

    var body: some View {
        Button {
            isChecked.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.square.fill" : "square")
                    .font(.system(size: 22))
                    .foregroundColor(isChecked ? .blue : palette.textSecondary)

                Text(text)
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Add Recording Consent Sheet

struct AddToSharedAlbumConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let album: Album
    let onConfirm: () -> Void

    @State private var dontAskAgain = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text("Share Recording?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("This recording will be shared with")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)

                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.blue)
                        Text("\(album.name)")
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                        Text("(\(album.participantCount) people)")
                            .foregroundColor(palette.textSecondary)
                    }
                    .font(.subheadline)
                }

                // Recording preview
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(palette.accent)
                        .frame(width: 44, height: 44)
                        .background(palette.cardBackground)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title)
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()
                }
                .padding()
                .background(palette.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal, 24)

                // Info text
                Text("Participants can play, add, and delete recordings in this shared album.")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                // Don't ask again toggle
                Toggle(isOn: $dontAskAgain) {
                    Text("Don't ask again for this album")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        if dontAskAgain {
                            // Save preference for this album
                            // This would be handled by AppState
                        }
                        dismiss()
                        onConfirm()
                    } label: {
                        Text("Share")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.blue)
                            .cornerRadius(12)
                    }

                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Delete from Shared Album Confirmation

struct DeleteFromSharedAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let album: Album
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.red.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "trash.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.red)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text("Delete for Everyone?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("This recording will be removed from")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)

                    HStack(spacing: 6) {
                        Image(systemName: "person.2.fill")
                            .foregroundColor(.blue)
                        Text(album.name)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                    }
                    .font(.subheadline)
                }

                // Recording preview
                HStack(spacing: 12) {
                    Image(systemName: "waveform")
                        .font(.title2)
                        .foregroundColor(.red)
                        .frame(width: 44, height: 44)
                        .background(palette.cardBackground)
                        .cornerRadius(8)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(recording.title)
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()
                }
                .padding()
                .background(palette.cardBackground)
                .cornerRadius(12)
                .padding(.horizontal, 24)

                // Warning text
                VStack(spacing: 8) {
                    Text("This action affects all participants.")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.red)

                    Text("Anyone in this shared album can delete recordings.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        dismiss()
                        onConfirm()
                    } label: {
                        Text("Delete for Everyone")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.red)
                            .cornerRadius(12)
                    }

                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Shared Album Badge

struct SharedAlbumBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 10))
            Text("Shared")
                .font(.system(size: 10, weight: .medium))
        }
        .foregroundColor(.white)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            LinearGradient(
                colors: [.blue, .purple],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(4)
    }
}

// MARK: - Shared Album Header Banner

struct SharedAlbumBanner: View {
    @Environment(\.themePalette) private var palette

    let album: Album

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 16))
                .foregroundColor(.blue)

            VStack(alignment: .leading, spacing: 2) {
                Text("Shared Album")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)

                Text("\(album.participantCount) participant\(album.participantCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()

            if album.isOwner {
                Text("Owner")
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.1),
                    Color.purple.opacity(0.05)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [.blue.opacity(0.3), .purple.opacity(0.3)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    lineWidth: 1
                )
        )
        .cornerRadius(12)
    }
}

// MARK: - Leave Shared Album Sheet

struct LeaveSharedAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album

    @State private var isLeaving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text("Leave Shared Album?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("You will no longer have access to recordings in \"\(album.name)\".")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Info
                VStack(alignment: .leading, spacing: 12) {
                    SharedAlbumInfoRow(icon: "xmark.circle", text: "You'll lose access to all recordings", color: .red)
                    SharedAlbumInfoRow(icon: "arrow.counterclockwise", text: "You can be re-invited by the owner", color: .blue)
                    SharedAlbumInfoRow(icon: "person.2", text: "Other participants won't be affected", color: .green)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        leaveAlbum()
                    } label: {
                        HStack {
                            if isLeaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Leave Album")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(isLeaving)

                    Button("Cancel") {
                        dismiss()
                    }
                    .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func leaveAlbum() {
        isLeaving = true
        Task {
            do {
                try await appState.sharedAlbumManager.leaveSharedAlbum(album)
                appState.removeSharedAlbum(album)
                dismiss()
            } catch {
                // Handle error
            }
            isLeaving = false
        }
    }
}

// MARK: - Shared Album Info Row Helper

struct SharedAlbumInfoRow: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Shared Album Row (for album list)

struct SharedAlbumRow: View {
    @Environment(\.themePalette) private var palette

    let album: Album
    let recordingCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // Album icon with glow effect
            ZStack {
                // Glow effect
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.3), .clear],
                            center: .center,
                            startRadius: 0,
                            endRadius: 24
                        )
                    )
                    .frame(width: 48, height: 48)

                // Icon
                Image(systemName: "folder.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            // Album info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(album.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)

                    SharedAlbumBadge()
                }

                HStack(spacing: 8) {
                    Text("\(recordingCount) recording\(recordingCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)

                    Text("•")
                        .foregroundColor(palette.textTertiary)

                    HStack(spacing: 2) {
                        Image(systemName: "person.2")
                            .font(.caption2)
                        Text("\(album.participantCount)")
                    }
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
        }
        .padding(.vertical, 4)
    }
}
