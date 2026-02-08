//
//  AppState.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import Foundation
import Observation
import SwiftUI
import CoreLocation
import WidgetKit
import os

// MARK: - UI Metrics (for Settings to access container geometry)

struct UIMetrics: Equatable {
    var containerSize: CGSize = .zero
    var safeAreaInsets: EdgeInsets = EdgeInsets()
    var topBarHeight: CGFloat = 72
    var buttonDiameter: CGFloat = 80
}

@MainActor
@Observable
final class AppState {
    private static let logger = Logger(subsystem: "com.iacompa.sonidea", category: "AppState")

    var recordings: [RecordingItem] = [] {
        didSet {
            recordingsContentVersion += 1
            invalidateRecordingsCache()
            clearSizeCache()
        }
    }
    /// Increments on any recordings mutation; views can observe this to detect content changes
    private(set) var recordingsContentVersion: Int = 0
    var tags: [Tag] = []
    var albums: [Album] = [] {
        didSet { invalidateAlbumsCache() }
    }

    // MARK: - Cached Filtered Arrays

    /// Cached filtered arrays, invalidated when source arrays change
    private var _cachedActiveRecordings: [RecordingItem]?
    private var _cachedTrashedRecordings: [RecordingItem]?
    private var _cachedRecordingsWithLocation: [RecordingItem]?
    private var _cachedSharedAlbums: [Album]?
    private var _cachedPersonalAlbums: [Album]?

    private func invalidateRecordingsCache() {
        _cachedActiveRecordings = nil
        _cachedTrashedRecordings = nil
        _cachedRecordingsWithLocation = nil
    }

    private func invalidateAlbumsCache() {
        _cachedSharedAlbums = nil
        _cachedPersonalAlbums = nil
    }
    var projects: [Project] = []
    var overdubGroups: [OverdubGroup] = []
    var appearanceMode: AppearanceMode = .system {
        didSet {
            saveAppearanceMode()
        }
    }
    var selectedTheme: AppTheme = .system {
        didSet {
            saveSelectedTheme()
            PhoneConnectivityManager.shared.sendThemeToWatch(selectedTheme)
        }
    }
    var appSettings: AppSettings = .default {
        didSet {
            saveAppSettings()
            // Apply settings to recorder
            recorder.qualityPreset = appSettings.recordingQuality
            recorder.appSettings = appSettings
            recorder.metronome.isEnabled = appSettings.metronomeEnabled
            recorder.metronome.bpm = appSettings.metronomeBPM
            recorder.metronome.volume = appSettings.metronomeVolume
        }
    }

    let recorder = RecorderManager()
    let locationManager = LocationManager()
    let supportManager = SupportManager()
    let syncManager = iCloudSyncManager()
    let proofManager = ProofManager()
    let sharedAlbumManager = SharedAlbumManager()
    let trialNudgeManager = TrialNudgeManager()

    private(set) var nextRecordingNumber: Int = 1

    private let recordingsKey = "savedRecordings"
    private let tagsKey = "savedTags"
    private let albumsKey = "savedAlbums"
    private let projectsKey = "savedProjects"
    private let overdubGroupsKey = "savedOverdubGroups"
    private let nextNumberKey = "nextRecordingNumber"
    private let appearanceModeKey = "appearanceMode"
    private let selectedThemeKey = "selectedTheme"
    private let tagMigrationKey = "didMigrateFavToFavorite"
    private let appSettingsKey = "appSettings"
    private let draftsMigrationKey = "didMigrateToDrafts"

    // MARK: - Debounced Save Tasks

    /// Coalesces rapid save calls — actual write happens after 0.3s of inactivity
    private var pendingSaveRecordings: Task<Void, Never>?
    private var pendingSaveAlbums: Task<Void, Never>?
    private var pendingSaveTags: Task<Void, Never>?
    private var pendingSaveProjects: Task<Void, Never>?
    private var pendingSaveOverdubGroups: Task<Void, Never>?

    /// Observer for flushing saves when app backgrounds
    private var backgroundObserver: NSObjectProtocol?

    // MARK: - Record Button Position State

    private let recordButtonPosXKey = "recordButtonPosX"
    private let recordButtonPosYKey = "recordButtonPosY"
    private let recordButtonHasStoredKey = "recordButtonHasStored"

    /// The persisted record button position (nil = use default)
    var recordButtonPosition: CGPoint? = nil

    /// Latest UI metrics from ContentView (used by Settings for reset)
    var uiMetrics: UIMetrics = UIMetrics()

    /// Pending recording navigation from Siri/Shortcuts intents.
    /// When set, RecordingsListView will open this recording and clear the value.
    var pendingNavigationRecordingID: UUID? = nil

    init() {
        // CRITICAL: Migrate UserDefaults data to file-based storage on first launch
        DataSafetyFileOps.migrateFromUserDefaultsIfNeeded()

        loadAppearanceMode()
        loadSelectedTheme()
        loadAppSettings()
        loadNextRecordingNumber()
        loadTags()
        loadAlbums()
        loadProjects()
        loadOverdubGroups()
        loadRecordings()
        validateOverdubGroupIntegrity()
        seedDefaultTagsIfNeeded()
        ensureDraftsAlbum()
        migrateFavTagToFavorite()
        migrateRecordingsToDrafts()
        migrateInboxToDrafts()
        purgeOldTrashedRecordings()
        recorder.qualityPreset = appSettings.recordingQuality
        recorder.appSettings = appSettings
        recorder.metronome.isEnabled = appSettings.metronomeEnabled
        recorder.metronome.bpm = appSettings.metronomeBPM
        recorder.metronome.volume = appSettings.metronomeVolume
        loadRecordButtonPosition()

        // Flush pending debounced saves when app backgrounds.
        // The closure runs synchronously on .main queue — no Task wrapper —
        // so the writes complete before the app is suspended.
        backgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // MainActor.assumeIsolated is safe here because queue: .main
            // guarantees we're on the main thread already.
            MainActor.assumeIsolated {
                self?.flushPendingSaves()
            }
        }

        // Connect sync manager
        syncManager.appState = self

        // Auto-enable iCloud sync on launch if previously enabled
        if appSettings.iCloudSyncEnabled {
            Task {
                await syncManager.enableSync()
            }
        }

        // Connect shared album manager
        sharedAlbumManager.appState = self

        // Validate shared albums on launch — remove stale shares and enforce access
        Task { [weak self] in
            guard let self else { return }
            // First, enforce subscription-based access (removes all shared albums for free users)
            await self.enforceSharedAlbumAccess()

            // Then, validate that each remaining shared album's share still exists
            // and resolve the current user's role
            var staleAlbums: [Album] = []
            for album in self.albums where album.isShared {
                let exists = await self.sharedAlbumManager.validateShareExists(for: album)
                if !exists || self.sharedAlbumManager.shareStale {
                    Self.logger.info("Removing stale shared album: \(album.name)")
                    staleAlbums.append(album)
                    self.sharedAlbumManager.shareStale = false
                } else if album.currentUserRole == nil {
                    // Resolve the current user's role from the CKShare
                    let resolved = await self.sharedAlbumManager.resolveCurrentUserRole(for: album)
                    if resolved.currentUserRole != nil {
                        if let currentIndex = self.albums.firstIndex(where: { $0.id == album.id }) {
                            self.albums[currentIndex] = resolved
                        }
                    }
                }
            }
            for album in staleAlbums {
                self.removeSharedAlbum(album)
                self.clearSharedRecordingInfoCache()
            }
        }

        // Handle Pro access loss - reset Pro-gated settings
        supportManager.onProAccessLost = { [weak self] in
            self?.enforceFreeTierSettings()
        }

