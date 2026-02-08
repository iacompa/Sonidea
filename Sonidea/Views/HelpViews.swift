//
// HelpViews.swift
// Sonidea
//

import SwiftUI
import MapKit

struct SonideaOverviewView: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        InfoGuideView(
            title: "What is Sonidea?",
            intro: "Sonidea is a professional audio recording app designed for creators, musicians, podcasters, journalists, and anyone who captures audio. More than a voice memo app \u{2014} it's a mobile recording studio with editing, transcription, collaboration, and studio-grade effects.",
            sections: [
                InfoGuideSection(
                    headline: "Professional Recording",
                    bullets: [
                        "Four quality presets: Standard (AAC 128kbps), High (AAC 256kbps), Lossless (ALAC), and WAV (16-bit PCM)",
                        "Real-time input gain control (-6 to +6 dB) with peak metering",
                        "Built-in limiter to prevent clipping on loud sources",
                        "Noise reduction for cleaner voice recordings",
                        "Pause and resume mid-recording with seamless stitching",
                        "Metronome/click track with tap tempo, time signatures, and count-in (plays through headphones only, never recorded)",
                        "Live monitoring effects: 4-band EQ and compressor while recording (audio stays clean)"
                    ]
                ),
                InfoGuideSection(
                    headline: "Multi-Track & Overdub",
                    bullets: [
                        "Layer up to 3 overdub tracks on any recording",
                        "Per-track volume, pan, mute, and solo controls",
                        "Sync adjustment (±500ms) to align layers perfectly",
                        "Bounce/mixdown to stereo WAV for sharing",
                        "Preview your mix before committing"
                    ]
                ),
                InfoGuideSection(
                    headline: "Waveform Editing",
                    bullets: [
                        "Interactive waveform editor with up to 100x zoom",
                        "Trim to selection or cut and remove sections",
                        "Crossfade cuts for smooth, click-free splices",
                        "Fade in/out with linear, S-curve, exponential, or logarithmic curves",
                        "Peak and LUFS loudness normalization (broadcast-standard ITU-R BS.1770-4)",
                        "Noise gate, compression, reverb, and echo effects",
                        "Full undo/redo history \u{2014} experiment freely",
                        "Reset to original: one tap restores your unedited recording"
                    ]
                ),
                InfoGuideSection(
                    headline: "Transcription & Search",
                    bullets: [
                        "On-device speech-to-text in 10+ languages",
                        "Word-level timestamps \u{2014} tap any word in the transcript to jump to that moment",
                        "Currently-playing word highlights as audio plays",
                        "Full-text search across all transcripts with typo tolerance",
                        "Search by title, tags, albums, notes, or spoken content",
                        "Fuzzy matching: \"mitocondria\" finds \"mitochondria\""
                    ]
                ),
                InfoGuideSection(
                    headline: "Smart Features",
                    bullets: [
                        "Auto-icon detection classifies recordings (voice, guitar, drums, piano, etc.)",
                        "Smart Naming suggests titles based on content and audio type",
                        "Location-based naming uses your current place (e.g., \"Starbucks \u{2014} 2:14 PM\")",
                        "GPS tagging with map view of all your recording locations"
                    ]
                ),
                InfoGuideSection(
                    headline: "Organization",
                    bullets: [
                        "Albums for grouping related recordings",
                        "Color-coded tags for instant filtering",
                        "Projects with version tracking (V1, V2, V3) and best-take marking",
                        "Calendar view to browse recordings by date",
                        "Timeline/journal view for chronological browsing",
                        "Map view to see recordings by location"
                    ]
                ),
                InfoGuideSection(
                    headline: "Playback & EQ",
                    bullets: [
                        "4-band parametric EQ with interactive graph and rotary knobs",
                        "Variable speed playback (0.5x to 2.0x) with pitch preserved",
                        "Skip silence detection to jump past quiet sections",
                        "Configurable skip intervals (5s, 10s, 15s)",
                        "Drop markers at key moments and tap to return"
                    ]
                ),
                InfoGuideSection(
                    headline: "Collaboration",
                    bullets: [
                        "Shared albums via iCloud with up to 5 participants",
                        "Role-based permissions: Admin, Member, or Viewer",
                        "Comments on shared recordings for feedback",
                        "Activity feed shows all changes and who made them",
                        "Shared album trash with configurable retention (7\u{2013}30 days)"
                    ]
                ),
                InfoGuideSection(
                    headline: "Export & Sync",
                    bullets: [
                        "Export in Original, WAV, M4A (AAC 256kbps), or ALAC format",
                        "Chapter markers embedded in M4A exports (visible in Podcasts, iTunes)",
                        "Bulk export albums as ZIP with metadata manifest",
                        "iCloud sync across iPhone, iPad, and Apple Watch",
                        "Apple Watch companion app with auto-transfer to phone",
                        "Tamper-evident proof receipts with SHA-256 timestamps"
                    ]
                ),
                InfoGuideSection(
                    headline: "Siri & Shortcuts",
                    bullets: [
                        "\"Hey Siri, start recording\" to capture hands-free",
                        "Shortcuts for: Start Recording, Get Last Recording, Transcribe, and Export",
                        "Action Button support on iPhone 15 Pro and later",
                        "Lock Screen widget for one-tap recording"
                    ]
                ),
                InfoGuideSection(
                    headline: "Personalization",
                    bullets: [
                        "7 studio-inspired themes: System, Angst Robot, Cream, Logic Pro, Fruity, AVID, and Dynamite",
                        "Movable floating record button \u{2014} drag it anywhere",
                        "Configurable playback speed, skip intervals, and more",
                        "Theme syncs to Apple Watch"
                    ]
                )
            ],
            tip: "Explore the feature guides below for detailed instructions on each capability."
        )
    }
}

