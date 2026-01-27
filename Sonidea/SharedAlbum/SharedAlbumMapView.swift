//
//  SharedAlbumMapView.swift
//  Sonidea
//
//  Map view for shared albums showing location-tagged recordings.
//  Displays pins with participant filtering and recording details.
//

import SwiftUI
import MapKit
import CoreLocation

struct SharedAlbumMapView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let album: Album
    let recordings: [(recording: RecordingItem, sharedInfo: SharedRecordingItem)]

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRecording: (recording: RecordingItem, sharedInfo: SharedRecordingItem)?
    @State private var filterParticipant: String? = nil
    @State private var showVerifiedOnly = false
    @State private var showFilters = false
    @State private var showRecordingDetail = false

    private var filteredRecordings: [(recording: RecordingItem, sharedInfo: SharedRecordingItem)] {
        recordings.filter { item in
            // Must have valid shared location
            guard item.sharedInfo.hasSharedLocation,
                  let lat = item.sharedInfo.sharedLatitude,
                  let lon = item.sharedInfo.sharedLongitude,
                  lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180,
                  lat.isFinite && lon.isFinite else { return false }

            // Participant filter
            if let participantId = filterParticipant {
                guard item.sharedInfo.creatorId == participantId else { return false }
            }

            // Verified filter
            if showVerifiedOnly {
                guard item.sharedInfo.isVerified else { return false }
            }

            return true
        }
    }

    private var uniqueParticipants: [String: String] {
        // Map participantId -> displayName
        var participants: [String: String] = [:]
        for item in recordings where item.sharedInfo.hasSharedLocation {
            participants[item.sharedInfo.creatorId] = item.sharedInfo.creatorDisplayName
        }
        return participants
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Map
                mapContent

                // Bottom sheet for selected recording
                if let selected = selectedRecording {
                    RecordingMapCard(
                        recording: selected.recording,
                        sharedInfo: selected.sharedInfo,
                        onClose: {
                            withAnimation {
                                selectedRecording = nil
                            }
                        },
                        onPlay: {
                            showRecordingDetail = true
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .background(palette.background)
            .navigationTitle("Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundColor(palette.accent)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showFilters.toggle()
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .foregroundColor(palette.accent)
                }
            }
            .sheet(isPresented: $showFilters) {
                MapFiltersSheet(
                    participants: uniqueParticipants,
                    selectedParticipant: $filterParticipant,
                    showVerifiedOnly: $showVerifiedOnly
                )
                .presentationDetents([.medium])
            }
            .sheet(isPresented: Binding(
                get: { showRecordingDetail && selectedRecording != nil },
                set: { showRecordingDetail = $0 }
            )) {
                if let selected = selectedRecording {
                    SharedRecordingDetailView(
                        recording: selected.recording,
                        sharedInfo: selected.sharedInfo,
                        album: album
                    )
                }
            }
        }
    }

    private var hasActiveFilters: Bool {
        filterParticipant != nil || showVerifiedOnly
    }

    @ViewBuilder
    private var mapContent: some View {
        if filteredRecordings.isEmpty {
            emptyStateView
        } else {
            Map(position: $cameraPosition) {
                ForEach(filteredRecordings, id: \.recording.id) { item in
                    if let lat = item.sharedInfo.sharedLatitude,
                       let lon = item.sharedInfo.sharedLongitude {
                        Annotation(
                            item.recording.title,
                            coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            anchor: .bottom
                        ) {
                            SharedRecordingPin(
                                initials: item.sharedInfo.creatorInitials,
                                isApproximate: item.sharedInfo.locationSharingMode == .approximate,
                                isVerified: item.sharedInfo.isVerified,
                                isSelected: selectedRecording?.recording.id == item.recording.id
                            )
                            .onTapGesture {
                                withAnimation {
                                    selectedRecording = item
                                }
                            }
                        }
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(palette.textTertiary)

            Text("No Location Data")
                .font(.headline)
                .foregroundColor(palette.textSecondary)

            Text("Recordings with shared locations will appear on the map")
                .font(.subheadline)
                .foregroundColor(palette.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
    }
}

// MARK: - Shared Recording Pin

struct SharedRecordingPin: View {
    let initials: String
    let isApproximate: Bool
    let isVerified: Bool
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                // Pin body
                Circle()
                    .fill(
                        LinearGradient(
                            colors: isSelected ? [.blue, .purple] : [.blue.opacity(0.8), .blue],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: isSelected ? 44 : 36, height: isSelected ? 44 : 36)
                    .shadow(color: .black.opacity(0.2), radius: isSelected ? 8 : 4, y: 2)

                // Initials
                Text(initials)
                    .font(.system(size: isSelected ? 14 : 12, weight: .bold))
                    .foregroundColor(.white)

                // Verified badge
                if isVerified {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .offset(x: isSelected ? 16 : 12, y: isSelected ? -16 : -12)
                }

                // Approximate indicator
                if isApproximate {
                    Circle()
                        .stroke(Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: isSelected ? 52 : 44, height: isSelected ? 52 : 44)
                }
            }

            // Pin point
            MapPinTriangle()
                .fill(isSelected ? Color.purple : Color.blue)
                .frame(width: 12, height: 8)
                .offset(y: -2)
        }
        .animation(.spring(response: 0.3), value: isSelected)
    }
}

private struct MapPinTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Recording Map Card

struct RecordingMapCard: View {
    @Environment(\.themePalette) private var palette

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem
    let onClose: () -> Void
    let onPlay: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Handle
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.gray.opacity(0.3))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            HStack(alignment: .top, spacing: 12) {
                // Info
                VStack(alignment: .leading, spacing: 8) {
                    Text(recording.title)
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)

                    HStack(spacing: 8) {
                        Text("by \(sharedInfo.creatorDisplayName)")
                            .font(.subheadline)
                            .foregroundColor(palette.accent)

                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                    }

                    if let placeName = sharedInfo.sharedPlaceName {
                        HStack(spacing: 4) {
                            Image(systemName: sharedInfo.locationSharingMode == .approximate ? "location.circle" : "location.fill")
                                .font(.caption)
                            Text(placeName)
                                .font(.caption)

                            if sharedInfo.locationSharingMode == .approximate {
                                Text("(~500m)")
                                    .font(.caption2)
                                    .foregroundColor(palette.textTertiary)
                            }
                        }
                        .foregroundColor(palette.textSecondary)
                    }

                    // Badges
                    HStack(spacing: 8) {
                        if sharedInfo.isVerified {
                            Label("Verified", systemImage: "checkmark.seal.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }

                        if sharedInfo.isSensitive {
                            Label("Sensitive", systemImage: "eye.slash.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }
                }

                Spacer()

                // Actions
                VStack(spacing: 8) {
                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(palette.textTertiary)
                    }

                    Button(action: onPlay) {
                        Image(systemName: "play.circle.fill")
                            .font(.title)
                            .foregroundColor(palette.accent)
                    }
                }
            }
            .padding()
        }
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(palette.cardBackground)
                .shadow(color: .black.opacity(0.15), radius: 10, y: -2)
        )
        .padding(.horizontal)
        .padding(.bottom)
    }
}

// MARK: - Map Filters Sheet

struct MapFiltersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    let participants: [String: String]
    @Binding var selectedParticipant: String?
    @Binding var showVerifiedOnly: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Participant") {
                    Button {
                        selectedParticipant = nil
                    } label: {
                        HStack {
                            Text("All Participants")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if selectedParticipant == nil {
                                Image(systemName: "checkmark")
                                    .foregroundColor(palette.accent)
                            }
                        }
                    }

                    ForEach(Array(participants.keys.sorted()), id: \.self) { participantId in
                        Button {
                            selectedParticipant = participantId
                        } label: {
                            HStack {
                                Text(participants[participantId] ?? "Unknown")
                                    .foregroundColor(palette.textPrimary)
                                Spacer()
                                if selectedParticipant == participantId {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(palette.accent)
                                }
                            }
                        }
                    }
                }

                Section("Filters") {
                    Toggle("Verified Only", isOn: $showVerifiedOnly)
                }

                Section {
                    Button("Clear All Filters") {
                        selectedParticipant = nil
                        showVerifiedOnly = false
                    }
                    .foregroundColor(.red)
                }
            }
            .navigationTitle("Map Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