        // Enforce free tier settings on launch if Pro access is already lost
        if !supportManager.canUseProFeatures {
            enforceFreeTierSettings()
        }
    }

    // MARK: - Pro Feature Enforcement

    /// Reset all Pro-gated settings to free tier defaults when Pro access is lost.
    /// This prevents users from exploiting features after trial/subscription ends.
    func enforceFreeTierSettings() {
        var settingsChanged = false
        var settings = appSettings

        // Auto-select icon is a Pro feature (skip if temporarily free)
        if settings.autoSelectIcon && !ProFeatureContext.autoIcons.isFree {
            settings.autoSelectIcon = false
            settingsChanged = true
        }

        // iCloud sync is a Pro feature
        if settings.iCloudSyncEnabled {
            settings.iCloudSyncEnabled = false
            settingsChanged = true
        }

        // Watch sync is a Pro feature
        if settings.watchSyncEnabled {
            settings.watchSyncEnabled = false
            settingsChanged = true
        }

        // Metronome is a Pro feature
        if settings.metronomeEnabled && !ProFeatureContext.metronome.isFree {
            settings.metronomeEnabled = false
            settingsChanged = true
        }

        // Assign once to trigger a single didSet
        if settingsChanged {
            appSettings = settings
        }
    }

    // MARK: - Record Button Position Management

    /// Load persisted record button position
    private func loadRecordButtonPosition() {
        let hasStored = UserDefaults.standard.bool(forKey: recordButtonHasStoredKey)
        guard hasStored else {
            recordButtonPosition = nil
            return
        }
        let x = CGFloat(UserDefaults.standard.double(forKey: recordButtonPosXKey))
        let y = CGFloat(UserDefaults.standard.double(forKey: recordButtonPosYKey))
        recordButtonPosition = CGPoint(x: x, y: y)
    }

    /// Persist record button position
    func persistRecordButtonPosition() {
        guard let pos = recordButtonPosition else {
            UserDefaults.standard.set(false, forKey: recordButtonHasStoredKey)
            UserDefaults.standard.removeObject(forKey: recordButtonPosXKey)
            UserDefaults.standard.removeObject(forKey: recordButtonPosYKey)
            return
        }
        UserDefaults.standard.set(true, forKey: recordButtonHasStoredKey)
        UserDefaults.standard.set(Double(pos.x), forKey: recordButtonPosXKey)
        UserDefaults.standard.set(Double(pos.y), forKey: recordButtonPosYKey)
    }

    /// Clamp a position to valid bounds (container coordinate space)
    func clampRecordButtonPosition(
        _ point: CGPoint,
        containerSize: CGSize,
        safeInsets: EdgeInsets,
        topBarHeight: CGFloat,
        buttonDiameter: CGFloat
    ) -> CGPoint {
        let radius = buttonDiameter / 2
        let padding: CGFloat = 12

        let minX = padding + radius
        let maxX = containerSize.width - padding - radius
        let minY = topBarHeight + padding + radius
        // Allow button to go very low - just above the home indicator with minimal margin
        let maxY = containerSize.height - radius - 8

        let clampedX = min(max(point.x, minX), maxX)
        let clampedY = min(max(point.y, minY), maxY)

        return CGPoint(x: clampedX, y: clampedY)
    }

    /// Compute default position (bottom-center, Voice Memos style)
    func defaultRecordButtonPosition(
        containerSize: CGSize,
        safeInsets: EdgeInsets,
        topBarHeight: CGFloat,
        buttonDiameter: CGFloat
    ) -> CGPoint {
        let radius = buttonDiameter / 2

        let centerX = containerSize.width / 2
        // Position just above home indicator with small margin
        let bottomY = containerSize.height - radius - 24

        return CGPoint(x: centerX, y: bottomY)
    }

    /// Reset record button to default position
    func resetRecordButtonPosition() {
        // Use stored metrics if available, otherwise nil triggers default on next render
        if uiMetrics.containerSize.width > 0 && uiMetrics.containerSize.height > 0 {
            let defaultPos = defaultRecordButtonPosition(
                containerSize: uiMetrics.containerSize,
                safeInsets: uiMetrics.safeAreaInsets,
                topBarHeight: uiMetrics.topBarHeight,
                buttonDiameter: uiMetrics.buttonDiameter
            )
            recordButtonPosition = defaultPos
        } else {
            recordButtonPosition = nil
        }
        persistRecordButtonPosition()
    }

    /// Update and clamp position (called on drag end)
    func updateRecordButtonPosition(_ newPosition: CGPoint) {
        let clamped = clampRecordButtonPosition(
            newPosition,
            containerSize: uiMetrics.containerSize,
            safeInsets: uiMetrics.safeAreaInsets,
            topBarHeight: uiMetrics.topBarHeight,
            buttonDiameter: uiMetrics.buttonDiameter
        )
        recordButtonPosition = clamped
        persistRecordButtonPosition()
    }

    // MARK: - Support Manager Hooks

    /// Call when app becomes active/foreground
    func onAppBecameActive() {
        supportManager.registerActiveDayIfNeeded()
    }

    /// Call when recording is saved
    func onRecordingSaved() {
        supportManager.onRecordingSaved(totalRecordings: activeRecordings.count)
    }

    /// Call when export succeeds
    func onExportSuccess() {
        supportManager.onExportSuccess(totalRecordings: activeRecordings.count)
    }

    /// Call when transcription succeeds
    func onTranscriptionSuccess() {
        supportManager.onTranscriptionSuccess(totalRecordings: activeRecordings.count)
    }

    /// Call when recording state changes
    func onRecordingStateChanged(isRecording: Bool) {
        supportManager.setRecordingState(isRecording)
    }

    // MARK: - Filtered Recording Lists

    /// Active recordings (not trashed) — cached, invalidated when recordings change
    var activeRecordings: [RecordingItem] {
        if let cached = _cachedActiveRecordings { return cached }
        let result = recordings.filter { !$0.isTrashed }
        _cachedActiveRecordings = result
        return result
    }

    /// Trashed recordings — cached, invalidated when recordings change
    var trashedRecordings: [RecordingItem] {
        if let cached = _cachedTrashedRecordings { return cached }
        let result = recordings.filter { $0.isTrashed }
        _cachedTrashedRecordings = result
        return result
    }

    var trashedCount: Int {
        trashedRecordings.count
    }

    /// Recordings with coordinates — cached, invalidated when recordings change
    var recordingsWithLocation: [RecordingItem] {
        if let cached = _cachedRecordingsWithLocation { return cached }
        let result = activeRecordings.filter { $0.hasCoordinates }
        _cachedRecordingsWithLocation = result
        return result
    }

    // MARK: - Recording Management

    /// Result of attempting to add a recording
    enum AddRecordingResult {
        case success(RecordingItem)
        case failure(String)
    }

    /// Add a recording from raw data, returns success/failure result
    @discardableResult
    func addRecording(from rawData: RawRecordingData) -> AddRecordingResult {
        Self.logger.debug("Attempting to add recording from: \(rawData.fileURL.lastPathComponent, privacy: .public), duration: \(rawData.duration)s")

        // Verify the file exists and is valid before adding
        let fileStatus = AudioDebug.verifyAudioFile(url: rawData.fileURL)
        guard fileStatus.isValid else {
            let errorMsg = fileStatus.errorMessage ?? "Unknown verification error"
            Self.logger.error("Cannot add recording - file verification failed: \(errorMsg, privacy: .public)")
            AudioDebug.logFileInfo(url: rawData.fileURL, context: "AppState.addRecording - failed verification")
            return .failure(errorMsg)
        }

        Self.logger.info("File verified, adding recording: \(rawData.fileURL.lastPathComponent, privacy: .public)")

        // Generate title based on settings
        let (title, titleSource) = generateRecordingTitle(locationLabel: rawData.locationLabel)

        // Add metronome BPM note if recorded with metronome
        var notes = ""
        if rawData.wasRecordedWithMetronome, let bpm = rawData.metronomeBPM {
            notes = "Recorded with \(Int(bpm)) BPM metronome"
        }

        let recording = RecordingItem(
            fileURL: rawData.fileURL,
            createdAt: rawData.createdAt,
            duration: rawData.duration,
            title: title,
            notes: notes,
            albumID: Album.draftsID,
            locationLabel: rawData.locationLabel,
            latitude: rawData.latitude,
            longitude: rawData.longitude,
            wasRecordedWithMetronome: rawData.wasRecordedWithMetronome,
            actualSampleRate: rawData.actualSampleRate,
            actualChannelCount: rawData.actualChannelCount,
            titleSourceRaw: titleSource.rawValue
        )

        recordings.insert(recording, at: 0)

        // Persist immediately — new recording must not be lost.
        // Uses the same path as all other mutations to avoid save race conditions.
        persistRecordings()

        Self.logger.info("Recording added successfully: \(title, privacy: .private)")

        // Trigger iCloud sync for new recording
        triggerSyncForNewRecording(recording)

        // Auto-transcribe if enabled
        if appSettings.autoTranscribe {
            Task {
                await autoTranscribe(recording: recording)
            }
        }

        // Auto-classify icon if enabled (Pro feature, or temporarily free)
        if appSettings.autoSelectIcon && (supportManager.canUseProFeatures || ProFeatureContext.autoIcons.isFree) {
            addToPendingClassifications(recording.id)
            Task {
                await autoClassifyIcon(recording: recording)
            }
        }

        // Pre-compute waveform in background so it's cached when user opens the recording
        Task.detached(priority: .utility) {
            await AudioWaveformExtractor.shared.precomputeWaveform(for: rawData.fileURL)
        }

        return .success(recording)
    }

    // MARK: - Auto-Naming

    /// Generate a recording title based on user settings.
    /// Priority: 1. Location (if enabled), 2. Generic ("Recording N")
    /// Context-based titles are generated later after transcription completes.
    private func generateRecordingTitle(locationLabel: String) -> (String, TitleSource) {
        // Priority 1: Location naming (if enabled and available)
        if appSettings.locationNamingEnabled && !locationLabel.isEmpty {
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "h:mm a"
            let time = timeFormatter.string(from: Date())
            // Still increment number for uniqueness tracking
            nextRecordingNumber += 1
            saveNextRecordingNumber()
            return ("\(locationLabel) - \(time)", .location)
        }

        // Default: Generic numbering
        let title = "Recording \(nextRecordingNumber)"
        nextRecordingNumber += 1
        saveNextRecordingNumber()
        return (title, .generic)
    }

    private func autoTranscribe(recording: RecordingItem) async {
        do {
            let result = try await TranscriptionManager.shared.transcribe(
                audioURL: recording.fileURL,
                language: appSettings.transcriptionLanguage
            )
            updateTranscript(result.text, segments: result.segments, for: recording.id)
        } catch {
            Self.logger.error("Auto-transcribe failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: - Icon Classification Retry Queue

    private static let pendingClassificationsKey = "pendingIconClassificationIDs"

    private func addToPendingClassifications(_ id: UUID) {
        var pending = Self.loadPendingClassificationIDs()
        pending.insert(id.uuidString)
        UserDefaults.standard.set(Array(pending), forKey: Self.pendingClassificationsKey)
    }

    private func removeFromPendingClassifications(_ id: UUID) {
        var pending = Self.loadPendingClassificationIDs()
        pending.remove(id.uuidString)
        UserDefaults.standard.set(Array(pending), forKey: Self.pendingClassificationsKey)
    }

    private static func loadPendingClassificationIDs() -> Set<String> {
        let array = UserDefaults.standard.stringArray(forKey: pendingClassificationsKey) ?? []
        return Set(array)
    }

    func retryPendingClassifications() {
        let pendingIDs = Self.loadPendingClassificationIDs()
        guard !pendingIDs.isEmpty else { return }

        #if DEBUG
        print("[AppState] Retrying \(pendingIDs.count) pending icon classifications")
        #endif

        for idString in pendingIDs {
            guard let uuid = UUID(uuidString: idString),
                  let recording = recording(for: uuid),
                  recording.iconSource != .user,
                  recording.iconName == nil || recording.iconSourceRaw != IconSource.auto.rawValue else {
                // Already classified or user-set — remove from queue
                if let uuid = UUID(uuidString: idString) {
                    removeFromPendingClassifications(uuid)
                }
                continue
            }

            Task {
                await autoClassifyIcon(recording: recording)
            }
        }
    }

    private func autoClassifyIcon(recording: RecordingItem) async {
        let taskID = await UIApplication.shared.beginBackgroundTask(withName: "IconClassification") {
            // Expiration handler — classification will be retried on next foreground
        }

        let updated = await AudioIconClassifierManager.shared.classifyAndUpdateIfNeeded(
            recording: recording,
            autoSelectEnabled: appSettings.autoSelectIcon
        )

        // Save if icon changed OR if predictions were updated (bug fix: predictions were silently discarded)
        if updated.iconName != recording.iconName || updated.iconPredictions != recording.iconPredictions {
            await MainActor.run {
                updateRecording(updated)
            }
            removeFromPendingClassifications(recording.id)
        } else if updated.iconName == nil && updated.iconPredictions == nil {
            // Classification produced no results — keep in retry queue
            addToPendingClassifications(recording.id)
        } else {
            // No changes needed — remove from queue
            removeFromPendingClassifications(recording.id)
        }

        await UIApplication.shared.endBackgroundTask(taskID)
    }

    func updateRecording(_ updated: RecordingItem) {
        guard RecordingRepository.updateRecording(updated, recordings: &recordings) else { return }
        saveRecordings()
        if let rec = recording(for: updated.id) {
            triggerSyncForRecording(rec)
        }
    }

    func updateTranscript(_ text: String, segments: [TranscriptionSegment]? = nil, for recordingID: UUID) {
        guard RecordingRepository.updateTranscript(text, segments: segments, for: recordingID, recordings: &recordings) else { return }

        // Generate context-based title if enabled and title is still generic
        if let index = recordings.firstIndex(where: { $0.id == recordingID }) {
            let recording = recordings[index]
            if appSettings.contextNamingEnabled && recording.titleSource == .generic {
                // Use async version for Apple Intelligence support
                let textCopy = text
                let recordingId = recordingID
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    if let autoTitle = await TitleGeneratorService.generateTitle(from: textCopy) {
                        if let idx = self.recordings.firstIndex(where: { $0.id == recordingId }) {
                            self.recordings[idx].autoTitle = autoTitle
                            self.saveRecordings()
                        }
                    }
                }
            }

            // Index transcript for search
            if let segments = segments {
                Task.detached(priority: .utility) {
                    try? await TranscriptSearchService.shared.indexTranscript(
                        recordingId: recording.id,
                        segments: segments,
                        title: recording.title,
                        createdAt: recording.createdAt
                    )
                }
            }
        }

        saveRecordings()
        if let rec = recording(for: recordingID) {
            triggerSyncForRecording(rec)
        }
    }

    func updatePlaybackPosition(_ position: TimeInterval, for recordingID: UUID) {
        RecordingRepository.updatePlaybackPosition(position, for: recordingID, recordings: &recordings)
        saveRecordings()
    }

    func updateRecordingLocation(recordingID: UUID, latitude: Double, longitude: Double, label: String) {
        guard let updated = RecordingRepository.updateRecordingLocation(
            recordingID: recordingID, latitude: latitude, longitude: longitude, label: label, recordings: &recordings
        ) else { return }
        saveRecordings()
        triggerSyncForRecording(updated)
    }

    func clearRecordingLocation(recordingID: UUID) {
        guard let updated = RecordingRepository.clearRecordingLocation(recordingID: recordingID, recordings: &recordings) else {
            return
        }
        saveRecordings()
        triggerSyncForRecording(updated)
    }

    func recording(for id: UUID) -> RecordingItem? {
        RecordingRepository.recording(for: id, in: recordings)
    }

    func recordings(for ids: [UUID]) -> [RecordingItem] {
        RecordingRepository.recordings(for: ids, in: recordings)
    }

    // MARK: - Trash Management

    func moveToTrash(_ recording: RecordingItem) {
        guard RecordingRepository.moveToTrash(recording, recordings: &recordings) else { return }
        saveRecordings()
        if let rec = self.recording(for: recording.id) {
            triggerSyncForRecording(rec)
        }
    }

    func moveToTrash(at offsets: IndexSet, from list: [RecordingItem]) {
        for index in offsets {
            let recording = list[index]
            moveToTrash(recording)
        }
    }

    func restoreFromTrash(_ recording: RecordingItem) {
        guard let restored = RecordingRepository.restoreFromTrash(recording, recordings: &recordings) else { return }
        saveRecordings()
        triggerSyncForRecording(restored)
    }

    func permanentlyDelete(_ recording: RecordingItem) {
        // Remove from transcript search index
        let recordingId = recording.id
        Task.detached(priority: .utility) {
            try? await TranscriptSearchService.shared.removeTranscript(recordingId: recordingId)
        }

        let result = RecordingRepository.permanentlyDelete(
            recording, recordings: &recordings, overdubGroups: &overdubGroups
        )
        for url in result.fileURLsToDelete {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                #if DEBUG
                print("Failed to delete file at \(url.lastPathComponent): \(error)")
                #endif
            }
        }
        persistRecordings()
        if result.overdubGroupsChanged { persistOverdubGroups() }
        for id in result.removedRecordingIDs {
            triggerSyncForDeletion(id)
        }
    }

    func emptyTrash() {
        let result = RecordingRepository.emptyTrash(
            recordings: &recordings, overdubGroups: &overdubGroups
        )
        for url in result.fileURLsToDelete {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                #if DEBUG
                print("Failed to delete file at \(url.lastPathComponent): \(error)")
                #endif
            }
        }
        persistRecordings()
        if result.overdubGroupsChanged { persistOverdubGroups() }
        for id in result.removedRecordingIDs {
            triggerSyncForDeletion(id)
        }
    }

    private func purgeOldTrashedRecordings() {
        let result = RecordingRepository.purgeOldTrashed(
            recordings: &recordings, overdubGroups: &overdubGroups
        )
        guard !result.removedRecordingIDs.isEmpty else { return }
        for url in result.fileURLsToDelete {
            do {
                try FileManager.default.removeItem(at: url)
            } catch {
                #if DEBUG
                print("Failed to delete file at \(url.lastPathComponent): \(error)")
                #endif
            }
        }
        saveRecordings()
        if result.overdubGroupsChanged { saveOverdubGroups() }
        for id in result.removedRecordingIDs {
            triggerSyncForDeletion(id)
        }
    }

    func deleteRecording(_ recording: RecordingItem) {
        // Now moves to trash instead of permanent delete
        moveToTrash(recording)
    }

    /// - Important: `offsets` must refer to indices within `activeRecordings` (non-trashed recordings only).
    ///   Callers using indices from a different source (e.g. `recordings`) will get incorrect results.
    @available(*, deprecated, message: "Use deleteRecording(_:) instead for safety — index-based deletion is fragile when activeRecordings differs from the caller's list.")
    func deleteRecordings(at offsets: IndexSet) {
        // Now moves to trash instead of permanent delete
        for index in offsets {
            let recording = activeRecordings[index]
            moveToTrash(recording)
        }
    }

    // MARK: - Tag Helpers

    func tag(for id: UUID) -> Tag? {
        TagRepository.tag(for: id, in: tags)
    }

    func tags(for ids: [UUID]) -> [Tag] {
        TagRepository.tags(for: ids, in: tags)
    }

    func tagUsageCount(_ tag: Tag) -> Int {
        TagRepository.tagUsageCount(tag, in: recordings)
    }

    func tagExists(name: String, excludingID: UUID? = nil) -> Bool {
        TagRepository.tagExists(name: name, excludingID: excludingID, in: tags)
    }

    @discardableResult
    func createTag(name: String, colorHex: String) -> Tag? {
        guard let tag = TagRepository.createTag(name: name, colorHex: colorHex, tags: &tags) else {
            return nil
        }
        saveTags()
        triggerSyncForMetadata()
        return tag
    }

    func updateTag(_ tag: Tag, name: String, colorHex: String) -> Bool {
        let result = TagRepository.updateTag(tag, name: name, colorHex: colorHex, tags: &tags)
        if result {
            saveTags()
            if let updated = self.tag(for: tag.id) {
                triggerSyncForTagUpdate(updated)
            }
        }
        return result
    }

    func deleteTag(_ tag: Tag) -> Bool {
        let tagId = tag.id
        let result = TagRepository.deleteTag(tag, tags: &tags, recordings: &recordings)
        if result {
            persistTags()
            persistRecordings()
            triggerSyncForTagDeletion(tagId)
        }
        return result
    }

    func mergeTags(sourceTagIDs: Set<UUID>, destinationTagID: UUID) {
        let deletedIDs = TagRepository.mergeTags(
            sourceTagIDs: sourceTagIDs,
            destinationTagID: destinationTagID,
            tags: &tags,
            recordings: &recordings
        )
        persistTags()
        persistRecordings()
        for tagID in deletedIDs {
            triggerSyncForTagDeletion(tagID)
        }
        triggerSyncForMetadata()
    }

    func moveTag(from source: IndexSet, to destination: Int) {
        TagRepository.moveTags(from: source, to: destination, tags: &tags)
        saveTags()
    }

    func toggleTag(_ tag: Tag, for recording: RecordingItem) -> RecordingItem {
        let updated = TagRepository.toggleTag(tag, on: recording)
        updateRecording(updated)
        return updated
    }

    func toggleFavorite(for recording: RecordingItem) -> RecordingItem {
        guard let favoriteTag = tags.first(where: { $0.name.lowercased() == "favorite" }) else {
            return recording
        }
        return toggleTag(favoriteTag, for: recording)
    }

    func isFavorite(_ recording: RecordingItem) -> Bool {
        TagRepository.isFavorite(recording)
    }

    /// Get the favorite tag ID (always exists as it's protected)
    var favoriteTagID: UUID {
        Tag.favoriteTagID
    }

    // MARK: - Album Helpers

    func album(for id: UUID?) -> Album? {
        AlbumRepository.album(for: id, in: albums)
    }

    @discardableResult
    func createAlbum(name: String) -> Album {
        let album = AlbumRepository.createAlbum(name: name, albums: &albums)
        saveAlbums()
        triggerSyncForMetadata()
        return album
    }

    func deleteAlbum(_ album: Album) {
        let albumId = album.id
        guard AlbumRepository.deleteAlbum(album, albums: &albums, recordings: &recordings) else { return }
        persistAlbums()
        persistRecordings()
        triggerSyncForAlbumDeletion(albumId)
    }

    func setAlbum(_ album: Album?, for recording: RecordingItem) -> RecordingItem {
        var updated = recording
        updated.albumID = album?.id ?? Album.draftsID
        updateRecording(updated)
        return updated
    }

    private func ensureDraftsAlbum() {
        let result = AlbumRepository.ensureDraftsAlbum(albums: &albums, recordings: &recordings)
        if result.albumsChanged { persistAlbums() }
        if result.recordingsChanged { persistRecordings() }
    }

    /// Ensure the Imports system album exists (called on first external import)
    func ensureImportsAlbum() {
        guard AlbumRepository.ensureImportsAlbum(albums: &albums) else { return }
        saveAlbums()
        triggerSyncForAlbum(Album.imports)
    }

    /// Check if Imports album exists
    var hasImportsAlbum: Bool {
        albums.contains(where: { $0.id == Album.importsID })
    }

    /// Ensure the Watch Recordings system album exists (called on first watch import)
    func ensureWatchRecordingsAlbum() {
        guard AlbumRepository.ensureWatchRecordingsAlbum(albums: &albums) else { return }
        saveAlbums()
        triggerSyncForAlbum(Album.watchRecordings)
    }

    // MARK: - Shared Album Management

    /// Get all shared albums — cached, invalidated when albums change
    var sharedAlbums: [Album] {
        if let cached = _cachedSharedAlbums { return cached }
        let result = albums.filter { $0.isShared }
        _cachedSharedAlbums = result
        return result
    }

    /// Get non-shared albums (for album picker sections) — cached, invalidated when albums change
    var personalAlbums: [Album] {
        if let cached = _cachedPersonalAlbums { return cached }
        let result = albums.filter { !$0.isShared }
        _cachedPersonalAlbums = result
        return result
    }

    /// Add a newly created shared album
    func addSharedAlbum(_ album: Album) {
        // Pro feature check - don't add if user doesn't have access
        guard supportManager.canUseProFeatures else {
            return
        }

        albums.append(album)
        saveAlbums()

        // Trigger iCloud sync
        triggerSyncForAlbum(album)

        // Schedule trial expiration warnings if on trial
        scheduleSharedAlbumTrialWarningsIfNeeded()
    }

    /// Remove a shared album (when leaving or owner stops sharing)
    func removeSharedAlbum(_ album: Album) {
        guard album.isShared else { return }

        let albumId = album.id
        albums.removeAll { $0.id == albumId }

        // Remove recordings associated with this shared album from local state
        // (They live in CloudKit shared zone, not locally persisted)
        recordings.removeAll { $0.albumID == albumId }

        saveAlbums()
        saveRecordings()
    }

    // MARK: - Free User Shared Album Enforcement

    /// Check if user can access shared albums (pro feature)
    var canAccessSharedAlbums: Bool {
        supportManager.canUseProFeatures
    }

    /// Check and enforce shared album access on app launch/foreground.
    /// Removes free users from shared albums when trial expires.
    func enforceSharedAlbumAccess() async {
        // If user has pro access, nothing to enforce
        guard !supportManager.canUseProFeatures else {
            // User subscribed - cancel any pending warnings
            supportManager.cancelSharedAlbumTrialWarnings()
            return
        }

        let userSharedAlbums = sharedAlbums

        // If user has shared albums but no pro access, remove them
        if !userSharedAlbums.isEmpty {
            // Leave all shared albums
            for album in userSharedAlbums {
                do {
                    // Leave the CloudKit share (this also removes their recordings)
                    if !album.isOwner {
                        try await sharedAlbumManager.leaveSharedAlbum(album)
                    } else {
                        // If they're the owner, we can't force them to leave - but they lose access
                        // Just remove from local state; share stays in CloudKit
                    }
                } catch {
                    // Log error but continue - we'll remove from local state anyway
                    Self.logger.error("Failed to leave shared album \(album.name, privacy: .private): \(error.localizedDescription, privacy: .public)")
                }

                // Remove from local state
                removeSharedAlbum(album)
            }

            // Clear caches
            clearSharedRecordingInfoCache()
        }
    }

    /// Schedule trial expiration notifications if user has shared albums
    /// Note: Trials are now handled by StoreKit intro offers, not local trial tracking.
    func scheduleSharedAlbumTrialWarningsIfNeeded() {
        // No-op: trials are now handled by StoreKit intro offers
    }

    /// Update shared album properties (participant count, etc.)
    func updateSharedAlbum(_ album: Album) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index] = album
        saveAlbums()
    }

    /// Check if recording can be added to album (handles shared album consent)
    func canAddRecordingToAlbum(_ album: Album, skipConsent: Bool = false) -> Bool {
        // For shared albums, check if consent is required
        if album.isShared && !album.skipAddRecordingConsent && !skipConsent {
            return false  // Need to show consent sheet
        }
        return true
    }

    /// Update shared album consent preference
    func setSkipConsentForAlbum(_ album: Album, skip: Bool) {
        guard let index = albums.firstIndex(where: { $0.id == album.id }) else { return }
        albums[index].skipAddRecordingConsent = skip
        saveAlbums()
    }

    /// Add recording to shared album (with CloudKit sync)
    func addRecordingToSharedAlbum(_ recording: RecordingItem, album: Album) {
        guard album.isShared else {
            // Not shared, use regular method
            _ = setAlbum(album, for: recording)
            return
        }

        // Update local state
        var updated = recording
        updated.albumID = album.id
        updated.modifiedAt = Date()
        updateRecording(updated)

        // Sync to CloudKit shared zone
        Task {
            do {
                try await sharedAlbumManager.addRecordingToSharedAlbum(recording: updated, album: album)
            } catch {
                Self.logger.error("Failed to sync recording to shared album: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Delete recording from shared album (deletes for everyone)
    func deleteRecordingFromSharedAlbum(_ recording: RecordingItem, album: Album) async throws {
        guard album.isShared else {
            // Not shared, use regular delete
            moveToTrash(recording)
            return
        }

        // Delete from CloudKit first — only remove locally on success
        let recordingId = recording.id
        try await sharedAlbumManager.deleteRecordingFromSharedAlbum(recordingId: recordingId, album: album)

        // CloudKit succeeded — now remove locally
        recordings.removeAll { $0.id == recordingId }
        saveRecordings()
    }

    // MARK: - Enhanced Shared Album Management

    /// Cached current CloudKit user ID (populated on launch / shared album access)
    var cachedCurrentUserId: String?

    /// Cache for shared recording metadata
    var sharedRecordingInfoCache: [UUID: SharedRecordingItem] = [:]

    /// Local activity events (for simulator/offline — merged into activity feed)
    var localActivityEvents: [SharedAlbumActivityEvent] = []

    /// Get shared recording info for a recording (from cache or creates default)
    func sharedRecordingInfo(for recording: RecordingItem, in album: Album) -> SharedRecordingItem? {
        guard album.isShared else { return nil }

        if let cached = sharedRecordingInfoCache[recording.id] {
            return cached
        }

        // Create default shared recording info
        return nil
    }

    /// Update cached shared recording info
    func updateSharedRecordingInfo(_ info: SharedRecordingItem) {
        sharedRecordingInfoCache[info.recordingId] = info
    }

    /// Clear shared recording info cache
    func clearSharedRecordingInfoCache() {
        sharedRecordingInfoCache.removeAll()
    }

    /// Move recording to shared album trash
    func moveToSharedAlbumTrash(
        recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        // Check permission: admin can delete anything, members only if allowed
        let userId = await sharedAlbumManager.getCurrentUserId() ?? "unknown"
        cachedCurrentUserId = userId
        let isOwnRecording = sharedInfo.creatorId == userId
        let canDelete = album.canDeleteAnyRecording || (isOwnRecording && album.canDeleteOwnRecording)
        guard canDelete else {
            throw SharedAlbumError.permissionDenied
        }

        let displayName = await sharedAlbumManager.getCurrentUserDisplayName()

        let trashItem = try await sharedAlbumManager.moveToTrash(
            recording: sharedInfo,
            localRecording: recording,
            album: album,
            deletedBy: userId,
            deletedByDisplayName: displayName
        )

        // Remove from local recordings
        recordings.removeAll { $0.id == recording.id }
        saveRecordings()

        // Clear from cache
        sharedRecordingInfoCache.removeValue(forKey: recording.id)
    }

    /// Restore recording from shared album trash
    func restoreFromSharedAlbumTrash(
        trashItem: SharedAlbumTrashItem,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.restoreFromTrash(trashItem: trashItem, album: album)

        // The recording will be re-synced from CloudKit
        // For now, we don't need to do anything local
    }

    /// Update location sharing for a recording in shared album
    func updateLocationSharing(
        for recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        mode: LocationSharingMode,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.updateLocationSharing(
            recording: sharedInfo,
            mode: mode,
            album: album,
            latitude: recording.latitude,
            longitude: recording.longitude,
            placeName: recording.locationLabel
        )

        // Update cache with new mode
        var updatedInfo = sharedInfo
        updatedInfo.locationSharingMode = mode
        if mode != .none, let lat = recording.latitude, let lon = recording.longitude {
            if let approx = SharedRecordingItem.approximateLocation(latitude: lat, longitude: lon, mode: mode) {
                updatedInfo.sharedLatitude = approx.latitude
                updatedInfo.sharedLongitude = approx.longitude
            }
            updatedInfo.sharedPlaceName = recording.locationLabel
        } else {
            updatedInfo.sharedLatitude = nil
            updatedInfo.sharedLongitude = nil
            updatedInfo.sharedPlaceName = nil
        }
        sharedRecordingInfoCache[recording.id] = updatedInfo
    }

    /// Mark recording as sensitive in shared album
    func markRecordingSensitive(
        recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        isSensitive: Bool,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.markRecordingSensitive(
            recording: sharedInfo,
            isSensitive: isSensitive,
            album: album
        )

        // Update cache
        var updatedInfo = sharedInfo
        updatedInfo.isSensitive = isSensitive
        updatedInfo.sensitiveApproved = false
        sharedRecordingInfoCache[recording.id] = updatedInfo
    }

    /// Approve or reject a sensitive recording (admin only)
    func approveSensitiveRecording(
        recording: RecordingItem,
        sharedInfo: SharedRecordingItem,
        approved: Bool,
        album: Album
    ) async throws {
        guard album.isShared else { return }

        try await sharedAlbumManager.approveSensitiveRecording(
            recording: sharedInfo,
            approved: approved,
            album: album
        )

        // Update cache
        var updatedInfo = sharedInfo
        updatedInfo.sensitiveApproved = approved
        if approved {
            updatedInfo.sensitiveApprovedBy = await sharedAlbumManager.getCurrentUserId()
            updatedInfo.sensitiveApprovedAt = Date()
        } else {
            updatedInfo.sensitiveApprovedBy = nil
            updatedInfo.sensitiveApprovedAt = nil
        }
        sharedRecordingInfoCache[recording.id] = updatedInfo
    }

    /// Get recordings with pending sensitive approval (for admin)
    func pendingSensitiveApprovals(in album: Album) -> [(recording: RecordingItem, sharedInfo: SharedRecordingItem)] {
        guard album.isShared, album.currentUserRole == .admin || (album.currentUserRole == nil && album.isOwner) else { return [] }

        return recordings(in: album).compactMap { recording -> (RecordingItem, SharedRecordingItem)? in
            guard let info = sharedRecordingInfoCache[recording.id],
                  info.isSensitive && !info.sensitiveApproved else {
                return nil
            }
            return (recording, info)
        }
    }

    /// Refresh shared album data from CloudKit
    func refreshSharedAlbumData(for album: Album) async {
        guard album.isShared else { return }

        // Fetch fresh settings
        if let settings = await sharedAlbumManager.fetchAlbumSettings(for: album) {
            var updatedAlbum = album
            updatedAlbum.sharedSettings = settings
            updateSharedAlbum(updatedAlbum)
        }

        // Fetch participants
        let participants = await sharedAlbumManager.fetchParticipants(for: album)
        if !participants.isEmpty {
            // Get the latest version after settings were updated
            let latestAlbum = self.albums.first(where: { $0.id == album.id }) ?? album
            var updatedAlbum = latestAlbum
            updatedAlbum.participants = participants
            updatedAlbum.participantCount = participants.count
            updateSharedAlbum(updatedAlbum)
        }

        // Purge expired trash items
        do {
            try await sharedAlbumManager.purgeExpiredTrashItems(for: album)
        } catch {
            Self.logger.error("Failed to purge expired trash items: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func migrateRecordingsToDrafts() {
        let didMigrate = UserDefaults.standard.bool(forKey: draftsMigrationKey)
        guard !didMigrate else { return }

        if AlbumRepository.migrateRecordingsToDrafts(recordings: &recordings) {
            saveRecordings()
        }
        UserDefaults.standard.set(true, forKey: draftsMigrationKey)
    }

    /// Migrate existing "Inbox" album to "Drafts"
    private func migrateInboxToDrafts() {
        if AlbumRepository.migrateInboxToDrafts(albums: &albums) {
            saveAlbums()
        }
    }

    // MARK: - Album Search Helpers

    func recordings(in album: Album) -> [RecordingItem] {
        AlbumRepository.recordings(in: album, from: recordings)
    }

    func recordingCount(in album: Album) -> Int {
        AlbumRepository.recordingCount(in: album, from: recordings)
    }

    func searchAlbums(query: String) -> [Album] {
        SearchService.searchAlbums(query: query, albums: albums)
    }

    // MARK: - Storage Size Helpers

    /// Cache for recording file sizes [RecordingID: Bytes]
    private var recordingSizeCache: [UUID: Int64] = [:]

    /// Get file size for a recording (cached)
    func recordingFileSize(_ recording: RecordingItem) -> Int64 {
        if let cached = recordingSizeCache[recording.id] {
            return cached
        }
        let size = recording.fileSizeBytes ?? 0
        recordingSizeCache[recording.id] = size
        return size
    }

    /// Get total size of all recordings in an album (bytes)
    func albumTotalBytes(_ album: Album) -> Int64 {
        recordings(in: album).reduce(0) { sum, recording in
            sum + recordingFileSize(recording)
        }
    }

    /// Get formatted total size of an album (e.g., "124 MB")
    func albumTotalSizeFormatted(_ album: Album) -> String {
        StorageFormatter.format(albumTotalBytes(album))
    }

    /// Get total size of all recordings in a project (bytes)
    func projectTotalBytes(_ project: Project) -> Int64 {
        recordings(in: project).reduce(0) { sum, recording in
            sum + recordingFileSize(recording)
        }
    }

    /// Get formatted total size of a project (e.g., "45.2 MB")
    func projectTotalSizeFormatted(_ project: Project) -> String {
        StorageFormatter.format(projectTotalBytes(project))
    }

    /// Invalidate size cache for a specific recording (call when recording is deleted/moved)
    func invalidateSizeCache(for recordingID: UUID) {
        recordingSizeCache.removeValue(forKey: recordingID)
    }

    /// Clear all size caches (call after major sync operations)
    func clearSizeCache() {
        recordingSizeCache.removeAll()
    }

    // MARK: - Search

    func searchRecordings(query: String, filterTagIDs: Set<UUID> = []) -> [RecordingItem] {
        SearchService.searchRecordings(
            query: query,
            filterTagIDs: filterTagIDs,
            recordings: activeRecordings,
            tags: tags,
            albums: albums,
            projects: projects
        )
    }

    // MARK: - Spot Computation (for Map)

    /// All recording spots (clustered by location)
    func allSpots() -> [RecordingSpot] {
        SpotClustering.computeSpots(
            recordings: activeRecordings,
            favoriteTagID: favoriteTagID,
            filterFavoritesOnly: false
        )
    }

    /// Top spots by total recording count
    func topSpots(limit: Int = 3) -> [RecordingSpot] {
        Array(allSpots().sorted { $0.totalCount > $1.totalCount }.prefix(limit))
    }

    /// Top spots with favorite recordings (sorted by favorite count)
    func topFavoriteSpots(limit: Int = 3) -> [RecordingSpot] {
        let spotsWithFavorites = SpotClustering.computeSpots(
            recordings: activeRecordings,
            favoriteTagID: favoriteTagID,
            filterFavoritesOnly: true
        )
        return Array(spotsWithFavorites.sorted { $0.favoriteCount > $1.favoriteCount }.prefix(limit))
    }

    /// Least used spots (at least 1 recording, sorted ascending)
    func leastUsedSpots(limit: Int = 3) -> [RecordingSpot] {
        let spots = allSpots().filter { $0.totalCount >= 1 }
        return Array(spots.sorted { $0.totalCount < $1.totalCount }.prefix(limit))
    }

    // MARK: - Batch Operations

    func addTagToRecordings(_ tag: Tag, recordingIDs: Set<UUID>) {
        RecordingRepository.addTag(tag, recordingIDs: recordingIDs, recordings: &recordings)
        saveRecordings()
        triggerSyncForMetadata()
    }

    func removeTagFromRecordings(_ tag: Tag, recordingIDs: Set<UUID>) {
        RecordingRepository.removeTag(tag, recordingIDs: recordingIDs, recordings: &recordings)
        saveRecordings()
        triggerSyncForMetadata()
    }

    func setAlbumForRecordings(_ album: Album?, recordingIDs: Set<UUID>) {
        AlbumRepository.setAlbumForRecordings(album, recordingIDs: recordingIDs, recordings: &recordings)
        saveRecordings()
        triggerSyncForMetadata()
    }

    func moveRecordingsToTrash(recordingIDs: Set<UUID>) {
        RecordingRepository.moveToTrash(recordingIDs: recordingIDs, recordings: &recordings)
        saveRecordings()
        triggerSyncForMetadata()
    }

    // MARK: - Import

    func importRecording(from url: URL, duration: TimeInterval, title: String? = nil, albumID: UUID = Album.draftsID, createdAt: Date = Date()) throws {
        // Verify source audio file exists before attempting import
        guard FileManager.default.fileExists(atPath: url.path) else {
            #if DEBUG
            print("[AppState.importRecording] Source audio file does not exist at: \(url.path) — aborting import to prevent ghost recording")
            #endif
            return
        }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        // Use UUID-based filename to avoid conflicts, preserving original extension
        let fileExtension = url.pathExtension.lowercased()
        let uniqueFilename = "\(UUID().uuidString).\(fileExtension)"
        let destURL = documentsPath.appendingPathComponent(uniqueFilename)

        // Copy file to documents
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.copyItem(at: url, to: destURL)

        // Verify destination file exists after copy before adding to state
        guard FileManager.default.fileExists(atPath: destURL.path) else {
            #if DEBUG
            print("[AppState.importRecording] Destination file missing after copy at: \(destURL.path) — aborting import to prevent ghost recording")
            #endif
            return
        }

        // Use provided title or generate one
        let recordingTitle = title ?? "Recording \(nextRecordingNumber)"
        if title == nil {
            nextRecordingNumber += 1
            saveNextRecordingNumber()
        }

        let recording = RecordingItem(
            fileURL: destURL,
            createdAt: createdAt,
            duration: duration,
            title: recordingTitle,
            albumID: albumID
        )

        recordings.insert(recording, at: 0)
        persistRecordings()

        // Trigger iCloud sync for imported recording
        triggerSyncForNewRecording(recording)

        // Trigger async waveform sampling
        Task {
            _ = await WaveformSampler.shared.samples(for: destURL, targetSampleCount: 150)
        }
    }

    // MARK: - Tag Migration

    private func migrateFavTagToFavorite() {
        let didMigrate = UserDefaults.standard.bool(forKey: tagMigrationKey)
        guard !didMigrate else { return }

        // Check if "fav" tag exists
        guard let favIndex = tags.firstIndex(where: { $0.name.lowercased() == "fav" }) else {
            UserDefaults.standard.set(true, forKey: tagMigrationKey)
            return
        }

        let oldFavTag = tags[favIndex]
        let oldFavID = oldFavTag.id

        // Check if "favorite" with the correct stable ID already exists
        let favoriteExists = tags.contains { $0.id == Tag.favoriteTagID }

        if !favoriteExists {
            // Create a new tag with the stable favoriteTagID, preserving the old tag's color
            let newFavoriteTag = Tag(id: Tag.favoriteTagID, name: "favorite", colorHex: oldFavTag.colorHex)

            // Update all recordings that reference the old fav tag UUID
            if oldFavID != Tag.favoriteTagID {
                for i in recordings.indices {
                    if let tagIndex = recordings[i].tagIDs.firstIndex(of: oldFavID) {
                        recordings[i].tagIDs[tagIndex] = Tag.favoriteTagID
                    }
                }
                persistRecordings()
            }

            // Remove the old "fav" tag and insert the new one
            tags.remove(at: favIndex)
            tags.insert(newFavoriteTag, at: favIndex)
            persistTags()
        } else {
            // Favorite tag with correct ID already exists — just migrate recording references
            if oldFavID != Tag.favoriteTagID {
                for i in recordings.indices {
                    if let tagIndex = recordings[i].tagIDs.firstIndex(of: oldFavID) {
                        recordings[i].tagIDs[tagIndex] = Tag.favoriteTagID
                    }
                }
                // Remove the old "fav" tag (duplicate)
                tags.remove(at: favIndex)
                persistRecordings()
                persistTags()
            }
        }

        UserDefaults.standard.set(true, forKey: tagMigrationKey)
    }

    // MARK: - Persistence (Debounced)
    //
    // Save calls are debounced: rapid mutations (e.g., batch operations) coalesce
    // into a single JSON encode + UserDefaults write after 0.3s of inactivity.
    // Pending saves are flushed immediately when the app backgrounds.

    private func saveRecordings() {
        pendingSaveRecordings?.cancel()
        pendingSaveRecordings = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistRecordings()
        }
    }

    private func persistRecordings() {
        // Cancel any pending debounced save to prevent a stale write from
        // overwriting this immediate (authoritative) save.
        pendingSaveRecordings?.cancel()
        pendingSaveRecordings = nil

        // Primary: file-based with checksum and backup rotation
        DataSafetyFileOps.saveSync(recordings, collection: .recordings)
        // Fallback: keep UserDefaults in sync for one release cycle
        do {
            let data = try JSONEncoder().encode(recordings)
            UserDefaults.standard.set(data, forKey: recordingsKey)
        } catch {
            Self.logger.error("Failed to encode recordings for UserDefaults fallback: \(error.localizedDescription, privacy: .public)")
        }
        // Update home screen widgets with latest data
        updateWidgetData()
    }

    /// Write recording data to the App Group shared container for widget consumption
    /// and reload all widget timelines.
    private func updateWidgetData() {
        let recent = recordings
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(5)
            .map { recording in
                WidgetRecordingInfo(
                    id: recording.id,
                    title: recording.title,
                    duration: recording.duration,
                    createdAt: recording.createdAt,
                    iconName: recording.iconName
                )
            }
        let widgetData = SharedWidgetData(
            recentRecordings: Array(recent),
            totalRecordingCount: recordings.count,
            lastUpdated: Date()
        )
        widgetData.save()
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func loadRecordings() {
        let saved = DataSafetyFileOps.load(RecordingItem.self, collection: .recordings)
        guard !saved.isEmpty else { return }
        // Load all recordings immediately; prune missing files in the background
        recordings = saved
        Task { [weak self] in
            // Skip file-pruning while iCloud sync is active — audio files may still be downloading
            guard let self else { return }
            if self.syncManager.isSyncing {
                return
            }
            let validURLs = await Task.detached {
                Set(saved.filter { FileManager.default.fileExists(atPath: $0.fileURL.path) }.map(\.id))
            }.value
            // Only remove recordings from the original snapshot — never touch recordings added after load
            let savedIDs = Set(saved.map(\.id))
            let invalidIDs = savedIDs.subtracting(validURLs)
            guard !invalidIDs.isEmpty else { return }
            let beforeCount = self.recordings.count
            self.recordings.removeAll { invalidIDs.contains($0.id) }
            if self.recordings.count < beforeCount {
                self.persistRecordings()
            }
        }
    }

    private func saveTags() {
        pendingSaveTags?.cancel()
        pendingSaveTags = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistTags()
        }
    }

    private func persistTags() {
        DataSafetyFileOps.saveSync(tags, collection: .tags)
        if let data = try? JSONEncoder().encode(tags) {
            UserDefaults.standard.set(data, forKey: tagsKey)
        }
    }

    private func loadTags() {
        let saved = DataSafetyFileOps.load(Tag.self, collection: .tags)
        guard !saved.isEmpty else { return }
        tags = saved
    }

    private func saveAlbums() {
        pendingSaveAlbums?.cancel()
        pendingSaveAlbums = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistAlbums()
        }
    }

    private func persistAlbums() {
        DataSafetyFileOps.saveSync(albums, collection: .albums)
        if let data = try? JSONEncoder().encode(albums) {
            UserDefaults.standard.set(data, forKey: albumsKey)
        }
    }

    private func loadAlbums() {
        let saved = DataSafetyFileOps.load(Album.self, collection: .albums)
        guard !saved.isEmpty else { return }
        albums = saved
    }

    /// Immediately write all pending debounced saves (called when app backgrounds)
    private func flushPendingSaves() {
        if pendingSaveRecordings != nil {
            pendingSaveRecordings?.cancel()
            pendingSaveRecordings = nil
            persistRecordings()
        }
        if pendingSaveAlbums != nil {
            pendingSaveAlbums?.cancel()
            pendingSaveAlbums = nil
            persistAlbums()
        }
        if pendingSaveTags != nil {
            pendingSaveTags?.cancel()
            pendingSaveTags = nil
            persistTags()
        }
        if pendingSaveProjects != nil {
            pendingSaveProjects?.cancel()
            pendingSaveProjects = nil
            persistProjects()
        }
        if pendingSaveOverdubGroups != nil {
            pendingSaveOverdubGroups?.cancel()
            pendingSaveOverdubGroups = nil
            persistOverdubGroups()
        }
    }

    private func saveNextRecordingNumber() {
        UserDefaults.standard.set(nextRecordingNumber, forKey: nextNumberKey)
    }

    private func loadNextRecordingNumber() {
        let saved = UserDefaults.standard.integer(forKey: nextNumberKey)
        nextRecordingNumber = saved > 0 ? saved : 1
    }

    private func saveAppearanceMode() {
        UserDefaults.standard.set(appearanceMode.rawValue, forKey: appearanceModeKey)
    }

    private func loadAppearanceMode() {
        guard let rawValue = UserDefaults.standard.string(forKey: appearanceModeKey),
              let mode = AppearanceMode(rawValue: rawValue) else {
            return
        }
        appearanceMode = mode
    }

    private func saveSelectedTheme() {
        UserDefaults.standard.set(selectedTheme.rawValue, forKey: selectedThemeKey)
    }

    private func loadSelectedTheme() {
        guard let rawValue = UserDefaults.standard.string(forKey: selectedThemeKey),
              let theme = AppTheme(rawValue: rawValue) else {
            return
        }
        selectedTheme = theme
    }

    private func saveAppSettings() {
        if let data = try? JSONEncoder().encode(appSettings) {
            UserDefaults.standard.set(data, forKey: appSettingsKey)
        }
    }

    private func loadAppSettings() {
        guard let data = UserDefaults.standard.data(forKey: appSettingsKey),
              let saved = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return
        }
        appSettings = saved
    }

    private func seedDefaultTagsIfNeeded() {
        let didSeed = TagRepository.seedDefaultTagsIfNeeded(tags: &tags)
        if didSeed || !tags.contains(where: { $0.id == Tag.favoriteTagID }) {
            saveTags()
        }
    }

    private func ensureFavoriteTagExists() {
        let countBefore = tags.count
        TagRepository.ensureFavoriteTagExists(tags: &tags)
        if tags.count != countBefore {
            saveTags()
        }
    }

    // MARK: - Album Rename

    func renameAlbum(_ album: Album, to newName: String) -> Bool {
        let oldName = album.name
        guard AlbumRepository.renameAlbum(album, to: newName, albums: &albums) else { return false }
        saveAlbums()

        let trimmedName = newName.trimmingCharacters(in: .whitespaces)

        // Trigger iCloud sync for album update
        if let index = albums.firstIndex(where: { $0.id == album.id }) {
            triggerSyncForAlbumUpdate(albums[index])
        }

        // Sync rename to CloudKit for shared albums
        if album.isShared {
            Task {
                do {
                    try await sharedAlbumManager.renameSharedAlbum(album, oldName: oldName, newName: trimmedName)
                } catch {
                    // Queue for retry on failure — local rename already succeeded
                    sharedAlbumManager.queuePendingOperation(
                        type: "renameAlbum",
                        albumId: album.id,
                        payload: ["oldName": oldName, "newName": trimmedName]
                    )
                }
            }
        }

        return true
    }

    // MARK: - Project Management

    /// Get a project by ID
    func project(for id: UUID?) -> Project? {
        ProjectRepository.project(for: id, in: projects)
    }

    /// Get all recordings (versions) belonging to a project, sorted by version index
    func recordings(in project: Project) -> [RecordingItem] {
        ProjectRepository.recordings(in: project, from: recordings)
    }

    /// Get recording count for a project
    func recordingCount(in project: Project) -> Int {
        ProjectRepository.recordingCount(in: project, from: recordings)
    }

    /// Get the next version number for a project
    func nextVersionIndex(for project: Project) -> Int {
        ProjectRepository.nextVersionIndex(for: project, recordings: recordings)
    }

    /// Get the best take recording for a project
    func bestTake(for project: Project) -> RecordingItem? {
        ProjectRepository.bestTake(for: project, recordings: recordings)
    }

    /// Create a new project from an existing recording (recording becomes V1)
    @discardableResult
    func createProject(from recording: RecordingItem, title: String? = nil) -> Project {
        let project = ProjectRepository.createProject(
            from: recording, title: title, projects: &projects, recordings: &recordings
        )
        saveProjects()
        saveRecordings()
        triggerSyncForProject(project)
        return project
    }

    /// Create a new empty project
    @discardableResult
    func createProject(title: String) -> Project {
        let project = ProjectRepository.createProject(title: title, projects: &projects)
        saveProjects()
        triggerSyncForProject(project)
        return project
    }

    /// Add a recording as a new version to an existing project
    func addVersion(recording: RecordingItem, to project: Project) {
        ProjectRepository.addVersion(recording: recording, to: project, projects: &projects, recordings: &recordings)
        saveRecordings()
        saveProjects()
    }

    /// Remove a recording from its project (makes it standalone)
    func removeFromProject(recording: RecordingItem) {
        ProjectRepository.removeFromProject(recording: recording, projects: &projects, recordings: &recordings)
        saveRecordings()
        saveProjects()
    }

    /// Set the best take for a project
    func setBestTake(_ recording: RecordingItem, for project: Project) {
        guard let updated = ProjectRepository.setBestTake(recording, for: project, projects: &projects) else { return }
        saveProjects()
        triggerSyncForProjectUpdate(updated)
    }

    /// Clear the best take for a project
    func clearBestTake(for project: Project) {
        guard let updated = ProjectRepository.clearBestTake(for: project, projects: &projects) else { return }
        saveProjects()
        triggerSyncForProjectUpdate(updated)
    }

    /// Update project properties
    func updateProject(_ project: Project) {
        guard let updated = ProjectRepository.updateProject(project, projects: &projects) else { return }
        saveProjects()
        triggerSyncForProjectUpdate(updated)
    }

    /// Toggle project pin status
    func toggleProjectPin(_ project: Project) {
        guard let updated = ProjectRepository.toggleProjectPin(project, projects: &projects) else { return }
        saveProjects()
        triggerSyncForProjectUpdate(updated)
    }

    /// Delete a project (recordings become standalone)
    func deleteProject(_ project: Project) {
        let deletedId = ProjectRepository.deleteProject(project, projects: &projects, recordings: &recordings)
        persistProjects()
        persistRecordings()
        triggerSyncForProjectDeletion(deletedId)
    }

    /// Get project statistics
    func stats(for project: Project) -> ProjectStats {
        ProjectRepository.stats(for: project, recordings: recordings)
    }

    /// Search projects by query
    func searchProjects(query: String) -> [Project] {
        SearchService.searchProjects(query: query, projects: projects)
    }

    /// Get all projects sorted (pinned first, then by updatedAt)
    var sortedProjects: [Project] {
        ProjectRepository.sortedProjects(projects)
    }

    /// Get recordings that are standalone (not part of any project)
    var standaloneRecordings: [RecordingItem] {
        ProjectRepository.standaloneRecordings(from: recordings)
    }

    // MARK: - Project Persistence

    private func saveProjects() {
        pendingSaveProjects?.cancel()
        pendingSaveProjects = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistProjects()
        }
    }

    private func persistProjects() {
        DataSafetyFileOps.saveSync(projects, collection: .projects)
        if let data = try? JSONEncoder().encode(projects) {
            UserDefaults.standard.set(data, forKey: projectsKey)
        }
    }

    private func loadProjects() {
        let saved = DataSafetyFileOps.load(Project.self, collection: .projects)
        guard !saved.isEmpty else { return }
        projects = saved
    }

    // MARK: - Overdub Groups Persistence

    private func saveOverdubGroups() {
        pendingSaveOverdubGroups?.cancel()
        pendingSaveOverdubGroups = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled, let self else { return }
            self.persistOverdubGroups()
        }
    }

    private func persistOverdubGroups() {
        DataSafetyFileOps.saveSync(overdubGroups, collection: .overdubGroups)
        if let data = try? JSONEncoder().encode(overdubGroups) {
            UserDefaults.standard.set(data, forKey: overdubGroupsKey)
        }
    }

    private func loadOverdubGroups() {
        let saved = DataSafetyFileOps.load(OverdubGroup.self, collection: .overdubGroups)
        guard !saved.isEmpty else { return }
        overdubGroups = saved
    }

    // MARK: - Factory Reset

    func factoryReset() {
        // Stop any active recording
        if recorder.recordingState.isActive {
            _ = recorder.stopRecording()
        }

        // Delete all files from documents directory
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        if let files = try? FileManager.default.contentsOfDirectory(at: documentsPath, includingPropertiesForKeys: nil) {
            for file in files {
                try? FileManager.default.removeItem(at: file)
            }
        }

        // Clear all data arrays
        recordings = []
        albums = []
        tags = []
        projects = []
        overdubGroups = []

        // Reset recording number
        nextRecordingNumber = 1

        // Reset settings and theme to defaults
        appSettings = .default
        selectedTheme = .system
        appearanceMode = .system

        // Clear ALL UserDefaults for a clean slate
        let allKeys = [
            recordingsKey, tagsKey, albumsKey, projectsKey,
            overdubGroupsKey, nextNumberKey, selectedThemeKey,
            appSettingsKey, draftsMigrationKey, tagMigrationKey,
            recordButtonPosXKey, recordButtonPosYKey,
            appearanceModeKey, recordButtonHasStoredKey
        ]
        for key in allKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Clear CloudKit-related keys from UserDefaults
        let cloudKitKeys = [
            "cloudkit.changeToken", "cloudkit.tombstones", "cloudkit.lastSync",
            "cloudkit.zoneCreated", "cloudkit.subscriptionCreated",
            "cloudkit.lastSyncedDates",
            "dataSafetyMigrationComplete"
        ]
        for key in cloudKitKeys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        // Delete the Application Support SonideaData directory
        let sonideaDataDir = DataSafetyFileOps.dataDirectory()
        try? FileManager.default.removeItem(at: sonideaDataDir)

        // Re-create default system items
        ensureDraftsAlbum()
        ensureFavoriteTagExists()

        // Persist clean state directly (not debounced) to ensure write completes
        persistRecordings()
        persistAlbums()
        persistTags()
        persistProjects()
        persistOverdubGroups()
    }

    // MARK: - Overdub Group Management

    /// Get overdub group by ID
    func overdubGroup(for id: UUID) -> OverdubGroup? {
        OverdubRepository.overdubGroup(for: id, in: overdubGroups)
    }

    /// Get overdub group for a recording (if it belongs to one)
    func overdubGroup(for recording: RecordingItem) -> OverdubGroup? {
        OverdubRepository.overdubGroup(for: recording, in: overdubGroups)
    }

    /// Get all recordings in an overdub group
    func recordings(in group: OverdubGroup) -> [RecordingItem] {
        OverdubRepository.recordings(in: group, from: recordings)
    }

    /// Get the base recording for an overdub group
    func baseRecording(for group: OverdubGroup) -> RecordingItem? {
        OverdubRepository.baseRecording(for: group, from: recordings)
    }

    /// Get layer recordings for an overdub group (ordered by index)
    func layerRecordings(for group: OverdubGroup) -> [RecordingItem] {
        OverdubRepository.layerRecordings(for: group, from: recordings)
    }

    /// Create a new overdub group with a base recording
    func createOverdubGroup(baseRecording: RecordingItem) -> OverdubGroup {
        let group = OverdubRepository.createOverdubGroup(
            baseRecording: baseRecording, groups: &overdubGroups, recordings: &recordings
        )
        saveOverdubGroups()
        saveRecordings()
        triggerSyncForOverdubGroup(group)
        return group
    }

    /// Add a layer recording to an overdub group
    func addLayerToOverdubGroup(
        groupId: UUID,
        layerRecording: RecordingItem,
        offsetSeconds: Double = 0
    ) {
        OverdubRepository.addLayer(
            groupId: groupId, layerRecording: layerRecording, offsetSeconds: offsetSeconds,
            groups: &overdubGroups, recordings: &recordings
        )
        saveOverdubGroups()
        saveRecordings()
        if let group = overdubGroups.first(where: { $0.id == groupId }) {
            triggerSyncForOverdubGroupUpdate(group)
        }
    }

    /// Remove a specific layer from its overdub group and move to trash
    func removeOverdubLayer(_ layer: RecordingItem) {
        guard let groupId = layer.overdubGroupId,
              let groupIndex = overdubGroups.firstIndex(where: { $0.id == groupId }) else { return }
        overdubGroups[groupIndex].layerRecordingIds.removeAll { $0 == layer.id }
        saveOverdubGroups()
        triggerSyncForOverdubGroupUpdate(overdubGroups[groupIndex])
        moveToTrash(layer)
    }

    /// Remove the last layer from an overdub group
    func removeLayerFromOverdubGroup(groupId: UUID) {
        if let fileURL = OverdubRepository.removeLastLayer(
            groupId: groupId, groups: &overdubGroups, recordings: &recordings
        ) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        saveOverdubGroups()
        saveRecordings()
        if let group = overdubGroups.first(where: { $0.id == groupId }) {
            triggerSyncForOverdubGroupUpdate(group)
        }
    }

    /// Check if a recording can have overdub layers added
    func canAddOverdubLayer(to recording: RecordingItem) -> Bool {
        guard supportManager.canUseProFeatures else { return false }
        return OverdubRepository.canAddLayer(to: recording, in: overdubGroups)
    }

    /// Get the number of existing layers for a recording
    func overdubLayerCount(for recording: RecordingItem) -> Int {
        OverdubRepository.overdubLayerCount(for: recording, in: overdubGroups)
    }

    /// Update layer offset for sync adjustment
    func updateLayerOffset(recordingId: UUID, offsetSeconds: Double) {
        OverdubRepository.updateLayerOffset(recordingId: recordingId, offsetSeconds: offsetSeconds, recordings: &recordings)
        saveRecordings()
        // Sync the recording whose offset changed
        if let recording = recordings.first(where: { $0.id == recordingId }) {
            triggerSyncForRecording(recording)
        }
    }

    /// Remove overdub groups whose base recording no longer exists
    private func validateOverdubGroupIntegrity() {
        let groupCountBefore = overdubGroups.count
        let layerCountsBefore = overdubGroups.map { $0.layerRecordingIds.count }

        let removedFileURLs = OverdubRepository.validateIntegrity(
            groups: &overdubGroups, recordings: &recordings
        )
        for url in removedFileURLs {
            try? FileManager.default.removeItem(at: url)
        }

        let groupsChanged = overdubGroups.count != groupCountBefore
        let layersChanged = overdubGroups.map({ $0.layerRecordingIds.count }) != layerCountsBefore
        if groupsChanged || layersChanged {
            saveOverdubGroups()
            Self.logger.info("Cleaned up orphaned overdub groups or dangling layer references")
        }
        if !removedFileURLs.isEmpty {
            saveRecordings()
        }
    }
}