// MARK: - Welcome Tutorial Popup

struct WelcomeTutorialSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // App icon area
                    Image(systemName: "waveform.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(palette.accent)
                        .padding(.top, 20)

                    Text("Welcome to Sonidea")
                        .font(.title.bold())
                        .foregroundStyle(palette.textPrimary)

                    Text("A professional voice memo app with editing, collaboration, and studio-grade tools.")
                        .font(.body)
                        .foregroundStyle(palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                    // Feature highlights
                    VStack(spacing: 16) {
                        WelcomeFeatureRow(icon: "mic.fill", color: .red, title: "Record", description: "Multiple quality presets, gain control, and limiter")
                        WelcomeFeatureRow(icon: "scissors", color: .blue, title: "Edit", description: "Trim, cut, fade, normalize, noise gate, and more")
                        WelcomeFeatureRow(icon: "magnifyingglass", color: .teal, title: "Search", description: "Find words inside transcripts with typo tolerance")
                        WelcomeFeatureRow(icon: "folder.fill", color: .orange, title: "Organize", description: "Albums, tags, projects, and smart naming")
                        WelcomeFeatureRow(icon: "person.2.fill", color: .green, title: "Collaborate", description: "Shared albums, overdub, and multi-track mixing")
                        WelcomeFeatureRow(icon: "paintpalette.fill", color: .purple, title: "Personalize", description: "7 studio-inspired themes and auto-icon detection")
                    }
                    .padding(.horizontal, 20)

                    Spacer(minLength: 20)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Get Started") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(palette.accent)
                }
            }
            .navigationTitle("Sonidea")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct WelcomeFeatureRow: View {
    @Environment(\.themePalette) private var palette
    let icon: String
    let color: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundStyle(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()
        }
        .padding(12)
        .background(palette.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Guide View

struct GuideView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Learn how to get the most out of Sonidea's features.")
                        .font(.subheadline)
                        .foregroundStyle(palette.textSecondary)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 16, trailing: 20))
                }

                // Overview section at the top
                Section {
                    NavigationLink {
                        SonideaOverviewView()
                    } label: {
                        GuideRow(
                            icon: "sparkles",
                            title: "What is Sonidea?",
                            subtitle: "A complete overview of everything you can do"
                        )
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Overview")
                        .foregroundStyle(palette.textSecondary)
                }

                Section {
                    NavigationLink {
                        RecordingPlaybackInfoView()
                    } label: {
                        GuideRow(
                            icon: "mic.fill",
                            title: "Recording & Playback",
                            subtitle: "Quality, EQ, speed, gain, and more"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        EditingInfoView()
                    } label: {
                        GuideRow(
                            icon: "scissors",
                            title: "Editing",
                            subtitle: "Trim, cut, and remove silence"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        TagsInfoView()
                    } label: {
                        GuideRow(
                            icon: "tag",
                            title: "Tags",
                            subtitle: "Organize recordings with custom labels"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        AlbumsInfoView()
                    } label: {
                        GuideRow(
                            icon: "folder",
                            title: "Albums",
                            subtitle: "Group related recordings together"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        SharedAlbumsInfoView()
                    } label: {
                        SharedAlbumsGuideRow()
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ProjectsInfoView()
                    } label: {
                        GuideRow(
                            icon: "folder.badge.plus",
                            title: "Projects",
                            subtitle: "Track multiple takes and versions"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        OverdubInfoView()
                    } label: {
                        GuideRow(
                            icon: "waveform.badge.plus",
                            title: "Overdub",
                            subtitle: "Layer recordings over existing tracks"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ExportInfoView()
                    } label: {
                        GuideRow(
                            icon: "square.and.arrow.up",
                            title: "Export",
                            subtitle: "Share recordings as WAV or ZIP"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        MapsInfoView()
                    } label: {
                        GuideRow(
                            icon: "map",
                            title: "Maps",
                            subtitle: "View recordings by location"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        RecordButtonInfoView()
                    } label: {
                        GuideRow(
                            icon: "hand.draw",
                            title: "Movable Record Button",
                            subtitle: "Position the button anywhere on screen"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        SearchInfoView()
                    } label: {
                        GuideRow(
                            icon: "magnifyingglass",
                            title: "Search & Browse",
                            subtitle: "Find recordings by title, calendar, or timeline"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        AppearanceInfoView()
                    } label: {
                        GuideRow(
                            icon: "paintpalette",
                            title: "Themes",
                            subtitle: "7 studio-inspired visual themes"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        iCloudSyncInfoView()
                    } label: {
                        GuideRow(
                            icon: "icloud",
                            title: "iCloud Sync",
                            subtitle: "Keep recordings synced across devices"
                        )
                    }
                    .listRowBackground(palette.cardBackground)

                    NavigationLink {
                        ProofReceiptsInfoView()
                    } label: {
                        GuideRow(
                            icon: "checkmark.seal",
                            title: "Proof Receipts",
                            subtitle: "Tamper-evident timestamps for your recordings"
                        )
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Features")
                        .foregroundStyle(palette.textSecondary)
                } footer: {
                    Spacer()
                        .frame(height: 24)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(palette.background)
            .navigationTitle("Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(palette.accent)
                }
            }
        }
    }
}

// MARK: - Guide Row

struct GuideRow: View {
    @Environment(\.themePalette) private var palette

    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(palette.accent)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()
        }
    }
}

struct SettingsInfoRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            Text(title)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Info Card

struct InfoCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

// MARK: - Info Bullet Row

struct InfoBulletRow: View {
    let text: String
    var icon: String = "circle.fill"

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 6))
                .foregroundColor(.secondary)
                .frame(width: 12, height: 20, alignment: .center)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Info Tip Row

struct InfoTipRow: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow)
                .frame(width: 12)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Info Guide Template

/// Data model for a section in an info guide (headline + bullet list)
struct InfoGuideSection {
    let headline: String
    let bullets: [String]
}

/// Data model for a note callout in an info guide (icon + text)
struct InfoGuideNote {
    let icon: String
    let iconColor: Color
    let text: String
}

/// Reusable template for info/guide views.
/// All standard info views share this pattern: intro text → info card sections → optional note → optional tip.
struct InfoGuideView: View {
    let title: String
    let intro: String
    let sections: [InfoGuideSection]
    var tip: String? = nil
    var note: InfoGuideNote? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(intro)
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                    InfoCard {
                        Text(section.headline)
                            .font(.headline)
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(section.bullets, id: \.self) { bullet in
                                InfoBulletRow(text: bullet)
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                if let note {
                    InfoCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: note.icon)
                                .font(.system(size: 14))
                                .foregroundColor(note.iconColor)
                            Text(note.text)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                }

                if let tip {
                    InfoCard {
                        InfoTipRow(text: tip)
                    }
                    .padding(.horizontal)
                }

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Recording & Playback Info View

struct RecordingPlaybackInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Recording & Playback",
            intro: "Sonidea captures ideas the moment they happen and gives you studio-level playback controls.",
            sections: [
                InfoGuideSection(headline: "Recording", bullets: [
                    "Tap the floating record button to start. Tap again to stop and save.",
                    "Pause and resume mid-recording — your audio is stitched seamlessly.",
                    "Adjust input gain (-6 to +6 dB) and enable a limiter to prevent clipping.",
                    "Recordings are auto-tagged with your GPS location when available."
                ]),
                InfoGuideSection(headline: "Recording quality", bullets: [
                    "Standard — AAC 128 kbps at 44.1 kHz (free tier).",
                    "High — AAC 256 kbps at 48 kHz (Pro).",
                    "Lossless — Apple Lossless (ALAC) at 48 kHz (Pro).",
                    "WAV — Uncompressed PCM 16-bit at 48 kHz (Pro)."
                ]),
                InfoGuideSection(headline: "Playback", bullets: [
                    "Adjust playback speed from 0.5x to 2x with pitch preserved.",
                    "Use the 4-band parametric EQ to shape the sound — drag the band points on the graph.",
                    "Skip Silence automatically jumps past quiet sections during playback.",
                    "Add markers at any point and tap them to jump back instantly."
                ]),
                InfoGuideSection(headline: "Live Activity", bullets: [
                    "While recording, a Live Activity appears on the Lock Screen and Dynamic Island.",
                    "Pause, resume, or stop your recording without unlocking the phone."
                ])
            ],
            tip: "Enable the limiter when recording loud sources — it catches peaks that would otherwise clip."
        )
    }
}

// MARK: - Editing Info View

struct EditingInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Editing",
            intro: "Clean up recordings with trim, cut, and silence removal — all from the waveform editor.",
            sections: [
                InfoGuideSection(headline: "How editing works", bullets: [
                    "Open a recording and tap Edit to enter the waveform editor.",
                    "Pinch to zoom into the waveform for precise selection.",
                    "Drag the selection handles to highlight a region."
                ]),
                InfoGuideSection(headline: "Edit actions", bullets: [
                    "Trim — keep only the selected region, remove everything else.",
                    "Cut — remove the selected region and join the remaining audio.",
                    "Remove Silence — automatically detect and strip all silent sections at once."
                ]),
                InfoGuideSection(headline: "Skip Silence settings", bullets: [
                    "Adjust the silence threshold (-60 to -20 dB) and minimum duration (100–1000 ms).",
                    "Toggle fade transitions on cut boundaries to avoid audio clicks."
                ])
            ],
            tip: "Editing is a Pro feature. Edits create new files — your original is safe until you confirm."
        )
    }
}

// MARK: - Tags Info View

struct TagsInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Tags",
            intro: "Tags let you label ideas fast so you can find them later.",
            sections: [
                InfoGuideSection(headline: "How Tags work", bullets: [
                    "Add tags to any recording (Hook, Verse, Beat, Lyrics, To Finish).",
                    "Tap tags to filter your library instantly.",
                    "Use multiple tags on the same recording (e.g., Hook + Melody).",
                    "The Favorite tag is built-in and cannot be deleted — use it to mark your best ideas.",
                    "Create, rename, recolor, or delete tags in Settings → Manage Tags."
                ])
            ],
            tip: "Tags are a Pro feature. Keep names short (1–2 words) so your filters stay clean."
        )
    }
}

