//
//  LocationSharingSheet.swift
//  Sonidea
//
//  Location sharing dialog for shared album recordings.
//  Privacy-first approach with approximate and precise options.
//

import SwiftUI
import CoreLocation

struct LocationSharingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let album: Album
    let currentMode: LocationSharingMode
    let onModeSelected: (LocationSharingMode) -> Void

    @State private var selectedMode: LocationSharingMode
    @State private var dontWarnAgain = false
    @State private var isSaving = false

    init(
        recording: RecordingItem,
        album: Album,
        currentMode: LocationSharingMode,
        onModeSelected: @escaping (LocationSharingMode) -> Void
    ) {
        self.recording = recording
        self.album = album
        self.currentMode = currentMode
        self.onModeSelected = onModeSelected
        self._selectedMode = State(initialValue: currentMode)
    }

    var hasLocation: Bool {
        recording.hasCoordinates
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "location.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.purple)
                }
                .padding(.top, 20)

                // Title
                VStack(spacing: 8) {
                    Text("Share Location")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(palette.textPrimary)

                    Text("Choose how to share this recording's location with album participants")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                if !hasLocation {
                    // No location warning
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)

                        Text("No Location Available")
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)

                        Text("This recording doesn't have location data. Enable location in settings to record with location.")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(palette.cardBackground)
                    .cornerRadius(12)
                    .padding(.horizontal)
                } else {
                    // Location options
                    VStack(spacing: 12) {
                        LocationModeOption(
                            mode: .none,
                            isSelected: selectedMode == .none,
                            onSelect: { selectedMode = .none }
                        )

                        LocationModeOption(
                            mode: .approximate,
                            isSelected: selectedMode == .approximate,
                            onSelect: { selectedMode = .approximate }
                        )

                        LocationModeOption(
                            mode: .precise,
                            isSelected: selectedMode == .precise,
                            onSelect: { selectedMode = .precise }
                        )
                    }
                    .padding(.horizontal)

                    // Current location preview
                    if !recording.locationLabel.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin")
                                .foregroundColor(palette.accent)

                            Text(recording.locationLabel)
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                        }
                        .padding()
                        .background(palette.cardBackground)
                        .cornerRadius(8)
                        .padding(.horizontal)
                    }
                }

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        saveLocationMode()
                    } label: {
                        HStack {
                            if isSaving {
                                ProgressView()
                                    .tint(.white)
                            }
                            Text("Save")
                        }
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.purple)
                        .cornerRadius(12)
                    }
                    .disabled(isSaving || (!hasLocation && selectedMode != .none))

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

    private func saveLocationMode() {
        isSaving = true
        onModeSelected(selectedMode)

        // Small delay for visual feedback
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

// MARK: - Location Mode Option

struct LocationModeOption: View {
    @Environment(\.themePalette) private var palette

    let mode: LocationSharingMode
    let isSelected: Bool
    let onSelect: () -> Void

    var icon: String {
        switch mode {
        case .none: return "location.slash"
        case .approximate: return "location.circle"
        case .precise: return "location.fill"
        }
    }

    var title: String {
        switch mode {
        case .none: return "Don't Share"
        case .approximate: return "Approximate"
        case .precise: return "Precise"
        }
    }

    var description: String {
        switch mode {
        case .none: return "Location will not be shared with participants"
        case .approximate: return "Share general area (~500m precision)"
        case .precise: return "Share exact location"
        }
    }

    var iconColor: Color {
        switch mode {
        case .none: return .gray
        case .approximate: return .orange
        case .precise: return .green
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(iconColor.opacity(0.15))
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18))
                        .foregroundColor(iconColor)
                }

                // Text
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)

                    Text(description)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? palette.accent : palette.textTertiary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(palette.cardBackground)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? palette.accent : Color.clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - First-Time Location Warning

struct LocationSharingWarningSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let onContinue: () -> Void

    @State private var understood = false
    @AppStorage("hasSeenLocationSharingWarning") private var hasSeenWarning = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 72, height: 72)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 28))
                        .foregroundColor(.orange)
                }
                .padding(.top, 20)

                // Title
                Text("Location Privacy")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(palette.textPrimary)

                // Warnings
                VStack(alignment: .leading, spacing: 16) {
                    WarningBullet(
                        icon: "eye.fill",
                        text: "All album participants can see shared locations"
                    )

                    WarningBullet(
                        icon: "location.fill",
                        text: "Precise mode shares exact coordinates"
                    )

                    WarningBullet(
                        icon: "person.2.fill",
                        text: "Consider who has access to this album"
                    )

                    WarningBullet(
                        icon: "hand.raised.fill",
                        text: "You can disable sharing anytime"
                    )
                }
                .padding(.horizontal, 24)

                // Acknowledgment
                Toggle(isOn: $understood) {
                    Text("I understand the privacy implications")
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)
                }
                .padding(.horizontal, 24)

                Spacer()

                // Buttons
                VStack(spacing: 12) {
                    Button {
                        hasSeenWarning = true
                        dismiss()
                        onContinue()
                    } label: {
                        Text("Continue")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(understood ? Color.orange : Color.gray)
                            .cornerRadius(12)
                    }
                    .disabled(!understood)

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
            .interactiveDismissDisabled()
        }
    }
}

struct WarningBullet: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.orange)
                .frame(width: 20)

            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
        }
    }
}
