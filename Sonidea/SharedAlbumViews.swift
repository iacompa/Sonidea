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

    private var recordingsWithLocation: [(recording: RecordingItem, sharedInfo: SharedRecordingItem)] {
        recordings.compactMap { recording in
            guard let info = sharedRecordingInfos[recording.id], info.hasSharedLocation else { return nil }
            return (recording, info)
        }
    }

    private var currentUserId: String? {
        nil // Would be fetched from CloudKit
    }

    var body: some View {
        NavigationStack {
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
            .background(palette.background)
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
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
                                // Show leave confirmation
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
            .sheet(isPresented: $showSettings) {
                SharedAlbumSettingsView(album: album, settings: $albumSettings)
            }
            .sheet(isPresented: $showParticipants) {
                SharedAlbumParticipantsView(album: album)
            }
            .sheet(isPresented: $showTrash) {
                SharedAlbumTrashView(album: album)
            }
            .sheet(isPresented: $showActivityFull) {
                SharedAlbumActivityView(album: album)
            }
            .sheet(isPresented: $showMap) {
                SharedAlbumMapView(album: album, recordings: recordingsWithLocation)
            }
            .sheet(item: $selectedRecording) { recording in
                SharedRecordingDetailView(
                    recording: recording,
                    sharedInfo: selectedSharedInfo,
                    album: album
                )
            }
            .onAppear {
                loadData()
            }
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
                SharedAlbumEmptyState(
                    isCurrentUserAdmin: album.currentUserRole == .admin,
                    onAddRecording: {
                        // Handle add recording
                    }
                )
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
                                selectedRecording = recording
                                selectedSharedInfo = sharedRecordingInfos[recording.id]
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
                    Button {
                        showMap = true
                    } label: {
                        ZStack(alignment: .bottomTrailing) {
                            // Placeholder for mini map
                            RoundedRectangle(cornerRadius: 12)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue.opacity(0.1), .purple.opacity(0.1)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(height: 200)
                                .overlay(
                                    VStack {
                                        Image(systemName: "map.fill")
                                            .font(.system(size: 40))
                                            .foregroundColor(palette.accent.opacity(0.5))

                                        Text("\(recordingsWithLocation.count) locations")
                                            .font(.subheadline)
                                            .foregroundColor(palette.textSecondary)
                                    }
                                )

                            // Expand button
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(8)
                                .background(Color.black.opacity(0.5))
                                .cornerRadius(8)
                                .padding(8)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding()

                    // Location list
                    List {
                        ForEach(recordingsWithLocation, id: \.recording.id) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.sharedInfo.locationSharingMode == .approximate ? "location.circle" : "location.fill")
                                    .foregroundColor(.purple)

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
            // Load recordings
            let albumRecordings = appState.recordings(in: album)

            // In debug mode, use cached shared recording info
            if appState.isSharedAlbumsDebugMode {
                await MainActor.run {
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
                    isLoading = false
                }
            } else {
                // Load activity
                let activity = await appState.sharedAlbumManager.fetchActivityFeed(for: album, limit: 50)

                // Load trash
                let trash = await appState.sharedAlbumManager.fetchTrashItems(for: album)

                // Load settings
                let settings = await appState.sharedAlbumManager.fetchAlbumSettings(for: album)

                await MainActor.run {
                    recordings = albumRecordings
                    activityEvents = activity
                    trashItems = trash
                    albumSettings = settings ?? .default
                    isLoading = false
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

    @State private var isPlaying = false
    @State private var playbackProgress: Double = 0
    @State private var showDemoAlert = false

    private var isDemoRecording: Bool {
        appState.isSharedAlbumsDebugMode && !FileManager.default.fileExists(atPath: recording.fileURL.path)
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
            .alert("Demo Recording", isPresented: $showDemoAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("This is a demo recording for testing purposes. Playback is not available for demo content.")
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

                Image(systemName: recording.presetIcon.systemName)
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
                                .background(Color.purple)
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
                .multilineTextAlignment(.center)
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

    private var playbackSection: some View {
        VStack(spacing: 16) {
            // Progress bar
            VStack(spacing: 4) {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.textTertiary.opacity(0.3))
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 2)
                            .fill(palette.accent)
                            .frame(width: geometry.size.width * playbackProgress, height: 4)
                    }
                }
                .frame(height: 4)

                HStack {
                    Text(formatTime(playbackProgress * recording.duration))
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .monospacedDigit()

                    Spacer()

                    Text(formatTime(recording.duration))
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .monospacedDigit()
                }
            }

            // Playback controls
            HStack(spacing: 32) {
                Button {
                    // Skip backward
                    if isDemoRecording {
                        showDemoAlert = true
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
                        isPlaying.toggle()
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(palette.accent)
                            .frame(width: 64, height: 64)

                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.title)
                            .foregroundColor(.white)
                    }
                }

                Button {
                    // Skip forward
                    if isDemoRecording {
                        showDemoAlert = true
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

    private func badgesSection(info: SharedRecordingItem) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Attributes")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            FlowLayout(spacing: 8) {
                if info.wasImported {
                    BadgeChip(icon: "square.and.arrow.down", text: "Imported", color: .blue)
                }

                if info.recordedWithHeadphones {
                    BadgeChip(icon: "headphones", text: "Headphones", color: .purple)
                }

                if info.isSensitive {
                    BadgeChip(icon: "eye.slash.fill", text: "Sensitive", color: .orange)
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
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

// FlowLayout is defined in RecordingDetailView.swift