// MARK: - Albums Info View

struct AlbumsInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Albums",
            intro: "Albums are folders that keep your recordings organized by project, session, or vibe.",
            sections: [
                InfoGuideSection(headline: "How Albums work", bullets: [
                    "Use Albums to separate drafts, sessions, clients, or song ideas.",
                    "Move a recording into an Album from its Details screen, or use swipe actions in the list.",
                    "Albums work with Search and Tags — filter by Album first, then refine with tags.",
                    "Rename an album by tapping the pencil icon in its detail view.",
                    "Create, rename, or delete albums anytime. System albums (like Drafts) cannot be renamed or deleted."
                ])
            ],
            tip: "Keep a \"Drafts\" album for quick capture, then move ideas into project-specific albums later."
        )
    }
}

// MARK: - Shared Albums Guide Row (Gold-styled)

struct SharedAlbumsGuideRow: View {
    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .font(.body)
                .foregroundStyle(Color.sharedAlbumGold)
                .shadow(color: .sharedAlbumGold.opacity(0.5), radius: 4, x: 0, y: 0)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text("Shared Albums")
                    .font(.body)
                    .foregroundStyle(Color.sharedAlbumGold)
                    .shadow(color: .sharedAlbumGold.opacity(0.4), radius: 3, x: 0, y: 0)
                Text("Collaborate on recordings with others")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }

            Spacer()
        }
    }
}