// MARK: - Pending Actions (for AppIntents, Widgets, Quick Actions)

enum PendingActionKeys {
    static let pendingStartRecording = "pendingStartRecording"
    static let pendingRecordingNavigation = "pendingRecordingNavigation"
    static let pendingTranscriptionResult = "pendingTranscriptionResult"
}

extension AppState {
    /// Check and consume pending start recording action
    func consumePendingStartRecording() {
        let pending = UserDefaults.standard.bool(forKey: PendingActionKeys.pendingStartRecording)
        guard pending else { return }

        // Clear the flag first to prevent double triggers
        UserDefaults.standard.set(false, forKey: PendingActionKeys.pendingStartRecording)

        // Start recording if not already recording
        if !recorder.isRecording {
            recorder.startRecording()
        }
    }

    /// Set the pending start recording flag (called from AppIntent/Quick Action)
    static func setPendingStartRecording() {
        UserDefaults.standard.set(true, forKey: PendingActionKeys.pendingStartRecording)
    }

    // MARK: - Pending Recording Navigation (for Siri/Shortcuts intents)

    /// Check and consume pending recording navigation (e.g. from GetLastRecordingIntent).
    /// Returns the recording ID to navigate to, or nil if no pending navigation.
    func consumePendingRecordingNavigation() -> UUID? {
        guard let idString = UserDefaults.standard.string(forKey: PendingActionKeys.pendingRecordingNavigation),
              let id = UUID(uuidString: idString) else {
            return nil
        }

        // Clear the flag first to prevent double triggers
        UserDefaults.standard.removeObject(forKey: PendingActionKeys.pendingRecordingNavigation)
        return id
    }

