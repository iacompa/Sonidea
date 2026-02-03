import SwiftUI

enum ProFeatureContext: String, Identifiable {
    case editMode
    case sharedAlbums
    case tags
    case icloudSync
    case autoIcons
    case recordingQuality
    case recordOverTrack
    case watchSync
    case projects
    case metronome
    case recordingEffects
    case mixer

    var id: String { rawValue }

    /// Features temporarily ungated for TestFlight testing.
    /// Remove items from this set to re-gate them behind Pro.
    static let temporarilyFree: Set<ProFeatureContext> = [.editMode, .recordOverTrack, .autoIcons, .metronome]

    var isFree: Bool { Self.temporarilyFree.contains(self) }

    var title: String {
        switch self {
        case .editMode: return "Unlock Editing"
        case .sharedAlbums: return "Unlock Shared Albums"
        case .tags: return "Unlock Tags"
        case .icloudSync: return "Unlock iCloud Sync"
        case .autoIcons: return "Unlock Auto Icons"
        case .recordingQuality: return "Unlock High Quality Recording"
        case .recordOverTrack: return "Multi-Track Recording"
        case .watchSync: return "Unlock Watch Sync"
        case .projects: return "Unlock Projects & Versioning"
        case .metronome: return "Unlock Metronome"
        case .recordingEffects: return "Unlock Live Effects"
        case .mixer: return "Unlock Mixer & Mixdown"
        }
    }

    var message: String {
        switch self {
        case .editMode: return "Trim, split, and fine-tune your recordings with the pro waveform editor."
        case .sharedAlbums: return "Create shared albums and collaborate on recordings with others."
        case .tags: return "Organize your recordings with custom tags and smart filtering."
        case .icloudSync: return "Keep your recordings in sync across all your Apple devices."
        case .autoIcons: return "Automatically detect and assign icons to your recordings."
        case .recordingQuality: return "Record in high quality AAC, lossless ALAC, or uncompressed WAV formats."
        case .recordOverTrack: return "Layer recordings on top of existing tracks with the Record Over Track feature. Mix, adjust sync, and create rich audio with up to 3 layers."
        case .watchSync: return "Automatically sync recordings from your Apple Watch to your iPhone. Recordings appear in the ⌚️ Recordings album."
        case .projects: return "Group recordings into projects with version tracking and best-take marking."
        case .metronome: return "Add a metronome to keep time while recording. Count-in, tap tempo, and customizable time signatures. Requires headphones."
        case .recordingEffects: return "Monitor your recording through EQ and compression in real time. Effects are for monitoring only — the recording stays clean."
        case .mixer: return "Mix overdub layers with per-track volume, pan, mute, and solo. Bounce to a stereo mixdown."
        }
    }

    var iconName: String {
        switch self {
        case .editMode: return "waveform"
        case .sharedAlbums: return "person.2.fill"
        case .tags: return "tag.fill"
        case .icloudSync: return "icloud.fill"
        case .autoIcons: return "sparkles"
        case .recordingQuality: return "dial.high.fill"
        case .recordOverTrack: return "square.stack.3d.up.fill"
        case .watchSync: return "applewatch"
        case .projects: return "folder.fill"
        case .metronome: return "metronome"
        case .recordingEffects: return "slider.horizontal.3"
        case .mixer: return "slider.vertical.3"
        }
    }
}

// MARK: - Pro Badge (inline label for settings)

struct ProBadge: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        Text("PRO")
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(palette.accent)
            .cornerRadius(4)
    }
}

// MARK: - Pro Upgrade Sheet

struct ProUpgradeSheet: View {
    let context: ProFeatureContext
    let onViewPlans: () -> Void
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: context.iconName)
                .font(.system(size: 44))
                .foregroundColor(palette.accent)
                .padding(.top, 32)

            Text(context.title)
                .font(.title3.weight(.bold))
                .foregroundColor(palette.textPrimary)

            Text(context.message)
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Text("Included with Sonidea Pro")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
                .padding(.top, 4)

            Spacer(minLength: 16)

            Button {
                onViewPlans()
            } label: {
                Text("View Plans")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(palette.accent)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 24)

            Button {
                onDismiss()
            } label: {
                Text("Not now")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(palette.sheetBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