// MARK: - Shared Albums Info View

struct SharedAlbumsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Shared Albums let you collaborate on recordings with trusted people via iCloud.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // What Shared Albums Are
                InfoCard {
                    Text("What is a Shared Album?")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "A collaborative album that syncs via iCloud with specific invited people.")
                        InfoBulletRow(text: "Only audio recordings are supported (no photos, videos, or other files).")
                        InfoBulletRow(text: "Shared albums appear with a gold glow, a badge, and participant count to distinguish them.")
                    }
                }
                .padding(.horizontal)

                // How to Create
                InfoCard {
                    Text("How to Create a Shared Album")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SharedAlbumInfoBullet(
                            prefix: "You cannot convert an existing album into a Shared Album.",
                            suffix: " You must create one fresh before adding recordings."
                        )
                        SharedAlbumInfoBullet(
                            prefix: "This prevents accidentally sharing a full private library or enabling mass deletion.",
                            suffix: ""
                        )
                    }

                    Text("Steps:")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .padding(.top, 8)

                    VStack(alignment: .leading, spacing: 8) {
                        SharedAlbumStepRow(number: 1, action: "Tap", highlight: "Create Shared Album", suffix: " in Settings.")
                        SharedAlbumStepRow(number: 2, action: "Name the album and choose initial settings.", highlight: nil, suffix: nil)
                        SharedAlbumStepRow(number: 3, action: "Tap", highlight: "Invite People", suffix: " to share the link.")
                        SharedAlbumStepRow(number: 4, action: "Add recordings (you'll see a confirmation before sharing).", highlight: nil, suffix: nil)
                    }
                }
                .padding(.horizontal)

                // Roles & Permissions
                InfoCard {
                    Text("Roles & Permissions")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 12) {
                        SharedAlbumRoleRow(
                            role: "Admin",
                            roleColor: .sharedAlbumGold,
                            description: "Invite/remove people, change settings, delete any recording."
                        )
                        SharedAlbumRoleRow(
                            role: "Member",
                            roleColor: .blue,
                            description: "Add recordings, edit their own metadata. Delete permission depends on album settings."
                        )
                        SharedAlbumRoleRow(
                            role: "Viewer",
                            roleColor: .secondary,
                            description: "Listen only. Cannot add or delete recordings."
                        )
                    }
                }
                .padding(.horizontal)

                // Confirmation & Privacy
                InfoCard {
                    Text("Privacy & Confirmation")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "When adding a recording to a shared album, you'll see a confirmation showing how many people will receive it.")
                        SharedAlbumInfoBullet(
                            prefix: "Location sharing is ",
                            highlight: "opt-in per album",
                            suffix: " and defaults to OFF."
                        )
                        InfoBulletRow(text: "If enabled, locations appear on a map with attribution (who recorded and when).")
                    }
                }
                .padding(.horizontal)

                // Trash & Restore
                InfoCard {
                    HStack(spacing: 8) {
                        Text("Shared Album Trash")
                            .font(.headline)
                            .foregroundColor(.primary)
                        Text("(Anti-disaster)")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Deletions in Shared Albums do not permanently delete immediately.")
                        SharedAlbumInfoBullet(
                            prefix: "Deleted recordings move to ",
                            highlight: "Shared Album Trash",
                            suffix: " for 7–30 days (configurable by admin)."
                        )
                        InfoBulletRow(text: "Restore permissions depend on album settings: either any participant can restore, or admins only.")
                        InfoBulletRow(text: "After the retention period, items are permanently removed.")
                    }
                }
                .padding(.horizontal)

                // Album Management
                InfoCard {
                    Text("Managing the Album")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "The album owner can rename the album from the toolbar menu or Settings. The new name syncs to all participants.")
                        InfoBulletRow(text: "Add comments to any recording — great for feedback or notes to collaborators.")
                        InfoBulletRow(text: "The recording creator controls whether others can download the audio file. Downloads default to off.")
                        InfoBulletRow(text: "Recordings can be flagged as sensitive. If the album requires approval, an admin must approve before the recording is visible.")
                    }
                }
                .padding(.horizontal)

                // Activity Feed
                InfoCard {
                    Text("Activity Feed")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SharedAlbumInfoBullet(
                            prefix: "Each shared album has an ",
                            highlight: "Activity",
                            suffix: " tab showing all actions: recordings added, deleted, or renamed, participant changes, settings updates, comments, and more."
                        )
                        InfoBulletRow(text: "This provides full transparency so everyone knows what happened and when.")
                    }
                }
                .padding(.horizontal)

                // Offline
                InfoCard {
                    Text("Offline support")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "If you lose connectivity, changes are queued and automatically synced when you're back online.")
                        InfoBulletRow(text: "Downloaded recordings are cached locally so you can listen without a connection.")
                    }
                }
                .padding(.horizontal)

                // Safety Warning
                InfoCard {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Safety Warning")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Only share albums with people you trust.")
                        InfoBulletRow(text: "Participants with permission can add or delete audio based on their role and album settings.")
                        InfoBulletRow(text: "Be aware of inappropriate content risks (spam, unwanted audio). Members can leave anytime.")
                    }
                }
                .padding(.horizontal)

                // Leaving a Shared Album
                InfoCard {
                    Text("Leaving a Shared Album")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SharedAlbumInfoBullet(
                            prefix: "Tap ",
                            highlight: "Leave Shared Album",
                            suffix: " in the album settings to remove yourself."
                        )
                        InfoBulletRow(text: "Your device will stop syncing that album.")
                        InfoBulletRow(text: "Recordings you added remain in the album for other participants unless they delete them.")
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Shared Albums")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Shared Album Info Helpers (Gold Highlighted Text)

/// A bullet row with optional gold-highlighted inline text
struct SharedAlbumInfoBullet: View {
    let prefix: String
    var highlight: String? = nil
    var suffix: String = ""

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 12, alignment: .leading)

            if let highlight = highlight {
                (Text(prefix)
                    .foregroundColor(.secondary) +
                 Text(highlight)
                    .foregroundColor(.sharedAlbumGold)
                    .fontWeight(.medium) +
                 Text(suffix)
                    .foregroundColor(.secondary))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(prefix + suffix)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A numbered step with optional gold-highlighted button/label text
struct SharedAlbumStepRow: View {
    let number: Int
    let action: String
    let highlight: String?
    let suffix: String?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.sharedAlbumGold)
                .frame(width: 20, alignment: .leading)

            if let highlight = highlight {
                (Text(action + " ")
                    .foregroundColor(.secondary) +
                 Text(highlight)
                    .foregroundColor(.sharedAlbumGold)
                    .fontWeight(.semibold) +
                 Text(suffix ?? "")
                    .foregroundColor(.secondary))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(action)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A role description row with colored role name
struct SharedAlbumRoleRow: View {
    let role: String
    let roleColor: Color
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.body)
                .foregroundColor(.secondary)
                .frame(width: 12, alignment: .leading)

            (Text(role)
                .foregroundColor(roleColor)
                .fontWeight(.semibold) +
             Text(": " + description)
                .foregroundColor(.secondary))
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Projects Info View

struct ProjectsInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Projects",
            intro: "Keep versions organized without clutter.",
            sections: [
                InfoGuideSection(headline: "How Projects work", bullets: [
                    "A Project groups related takes for the same idea (Hook v1, Chorus v2, Verse idea).",
                    "Record New Version creates a linked take (V2, V3...) inside the same Project instead of making scattered files.",
                    "Mark a Best Take to highlight the version you want to keep. Press and hold a take to set it.",
                    "Pin important projects so they always appear at the top of your list.",
                    "Albums vs. Projects: Albums organize your library. Projects organize versions of the same idea."
                ])
            ],
            tip: "Use Record New Version in a recording's Details to quickly capture another take without leaving the project."
        )
    }
}

