//
//  MapView.swift
//  VoiceMemoPro
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import MapKit

// MARK: - Bottom Sheet State

enum BottomSheetState {
    case collapsed
    case expanded

    var detentHeight: CGFloat {
        switch self {
        case .collapsed: return 180
        case .expanded: return 500
        }
    }
}

// MARK: - Full-Screen Map View with Bottom Sheet

struct GPSInsightsMapView: View {
    @Environment(AppState.self) var appState
    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedRecording: RecordingItem?
    @State private var sheetState: BottomSheetState = .collapsed
    @State private var dragOffset: CGFloat = 0

    // Computed spots data
    private var allSpots: [RecordingSpot] {
        SpotClustering.computeSpots(
            recordings: appState.activeRecordings,
            favoriteTagID: appState.favoriteTagID,
            filterFavoritesOnly: false
        ).sorted { $0.totalCount > $1.totalCount }
    }

    private var topRecordedSpot: RecordingSpot? {
        allSpots.first
    }

    private var topFavoritedSpot: RecordingSpot? {
        allSpots.filter { $0.favoriteCount > 0 }.max { $0.favoriteCount < $1.favoriteCount }
    }

    private var hasLocations: Bool {
        !appState.recordingsWithLocation.isEmpty
    }

    var body: some View {
        GeometryReader { geometry in
            let safeArea = geometry.safeAreaInsets
            let screenHeight = geometry.size.height

            ZStack(alignment: .bottom) {
                // Full-screen map
                mapLayer

                // Bottom sheet overlay
                bottomSheet(geometry: geometry, safeArea: safeArea, screenHeight: screenHeight)
            }
        }
        .onAppear {
            fitMapToAllRecordings()
        }
    }

    // MARK: - Map Layer

    private var mapLayer: some View {
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
        .mapStyle(.standard(
            elevation: .flat,
            pointsOfInterest: .excludingAll,
            showsTraffic: false
        ))
        .mapControlVisibility(.hidden)
        .sheet(item: $selectedRecording) { recording in
            RecordingDetailView(recording: recording)
        }
    }

    // MARK: - Bottom Sheet

