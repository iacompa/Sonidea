//
//  SharedAlbumViews.swift
//  Sonidea
//
//  UI components for Shared Albums feature.
//

import SwiftUI
import CloudKit
import MapKit

// MARK: - Create Shared Album Flow

struct CreateSharedAlbumSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var albumName = ""
    @State private var showSafetyGate = false
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var iCloudAvailable = true
    @State private var proUpgradeContext: ProFeatureContext?
    @State private var showTipJar = false

    var body: some View {
        NavigationStack {
            // Pro feature guard - show upgrade prompt if user doesn't have access
            if !appState.supportManager.canUseProFeatures {
                Color.clear.onAppear { proUpgradeContext = .sharedAlbums }
            } else {
                createAlbumContent
            }
        }
        .sheet(item: $proUpgradeContext) { context in
            ProUpgradeSheet(
                context: context,
                onViewPlans: {
                    proUpgradeContext = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        showTipJar = true
                    }
                },
                onDismiss: {
                    proUpgradeContext = nil
                    dismiss()
                }
            )
            .environment(\.themePalette, palette)
        }
        .sheet(isPresented: $showTipJar) {
            TipJarView()
        }
    }

    private var createAlbumContent: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [palette.accent.opacity(0.3), palette.accent.opacity(0.15)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 80, height: 80)

                    Image(systemName: "person.2.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [palette.accent, palette.accent.opacity(0.7)],
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

                // iCloud availability warning
                if !iCloudAvailable {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.icloud")
                            .foregroundColor(.orange)
                        Text("Sign in to iCloud to create shared albums")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                    .padding(.horizontal)
                }

                Spacer()

                // Continue button
                Button {
                    errorMessage = nil
                    let trimmed = albumName.trimmingCharacters(in: .whitespaces)
                    if trimmed.isEmpty {
                        errorMessage = "Please enter an album name"
                    } else if trimmed.count > 50 {
                        errorMessage = "Album name must be 50 characters or less"
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
                            colors: [palette.accent, palette.accent.opacity(0.7)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .disabled(albumName.trimmingCharacters(in: .whitespaces).isEmpty || isCreating || !iCloudAvailable)
            }
            .background(palette.background)
            .onChange(of: albumName) {
                if albumName.count > 50 {
                    albumName = String(albumName.prefix(50))
                }
            }
            .task {
                iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
            }
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
                    isCreating: $isCreating,
                    onConfirm: {
                        createSharedAlbum()
                    }
                )
            }
            .interactiveDismissDisabled(isCreating)
    }

    private func createSharedAlbum() {
        isCreating = true
        Task {
            do {
                let album = try await appState.sharedAlbumManager.createSharedAlbum(name: albumName.trimmingCharacters(in: .whitespaces))
                appState.addSharedAlbum(album)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
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
    @Binding var isCreating: Bool
    let onConfirm: () -> Void

    @State private var understandsAddDelete = false
    @State private var trustsParticipants = false
    @State private var safetyGateError: String?

    private var canContinue: Bool {
        understandsAddDelete && trustsParticipants && !isCreating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Warning icon
                    ZStack {
                        Circle()
                            .fill(palette.accent.opacity(0.15))
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

                    // Error message shown directly in the safety gate
                    if let error = safetyGateError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .padding(.horizontal, 24)
                    }

                    Spacer(minLength: 40)

                    // Buttons
                    VStack(spacing: 12) {
                        Button {
                            safetyGateError = nil
                            onConfirm()
                            dismiss()
                        } label: {
                            HStack(spacing: 8) {
                                if isCreating {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Create \"\(albumName)\"")
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canContinue ? palette.accent : palette.textTertiary)
                            .cornerRadius(12)
                        }
                        .disabled(!canContinue)

                        Button("Cancel") {
                            dismiss()
                        }
                        .foregroundColor(palette.textSecondary)
                        .disabled(isCreating)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .background(palette.background)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isCreating)  // Prevent dismiss while creating
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
                    .foregroundColor(isChecked ? palette.accent : palette.textSecondary)

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
                        .fill(palette.accent.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 28))
                        .foregroundColor(palette.accent)
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
                            .foregroundColor(palette.accent)
                        Text("\(album.name)")
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                        onConfirm()
                        dismiss()
                    } label: {
                        Text("Share")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(palette.accent)
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
                            .foregroundColor(palette.accent)
                        Text(album.name)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)
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
                        onConfirm()
                        dismiss()
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
        HStack(spacing: 3) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 8, weight: .bold))

            Text("SHARED")
                .font(.system(size: 9, weight: .bold))
        }
        .foregroundColor(.sharedAlbumGold)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(Color.sharedAlbumGold.opacity(0.12))
                .shadow(color: .sharedAlbumGold.opacity(0.3), radius: 4, x: 0, y: 0)
        )
        .overlay(
            Capsule()
                .stroke(Color.sharedAlbumGold.opacity(0.5), lineWidth: 1)
        )
        .accessibilityHidden(true)
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
                .foregroundColor(palette.accent)

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
                    .foregroundColor(palette.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.accent.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding()
        .background(
            LinearGradient(
                colors: [
                    palette.accent.opacity(0.1),
                    palette.accent.opacity(0.05)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    LinearGradient(
                        colors: [palette.accent.opacity(0.3), palette.accent.opacity(0.15)],
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
    @State private var leaveError: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(palette.accent.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 28))
                        .foregroundColor(palette.accent)
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
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                // Info
                VStack(alignment: .leading, spacing: 12) {
                    SharedAlbumInfoRow(icon: "xmark.circle", text: "You'll lose access to all recordings", color: .red)
                    SharedAlbumInfoRow(icon: "arrow.counterclockwise", text: "You can be re-invited by the owner", color: palette.accent)
                    SharedAlbumInfoRow(icon: "person.2", text: "Other participants won't be affected", color: .green)
                }
                .padding(.horizontal, 24)

                if let error = leaveError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

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
            .interactiveDismissDisabled(isLeaving)
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
                leaveError = error.localizedDescription
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
                            colors: [palette.accent.opacity(0.3), .clear],
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
                            colors: [palette.accent, palette.accent.opacity(0.7)],
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

// MARK: - Shared Album Detail View with Tabs

enum SharedAlbumTab: String, CaseIterable {
    case recordings
    case activity
    case map

    var title: String {
        switch self {
        case .recordings: return "Recordings"
        case .activity: return "Activity"
        case .map: return "Map"
        }
    }

    var icon: String {
        switch self {
        case .recordings: return "waveform"
        case .activity: return "clock.arrow.circlepath"
        case .map: return "map"
        }
    }
}

struct SharedAlbumDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album

    @State private var selectedTab: SharedAlbumTab = .recordings
    @State private var recordings: [RecordingItem] = []
    @State private var sharedRecordingInfos: [UUID: SharedRecordingItem] = [:]
    @State private var activityEvents: [SharedAlbumActivityEvent] = []
    @State private var trashItems: [SharedAlbumTrashItem] = []
    @State private var isLoading = true

    // Sheets
    @State private var showSettings = false
    @State private var showParticipants = false
    @State private var showTrash = false
    @State private var showActivityFull = false
    @State private var showMap = false
    @State private var albumSettings: SharedAlbumSettings = .default
    @State private var selectedRecording: RecordingItem?
    @State private var selectedSharedInfo: SharedRecordingItem?
    @State private var currentUserId: String?
    @State private var shareIsStale = false
    @State private var showLeaveAlbum = false
    @State private var showAddRecordingInfo = false
    @State private var showProRequired = false
    @State private var showRenameAlert = false
    @State private var renameText = ""

    private var recordingsWithLocation: [(recording: RecordingItem, sharedInfo: SharedRecordingItem)] {
        recordings.compactMap { recording in
            guard let info = sharedRecordingInfos[recording.id], info.hasSharedLocation else { return nil }
            return (recording, info)
        }
    }

    /// Reactive lookup so the navigation title updates after rename
    private var currentAlbum: Album {
        appState.albums.first(where: { $0.id == album.id }) ?? album
    }

    var body: some View {
        NavigationStack {
            Group {
                if !appState.supportManager.canUseProFeatures {
                    // Pro required - show blocking message
                    proRequiredView
                } else {
                    mainContent
                }
            }
            .background(palette.background)
            .navigationTitle(currentAlbum.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                if appState.supportManager.canUseProFeatures {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Menu {
                            if album.canRename {
                                Button {
                                    renameText = currentAlbum.name
                                    showRenameAlert = true
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                            }

                            Button {
                                showParticipants = true
                            } label: {
                                Label("Participants", systemImage: "person.2")
                            }

                            if album.canEditSettings {
                                Button {
                                    showSettings = true
                                } label: {
                                    Label("Settings", systemImage: "gearshape")
                                }
                            }

                            Button {
                                showTrash = true
                            } label: {
                                Label("Trash (\(trashItems.count))", systemImage: "trash")
                            }

                            if !album.isOwner {
                                Divider()

                                Button(role: .destructive) {
                                    showLeaveAlbum = true
                                } label: {
                                    Label("Leave Album", systemImage: "rectangle.portrait.and.arrow.right")
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .foregroundColor(palette.accent)
                        }
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: { loadData() }) {
                SharedAlbumSettingsView(album: album, settings: $albumSettings)
            }
            .sheet(isPresented: $showParticipants, onDismiss: { loadData() }) {
                SharedAlbumParticipantsView(album: album)
            }
            .sheet(isPresented: $showTrash, onDismiss: { loadData() }) {
                SharedAlbumTrashView(album: album)
            }
            .sheet(isPresented: $showActivityFull) {
                SharedAlbumActivityView(album: album)
            }
            .sheet(isPresented: $showMap) {
                SharedAlbumMapView(album: album, recordings: recordingsWithLocation)
            }
            .sheet(isPresented: $showLeaveAlbum) {
                LeaveSharedAlbumSheet(album: album)
            }
            .alert("Album No Longer Available", isPresented: $shareIsStale) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("The owner has stopped sharing this album. It will be removed from your library.")
            }
            .alert("Add Recordings", isPresented: $showAddRecordingInfo) {
                Button("OK") {}
            } message: {
                Text("To add a recording, go to your recordings list and move a recording into this shared album.")
            }
            .alert("Rename Album", isPresented: $showRenameAlert) {
                TextField("Album name", text: $renameText)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    let trimmed = renameText.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty, trimmed != currentAlbum.name else { return }
                    if appState.renameAlbum(currentAlbum, to: trimmed) {
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                    }
                }
            } message: {
                Text("Enter a new name for this shared album.")
            }
            .sheet(item: $selectedRecording) { recording in
                SharedRecordingDetailView(
                    recording: recording,
                    sharedInfo: selectedSharedInfo,
                    album: album
                )
                .environment(appState)
                .environment(\.themePalette, palette)
            }
            .onAppear {
                loadData()
            }
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            // Album header
            SharedAlbumBanner(album: album)
                .padding(.horizontal)
                .padding(.top, 8)

            // Tab bar
            tabBar

            // Tab content
            tabContent
        }
    }

    private var proRequiredView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 48))
                .foregroundColor(palette.accent)

            Text("Pro Feature Required")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(palette.textPrimary)

            Text("Shared Albums are a Pro feature. Subscribe to access shared albums and collaborate with others.")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                dismiss()
            } label: {
                Text("Go Back")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(palette.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(SharedAlbumTab.allCases, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16))

                        Text(tab.title)
                            .font(.caption)
                    }
                    .foregroundColor(selectedTab == tab ? palette.accent : palette.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        VStack {
                            Spacer()
                            if selectedTab == tab {
                                Rectangle()
                                    .fill(palette.accent)
                                    .frame(height: 2)
                            }
                        }
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .background(palette.cardBackground)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .recordings:
            recordingsTab
        case .activity:
            activityTab
        case .map:
            mapTab
        }
    }

    private var recordingsTab: some View {
        Group {
            if isLoading {
                ProgressView("Loading recordings...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if recordings.isEmpty {
                VStack(spacing: 12) {
                    SharedAlbumEmptyState(
                        isCurrentUserAdmin: album.currentUserRole == .admin,
                        onAddRecording: {
                            showAddRecordingInfo = true
                        }
                    )

                    Text("Share the invite link to add collaborators")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    // Header stats
                    SharedRecordingListHeader(
                        totalCount: recordings.count,
                        myCount: recordings.filter { sharedRecordingInfos[$0.id]?.creatorId == currentUserId }.count,
                        othersCount: recordings.filter { sharedRecordingInfos[$0.id]?.creatorId != currentUserId }.count
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)

                    // Recordings
                    ForEach(recordings) { recording in
                        SharedRecordingRow(
                            recording: recording,
                            sharedInfo: sharedRecordingInfos[recording.id],
                            isCurrentUserRecording: sharedRecordingInfos[recording.id]?.creatorId == currentUserId,
                            onTap: {
                                // Set sharedInfo BEFORE recording to avoid showing stale data
                                // (selectedRecording triggers the sheet)
                                selectedSharedInfo = sharedRecordingInfos[recording.id]
                                selectedRecording = recording
                            }
                        )
                    }
                }
                .listStyle(.plain)
            }
        }
    }

    private var activityTab: some View {
        Group {
            if activityEvents.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundColor(palette.textTertiary)

                    Text("No Activity Yet")
                        .font(.headline)
                        .foregroundColor(palette.textSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(activityEvents.prefix(20)) { event in
                            ActivityEventRow(event: event)
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                            if event.id != activityEvents.prefix(20).last?.id {
                                Divider()
                                    .padding(.leading, 60)
                            }
                        }

                        if activityEvents.count > 20 {
                            Button("View All Activity") {
                                showActivityFull = true
                            }
                            .padding()
                        }
                    }
                }
            }
        }
    }

    private var mapTab: some View {
        Group {
            if recordingsWithLocation.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "map")
                        .font(.system(size: 48))
                        .foregroundColor(palette.textTertiary)

                    Text("No Location Data")
                        .font(.headline)
                        .foregroundColor(palette.textSecondary)

                    Text("Recordings with shared locations will appear here")
                        .font(.subheadline)
                        .foregroundColor(palette.textTertiary)
                        .multilineTextAlignment(.center)

                    Button("Open Full Map") {
                        showMap = true
                    }
                    .buttonStyle(.bordered)
                }
                .padding()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    // Mini map preview
                    ZStack(alignment: .bottomTrailing) {
                        Map {
                            ForEach(recordingsWithLocation, id: \.recording.id) { item in
                                if let lat = item.sharedInfo.sharedLatitude,
                                   let lon = item.sharedInfo.sharedLongitude {
                                    Annotation(
                                        item.recording.title,
                                        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                        anchor: .bottom
                                    ) {
                                        Circle()
                                            .fill(palette.accent)
                                            .frame(width: 12, height: 12)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 2)
                                            )
                                    }
                                }
                            }
                        }
                        .mapStyle(.standard(elevation: .realistic))
                        .frame(height: 200)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .allowsHitTesting(false)

                        // Expand button
                        Button {
                            showMap = true
                        } label: {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .padding(8)
                        }
                    }
                    .padding()

                    // Location list
                    List {
                        ForEach(recordingsWithLocation, id: \.recording.id) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.sharedInfo.locationSharingMode == .approximate ? "location.circle" : "location.fill")
                                    .foregroundColor(palette.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.recording.title)
                                        .font(.subheadline)
                                        .foregroundColor(palette.textPrimary)

                                    Text(item.sharedInfo.sharedPlaceName ?? "Unknown location")
                                        .font(.caption)
                                        .foregroundColor(palette.textSecondary)
                                }

                                Spacer()

                                Text(item.sharedInfo.creatorInitials)
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                                    .frame(width: 24, height: 24)
                                    .background(Circle().fill(palette.accent))
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
    }

    private func loadData() {
        isLoading = true
        Task {
            defer {
                Task { @MainActor in
                    isLoading = false
                }
            }

            // Validate share still exists (non-owner)
            #if DEBUG
            let skipValidation = appState.isSharedAlbumsDebugMode
            #else
            let skipValidation = false
            #endif
            if !album.isOwner && !skipValidation {
                let valid = await appState.sharedAlbumManager.validateShareExists(for: album)
                if !valid {
                    await MainActor.run {
                        shareIsStale = true
                    }
                    return
                }
            }

            // Fetch current user ID
            let userId = await appState.sharedAlbumManager.getCurrentUserId()

            // Load recordings
            let albumRecordings = appState.recordings(in: album)

            #if DEBUG
            let useDebugMode = appState.isSharedAlbumsDebugMode
            #else
            let useDebugMode = false
            #endif

            if useDebugMode {
                #if DEBUG
                await MainActor.run {
                    currentUserId = userId ?? "user_001"  // Debug fallback
                    recordings = albumRecordings
                    // Copy from appState cache
                    for recording in albumRecordings {
                        if let info = appState.sharedRecordingInfoCache[recording.id] {
                            sharedRecordingInfos[recording.id] = info
                        }
                    }
                    activityEvents = appState.debugMockActivityFeed()
                    trashItems = appState.debugMockTrashItems()
                    albumSettings = album.sharedSettings ?? .default
                }
                #endif
            } else {
                // Load shared recording info (creator attribution, location, etc.)
                let sharedInfos = await appState.sharedAlbumManager.fetchSharedRecordingInfo(for: album)

                // Load activity
                let activity = await appState.sharedAlbumManager.fetchActivityFeed(for: album, limit: 50)

                // Load trash
                let trash = await appState.sharedAlbumManager.fetchTrashItems(for: album)

                // Load settings
                let settings = await appState.sharedAlbumManager.fetchAlbumSettings(for: album)

                await MainActor.run {
                    currentUserId = userId
                    recordings = albumRecordings
                    sharedRecordingInfos = sharedInfos
                    let localEvents = appState.localActivityEvents.filter { $0.albumId == album.id }
                    activityEvents = (activity + localEvents).sorted { $0.timestamp > $1.timestamp }
                    trashItems = trash
                    albumSettings = settings ?? .default
                }
            }
        }
    }
}

