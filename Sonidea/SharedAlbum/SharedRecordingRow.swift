//
//  SharedRecordingRow.swift
//  Sonidea
//
//  Enhanced recording row for shared albums.
//  Shows creator attribution, badges, and location info.
//

import SwiftUI

struct SharedRecordingRow: View {
    @Environment(\.themePalette) private var palette
    @Environment(\.colorScheme) private var colorScheme

    let recording: RecordingItem
    let sharedInfo: SharedRecordingItem?
    let isCurrentUserRecording: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Waveform icon with creator indicator
                recordingIcon

                // Recording info
                VStack(alignment: .leading, spacing: 4) {
                    // Title with badges
                    HStack(spacing: 6) {
                        Text(recording.title)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundColor(palette.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.tail)

                        // Badges
                        badgesRow
                    }

                    // Creator and timestamp
                    HStack(spacing: 8) {
                        if let info = sharedInfo, !isCurrentUserRecording {
                            Text(info.creatorDisplayName)
                                .font(.caption)
                                .foregroundColor(palette.accent)
                        }

                        Text(recording.formattedDuration)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)

                        Text(relativeDate)
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }

                    // Location if shared
                    if let info = sharedInfo, info.hasSharedLocation, let placeName = info.sharedPlaceName {
                        HStack(spacing: 4) {
                            Image(systemName: info.locationSharingMode == .approximate ? "location.circle" : "location.fill")
                                .font(.caption2)
                            Text(placeName)
                                .font(.caption)
                        }
                        .foregroundColor(palette.textSecondary)
                    }
                }

                Spacer()

                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(palette.textTertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var recordingIcon: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 8)
                .fill(recording.iconTileBackground(for: colorScheme))
                .frame(width: 44, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(recording.iconTileBorder(for: colorScheme), lineWidth: 1)
                )

            // Icon
            Image(systemName: recording.displayIconSymbol)
                .font(.system(size: 18))
                .foregroundColor(recording.iconSymbolColor(for: colorScheme))

            // Creator avatar overlay (for others' recordings)
            if let info = sharedInfo, !isCurrentUserRecording {
                Text(info.creatorInitials)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(palette.accent))
                    .offset(x: 14, y: 14)
            }
        }
        .accessibilityLabel("Recording: \(recording.title)")
    }

    @ViewBuilder
    private var badgesRow: some View {
        HStack(spacing: 4) {
            if sharedInfo?.wasImported == true {
                RecordingBadge(badge: .imported)
            }

            if sharedInfo?.recordedWithHeadphones == true {
                RecordingBadge(badge: .headphones)
            }

if sharedInfo?.isVerified == true {
                RecordingBadge(badge: .verified)
            }

            if sharedInfo?.isSensitive == true {
                RecordingBadge(badge: .sensitive)
            }

            if sharedInfo?.hasSharedLocation == true {
                RecordingBadge(badge: .location)
            }
        }
    }

    private static let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private var relativeDate: String {
        Self.relativeDateFormatter.localizedString(for: recording.createdAt, relativeTo: Date())
    }
}

// MARK: - Recording Badge

struct RecordingBadge: View {
    let badge: SharedRecordingBadge

    var color: Color {
        switch badge {
        case .imported: return .blue
        case .headphones: return .purple
        case .sensitive: return .orange
        case .verified: return .green
        case .location: return .teal
        }
    }

    var body: some View {
        Image(systemName: badge.iconName)
            .font(.system(size: 10))
            .foregroundColor(color)
    }
}

// MARK: - Badge Legend (for help/info)

struct SharedRecordingBadgeLegend: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recording Badges")
                .font(.headline)
                .foregroundColor(palette.textPrimary)

            ForEach(SharedRecordingBadge.allCases, id: \.self) { badge in
                HStack(spacing: 12) {
                    RecordingBadge(badge: badge)
                        .frame(width: 20)

                    Text(badge.displayName)
                        .font(.subheadline)
                        .foregroundColor(palette.textPrimary)

                    Spacer()
                }
            }
        }
        .padding()
        .background(palette.cardBackground)
        .cornerRadius(12)
    }
}

// MARK: - Shared Recording List Header

struct SharedRecordingListHeader: View {
    @Environment(\.themePalette) private var palette

    let totalCount: Int
    let myCount: Int
    let othersCount: Int

    var body: some View {
        HStack(spacing: 16) {
            CountChip(count: totalCount, label: "Total", color: palette.accent)
            CountChip(count: myCount, label: "Mine", color: .green)
            CountChip(count: othersCount, label: "Others", color: .blue)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

struct CountChip: View {
    let count: Int
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(count)")
                .font(.headline)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Empty State for Shared Album

struct SharedAlbumEmptyState: View {
    @Environment(\.themePalette) private var palette

    let isCurrentUserAdmin: Bool
    let onAddRecording: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue.opacity(0.2), .purple.opacity(0.2)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 100, height: 100)

                Image(systemName: "waveform.path")
                    .font(.system(size: 40))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }

            VStack(spacing: 8) {
                Text("No Recordings Yet")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)

                Text("Be the first to add a recording to this shared album")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                onAddRecording()
            } label: {
                Label("Add Recording", systemImage: "plus.circle.fill")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
            }
        }
        .padding(32)
    }
}