// MARK: - Overdub Info View

struct OverdubInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Overdub",
            intro: "Record new layers over an existing track — like a one-person band.",
            sections: [
                InfoGuideSection(headline: "How Overdub works", bullets: [
                    "Open any recording's Details and tap Overdub to start a session.",
                    "Headphones are required — this prevents audio feedback from the speaker into the mic.",
                    "You'll hear the original track (and any existing layers) while recording a new layer.",
                    "Each base track supports up to 3 layers. All layers stay linked in an Overdub Group."
                ]),
                InfoGuideSection(headline: "Mix controls", bullets: [
                    "Adjust the base track volume and layer volume independently while recording.",
                    "Toggle \"Hear Previous Layers\" off if you only want to hear the base track during recording.",
                    "Auto-headroom reduces the mixer gain when multiple sources play to prevent clipping."
                ]),
                InfoGuideSection(headline: "Sync adjustment & preview", bullets: [
                    "After recording a layer, expand Sync Adjustment to shift it ±500 ms in 10 ms steps.",
                    "Tap Preview Mix to hear the base, existing layers, and the new layer together before saving.",
                    "Drag the slider while previewing — playback restarts instantly with the new offset so you can dial it in by ear.",
                    "Positive values delay the layer; negative values make it play earlier."
                ]),
                InfoGuideSection(headline: "Finding overdubs in your library", bullets: [
                    "Base tracks show an orange OVERDUB badge with layer count.",
                    "Layers show a purple LAYER 1/2/3 badge.",
                    "In any overdub recording's Details, the Overdub Group section shows all linked tracks."
                ])
            ],
            note: InfoGuideNote(icon: "headphones", iconColor: .orange, text: "Tip: Wired headphones have the lowest latency. Bluetooth works but may need more sync adjustment.")
        )
    }
}

