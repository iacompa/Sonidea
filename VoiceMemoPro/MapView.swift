//
//  MapView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import MapKit

struct GPSInsightsMapView: View {
    @Environment(AppState.self) var appState
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRecording: RecordingItem?
    @State private var selectedSpot: RecordingSpot?
    @State private var showSpotRecordings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Insights Panels
                insightsPanels

                // Map View with individual pins
                mapSection
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120) // Space for dock
        }
        .onAppear {
            fitMapToAllRecordings()
        }
    }

    // MARK: - Insights Panels

    @ViewBuilder
    private var insightsPanels: some View {
        let topSpots = appState.topSpots()
        let favoriteSpots = appState.topFavoriteSpots()
        let hasLocations = !appState.recordingsWithLocation.isEmpty

        if !hasLocations {
            emptyInsightsState
        } else {
            VStack(spacing: 12) {
                // Most Recorded Spots
                InsightsPanelView(
                    title: "Most Recorded Spots",
                    icon: "mappin.and.ellipse",
                    spots: topSpots,
                    emptyMessage: "No recording locations yet",
                    countLabel: { "\($0.totalCount) recordings" },
                    onSpotTap: { spot in
                        zoomToSpot(spot)
                    }
                )

                // Most Favorited Spots
                InsightsPanelView(
                    title: "Most Favorited Spots",
                    icon: "heart.fill",
                    spots: favoriteSpots,
                    emptyMessage: "No favorite recordings with locations",
                    countLabel: { "\($0.favoriteCount) favorites" },
                    onSpotTap: { spot in
                        zoomToSpot(spot)
                    }
                )
            }
        }
    }

    private var emptyInsightsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No locations yet")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Record with location permissions enabled to see insights")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Map Section

    private var mapSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Recording Locations")
                .font(.headline)
                .foregroundColor(.primary)

            if appState.recordingsWithLocation.isEmpty {
                emptyMapState
            } else {
                mapWithIndividualPins
            }
        }
    }

    private var emptyMapState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No recording locations yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text("Enable Location While Using to drop pins automatically.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var mapWithIndividualPins: some View {
        Map(position: $cameraPosition) {
            // Show a pin for EACH recording with coordinates
            ForEach(appState.recordingsWithLocation) { recording in
                if let coordinate = recording.coordinate {
                    Annotation(recording.title, coordinate: coordinate) {
                        Button {
                            selectedRecording = recording
                        } label: {
                            RecordingMapPin()
                        }
                    }
                }
            }
        }
        // Clean map style: no POIs, no business labels
        .mapStyle(.standard(
            elevation: .flat,
            pointsOfInterest: .excludingAll,
            showsTraffic: false
        ))
        .mapControlVisibility(.hidden) // Hide compass and scale
        .frame(height: 350)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
        .sheet(isPresented: $showSpotRecordings) {
            if let spot = selectedSpot {
                SpotRecordingsSheet(spot: spot)
            }
        }
    }

    // MARK: - Actions

    private func fitMapToAllRecordings() {
        let recordingsWithCoords = appState.recordingsWithLocation
        guard !recordingsWithCoords.isEmpty else { return }

        // Calculate bounding box
        var minLat = Double.greatestFiniteMagnitude
        var maxLat = -Double.greatestFiniteMagnitude
        var minLon = Double.greatestFiniteMagnitude
        var maxLon = -Double.greatestFiniteMagnitude

        for recording in recordingsWithCoords {
            guard let lat = recording.latitude, let lon = recording.longitude else { continue }
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
        }

        // Add padding
        let latPadding = max(0.01, (maxLat - minLat) * 0.2)
        let lonPadding = max(0.01, (maxLon - minLon) * 0.2)

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: (maxLat - minLat) + latPadding,
            longitudeDelta: (maxLon - minLon) + lonPadding
        )

        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func zoomToSpot(_ spot: RecordingSpot) {
        withAnimation {
            cameraPosition = .region(MKCoordinateRegion(
                center: spot.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            ))
        }
        selectedSpot = spot
        showSpotRecordings = true
    }
}

// MARK: - Recording Map Pin

struct RecordingMapPin: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            // Shadow/glow
            Circle()
                .fill(Color.red.opacity(0.3))
                .frame(width: 36, height: 36)

            // White background circle
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Red inner circle
            Circle()
                .fill(Color.red)
                .frame(width: 22, height: 22)

            // Waveform icon
            Image(systemName: "waveform")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Insights Panel View

struct InsightsPanelView: View {
    let title: String
    let icon: String
    let spots: [RecordingSpot]
    let emptyMessage: String
    let countLabel: (RecordingSpot) -> String
    let onSpotTap: (RecordingSpot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(.accentColor)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 12)

            // Content
            if spots.isEmpty {
                Text(emptyMessage)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                        Button {
                            onSpotTap(spot)
                        } label: {
                            HStack {
                                Text("\(index + 1).")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .leading)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(spot.displayName)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                        .foregroundColor(.primary)
                                        .lineLimit(1)
                                    Text(countLabel(spot))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                        }
                        .buttonStyle(.plain)

                        if index < spots.count - 1 {
                            Divider()
                                .padding(.leading, 48)
                        }
                    }
                }
                .padding(.bottom, 4)
            }
        }
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Spot Recordings Sheet

struct SpotRecordingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let spot: RecordingSpot
    @State private var selectedRecording: RecordingItem?

    private var recordings: [RecordingItem] {
        appState.recordings(for: spot.recordingIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(recordings) { recording in
                        Button {
                            selectedRecording = recording
                        } label: {
                            SpotRecordingRow(recording: recording)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("\(recordings.count) recordings at this spot")
                }
            }
            .navigationTitle(spot.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedRecording) { recording in
                RecordingDetailView(recording: recording)
            }
        }
    }
}

struct SpotRecordingRow: View {
    @Environment(AppState.self) var appState
    @Environment(\.colorScheme) var colorScheme
    let recording: RecordingItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(recording.iconSymbolColor(for: colorScheme))
                .frame(width: 36, height: 36)
                .background(recording.iconTileBackground(for: colorScheme))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(recording.iconTileBorder(for: colorScheme), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(recording.title)
                    .font(.body)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(recording.formattedDuration)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(recording.formattedDate)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if appState.isFavorite(recording) {
                Image(systemName: "heart.fill")
                    .font(.caption)
                    .foregroundColor(.pink)
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Preview

#Preview {
    GPSInsightsMapView()
        .environment(AppState())
}