    /// Check and consume pending transcription result (from TranscribeRecordingIntent).
    /// Saves the transcript to the recording if found.
    func consumePendingTranscriptionResult() {
        guard let data = UserDefaults.standard.data(forKey: PendingActionKeys.pendingTranscriptionResult) else {
            return
        }

        // Clear the flag first to prevent double triggers
        UserDefaults.standard.removeObject(forKey: PendingActionKeys.pendingTranscriptionResult)

        do {
            let decoded = try JSONDecoder().decode([String: String].self, from: data)
            guard let idString = decoded["recordingID"],
                  let recordingID = UUID(uuidString: idString),
                  let transcript = decoded["transcript"] else { return }

            // Update the recording's transcript if it doesn't already have one
            if let index = recordings.firstIndex(where: { $0.id == recordingID }) {
                if recordings[index].transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    recordings[index].transcript = transcript
                    recordings[index].modifiedAt = Date()
                    saveRecordings()
                }
            }
        } catch {
            Self.logger.error("Failed to decode pending transcription result: \(error.localizedDescription)")
        }
    }
}

#if DEBUG
// MARK: - Debug Mode for Shared Albums Testing

extension AppState {
    private static let sharedAlbumsDebugModeKey = "sharedAlbumsDebugMode"
    private static let debugSharedAlbumIdKey = "debugSharedAlbumId"