    private func bottomSheet(geometry: GeometryProxy, safeArea: EdgeInsets, screenHeight: CGFloat) -> some View {
        let collapsedHeight: CGFloat = 180
        let expandedHeight: CGFloat = min(500, screenHeight * 0.6)
        let currentHeight = sheetState == .collapsed ? collapsedHeight : expandedHeight
        let sheetHeight = currentHeight - dragOffset
        let clampedHeight = max(collapsedHeight, min(expandedHeight, sheetHeight))

        return VStack(spacing: 0) {
            // Drag handle
            dragHandle

            // Content
            if hasLocations {
                sheetContent(expandedHeight: expandedHeight)
            } else {
                emptyStateContent
            }
        }
        .frame(height: clampedHeight + safeArea.bottom)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.15), radius: 10, y: -5)
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    dragOffset = -value.translation.height
                }
                .onEnded { value in
                    let velocity = value.predictedEndTranslation.height - value.translation.height
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        // Determine state based on drag direction and velocity
                        if velocity < -100 {
                            // Swiped up fast
                            sheetState = .expanded
                        } else if velocity > 100 {
                            // Swiped down fast
                            sheetState = .collapsed
                        } else {
                            // Slow drag - snap to nearest
                            let midpoint = (collapsedHeight + expandedHeight) / 2
                            let targetHeight = currentHeight - value.translation.height
                            sheetState = targetHeight > midpoint ? .expanded : .collapsed
                        }
                        dragOffset = 0
                    }
                }
        )
    }

    private var dragHandle: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(Color(.systemGray3))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Title
            HStack {
                Image(systemName: "map.fill")
                    .foregroundColor(.accentColor)
                Text("Recording Spots")
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()

                // Expand/collapse chevron
                Image(systemName: sheetState == .expanded ? "chevron.down" : "chevron.up")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                sheetState = sheetState == .collapsed ? .expanded : .collapsed
            }
        }
    }

    @ViewBuilder
    private func sheetContent(expandedHeight: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 16) {
                // Stat cards row
                HStack(spacing: 12) {
                    // Most Recorded Spot
                    StatCard(
                        title: "Most Recorded",
                        icon: "mappin.and.ellipse",
                        iconColor: .blue,
                        spotName: topRecordedSpot?.displayName ?? "No spots yet",
                        count: topRecordedSpot?.totalCount ?? 0,
                        countLabel: "recordings"
                    ) {
                        if let spot = topRecordedSpot {
                            zoomToSpot(spot)
                        }
                    }

                    // Most Favorited Spot
                    StatCard(
                        title: "Most Favorited",
                        icon: "heart.fill",
                        iconColor: .pink,
                        spotName: topFavoritedSpot?.displayName ?? "No favorites",
                        count: topFavoritedSpot?.favoriteCount ?? 0,
                        countLabel: "favorites"
                    ) {
                        if let spot = topFavoritedSpot {
                            zoomToSpot(spot)
                        }
                    }
                }
                .padding(.horizontal, 16)

                // Ranked list (only visible when expanded)
                if sheetState == .expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("All Spots")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 16)

                        if allSpots.isEmpty {
                            Text("No recording spots yet")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 20)
                        } else {
                            ForEach(Array(allSpots.enumerated()), id: \.element.id) { index, spot in
                                SpotListRow(
                                    rank: index + 1,
                                    spot: spot,
                                    onTap: {
                                        zoomToSpot(spot)
                                    }
                                )
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.bottom, 16)
        }
        .scrollDisabled(sheetState == .collapsed)
    }

    private var emptyStateContent: some View {
        VStack(spacing: 12) {
            Image(systemName: "location.slash")
                .font(.system(size: 32))
                .foregroundColor(.secondary)
            Text("No locations yet")
                .font(.headline)
                .foregroundColor(.primary)
            Text("Record with location permissions enabled to see your spots on the map")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Map Actions

    private func fitMapToAllRecordings() {
        let recordingsWithCoords = appState.recordingsWithLocation
        guard !recordingsWithCoords.isEmpty else { return }

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

        let latPadding = max(0.01, (maxLat - minLat) * 0.3)
        let lonPadding = max(0.01, (maxLon - minLon) * 0.3)

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
        withAnimation(.easeInOut(duration: 0.5)) {
            cameraPosition = .region(MKCoordinateRegion(
                center: spot.centerCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
            ))
        }
    }
}

// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let icon: String
    let iconColor: Color
    let spotName: String
    let count: Int
    let countLabel: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.caption)
                        .foregroundColor(iconColor)
                    Text(title)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(.secondary)
                }

                // Spot name
                Text(spotName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                // Count
                if count > 0 {
                    Text("\(count) \(countLabel)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
        .buttonStyle(.plain)
        .disabled(count == 0)
    }
}

// MARK: - Spot List Row

struct SpotListRow: View {
    let rank: Int
    let spot: RecordingSpot
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Rank badge
                Text("\(rank)")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .frame(width: 28, height: 28)
                    .background(
                        Circle()
                            .fill(rankColor)
                    )

                // Spot info
                VStack(alignment: .leading, spacing: 2) {
                    Text(spot.displayName)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("\(spot.totalCount) recording\(spot.totalCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        if spot.favoriteCount > 0 {
                            HStack(spacing: 2) {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 9))
                                    .foregroundColor(.pink)
                                Text("\(spot.favoriteCount)")
                                    .font(.caption)
                                    .foregroundColor(.pink)
                            }
                        }
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.clear)
        }
        .buttonStyle(.plain)
    }

    private var rankColor: Color {
        switch rank {
        case 1: return .yellow.opacity(0.9)
        case 2: return .gray.opacity(0.7)
        case 3: return .orange.opacity(0.7)
        default: return Color(.systemGray3)
        }
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

// MARK: - Preview

#Preview {
    GPSInsightsMapView()
        .environment(AppState())
}
