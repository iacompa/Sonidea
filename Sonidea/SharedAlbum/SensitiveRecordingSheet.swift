//
//  SensitiveRecordingSheet.swift
//  Sonidea
//
//  Sensitive content handling for shared album recordings.
//  Includes mark as sensitive, playback confirmation, and admin approval UI.
//

import SwiftUI

// MARK: - Mark as Sensitive Sheet

struct MarkSensitiveSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem
    let album: Album
    let onConfirm: (Bool) -> Void

    @State private var isSaving = false

    private var isSensitive: Bool {
        sharedInfo.isSensitive
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: isSensitive ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text(isSensitive ? "Remove Sensitive Mark?" : "Mark as Sensitive?")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text(isSensitive
                         ? "This recording will no longer require a warning before playback"
                         : "Participants will see a warning before playing this recording")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Recording preview
                RecordingPreviewCard(recording: recording)
                    .padding(.horizontal, 24)

                if !isSensitive {
                    // Info about sensitive mode
                    VStack(alignment: .leading, spacing: 12) {
                        SensitiveInfoRow(
                            icon: "exclamationmark.triangle",
                            text: "Shows a warning before playback"
                        )

                        SensitiveInfoRow(
                            icon: "eye.slash",
                            text: "Helps protect unexpected sensitive content"
                        )

                        if album.sharedSettings?.requireSensitiveApproval == true {
                            SensitiveInfoRow(
                                icon: "person.badge.shield.checkmark",
                                text: "Requires admin approval before others can listen",
                                highlight: true
                            )
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        isSaving = true
                        onConfirm(!isSensitive)
                        dismiss()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text(isSensitive ? "Remove Sensitive Mark" : "Mark as Sensitive")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.orange)
                        .cornerRadius(12)
                    }
                    .disabled(isSaving)

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

struct SensitiveInfoRow: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let text: String
    var highlight: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(highlight ? .blue : .orange)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundColor(highlight ? palette.accent : palette.textSecondary)
        }
    }
}

// MARK: - Sensitive Playback Confirmation

struct SensitivePlaybackConfirmation: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem
    let onConfirm: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "eye.slash.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text("Sensitive Content")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("This recording has been marked as containing sensitive content")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Recording preview
                RecordingPreviewCard(recording: recording)
                    .padding(.horizontal, 24)

                // Creator info
                HStack(spacing: 8) {
                    Text("Shared by")
                        .foregroundColor(palette.textSecondary)
                    Text(sharedInfo.creatorDisplayName)
                        .fontWeight(.medium)
                        .foregroundColor(palette.accent)
                }
                .font(.subheadline)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        onConfirm()
                        dismiss()
                    } label: {
                        Label("Play Anyway", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.orange)
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

// MARK: - Admin Approval Sheet

struct SensitiveApprovalSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem
    let album: Album
    let onApprove: () -> Void
    let onReject: () -> Void

    @State private var isProcessing = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.blue)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text("Approval Required")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("This sensitive recording needs admin approval before other participants can listen")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Recording preview
                RecordingPreviewCard(recording: recording)
                    .padding(.horizontal, 24)

                // Creator info
                VStack(spacing: 8) {
                    HStack {
                        Text("Submitted by")
                            .foregroundColor(palette.textSecondary)
                        Text(sharedInfo.creatorDisplayName)
                            .fontWeight(.medium)
                            .foregroundColor(palette.accent)
                    }

                    Text(relativeDate(from: sharedInfo.createdAt))
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                }
                .font(.subheadline)

                // Info
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Approve: All participants can listen")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.red)
                        Text("Reject: Recording remains hidden from others")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Button {
                            isProcessing = true
                            onReject()
                            dismiss()
                        } label: {
                            Label("Reject", systemImage: "xmark")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.red)
                                .cornerRadius(12)
                        }
                        .disabled(isProcessing)

                        Button {
                            isProcessing = true
                            onApprove()
                            dismiss()
                        } label: {
                            HStack {
                                if isProcessing {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Label("Approve", systemImage: "checkmark")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.green)
                            .cornerRadius(12)
                        }
                        .disabled(isProcessing)
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

    private func relativeDate(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Recording Preview Card

struct RecordingPreviewCard: View {
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem

    var body: some View {
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
                    .lineLimit(1)

                Text(recording.formattedDuration)
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            Spacer()
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Pending Approvals List (for Admin)

struct PendingApprovalsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album
    let pendingRecordings: [(recording: RecordingItem, sharedInfo: SharedRecordingItem)]

    @State private var selectedRecording: (recording: RecordingItem, sharedInfo: SharedRecordingItem)?
    @State private var showApprovalSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if pendingRecordings.isEmpty {
                    emptyStateView
                } else {
                    pendingList
                }
            }
            .background(palette.background)
            .navigationTitle("Pending Approvals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }
            }
            .sheet(isPresented: $showApprovalSheet) {
                if let selected = selectedRecording {
                    SensitiveApprovalSheet(
                        recording: selected.recording,
                        sharedInfo: selected.sharedInfo,
                        album: album,
                        onApprove: {
                            approveRecording(selected.sharedInfo)
                        },
                        onReject: {
                            rejectRecording(selected.sharedInfo)
                        }
                    )
                }
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.green)

            Text("All Caught Up")
                .font(.headline)
                .foregroundColor(palette.textSecondary)

            Text("No recordings pending approval")
                .font(.subheadline)
                .foregroundColor(palette.textTertiary)
        }
    }

    private var pendingList: some View {
        List {
            ForEach(pendingRecordings, id: \.recording.id) { item in
                Button {
                    selectedRecording = item
                    showApprovalSheet = true
                } label: {
                    PendingApprovalRow(
                        recording: item.recording,
                        sharedInfo: item.sharedInfo
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
    }

    private func approveRecording(_ sharedInfo: SharedRecordingItem) {
        Task {
            try? await appState.sharedAlbumManager.approveSensitiveRecording(
                recording: sharedInfo,
                approved: true,
                album: album
            )
        }
    }

    private func rejectRecording(_ sharedInfo: SharedRecordingItem) {
        Task {
            try? await appState.sharedAlbumManager.approveSensitiveRecording(
                recording: sharedInfo,
                approved: false,
                album: album
            )
        }
    }
}

struct PendingApprovalRow: View {
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem

    var body: some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 44, height: 44)

                Image(systemName: "eye.slash.fill")
                    .foregroundColor(.orange)
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(palette.textPrimary)

                HStack(spacing: 8) {
                    Text("by \(sharedInfo.creatorDisplayName)")
                        .foregroundColor(palette.accent)

                    Text(recording.formattedDuration)
                        .foregroundColor(palette.textSecondary)
                }
                .font(.caption)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
        }
        .padding(.vertical, 4)
    }
}