    /// Whether debug mode is enabled for shared albums
    var isSharedAlbumsDebugMode: Bool {
        get { UserDefaults.standard.bool(forKey: Self.sharedAlbumsDebugModeKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.sharedAlbumsDebugModeKey) }
    }

    /// The debug shared album ID (stored to maintain consistency)
    private var debugSharedAlbumId: UUID {
        if let idString = UserDefaults.standard.string(forKey: Self.debugSharedAlbumIdKey),
           let id = UUID(uuidString: idString) {
            return id
        }
        let newId = UUID()
        UserDefaults.standard.set(newId.uuidString, forKey: Self.debugSharedAlbumIdKey)
        return newId
    }

    /// Enable debug mode and create mock shared album
    func enableSharedAlbumsDebugMode() {
        isSharedAlbumsDebugMode = true
        createMockSharedAlbum()
    }

    /// Disable debug mode and remove mock data
    func disableSharedAlbumsDebugMode() {
        isSharedAlbumsDebugMode = false
        removeMockSharedAlbum()
    }

    /// Create a mock shared album with sample data
    private func createMockSharedAlbum() {
        let albumId = debugSharedAlbumId

        // Check if already exists
        if albums.contains(where: { $0.id == albumId }) {
            return
        }

        // Create mock participants
        let participants = [
            SharedAlbumParticipant(
                id: "user_001",
                displayName: "You (Admin)",
                role: .admin,
                acceptanceStatus: .accepted,
                joinedAt: Date().addingTimeInterval(-86400 * 7),
                avatarInitials: "YO"
            ),
            SharedAlbumParticipant(
                id: "user_002",
                displayName: "Sarah Johnson",
                role: .member,
                acceptanceStatus: .accepted,
                joinedAt: Date().addingTimeInterval(-86400 * 5),
                avatarInitials: "SJ"
            ),
            SharedAlbumParticipant(
                id: "user_003",
                displayName: "Mike Chen",
                role: .member,
                acceptanceStatus: .accepted,
                joinedAt: Date().addingTimeInterval(-86400 * 3),
                avatarInitials: "MC"
            ),
            SharedAlbumParticipant(
                id: "user_004",
                displayName: "Emily Davis",
                role: .viewer,
                acceptanceStatus: .pending,
                joinedAt: nil,
                avatarInitials: "ED"
            )
        ]

        // Create the shared album
        let sharedAlbum = Album(
            id: albumId,
            name: "Demo Shared Album",
            createdAt: Date().addingTimeInterval(-86400 * 7),
            isSystem: false,
            isShared: true,
            shareURL: URL(string: "https://www.icloud.com/share/demo"),
            participantCount: participants.count,
            isOwner: true,
            cloudKitShareRecordName: "demo_share_record",
            skipAddRecordingConsent: false,
            sharedSettings: SharedAlbumSettings(
                allowMembersToDelete: true,
                trashRestorePermission: .anyParticipant,
                trashRetentionDays: 14,
                defaultLocationSharingMode: .approximate,
                allowMembersToShareLocation: true,
                requireSensitiveApproval: false
            ),
            currentUserRole: .admin,
            participants: participants
        )

        albums.append(sharedAlbum)
        saveAlbums()

        // Create mock recordings
        createMockRecordingsForDebugAlbum(albumId: albumId)

        // Create mock shared recording info
        createMockSharedRecordingInfo(albumId: albumId)
    }

