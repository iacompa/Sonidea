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
    @State private var selectedSpot: RecordingSpot?
    @State private var showSpotRecordings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Insights Panels
                insightsPanels

                // Map View
                mapSection
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 120) // Space for dock
        }
    }

    // MARK: - Insights Panels

    @ViewBuilder
    private var insightsPanels: some View {
        let topSpots = appState.topSpots()
        let favoriteSpots = appState.topFavoriteSpots()
        let leastUsed = appState.leastUsedSpots()
        let hasLocations = !appState.recordingsWithLocation.isEmpty

        if !hasLocations {
            emptyInsightsState
        } else {
            VStack(spacing: 12) {
                // Top Spots to Record
                InsightsPanelView(
                    title: "Top Spots to Record",
                    icon: "mappin.and.ellipse",
                    spots: topSpots,
                    emptyMessage: "No recording locations yet",
                    countLabel: { "\($0.totalCount) recordings" },
                    onSpotTap: { spot in
                        zoomToSpot(spot)
                    }
                )

                // Top Favorite Spots
                InsightsPanelView(
                    title: "Top Favorite Spots",
                    icon: "heart.fill",
                    spots: favoriteSpots,
                    emptyMessage: "No favorite recordings with locations",
                    countLabel: { "\($0.favoriteCount) favorites" },
                    onSpotTap: { spot in
                        zoomToSpot(spot)
                    }
                )

                // Least Used Spots
                InsightsPanelView(
                    title: "Least Used Spots",
                    icon: "arrow.down.circle",
                    spots: leastUsed,
                    emptyMessage: "Record in more locations to see insights",
                    countLabel: { "\($0.totalCount) recordings" },
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
                mapWithPins
            }
        }
    }

    private var emptyMapState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map.circle.fill")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            Text("No locations yet")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text("Recordings with location data will appear here")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var mapWithPins: some View {
        Map(position: $cameraPosition) {
            ForEach(appState.allSpots()) { spot in
                Annotation(spot.displayName, coordinate: spot.centerCoordinate) {
                    Button {
                        selectedSpot = spot
                        showSpotRecordings = true
                    } label: {
                        ZStack {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 32, height: 32)
                            Text("\(spot.totalCount)")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }
                }
            }
        }
        .mapStyle(.standard)
        .frame(height: 350)
        .cornerRadius(12)
        .sheet(isPresented: $showSpotRecordings) {
            if let spot = selectedSpot {
                SpotRecordingsSheet(spot: spot)
            }
        }
    }

    // MARK: - Actions

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
    let recording: RecordingItem

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(recording.iconColor)
                .cornerRadius(6)

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