// MARK: - Maps Info View

struct MapsInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Maps",
            intro: "Maps lets you see your creative footprint—where your ideas were captured over time.",
            sections: [
                InfoGuideSection(headline: "How Maps work", bullets: [
                    "Each recording can save an optional location when it's created.",
                    "Open Maps to see your recording spots over time—sessions, trips, and favorite places.",
                    "Tap a pin to jump straight to that recording's details.",
                    "You control it anytime: enable or disable Location in iOS Settings."
                ])
            ],
            note: InfoGuideNote(icon: "info.circle.fill", iconColor: .blue, text: "Location is optional. Sonidea works fully without it, and you can turn it off anytime.")
        )
    }
}

// MARK: - Record Button Info View

struct RecordButtonInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Movable Record Button",
            intro: "Move the record button anywhere so it's always where your thumb expects it.",
            sections: [
                InfoGuideSection(headline: "How it works", bullets: [
                    "Drag the record button anywhere on screen (below the top bar).",
                    "Your placement is saved automatically.",
                    "Long-press the button to reveal quick options, including Reset.",
                    "You can also reset it anytime in Settings → Reset Record Button Position."
                ])
            ],
            note: InfoGuideNote(icon: "arrow.counterclockwise", iconColor: .blue, text: "Reset returns the button to the default bottom position.")
        )
    }
}