    /// Create mock recordings for the debug shared album
    private func createMockRecordingsForDebugAlbum(albumId: UUID) {
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let mockRecordings: [(title: String, duration: TimeInterval, daysAgo: Int, lat: Double?, lon: Double?, notes: String)] = [
            ("Team Brainstorm Session", 847.5, 1, 37.7749, -122.4194, "Weekly team meeting - discussed Q2 roadmap"),
            ("Interview with Dr. Smith", 1523.0, 2, 37.7849, -122.4094, "Expert interview for research project"),
            ("Field Notes - Park Visit", 324.0, 3, 37.7694, -122.4862, "Nature sounds and observations"),
            ("Quick Voice Memo", 45.0, 4, nil, nil, "Reminder about tomorrow's presentation"),
            ("Client Feedback Call", 1892.0, 5, 37.7849, -122.4294, "Quarterly review with client"),
            ("Music Idea #7", 128.0, 6, nil, nil, "Melody idea for new project")
        ]

        for (index, mock) in mockRecordings.enumerated() {
            let recordingId = UUID(uuidString: "00000000-0000-0000-0000-\(String(format: "%012d", index + 100))")!

            // Create a placeholder file URL (won't actually play)
            let fileURL = documentsURL.appendingPathComponent("demo_recording_\(index).m4a")

            let recording = RecordingItem(
                id: recordingId,
                fileURL: fileURL,
                createdAt: Date().addingTimeInterval(-86400 * Double(mock.daysAgo)),
                duration: mock.duration,
                title: mock.title,
                notes: mock.notes,
                tagIDs: [],
                albumID: albumId,
                locationLabel: mock.lat != nil ? "San Francisco, CA" : "",
                transcript: "",
                latitude: mock.lat,
                longitude: mock.lon,
                trashedAt: nil,
                lastPlaybackPosition: 0,
                iconColorHex: nil,
                iconName: nil
            )

            recordings.append(recording)
        }

        saveRecordings()
    }