// MARK: - Shared Recording Detail View

struct SharedRecordingDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem?
    let album: Album

    @State private var playback = PlaybackEngine()
    @State private var showDemoAlert = false
    @State private var isLoadingAudio = false
    @State private var audioLoadError: String?
    @State private var comments: [SharedAlbumComment] = []
    @State private var newCommentText = ""
    @State private var isSubmittingComment = false
    @State private var commentError: String?
    @State private var allowDownload: Bool = false
    @State private var isTogglingDownload = false
    @State private var isRevertingDownload = false
    @State private var showDisableDownloadAlert = false
    @State private var currentUserId: String?

    private var isCreator: Bool {
        guard let userId = currentUserId, let info = sharedInfo else { return false }
        return info.creatorId == userId
    }

    private var canDownload: Bool {
        isCreator || (sharedInfo?.allowDownload ?? false)
    }

    private var isDemoRecording: Bool {
        #if DEBUG
        return appState.isSharedAlbumsDebugMode && !FileManager.default.fileExists(atPath: recording.fileURL.path)
        #else
        return false
        #endif
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Recording artwork/icon
                    recordingHeader

                    // Info section
                    infoSection

                    // Creator info
                    if let info = sharedInfo {
                        creatorSection(info: info)
                    }

                    // Download permission (only in shared albums)
                    if album.isShared, let info = sharedInfo {
                        downloadPermissionSection(info: info)
                    }

                    // Playback controls
                    playbackSection

                    // Badges
                    if let info = sharedInfo {
                        badgesSection(info: info)
                    }

                    // Location
                    if let info = sharedInfo, info.hasSharedLocation {
                        locationSection(info: info)
                    }

                    // Notes
                    if !recording.notes.isEmpty {
                        notesSection
                    }

                    // Comments (Pro feature)
                    if appState.supportManager.canUseProFeatures {
                        commentsSection
                    }
                }
                .padding()
            }
            .background(palette.background)
            .navigationTitle("Recording Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }
            }
            .onAppear {
                allowDownload = sharedInfo?.allowDownload ?? false
                Task {
                    currentUserId = await appState.sharedAlbumManager.getCurrentUserId()
                }
                if appState.supportManager.canUseProFeatures {
                    loadComments()
                }
            }
            .onDisappear {
                playback.stop()
            }
            .alert("Demo Recording", isPresented: $showDemoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This is a demo recording for testing purposes. Playback is not available for demo content.")
            }
            .alert("Download Permission", isPresented: $showDownloadPermissionInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Control whether others in this shared album can download your recording.\n\n• Stream only: Others can listen but not save a copy\n• Allow download: Others can save a local copy and export")
            }
            .alert("Disable Downloads?", isPresented: $showDisableDownloadAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Disable", role: .destructive) {
                    allowDownload = false
                    toggleDownload(false)
                }
            } message: {
                Text("Other participants will no longer be able to download this recording.")
            }
            .alert("Comment Error", isPresented: Binding(
                get: { commentError != nil },
                set: { if !$0 { commentError = nil } }
            )) {
                Button("OK") { commentError = nil }
            } message: {
                Text(commentError ?? "")
            }
        }
    }

    private var recordingHeader: some View {
        VStack(spacing: 16) {
            // Large icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [palette.accent.opacity(0.3), palette.accent.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 120, height: 120)

                Image(systemName: recording.displayIconSymbol)
                    .font(.system(size: 48))
                    .foregroundColor(palette.accent)

                // Demo badge
                if isDemoRecording {
                    VStack {
                        HStack {
                            Spacer()
                            Text("DEMO")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accent)
                                .cornerRadius(4)
                        }
                        Spacer()
                    }
                    .frame(width: 120, height: 120)
                    .padding(8)
                }
            }

            // Title
            Text(recording.title)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }

    private var infoSection: some View {
        HStack(spacing: 24) {
            InfoItem(
                icon: "clock",
                value: recording.formattedDuration,
                label: "Duration"
            )

            InfoItem(
                icon: "calendar",
                value: recording.createdAt.formatted(date: .abbreviated, time: .omitted),
                label: "Recorded"
            )

            if !recording.locationLabel.isEmpty {
                InfoItem(
                    icon: "location",
                    value: recording.locationLabel,
                    label: "Location"
                )
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    private func creatorSection(info: SharedRecordingItem) -> some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.2))
                    .frame(width: 44, height: 44)

                Text(info.creatorInitials)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(palette.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Shared by")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)

                Text(info.creatorDisplayName)
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
            }

            Spacer()

            if info.isVerified {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Verified")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    @State private var showDownloadPermissionInfo = false

    private func downloadPermissionSection(info: SharedRecordingItem) -> some View {
        VStack(spacing: 12) {
            if isCreator {
                // Creator sees a toggle to allow/disallow downloads
                HStack(spacing: 12) {
                    Image(systemName: allowDownload ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(allowDownload ? palette.accent : palette.textTertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Allow others to download")
                                .font(.subheadline)
                                .foregroundColor(palette.textPrimary)

                            Button {
                                showDownloadPermissionInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 12))
                                    .foregroundColor(palette.textSecondary)
                            }
                        }

                        Text(allowDownload ? "Others can save a local copy" : "Others can only stream")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()

                    if isTogglingDownload {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button {
                            if allowDownload {
                                // Toggling OFF — show confirmation first
                                showDisableDownloadAlert = true
                            } else {
                                // Toggling ON — apply immediately
                                allowDownload = true
                                toggleDownload(true)
                            }
                        } label: {
                            Image(systemName: allowDownload ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 28))
                                .foregroundColor(allowDownload ? palette.accent : palette.textTertiary)
                        }
                    }
                }
            } else {
                // Non-creator sees the current permission status
                HStack(spacing: 12) {
                    Image(systemName: info.allowDownload ? "arrow.down.circle.fill" : "arrow.down.circle")
                        .font(.title3)
                        .foregroundColor(info.allowDownload ? palette.accent : palette.textTertiary)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.allowDownload ? "Download available" : "Stream only")
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)

                        Text(info.allowDownload ? "Creator has enabled downloads" : "Creator has not enabled downloads")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    private func toggleDownload(_ allow: Bool) {
        guard let info = sharedInfo else { return }
        isTogglingDownload = true
        Task {
            do {
                try await appState.sharedAlbumManager.toggleDownloadPermission(
                    recordingId: info.recordingId,
                    album: album,
                    allow: allow
                )
                // Success - keep the new value
                await MainActor.run {
                    isTogglingDownload = false
                }
            } catch {
                // Revert on failure
                await MainActor.run {
                    allowDownload = !allow
                    isTogglingDownload = false
                }
            }
        }
    }

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Loading/error state
            if isLoadingAudio {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Loading audio...")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .padding()
            } else if let error = audioLoadError {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .padding()
            }

            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.textTertiary.opacity(0.3))
                            .frame(height: 4)

                        let progress = playback.duration > 0 ? playback.currentTime / playback.duration : 0
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.accent)
                            .frame(width: geometry.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(playback.currentTime))
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .monospacedDigit()

                    Spacer()

                    Text(formatTime(playback.duration > 0 ? playback.duration : recording.duration))
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            // Playback controls
            HStack(spacing: 32) {
                Button {
                    if isDemoRecording {
                        showDemoAlert = true
                    } else {
                        playback.skip(seconds: -15)
                    }
                } label: {
                    Image(systemName: "gobackward.15")
                        .font(.title2)
                        .foregroundColor(palette.textPrimary)
                }

                Button {
                    if isDemoRecording {
                        showDemoAlert = true
                    } else {
                        handlePlayPause()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 64, height: 64)

                        Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }

                Button {
                    if isDemoRecording {
                        showDemoAlert = true
                    } else {
                        playback.skip(seconds: 30)
                    }
                } label: {
                    Image(systemName: "goforward.30")
                        .font(.title2)
                        .foregroundColor(palette.textPrimary)
                }
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    private func handlePlayPause() {
        if playback.isPlaying {
            playback.pause()
        } else if playback.isLoaded {
            playback.play()
        } else {
            // Need to load audio first
            loadAndPlay()
        }
    }

    private func loadAndPlay() {
        // Check if the file exists locally
        let fileURL = recording.fileURL
        if FileManager.default.fileExists(atPath: fileURL.path) {
            playback.load(url: fileURL)
            playback.play()
            return
        }

        // File doesn't exist locally — download from CloudKit
        isLoadingAudio = true
        audioLoadError = nil
        Task {
            do {
                let localURL = try await appState.sharedAlbumManager.fetchRecordingAudio(
                    recordingId: recording.id,
                    album: album
                )
                await MainActor.run {
                    isLoadingAudio = false
                    playback.load(url: localURL)
                    playback.play()
                }
            } catch {
                await MainActor.run {
                    isLoadingAudio = false
                    audioLoadError = "Could not load audio: \(error.localizedDescription)"
                }
            }
        }
    }

    private func badgesSection(info: SharedRecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attributes")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            FlowLayout(spacing: 8) {
                if info.wasImported {
                    BadgeChip(icon: "square.and.arrow.down", text: "Imported", color: palette.accent)
                }

                if info.recordedWithHeadphones {
                    BadgeChip(icon: "headphones", text: "Headphones", color: palette.accent)
                }

                if info.isSensitive {
                    BadgeChip(icon: "eye.slash.fill", text: "Sensitive", color: palette.accent)
                }

                if info.isVerified {
                    BadgeChip(icon: "checkmark.seal.fill", text: "Verified", color: .green)
                }

                if info.locationSharingMode != .none {
                    BadgeChip(
                        icon: info.locationSharingMode == .approximate ? "location.circle" : "location.fill",
                        text: info.locationSharingMode == .approximate ? "Approximate Location" : "Precise Location",
                        color: .teal
                    )
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    private func locationSection(info: SharedRecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "map")
                    .foregroundColor(palette.accent)
                Text("Location")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
            }

            if let placeName = info.sharedPlaceName {
                HStack(spacing: 8) {
                    Image(systemName: info.locationSharingMode == .approximate ? "location.circle" : "location.fill")
                        .foregroundColor(palette.textSecondary)

                    Text(placeName)
                        .font(.body)
                        .foregroundColor(palette.textPrimary)

                    if info.locationSharingMode == .approximate {
                        Text("(~500m)")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "note.text")
                    .foregroundColor(palette.accent)
                Text("Notes")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
            }

            Text(recording.notes)
                .font(.body)
                .foregroundColor(palette.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Comments

    private var commentsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "bubble.left.fill")
                    .foregroundColor(palette.accent)
                Text("Comments")
                    .font(.headline)
                    .foregroundColor(palette.textPrimary)
                Spacer()
                if !comments.isEmpty {
                    Text("\(comments.count)")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
            }

            // Input
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 8) {
                    TextField("Add a comment...", text: $newCommentText)
                        .textFieldStyle(.roundedBorder)
                        .disabled(isSubmittingComment)
                        .onChange(of: newCommentText) {
                            if newCommentText.count > 500 {
                                newCommentText = String(newCommentText.prefix(500))
                            }
                        }

                    Button {
                        submitComment()
                    } label: {
                        if isSubmittingComment {
                            ProgressView()
                                .frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(
                                    newCommentText.trimmingCharacters(in: .whitespaces).isEmpty
                                        ? palette.textTertiary : palette.accent
                                )
                        }
                    }
                    .disabled(newCommentText.trimmingCharacters(in: .whitespaces).isEmpty || isSubmittingComment)
                }

                Text("\(newCommentText.count)/500")
                    .font(.caption2)
                    .foregroundColor(newCommentText.count > 450 ? .orange : palette.textTertiary)
            }

            // List
            if comments.isEmpty {
                Text("No comments yet. Be the first to comment!")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 0) {
                    ForEach(comments) { comment in
                        CommentRow(comment: comment, onDelete: {
                            deleteComment(comment)
                        })
                        if comment.id != comments.last?.id {
                            Divider().padding(.leading, 44)
                        }
                    }
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    private func loadComments() {
        Task {
            let fetched = await appState.sharedAlbumManager.fetchComments(
                for: recording.id,
                album: album
            )
            comments = fetched
        }
    }

    private func submitComment() {
        let trimmed = newCommentText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        isSubmittingComment = true
        commentError = nil
        Task {
            var authorName = "You"
            do {
                let comment = try await appState.sharedAlbumManager.addComment(
                    recordingId: recording.id,
                    recordingTitle: recording.title,
                    album: album,
                    text: trimmed
                )
                comments.append(comment)
                authorName = comment.authorDisplayName
                newCommentText = ""
            } catch {
                #if DEBUG
                let isDebugMode = appState.isSharedAlbumsDebugMode
                #else
                let isDebugMode = false
                #endif
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" || isDebugMode {
                    // CloudKit unavailable (e.g. simulator) — save locally for display
                    let localComment = SharedAlbumComment(
                        recordingId: recording.id,
                        authorId: "local",
                        authorDisplayName: "You",
                        text: trimmed
                    )
                    comments.append(localComment)
                    newCommentText = ""
                } else {
                    commentError = "Could not post comment. Please try again."
                }
            }

            // Always add local activity event for immediate visibility in activity tab
            // (CloudKit also logs it server-side, but this ensures instant local display)
            let event = SharedAlbumActivityEvent(
                albumId: album.id,
                actorId: "local",
                actorDisplayName: authorName,
                eventType: .commentAdded,
                targetRecordingId: recording.id,
                targetRecordingTitle: recording.title,
                newValue: trimmed
            )
            appState.localActivityEvents.append(event)

            isSubmittingComment = false
        }
    }

    private func deleteComment(_ comment: SharedAlbumComment) {
        // Only allow deleting own comments
        guard let currentUserId = appState.sharedAlbumManager.cachedCurrentUserId,
              comment.authorId == currentUserId else {
            return
        }

        Task {
            do {
                try await appState.sharedAlbumManager.deleteComment(
                    commentId: comment.id,
                    album: album
                )
                comments.removeAll { $0.id == comment.id }

                // Add activity event for comment deletion
                let event = SharedAlbumActivityEvent(
                    albumId: album.id,
                    actorId: currentUserId,
                    actorDisplayName: comment.authorDisplayName,
                    eventType: .commentDeleted,
                    targetRecordingId: recording.id,
                    targetRecordingTitle: recording.title
                )
                appState.localActivityEvents.append(event)
            } catch {
                #if DEBUG
                print("Failed to delete comment: \(error)")
                #endif
            }
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let clamped = max(0, seconds)
        let mins = Int(clamped) / 60
        let secs = Int(clamped) % 60
        return String(format: "%d:%02d", mins, secs)
    }
}

// MARK: - Helper Views for Detail

struct InfoItem: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(palette.accent)

            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(palette.textPrimary)
                .lineLimit(1)

            Text(label)
                .font(.caption)
                .foregroundColor(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct BadgeChip: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
            Text(text)
                .font(.caption)
        }
        .foregroundColor(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.15))
        .cornerRadius(8)
    }
}

// MARK: - Comment Row

struct CommentRow: View {
    @Environment(\.themePalette) private var palette
    @Environment(AppState.self) private var appState

    let comment: SharedAlbumComment
    let onDelete: () -> Void

    private var isOwnComment: Bool {
        // Compare against current cached user id if available
        guard let currentUserId = appState.sharedAlbumManager.cachedCurrentUserId else {
            return false
        }
        return comment.authorId == currentUserId
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle()
                    .fill(palette.accent.opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(comment.authorInitials)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.accent)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(comment.authorDisplayName)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                    Text(comment.relativeTime)
                        .font(.caption2)
                        .foregroundColor(palette.textTertiary)
                    Spacer()
                }

                Text(comment.text)
                    .font(.subheadline)
                    .foregroundColor(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 8)
        .contextMenu {
            if isOwnComment {
                Button(role: .destructive) {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }
}

// FlowLayout is defined in RecordingDetailView.swift