// MARK: - Search Info View

struct SearchInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Search & Browse",
            intro: "Find any recording instantly using search, or browse your library by calendar or timeline.",
            sections: [
                InfoGuideSection(headline: "Transcript Search", bullets: [
                    "Search inside transcripts to find exactly what was said",
                    "Typo-tolerant matching \u{2014} \"mitocondria\" finds \"mitochondria\"",
                    "Results show matching snippets with highlighted keywords",
                    "Tap a result to open the recording at that exact moment",
                    "Recent recordings rank higher in search results"
                ]),
                InfoGuideSection(headline: "Tappable Transcripts", bullets: [
                    "Open any transcribed recording to see the full transcript",
                    "Each word is tappable \u{2014} tap to jump to that moment in the audio",
                    "The currently-playing word highlights as the recording plays",
                    "Scroll through the transcript while listening to follow along"
                ]),
                InfoGuideSection(headline: "Quick Search", bullets: [
                    "Tap the magnifying glass in the top bar",
                    "Search by title, tags, albums, or transcript content",
                    "Filter results by tapping tag chips below the search bar",
                    "Results update as you type"
                ]),
                InfoGuideSection(headline: "Browse Modes", bullets: [
                    "List — classic scrollable list of all recordings",
                    "Grid — visual card layout with color thumbnails",
                    "Calendar — monthly view with dots on days you recorded; tap a day to see that day's recordings",
                    "Timeline — chronological journal grouped by day, showing time, tags, location, and project context",
                    "Map — see all GPS-tagged recordings on an interactive map"
                ])
            ],
            tip: "Switch browse modes using the view picker at the top of the recordings list."
        )
    }
}

// MARK: - Appearance Info View

struct AppearanceInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Themes",
            intro: "Choose from 7 studio-inspired themes to make Sonidea feel like your favorite DAW.",
            sections: [
                InfoGuideSection(headline: "Available themes", bullets: [
                    "System — clean default look, follows Light or Dark mode",
                    "Angst Robot — purple-tinted dark theme inspired by Ableton Live",
                    "Cream — warm amber tones on a light background",
                    "Logic — periwinkle accents on dark, inspired by Logic Pro",
                    "Fruity — orange accents on dark, inspired by FL Studio",
                    "AVID — teal and mint on dark, inspired by Pro Tools",
                    "Dynamite — bold red and blue on charcoal"
                ]),
                InfoGuideSection(headline: "How to change your theme", bullets: [
                    "Go to Settings → Theme",
                    "Tap any theme to preview it instantly",
                    "Your choice applies across the entire app"
                ])
            ],
            tip: "You can also customize tag colors in Settings → Manage Tags to match your workflow."
        )
    }
}

// MARK: - iCloud Sync Info View