    /// Create mock shared recording info for debug recordings
    private func createMockSharedRecordingInfo(albumId: UUID) {
        let albumRecordings = recordings.filter { $0.albumID == albumId }

        let creators = [
            ("user_001", "You", "YO"),
            ("user_002", "Sarah Johnson", "SJ"),
            ("user_003", "Mike Chen", "MC")
        ]

        for (index, recording) in albumRecordings.enumerated() {
            let creator = creators[index % creators.count]

            let locationMode: LocationSharingMode = recording.latitude != nil ? .approximate : .none

            let sharedInfo = SharedRecordingItem(
                id: UUID(),
                recordingId: recording.id,
                albumId: albumId,
                creatorId: creator.0,
                creatorDisplayName: creator.1,
                createdAt: recording.createdAt,
                wasImported: index == 1,
                recordedWithHeadphones: index == 2,
                isSensitive: index == 3,
                sensitiveApproved: index == 3,
                sensitiveApprovedBy: index == 3 ? "user_001" : nil,
                locationSharingMode: locationMode,
                sharedLatitude: locationMode != .none ? recording.latitude : nil,
                sharedLongitude: locationMode != .none ? recording.longitude : nil,
                sharedPlaceName: locationMode != .none ? "San Francisco, CA" : nil,
                isVerified: index < 3,
                verifiedAt: index < 3 ? recording.createdAt : nil
            )

            sharedRecordingInfoCache[recording.id] = sharedInfo
        }
    }

