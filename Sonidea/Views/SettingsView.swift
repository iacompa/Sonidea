//
//  SettingsView.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

enum HelpTopic: String, Identifiable, CaseIterable {
    case iCloud
    case collaboration
    case tags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .iCloud: return "iCloud Sync"
        case .collaboration: return "Shared Albums"
        case .tags: return "Tags"
        }
    }

    var icon: String {
        switch self {
        case .iCloud: return "icloud"
        case .collaboration: return "person.2.fill"
        case .tags: return "tag"
        }
    }

    /// Content used by both Guide view and Settings info sheets
    var content: [(heading: String?, bullets: [String])] {
        switch self {
        case .iCloud:
            return [
                (nil, [
                    "Sync recordings, tags, albums, and projects across all your devices.",
                    "Changes made on one device appear automatically on others.",
                    "Ensure iCloud is enabled in your device Settings for Sonidea."
                ]),
                ("Troubleshooting", [
                    "If sync seems stuck, try toggling iCloud off and on.",
                    "Large recordings may take time to upload on slow connections.",
                    "Check iCloud storage isn't full."
                ])
            ]
        case .collaboration:
            return [
                (nil, [
                    "Share albums with specific people via iCloud.",
                    "Shared albums sync audio recordings only (no photos/videos).",
                    "You cannot convert an existing album—create a new Shared Album first."
                ]),
                ("Roles", [
                    "Admin: Full control—invite/remove people, change settings, delete any recording.",
                    "Member: Add recordings, edit own recordings; delete permission depends on settings.",
                    "Viewer: Listen only, cannot add or delete."
                ]),
                ("Safety", [
                    "Deletions move to Shared Album Trash for 7–30 days before permanent removal.",
                    "Activity tab shows who added, deleted, or modified recordings.",
                    "Only share with people you trust."
                ])
            ]
        case .tags:
            return [
                (nil, [
                    "Tags help you organize and find recordings quickly.",
                    "Add multiple tags to any recording.",
                    "Filter your library by tag to focus on specific topics."
                ]),
                ("Tips", [
                    "Use consistent naming for easy filtering.",
                    "Create tags for projects, moods, or categories.",
                    "Tags sync across all your devices via iCloud."
                ])
            ]
        }
    }
}

// MARK: - Settings Section Header with Info Icon

struct SettingsSectionHeader: View {
    let title: String
    let topic: HelpTopic?
    let onInfoTap: (() -> Void)?
    var isGold: Bool = false
    var showProBadge: Bool = false

    @Environment(\.themePalette) private var palette

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundColor(isGold ? Color.sharedAlbumGold : palette.textSecondary)

            if showProBadge {
                ProBadge()
            }

            if let _ = topic, let onTap = onInfoTap {
                Button {
                    onTap()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14))
                        .foregroundColor(isGold ? Color.sharedAlbumGold.opacity(0.8) : palette.textTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
            }

            Spacer()

            // Optional sparkles for Collaboration
            if isGold {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
            }
        }
    }
}

// MARK: - Help Sheet View