struct iCloudSyncInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Keep your recordings, tags, albums, and projects synced across all your Apple devices.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How iCloud Sync works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Enable iCloud Sync in Settings to start syncing automatically.")
                        InfoBulletRow(text: "Recordings, audio files, tags, albums, and projects all sync in real-time.")
                        InfoBulletRow(text: "Changes on one device appear on your other devices within seconds.")
                        InfoBulletRow(text: "Works in the background — no manual syncing needed.")
                    }
                }
                .padding(.horizontal)

                // What syncs
                InfoCard {
                    Text("What gets synced")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Audio files — your actual recordings")
                        InfoBulletRow(text: "Metadata — titles, notes, transcripts, locations")
                        InfoBulletRow(text: "Tags — all your custom tags and assignments")
                        InfoBulletRow(text: "Albums — including the Drafts and Imports system albums")
                        InfoBulletRow(text: "Projects — versions, best takes, and project notes")
                        InfoBulletRow(text: "Deletions — trashed items sync across devices too")
                    }
                }
                .padding(.horizontal)

                // Status indicators
                InfoCard {
                    Text("Sync status indicators")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.icloud.fill")
                                .foregroundColor(.green)
                            Text("Synced — Everything is up to date")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.2.circlepath.icloud")
                                .foregroundColor(.blue)
                            Text("Syncing — Upload or download in progress")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.icloud.fill")
                                .foregroundColor(.red)
                            Text("Error — Check your connection and try again")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "person.icloud")
                                .foregroundColor(.yellow)
                            Text("Sign in required — Log in to iCloud")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal)

                // Requirements
                InfoCard {
                    Text("Requirements")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Signed in to iCloud on all devices")
                        InfoBulletRow(text: "Sonidea installed on each device")
                        InfoBulletRow(text: "Sufficient iCloud storage for audio files")
                        InfoBulletRow(text: "Internet connection for syncing")
                    }
                }
                .padding(.horizontal)

                // Tips
                InfoCard {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Tips for best results:")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)
                            Text("• Use \"Sync Now\" after making many changes offline\n• Large recordings may take longer to upload\n• Edits and deletions sync immediately when online")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("iCloud Sync")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Export Info View

struct ExportInfoView: View {
    var body: some View {
        InfoGuideView(
            title: "Export",
            intro: "Export your recordings as high-quality WAV files, or bulk-export an entire album as a ZIP archive.",
            sections: [
                InfoGuideSection(headline: "Exporting a single recording", bullets: [
                    "Open a recording and tap the share icon",
                    "The recording is converted to 16-bit PCM WAV at its original sample rate",
                    "Share via AirDrop, Files, Messages, or any app that accepts audio"
                ]),
                InfoGuideSection(headline: "Bulk export (ZIP)", bullets: [
                    "Export all recordings or a single album at once",
                    "Creates a ZIP file with WAV audio organized into album folders",
                    "Includes a manifest.json with metadata: titles, dates, durations, tags, and locations",
                    "Recordings without an album are placed in an \"Unsorted\" folder"
                ])
            ],
            tip: "The manifest file makes it easy to catalog or import your recordings into a DAW or project manager."
        )
    }
}

// MARK: - Proof Receipts Info View

struct ProofReceiptsInfoView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Summary
                Text("Proof receipts create a tamper-evident record of your recordings, proving when and where they were captured.")
                    .font(.body)
                    .foregroundColor(.primary)
                    .padding(.horizontal)

                // How it works
                InfoCard {
                    Text("How it works")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "A SHA-256 hash (digital fingerprint) of your audio file is computed")
                        InfoBulletRow(text: "The hash is uploaded to Apple's CloudKit servers, which stamp it with a server-side timestamp")
                        InfoBulletRow(text: "If location was captured, a separate hash of the GPS coordinates is stored as well")
                        InfoBulletRow(text: "The result is a verifiable receipt that the recording existed at that time and place")
                    }
                }
                .padding(.horizontal)

                // Verification
                InfoCard {
                    Text("Verification")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        InfoBulletRow(text: "Sonidea re-computes the hash and compares it to the stored receipt")
                        InfoBulletRow(text: "If the file has been altered, the hashes won't match and the status shows a mismatch warning")
                        InfoBulletRow(text: "An unmodified recording shows a green \"Proven\" status")
                    }
                }
                .padding(.horizontal)

                // Status indicators
                InfoCard {
                    Text("Status indicators")
                        .font(.headline)
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                            Text("Proven — receipt verified, file unmodified")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .foregroundColor(.orange)
                            Text("Pending — waiting to upload (e.g., offline)")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("Mismatch — file was modified after proof was created")
                                .font(.subheadline)
                                .foregroundColor(.primary)
                        }
                    }
                }
                .padding(.horizontal)

                // Tip
                InfoCard {
                    InfoTipRow(text: "Proof receipts work offline too. Pending proofs are automatically uploaded when you reconnect.")
                }
                .padding(.horizontal)

                Spacer(minLength: 40)
            }
            .padding(.top)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Proof Receipts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