    /// Remove mock shared album and associated data
    private func removeMockSharedAlbum() {
        let albumId = debugSharedAlbumId

        // Remove the album
        albums.removeAll { $0.id == albumId }
        saveAlbums()

        // Remove associated recordings
        let recordingIds = recordings.filter { $0.albumID == albumId }.map { $0.id }
        recordings.removeAll { $0.albumID == albumId }
        saveRecordings()

        // Clear cached shared info
        for id in recordingIds {
            sharedRecordingInfoCache.removeValue(forKey: id)
        }
    }

    /// Get mock activity feed for debug mode
    func debugMockActivityFeed() -> [SharedAlbumActivityEvent] {
        guard isSharedAlbumsDebugMode else { return [] }

        let albumId = debugSharedAlbumId
        let albumRecordings = recordings.filter { $0.albumID == albumId }

        var events: [SharedAlbumActivityEvent] = []

        // Generate mock activity events
        let activities: [(type: ActivityEventType, actorId: String, actorName: String, hoursAgo: Int)] = [
            (.recordingAdded, "user_002", "Sarah Johnson", 2),
            (.recordingAdded, "user_003", "Mike Chen", 5),
            (.locationEnabled, "user_002", "Sarah Johnson", 6),
            (.participantJoined, "user_003", "Mike Chen", 72),
            (.recordingAdded, "user_001", "You", 96),
            (.participantJoined, "user_002", "Sarah Johnson", 120),
            (.settingAllowDeletesChanged, "user_001", "You", 168)
        ]

        for (index, activity) in activities.enumerated() {
            let event = SharedAlbumActivityEvent(
                id: UUID(),
                albumId: albumId,
                timestamp: Date().addingTimeInterval(-3600 * Double(activity.hoursAgo)),
                actorId: activity.actorId,
                actorDisplayName: activity.actorName,
                eventType: activity.type,
                targetRecordingId: activity.type == .recordingAdded ? albumRecordings[safe: index % albumRecordings.count]?.id : nil,
                targetRecordingTitle: activity.type == .recordingAdded ? albumRecordings[safe: index % albumRecordings.count]?.title : nil,
                targetParticipantId: activity.type == .participantJoined ? activity.actorId : nil,
                targetParticipantName: activity.type == .participantJoined ? activity.actorName : nil,
                oldValue: activity.type == .settingAllowDeletesChanged ? "Off" : nil,
                newValue: activity.type == .settingAllowDeletesChanged ? "On" : nil
            )
            events.append(event)
        }

        return events.sorted { $0.timestamp > $1.timestamp }
    }

    /// Get mock trash items for debug mode
    func debugMockTrashItems() -> [SharedAlbumTrashItem] {
        guard isSharedAlbumsDebugMode else { return [] }

        let albumId = debugSharedAlbumId

        return [
            SharedAlbumTrashItem(
                id: UUID(),
                recordingId: UUID(),
                albumId: albumId,
                title: "Deleted Meeting Notes",
                duration: 456.0,
                creatorId: "user_002",
                creatorDisplayName: "Sarah Johnson",
                deletedBy: "user_001",
                deletedByDisplayName: "You",
                deletedAt: Date().addingTimeInterval(-86400 * 2),
                originalCreatedAt: Date().addingTimeInterval(-86400 * 10),
                audioAssetReference: nil
            ),
            SharedAlbumTrashItem(
                id: UUID(),
                recordingId: UUID(),
                albumId: albumId,
                title: "Old Voice Memo",
                duration: 89.0,
                creatorId: "user_003",
                creatorDisplayName: "Mike Chen",
                deletedBy: "user_003",
                deletedByDisplayName: "Mike Chen",
                deletedAt: Date().addingTimeInterval(-86400 * 12),
                originalCreatedAt: Date().addingTimeInterval(-86400 * 20),
                audioAssetReference: nil
            )
        ]
    }
}

// Safe array subscript extension (used by debug mock data)
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
#endif
