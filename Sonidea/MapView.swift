//
//  MapView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import MapKit
import CoreLocation

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
    @Environment(\.themePalette) var palette
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

    private var topRecordedSpots: [RecordingSpot] {
        Array(allSpots.prefix(3))
    }

    private var topFavoritedSpots: [RecordingSpot] {
        allSpots
            .filter { $0.favoriteCount > 0 }
            .sorted { $0.favoriteCount > $1.favoriteCount }
            .prefix(3)
            .map { $0 }
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
                .environment(appState)
                .environment(\.themePalette, palette)
                .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
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
                .fill(palette.useMaterials ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(palette.sheetBackground))
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
            // Drag indicator capsule
            Capsule()
                .fill(palette.stroke)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Title row
            HStack {
                Image(systemName: "map.fill")
                    .font(.system(size: 16))
                    .foregroundColor(palette.accent)

                Text("Recording Spots")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)

                Spacer()

                // Expand/collapse chevron
                Image(systemName: sheetState == .expanded ? "chevron.down" : "chevron.up")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(palette.textSecondary)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)

            // Separator line
            Rectangle()
                .fill(palette.separator)
                .frame(height: 0.5)
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
                // Top 3 sections in collapsed view
                HStack(alignment: .top, spacing: 12) {
                    // Most Recorded Section
                    SpotCategorySection(
                        title: "Most Recorded",
                        icon: "mappin.and.ellipse",
                        iconColor: palette.accent,
                        spots: topRecordedSpots,
                        valueKeyPath: \.totalCount,
                        valueLabel: "recordings",
                        onSpotTap: zoomToSpot
                    )

                    // Most Favorited Section
                    SpotCategorySection(
                        title: "Most Favorited",
                        icon: "heart.fill",
                        iconColor: palette.recordButton,
                        spots: topFavoritedSpots,
                        valueKeyPath: \.favoriteCount,
                        valueLabel: "favorites",
                        onSpotTap: zoomToSpot
                    )
                }
                .padding(.horizontal, 16)

                // Ranked list (only visible when expanded)
                if sheetState == .expanded {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("All Spots")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textSecondary)
                            .padding(.horizontal, 16)

                        if allSpots.isEmpty {
                            Text("No recording spots yet")
                                .font(.subheadline)
                                .foregroundColor(palette.textTertiary)
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

    @ViewBuilder
    private var emptyStateContent: some View {
        let locationStatus = appState.locationManager.authorizationStatus

        VStack(spacing: 12) {
            Image(systemName: locationIconName(for: locationStatus))
                .font(.system(size: 32))
                .foregroundColor(palette.textSecondary)

            Text(locationTitle(for: locationStatus))
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            Text(locationDescription(for: locationStatus))
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            // Show CTA button based on authorization status
            if locationStatus == .notDetermined {
                Button {
                    appState.locationManager.requestPermission()
                } label: {
                    Label("Enable Location", systemImage: "location.fill")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.primaryButtonForeground)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.primaryButtonBackground)
                .padding(.top, 8)
            } else if locationStatus == .denied || locationStatus == .restricted {
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("Open Settings", systemImage: "gear")
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.secondaryButtonForeground)
                }
                .buttonStyle(.bordered)
                .tint(palette.accent)
                .padding(.top, 8)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func locationIconName(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "location.circle"
        case .denied, .restricted:
            return "location.slash"
        default:
            return "mappin.slash"
        }
    }

    private func locationTitle(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Enable Location"
        case .denied, .restricted:
            return "Location Access Denied"
        default:
            return "No locations yet"
        }
    }

    private func locationDescription(for status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Allow location access to automatically tag your recordings with where they were made"
        case .denied, .restricted:
            return "Location access is disabled. Enable it in Settings to see your recording spots on the map"
        default:
            return "Record with location enabled or manually add locations to your recordings to see them here"
        }
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

// MARK: - Spot Category Section

struct SpotCategorySection: View {
    @Environment(\.themePalette) private var palette
    let title: String
    let icon: String
    let iconColor: Color
    let spots: [RecordingSpot]
    let valueKeyPath: KeyPath<RecordingSpot, Int>
    let valueLabel: String
    let onSpotTap: (RecordingSpot) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(iconColor)
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(palette.textSecondary)
            }

            if spots.isEmpty {
                Text("No spots yet")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                    .padding(.vertical, 4)
            } else {
                // Show up to 3 spots with rank
                ForEach(Array(spots.enumerated()), id: \.element.id) { index, spot in
                    Button {
                        onSpotTap(spot)
                    } label: {
                        HStack(spacing: 6) {
                            // Rank number
                            Text("\(index + 1).")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(rankColor(for: index + 1))
                                .frame(width: 16, alignment: .leading)

                            // Spot name
                            Text(spot.displayName)
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(palette.textPrimary)
                                .lineLimit(1)

                            Spacer(minLength: 4)

                            // Count
                            Text("\(spot[keyPath: valueKeyPath])")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(palette.cardBackground)
        )
    }

    private func rankColor(for rank: Int) -> Color {
        switch rank {
        case 1: return .orange
        case 2: return .gray
        case 3: return .brown
        default: return .secondary
        }
    }
}

// MARK: - Spot List Row

struct SpotListRow: View {
    @Environment(\.themePalette) private var palette
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
                        .foregroundColor(palette.textPrimary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text("\(spot.totalCount) recording\(spot.totalCount == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

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
                    .foregroundColor(palette.textSecondary)
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
        default: return palette.textSecondary.opacity(0.5)
        }
    }
}

// MARK: - Recording Map Pin

struct RecordingMapPin: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.themePalette) private var palette

    var body: some View {
        ZStack {
            // Shadow/glow
            Circle()
                .fill(palette.recordButton.opacity(0.3))
                .frame(width: 36, height: 36)

            // White background circle
            Circle()
                .fill(Color.white)
                .frame(width: 28, height: 28)
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)

            // Themed record button color
            Circle()
                .fill(palette.recordButton)
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