struct HelpSheetView: View {
    let topic: HelpTopic
    @Environment(\.dismiss) private var dismiss
    @Environment(\.themePalette) private var palette

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    HStack(spacing: 12) {
                        Image(systemName: topic.icon)
                            .font(.title2)
                            .foregroundColor(topic == .collaboration ? Color.sharedAlbumGold : palette.accent)
                            .frame(width: 40, height: 40)
                            .background(
                                Circle()
                                    .fill(topic == .collaboration ? Color.sharedAlbumGold.opacity(0.15) : palette.accent.opacity(0.15))
                            )

                        Text(topic.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                    }
                    .padding(.bottom, 8)

                    // Content sections
                    ForEach(Array(topic.content.enumerated()), id: \.offset) { _, section in
                        VStack(alignment: .leading, spacing: 12) {
                            if let heading = section.heading {
                                Text(heading)
                                    .font(.headline)
                                    .foregroundColor(palette.textPrimary)
                            }

                            ForEach(section.bullets, id: \.self) { bullet in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundColor(palette.textSecondary)
                                    Text(bullet)
                                        .font(.subheadline)
                                        .foregroundColor(palette.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    Spacer(minLength: 40)
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(topic.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Settings Sheet
struct SettingsSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var isExporting = false
    @State private var exportProgress: String = ""
    @State private var showShareSheet = false
    @State private var exportedZIPURL: URL?
    @State private var showAlbumPicker = false
    @State private var showTagManager = false
    @State private var showTrashView = false
    @State private var showEmptyTrashAlert = false
    @State private var showFileImporter = false
    @State private var showImportDestinationSheet = false
    @State private var pendingImportURLs: [URL] = []
    @State private var importErrors: [String] = []
    @State private var showImportErrorAlert = false

    @State private var showBulkFormatPicker = false
    @State private var bulkExportScope: ExportScope = .all
    @State private var bulkExportAlbum: Album?
    @State private var showLockScreenHelp = false
    @State private var showActionButtonHelp = false
    @State private var showMicrophoneSheet = false
    @State private var showStorageEstimateSheet = false
    @State private var showSiriShortcutsHelp = false
    @State private var showGuide = false
    @State private var showCreateSharedAlbumSheet = false
    @State private var isResetButtonAnimating = false
    @State private var activeHelpTopic: HelpTopic?
    @State private var showAutoIconInfo = false
    @State private var showResetStep1 = false
    @State private var showResetStep2 = false
    @State private var resetConfirmText = ""
    @State private var resetConfirmationChecked = false
    @State private var showResetLoading = false
    @State private var proUpgradeContext: ProFeatureContext? = nil
    @State private var showSupport = false

    private func requirePro(_ context: ProFeatureContext) -> Bool {
        if appState.supportManager.canUseProFeatures { return true }
        proUpgradeContext = context
        return false
    }

    /// Whether recording settings should be locked (recording is in progress)
    private var isRecordingActive: Bool {
        appState.recorder.isActive
    }

    /// Whether Apple Intelligence is available on this device (iOS 26+ with Apple Silicon)
    private var isAppleIntelligenceAvailable: Bool {
        if #available(iOS 26.0, *) {
            // iOS 26+ means the device has Apple Intelligence capability
            // FoundationModels framework is available
            return true
        }
        return false
    }

    // Sync status color based on state
    private var syncStatusColor: Color {
        switch appState.syncManager.status {
        case .disabled:
            return palette.textSecondary
        case .initializing, .syncing:
            return palette.accent
        case .synced:
            return .green
        case .error:
            return .red
        case .networkUnavailable:
            return .orange
        case .accountUnavailable:
            return .yellow
        }
    }

    var body: some View {
        @Bindable var appState = appState

        NavigationStack {
            List {
                // MARK: Quick Access Section
                Section {
                    Button { showLockScreenHelp = true } label: {
                        HStack {
                            Image(systemName: "lock.rectangle.on.rectangle")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Lock Screen Widget")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Button { showActionButtonHelp = true } label: {
                        HStack {
                            Image(systemName: "button.horizontal.top.press")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Action Button")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Button { showSiriShortcutsHelp = true } label: {
                        HStack {
                            Image(systemName: "mic.badge.plus")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                            Text("Siri & Shortcuts")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Quick Access")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Set up fast ways to start recording from anywhere.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: Record Button Position Section
                Section {
                    Button {
                        // Perform reset
                        appState.resetRecordButtonPosition()
                        // Trigger animation after reset
                        withAnimation(.easeInOut(duration: 0.4)) {
                            isResetButtonAnimating = true
                        }
                        // Success haptic
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
                        // Reset animation state after completion
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            isResetButtonAnimating = false
                        }
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(palette.accent)
                                .frame(width: 24)
                                .rotationEffect(.degrees(isResetButtonAnimating ? -360 : 0))
                                .animation(.easeInOut(duration: 0.4), value: isResetButtonAnimating)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reset Record Button Position")
                                    .foregroundColor(palette.textPrimary)
                                Text("Moves the floating button back to the default location.")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                }

                // MARK: Recording Section
                Section {
                    // Recording Quality
                    Picker("Quality", selection: $appState.appSettings.recordingQuality) {
                        ForEach(RecordingQualityPreset.allCases) { preset in
                            Text(preset.displayName)
                                .tag(preset)
                        }
                    }
                    .disabled(isRecordingActive)
                    .listRowBackground(palette.cardBackground)

                    // Recording Mode
                    Picker("Mode", selection: $appState.appSettings.recordingMode) {
                        ForEach(RecordingMode.allCases) { mode in
                            Text(mode.displayName)
                                .tag(mode)
                        }
                    }
                    .disabled(isRecordingActive)
                    .listRowBackground(palette.cardBackground)

                    // Microphone
                    Button {
                        showMicrophoneSheet = true
                    } label: {
                        HStack {
                            Text("Microphone")
                                .foregroundStyle(palette.textPrimary)
                            Spacer()
                            Text(microphoneDisplayName)
                                .foregroundStyle(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.textTertiary)
                        }
                    }
                    .disabled(isRecordingActive)
                    .listRowBackground(palette.cardBackground)

                    // Prevent Sleep
                    Toggle("Prevent Sleep", isOn: $appState.appSettings.preventSleepWhileRecording)
                        .tint(palette.accent)
                        .listRowBackground(palette.cardBackground)

                    // Noise Reduction (Voice Processing)
                    VStack(alignment: .leading, spacing: 4) {
                        Toggle("Noise Reduction", isOn: $appState.appSettings.noiseReductionEnabled)
                            .tint(palette.accent)
                            .disabled(isRecordingActive)
                        Text("Reduces background noise during recording. Best for speech. May affect audio quality for music.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)

                    // Metronome (plays through headphones only during recording)
                    Toggle("Metronome", isOn: $appState.appSettings.metronomeEnabled)
                        .tint(palette.accent)
                        .disabled(isRecordingActive)
                        .onChange(of: appState.appSettings.metronomeEnabled) { _, enabled in
                            if enabled && !appState.supportManager.canUseProFeatures && !ProFeatureContext.metronome.isFree {
                                appState.appSettings.metronomeEnabled = false
                                proUpgradeContext = .metronome
                            }
                        }
                        .listRowBackground(palette.cardBackground)

                    if appState.appSettings.metronomeEnabled {
                        VStack(alignment: .leading, spacing: 8) {
                            // Headphone requirement note
                            HStack(spacing: 6) {
                                Image(systemName: "headphones")
                                    .foregroundStyle(palette.accent)
                                    .font(.caption)
                                Text("Requires headphones (wired or Bluetooth)")
                                    .font(.caption)
                                    .foregroundStyle(palette.textSecondary)
                            }

                            Divider()

                            HStack {
                                Text("BPM")
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text("\(Int(appState.appSettings.metronomeBPM))")
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                            }
                            Slider(value: $appState.appSettings.metronomeBPM, in: 10...240, step: 1)
                                .tint(palette.accent)
                            Button {
                                appState.recorder.metronome.tapTempo()
                                appState.appSettings.metronomeBPM = appState.recorder.metronome.bpm
                            } label: {
                                HStack {
                                    Image(systemName: "hand.tap")
                                    Text("Tap Tempo")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.bordered)
                            .tint(palette.accent)

                            Divider()

                            HStack {
                                Text("Volume")
                                    .foregroundStyle(palette.textPrimary)
                                Spacer()
                                Text("\(Int(appState.appSettings.metronomeVolume * 100))%")
                                    .foregroundStyle(palette.textSecondary)
                                    .monospacedDigit()
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "speaker.fill")
                                    .foregroundStyle(palette.textSecondary)
                                    .font(.caption)
                                Slider(value: $appState.appSettings.metronomeVolume, in: 0.1...1.0, step: 0.05)
                                    .tint(palette.accent)
                                Image(systemName: "speaker.wave.3.fill")
                                    .foregroundStyle(palette.textSecondary)
                                    .font(.caption)
                            }
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    HStack {
                        Text("Recording")
                        Spacer()
                        Button {
                            showStorageEstimateSheet = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(palette.textSecondary)
                    }
                    .textCase(nil)
                } footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(appState.appSettings.recordingQuality.description)
                        Text(appState.appSettings.recordingMode.description)
                        if appState.appSettings.preventSleepWhileRecording {
                            Text("Screen will stay on while recording.")
                        }
                        if appState.appSettings.metronomeEnabled {
                            Text("Metronome: \(Int(appState.appSettings.metronomeBPM)) BPM · \(Int(appState.appSettings.metronomeVolume * 100))% vol. Plays through headphones only and is not recorded.")
                        }
                    }
                    .foregroundColor(palette.textSecondary)
                }

                Section {
                    Picker("Skip Interval", selection: $appState.appSettings.skipInterval) {
                        ForEach(SkipInterval.allCases) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Picker("Playback Speed", selection: $appState.appSettings.playbackSpeed) {
                        Text("0.5x").tag(Float(0.5))
                        Text("0.75x").tag(Float(0.75))
                        Text("1.0x").tag(Float(1.0))
                        Text("1.25x").tag(Float(1.25))
                        Text("1.5x").tag(Float(1.5))
                        Text("1.75x").tag(Float(1.75))
                        Text("2.0x").tag(Float(2.0))
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Playback")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Toggle("Auto-Transcribe", isOn: $appState.appSettings.autoTranscribe)
                        .tint(palette.toggleOnTint)
                        .listRowBackground(palette.cardBackground)

                    Picker("Language", selection: $appState.appSettings.transcriptionLanguage) {
                        ForEach(TranscriptionLanguage.allCases) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Transcription")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Automatically transcribe new recordings when saved.")

                        if !appState.appSettings.autoTranscribe {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text("Without transcripts, recordings won't appear in transcript search and Smart Naming won't work. You can still manually transcribe individual recordings.")
                            }
                            .font(.caption)
                        }
                    }
                    .foregroundColor(palette.textSecondary)
                }

                Section {
                    HStack {
                        Toggle("Auto-Select Icon", isOn: $appState.appSettings.autoSelectIcon)
                            .tint(palette.toggleOnTint)
                            .onChange(of: appState.appSettings.autoSelectIcon) { oldValue, enabled in
                                if enabled && !appState.supportManager.canUseProFeatures && !ProFeatureContext.autoIcons.isFree {
                                    appState.appSettings.autoSelectIcon = false
                                    proUpgradeContext = .autoIcons
                                    return
                                }
                                // Avoid acting on programmatic revert (false -> false)
                                guard oldValue != enabled else { return }
                            }

                        Button {
                            showAutoIconInfo = true
                        } label: {
                            Image(systemName: "info.circle")
                                .font(.system(size: 18))
                                .foregroundColor(palette.accent)
                        }
                        .buttonStyle(.plain)
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    HStack(spacing: 6) {
                        Text("Smart Detection")
                        if !appState.supportManager.canUseProFeatures { ProBadge() }
                    }
                    .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Automatically detect audio type (voice, guitar, drums, keys) and set the recording icon.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Auto-Naming Section
                Section {
                    Toggle("Location-based naming", isOn: $appState.appSettings.locationNamingEnabled)
                        .tint(palette.toggleOnTint)
                        .listRowBackground(palette.cardBackground)
                        .onChange(of: appState.appSettings.locationNamingEnabled) { _, isOn in
                            // Mutually exclusive: turn off smart naming when location is enabled
                            if isOn && appState.appSettings.contextNamingEnabled {
                                appState.appSettings.contextNamingEnabled = false
                            }
                        }

                    Toggle(isOn: $appState.appSettings.contextNamingEnabled) {
                        HStack(spacing: 8) {
                            Text("Smart Naming")
                            if isAppleIntelligenceAvailable {
                                Image(systemName: "apple.intelligence")
                                    .font(.footnote)
                                    .foregroundColor(.purple)
                            }
                        }
                    }
                    .tint(palette.toggleOnTint)
                    .listRowBackground(palette.cardBackground)
                    .onChange(of: appState.appSettings.contextNamingEnabled) { _, isOn in
                        // Mutually exclusive: turn off location naming when smart naming is enabled
                        if isOn && appState.appSettings.locationNamingEnabled {
                            appState.appSettings.locationNamingEnabled = false
                        }
                    }
                } header: {
                    Text("Auto-Naming")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Choose one naming style, or turn both off for generic numbering (\"Recording 1\", etc.).")

                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "location.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            Text("Location naming uses your current place (e.g., \"Starbucks - 2:14 PM\").")
                        }

                        if isAppleIntelligenceAvailable {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "apple.intelligence")
                                    .font(.caption)
                                    .foregroundColor(.purple)
                                Text("Smart Naming combines audio detection (guitar, piano, drums) with transcripts to suggest titles like \"Guitar Practice\" or \"Piano Lesson\". Works for instrumental recordings too. All processing is on-device.")
                            }
                        } else {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "brain")
                                    .font(.caption)
                                Text("Smart Naming combines audio detection (guitar, piano, drums) with transcripts to suggest titles. Works for instrumental recordings too.")
                            }
                        }

                        Text("Duplicate titles are automatically numbered (\"Guitar Recording\", \"Guitar Recording 2\", etc.).")
                            .font(.caption2)
                    }
                    .foregroundColor(palette.textSecondary)
                }

                // MARK: Theme Section
                Section {
                    ForEach(AppTheme.allCases) { theme in
                        Button {
                            appState.selectedTheme = theme
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(theme.displayName)
                                        .font(.body)
                                        .foregroundStyle(palette.textPrimary)
                                    Text(theme.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                }
                                Spacer()
                                if appState.selectedTheme == theme {
                                    Image(systemName: "checkmark")
                                        .font(.body.weight(.semibold))
                                        .foregroundStyle(palette.accent)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    Text("Theme")
                        .foregroundStyle(palette.textSecondary)
                } footer: {
                    Text("Not all pages will change themes.")
                        .foregroundStyle(palette.textSecondary)
                }

                Section {
                    Picker("Appearance", selection: $appState.appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Light/Dark Mode")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Applies when using the System theme.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - iCloud Sync Section
                Section {
                    Toggle("iCloud Sync", isOn: $appState.appSettings.iCloudSyncEnabled)
                        .tint(palette.toggleOnTint)
                        .listRowBackground(palette.cardBackground)
                        .onChange(of: appState.appSettings.iCloudSyncEnabled) { oldValue, enabled in
                            if enabled && !appState.supportManager.canUseProFeatures {
                                appState.appSettings.iCloudSyncEnabled = false
                                proUpgradeContext = .icloudSync
                                return
                            }
                            // Avoid acting on programmatic revert (false -> false)
                            guard oldValue != enabled else { return }
                            Task {
                                if enabled {
                                    await appState.syncManager.enableSync()
                                } else {
                                    appState.syncManager.disableSync()
                                }
                            }
                        }

                    // Sync status row (only when enabled)
                    if appState.appSettings.iCloudSyncEnabled {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 8) {
                                Image(systemName: appState.syncManager.status.iconName)
                                    .foregroundColor(syncStatusColor)
                                    .font(.system(size: 14))

                                Text(appState.syncManager.status.displayText)
                                    .font(.subheadline)
                                    .foregroundColor(palette.textSecondary)

                                Spacer()

                                if appState.syncManager.isSyncing {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .tint(palette.accent)
                                }
                            }

                            // Progress bar when syncing
                            if let progress = appState.syncManager.status.progress, progress > 0 {
                                ProgressView(value: progress)
                                    .tint(palette.accent)
                            }

                            // Show current upload if any
                            if let currentUpload = appState.syncManager.uploadProgress.first(where: { $0.status == .uploading }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.caption2)
                                        .foregroundColor(palette.textTertiary)
                                    Text(currentUpload.fileName)
                                        .font(.caption2)
                                        .foregroundColor(palette.textTertiary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text("\(Int(currentUpload.progress * 100))%")
                                        .font(.caption2)
                                        .foregroundColor(palette.textTertiary)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .listRowBackground(palette.cardBackground)
                    }
                } header: {
                    SettingsSectionHeader(
                        title: "iCloud",
                        topic: .iCloud,
                        onInfoTap: { activeHelpTopic = .iCloud },
                        showProBadge: !appState.supportManager.canUseProFeatures
                    )
                } footer: {
                    Text("Sync recordings, tags, albums, and projects across all your devices.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Watch Sync Section
                Section {
                    Toggle(isOn: $appState.appSettings.watchSyncEnabled) {
                        HStack(spacing: 8) {
                            Image(systemName: "applewatch")
                                .foregroundColor(.green)
                                .font(.system(size: 14))
                            Text("Auto Sync Watch Recordings")
                        }
                    }
                    .tint(palette.toggleOnTint)
                    .listRowBackground(palette.cardBackground)
                    .onChange(of: appState.appSettings.watchSyncEnabled) { oldValue, enabled in
                        if enabled && !appState.supportManager.canUseProFeatures {
                            appState.appSettings.watchSyncEnabled = false
                            proUpgradeContext = .watchSync
                            return
                        }
                        // Avoid acting on programmatic revert (false -> false)
                        guard oldValue != enabled else { return }
                    }
                } header: {
                    HStack(spacing: 6) {
                        Text("Apple Watch")
                            .foregroundStyle(palette.textSecondary)
                        if !appState.supportManager.canUseProFeatures {
                            ProBadge()
                        }
                    }
                } footer: {
                    Text("Automatically import recordings from the Sonidea Apple Watch app into the ⌚️ Recordings album. Requires the Sonidea watch app and a Pro plan.")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Shared Albums Section
                Section {
                    Button {
                        if requirePro(.sharedAlbums) {
                            showCreateSharedAlbumSheet = true
                        }
                    } label: {
                        HStack(spacing: 12) {
                            // Gold gradient icon
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.65, blue: 0.13)],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .frame(width: 32, height: 32)
                                Image(systemName: "person.2.fill")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundColor(.white)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text("Create Shared Album")
                                    .font(.headline)
                                    .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                                Text("Collaborate with others")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }

                            Spacer()

                            // Premium badge
                            Text("NEW")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    LinearGradient(
                                        colors: [Color(red: 1.0, green: 0.84, blue: 0.0), Color(red: 0.85, green: 0.65, blue: 0.13)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .cornerRadius(4)

                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(palette.cardBackground)

                    // Show existing shared albums count
                    if !appState.sharedAlbums.isEmpty {
                        HStack {
                            Image(systemName: "square.stack.fill")
                                .foregroundColor(Color(red: 0.85, green: 0.65, blue: 0.13))
                                .frame(width: 24)
                            Text("Your Shared Albums")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(appState.sharedAlbums.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(Color(red: 0.85, green: 0.65, blue: 0.13))
                                .cornerRadius(10)
                        }
                        .listRowBackground(palette.cardBackground)
                    }

                    // Debug mode toggle
                    #if DEBUG
                    Toggle(isOn: Binding(
                        get: { appState.isSharedAlbumsDebugMode },
                        set: { newValue in
                            if newValue {
                                appState.enableSharedAlbumsDebugMode()
                            } else {
                                appState.disableSharedAlbumsDebugMode()
                            }
                        }
                    )) {
                        HStack(spacing: 8) {
                            Image(systemName: "ant.fill")
                                .foregroundColor(.purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Demo Mode")
                                    .foregroundColor(palette.textPrimary)
                                Text("Test UI without iCloud")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                        }
                    }
                    .tint(.purple)
                    .listRowBackground(palette.cardBackground)
                    #endif
                } header: {
                    SettingsSectionHeader(
                        title: "Collaboration",
                        topic: .collaboration,
                        onInfoTap: { activeHelpTopic = .collaboration },
                        isGold: true,
                        showProBadge: !appState.supportManager.canUseProFeatures
                    )
                } footer: {
                    #if DEBUG
                    if appState.isSharedAlbumsDebugMode {
                        Text("Demo mode active - showing sample shared album data. Disable to remove demo content.")
                            .foregroundColor(.purple)
                    } else {
                        Text("Collaborate on albums with up to 5 people. Share audio recordings in real-time with role-based permissions.")
                            .foregroundColor(palette.textSecondary)
                    }
                    #else
                    Text("Collaborate on albums with up to 5 people. Share audio recordings in real-time with role-based permissions.")
                        .foregroundColor(palette.textSecondary)
                    #endif
                }

                Section {
                    Button {
                        if requirePro(.tags) {
                            showTagManager = true
                        }
                    } label: {
                        HStack {
                            Image(systemName: "tag.fill")
                                .foregroundColor(palette.accent)
                            Text("Manage Tags")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(appState.tags.count)")
                                .foregroundColor(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    SettingsSectionHeader(
                        title: "Tags",
                        topic: .tags,
                        onInfoTap: { activeHelpTopic = .tags },
                        showProBadge: !appState.supportManager.canUseProFeatures
                    )
                }

                Section {
                    Button {
                        bulkExportAlbum = nil
                        showBulkFormatPicker = true
                    } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(palette.accent)
                            Text("Export All Recordings")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if isExporting && exportProgress == "all" {
                                ProgressView()
                                    .tint(palette.accent)
                            }
                        }
                    }
                    .disabled(isExporting || appState.activeRecordings.isEmpty)
                    .listRowBackground(palette.cardBackground)

                    Button { showAlbumPicker = true } label: {
                        HStack {
                            Image(systemName: "square.stack")
                                .foregroundColor(palette.accent)
                            Text("Export Album...")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            if isExporting && exportProgress == "album" {
                                ProgressView()
                                    .tint(palette.accent)
                            }
                        }
                    }
                    .disabled(isExporting || appState.albums.isEmpty)
                    .listRowBackground(palette.cardBackground)

                    Button { showFileImporter = true } label: {
                        HStack {
                            Image(systemName: "square.and.arrow.down")
                                .foregroundColor(palette.accent)
                            Text("Import Recordings")
                                .foregroundColor(palette.textPrimary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Export & Import")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Export as WAV files in ZIP. Import m4a, wav, mp3, or aiff files.")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    Button { showTrashView = true } label: {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("View Trash")
                                .foregroundColor(palette.textPrimary)
                            Spacer()
                            Text("\(appState.trashedCount) items")
                                .foregroundColor(palette.textSecondary)
                            Image(systemName: "chevron.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Button(role: .destructive) { showEmptyTrashAlert = true } label: {
                        HStack {
                            Image(systemName: "trash.slash")
                            Text("Empty Trash Now")
                        }
                    }
                    .disabled(appState.trashedCount == 0)
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("Trash")
                        .foregroundColor(palette.textSecondary)
                } footer: {
                    Text("Items in trash are automatically deleted after 30 days.")
                        .foregroundColor(palette.textSecondary)
                }

                Section {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(palette.textSecondary)
                        Text("Sonidea")
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        Text("2.0")
                            .foregroundColor(palette.textSecondary)
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://www.notion.so/sonidea/Sonidea-Privacy-Policy-2f72934c965380a3bafaf7967e2295df")!) {
                        HStack {
                            Image(systemName: "hand.raised")
                                .foregroundColor(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Privacy Policy")
                                    .foregroundColor(palette.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://sonidea.notion.site/Sonidea-Terms-and-Conditions-2fb2934c965380fe8461ef99bab80490")!) {
                        HStack {
                            Image(systemName: "doc.text")
                                .foregroundColor(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Terms of Use")
                                    .foregroundColor(palette.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://forms.gle/rmEQg3nXDaoHCGj5A")!) {
                        HStack {
                            Image(systemName: "ladybug")
                                .foregroundColor(.red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Report a Bug")
                                    .foregroundColor(palette.textPrimary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)

                    Link(destination: URL(string: "https://forms.gle/4Hf5DMDJBCD9gdir6")!) {
                        HStack {
                            Image(systemName: "lightbulb")
                                .foregroundColor(.yellow)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("App Suggestions")
                                    .foregroundColor(palette.textPrimary)
                                Text("Tell us what you'd like to see in our app.")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("About")
                        .foregroundColor(palette.textSecondary)
                }

                // MARK: - Sync Now Button (Bottom of Settings)
                if appState.appSettings.iCloudSyncEnabled {
                    Section {
                        Button {
                            Task { await appState.syncManager.syncNow() }
                        } label: {
                            HStack {
                                Spacer()
                                if appState.syncManager.isSyncing {
                                    ProgressView()
                                        .tint(.white)
                                        .padding(.trailing, 8)
                                }
                                Text(appState.syncManager.isSyncing ? "Syncing..." : "Sync Now")
                                    .fontWeight(.semibold)
                                Spacer()
                            }
                            .foregroundColor(.white)
                            .padding(.vertical, 12)
                            .background(appState.syncManager.isSyncing ? Color.gray : palette.accent)
                            .cornerRadius(10)
                        }
                        .disabled(appState.syncManager.isSyncing)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                }

                #if DEBUG
                // MARK: - Debug Tier Testing
                Section {
                    let mgr = appState.supportManager
                    Picker("Tier Override", selection: Binding<Int>(
                        get: {
                            if mgr.debugProOverride == nil { return 0 }
                            return mgr.debugProOverride == true ? 1 : 2
                        },
                        set: { val in
                            switch val {
                            case 1: mgr.debugProOverride = true
                            case 2: mgr.debugProOverride = false
                            default: mgr.debugProOverride = nil
                            }
                        }
                    )) {
                        Text("Normal").tag(0)
                        Text("Force Pro").tag(1)
                        Text("Force Free").tag(2)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(palette.cardBackground)
                } header: {
                    Text("DEBUG")
                        .foregroundColor(.red)
                }
                #endif

                // MARK: - Factory Reset
                Section {
                    Button(role: .destructive) {
                        showResetStep1 = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                                .foregroundColor(.red)
                            Text("Reset App")
                                .foregroundColor(.red)
                        }
                    }
                    .listRowBackground(palette.cardBackground)
                } footer: {
                    Text("Erase all recordings, albums, tags, projects, and settings. The app will return to its initial state.")
                        .foregroundColor(palette.textSecondary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(palette.groupedBackground)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Guide") {
                        showGuide = true
                    }
                    .foregroundColor(palette.accent)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
            .alert("Reset App?", isPresented: $showResetStep1) {
                Button("Cancel", role: .cancel) {}
                Button("I Understand, Continue", role: .destructive) {
                    resetConfirmText = ""
                    showResetLoading = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        showResetLoading = false
                        showResetStep2 = true
                    }
                }
            } message: {
                Text("This will permanently delete ALL your recordings, albums, tags, projects, overdubs, and settings.\n\nPlease back up any recordings you want to keep before proceeding.")
            }
            .fullScreenCover(isPresented: $showResetLoading) {
                ZStack {
                    palette.background.ignoresSafeArea()
                    VStack(spacing: 24) {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.red)
                        Text("Preparing reset...")
                            .font(.headline)
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
            .sheet(isPresented: $showResetStep2) {
                NavigationStack {
                    ScrollView {
                        VStack(spacing: 24) {
                            Spacer().frame(height: 40)

                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.red)

                            Text("This Cannot Be Undone")
                                .font(.title2)
                                .fontWeight(.bold)
                                .foregroundColor(palette.textPrimary)

                            Text("Type RESET below to confirm you want to erase all app data and return to factory settings.")
                                .font(.subheadline)
                                .foregroundColor(palette.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal)

                            TextField("Type RESET", text: $resetConfirmText)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .padding(.horizontal, 40)

                            Button(role: .destructive) {
                                appState.factoryReset()
                                showResetStep2 = false
                                dismiss()
                            } label: {
                                Text("Erase Everything")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(resetConfirmText == "RESET" ? Color.red : Color.gray.opacity(0.3))
                                    .foregroundColor(.white)
                                    .cornerRadius(12)
                            }
                            .disabled(resetConfirmText != "RESET")
                            .padding(.horizontal, 40)

                            Spacer().frame(height: 40)
                        }
                    }
                    .background(palette.background)
                    .navigationTitle("Confirm Reset")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showResetStep2 = false
                            }
                            .foregroundColor(palette.accent)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
            }
            .tint(palette.accent)
            .sheet(isPresented: $showGuide) {
                GuideView()
            }
            .sheet(item: $activeHelpTopic) { topic in
                HelpSheetView(topic: topic)
            }
            .sheet(isPresented: $showMicrophoneSheet) {
                MicrophoneSelectorSheet()
            }
            .sheet(isPresented: $showStorageEstimateSheet) {
                StorageEstimateSheet()
            }
            .sheet(isPresented: $showShareSheet) {
                if let url = exportedZIPURL {
                    ShareSheet(items: [url])
                }
            }
            .sheet(isPresented: $showAlbumPicker) {
                ExportAlbumPickerSheet { album in
                    bulkExportAlbum = album
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        showBulkFormatPicker = true
                    }
                }
            }
            .sheet(isPresented: $showTagManager) {
                TagManagerView()
            }
            .sheet(item: $proUpgradeContext) { context in
                ProUpgradeSheet(
                    context: context,
                    onViewPlans: {
                        proUpgradeContext = nil
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showSupport = true
                        }
                    },
                    onDismiss: {
                        proUpgradeContext = nil
                    }
                )
                .environment(\.themePalette, palette)
            }
            .iPadSheet(isPresented: $showSupport) {
                SupportView()
                    .environment(appState)
                    .environment(\.themePalette, palette)
            }
            .sheet(isPresented: $showTrashView) {
                TrashView()
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio, .mpeg4Audio, .wav, .mp3, .aiff],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    pendingImportURLs = urls
                    showImportDestinationSheet = true
                case .failure(let error):
                    importErrors = [error.localizedDescription]
                    showImportErrorAlert = true
                }
            }
            .sheet(isPresented: $showImportDestinationSheet) {
                ImportDestinationSheet(
                    urls: pendingImportURLs,
                    onImport: { albumID in
                        performImport(urls: pendingImportURLs, albumID: albumID)
                    }
                )
            }
            .alert("Import Error", isPresented: $showImportErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(importErrors.joined(separator: "\n"))
            }
            .alert("Empty Trash?", isPresented: $showEmptyTrashAlert) {
                Button("Cancel", role: .cancel) {}
                Button("Empty Trash", role: .destructive) { appState.emptyTrash() }
            } message: {
                Text("This will permanently delete \(appState.trashedCount) items. This cannot be undone.")
            }
            .sheet(isPresented: $showLockScreenHelp) {
                LockScreenWidgetHelpSheet()
            }
            .sheet(isPresented: $showActionButtonHelp) {
                ActionButtonHelpSheet()
            }
            .sheet(isPresented: $showSiriShortcutsHelp) {
                SiriShortcutsHelpSheet()
            }
            .sheet(isPresented: $showCreateSharedAlbumSheet) {
                CreateSharedAlbumSheet()
            }
            .sheet(isPresented: $showAutoIconInfo) {
                AutoIconInfoSheet()
                    .presentationDetents([.height(280)])
                    .presentationDragIndicator(.visible)
            }
            .sheet(isPresented: $showBulkFormatPicker) {
                BulkExportFormatPicker { formats in
                    if let album = bulkExportAlbum {
                        exportAlbum(album, formats: formats)
                    } else {
                        exportAllRecordings(formats: formats)
                    }
                }
            }
        }
    }

    private func exportAllRecordings(formats: Set<ExportFormat>) {
        isExporting = true
        exportProgress = "all"
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    appState.activeRecordings,
                    scope: .all,
                    formats: formats,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                exportProgress = ""
                showShareSheet = true
                appState.onExportSuccess()
            } catch {
                isExporting = false
                exportProgress = "Export failed: \(error.localizedDescription)"
                // Auto-clear error message after 3 seconds
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if exportProgress.hasPrefix("Export failed") { exportProgress = "" }
                }
            }
        }
    }

    private func exportAlbum(_ album: Album, formats: Set<ExportFormat>) {
        isExporting = true
        exportProgress = "album"
        Task {
            do {
                let recordings = appState.recordings(in: album)
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    recordings,
                    scope: .album(album),
                    formats: formats,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                exportProgress = ""
                showShareSheet = true
                appState.onExportSuccess()
            } catch {
                isExporting = false
                exportProgress = "Export failed: \(error.localizedDescription)"
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if exportProgress.hasPrefix("Export failed") { exportProgress = "" }
                }
            }
        }
    }

    private func performImport(urls: [URL], albumID: UUID) {
        Task {
            var errors: [String] = []

            for url in urls {
                guard url.startAccessingSecurityScopedResource() else {
                    errors.append("\(url.lastPathComponent): Access denied")
                    continue
                }

                let duration = await Task.detached {
                    self.getAudioDuration(url: url)
                }.value
                let title = titleFromFilename(url.lastPathComponent)

                do {
                    try appState.importRecording(from: url, duration: duration, title: title, albumID: albumID)
                } catch {
                    errors.append("\(url.lastPathComponent): \(error.localizedDescription)")
                }

                url.stopAccessingSecurityScopedResource()
            }

            pendingImportURLs = []

            if !errors.isEmpty {
                importErrors = errors
                showImportErrorAlert = true
            }
        }
    }

    private func titleFromFilename(_ filename: String) -> String {
        // Remove extension
        var name = (filename as NSString).deletingPathExtension

        // Replace underscores and dashes with spaces
        name = name.replacingOccurrences(of: "_", with: " ")
        name = name.replacingOccurrences(of: "-", with: " ")

        // Collapse multiple spaces
        while name.contains("  ") {
            name = name.replacingOccurrences(of: "  ", with: " ")
        }

        // Trim whitespace
        name = name.trimmingCharacters(in: .whitespaces)

        // Fallback if empty
        if name.isEmpty {
            return "Imported Recording"
        }

        return name
    }

    private func getAudioDuration(url: URL) -> TimeInterval {
        do {
            let audioFile = try AVAudioFile(forReading: url)
            return Double(audioFile.length) / audioFile.processingFormat.sampleRate
        } catch {
            return 0
        }
    }

    /// Display name for the currently selected microphone
    private var microphoneDisplayName: String {
        // If no preferred UID, show "Automatic"
        guard let preferredUID = appState.appSettings.preferredInputUID else {
            return "Automatic"
        }

        // Check if the preferred input is currently available
        if let input = AudioSessionManager.shared.input(for: preferredUID) {
            return input.portName
        }

        // Preferred input not available
        return "Not connected"
    }
}
