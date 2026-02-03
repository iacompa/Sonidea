# Sonidea - Voice Memo Pro App

## Overview
Sonidea is a premium voice memo app for iOS, iPadOS, and watchOS built with SwiftUI and AVAudioEngine. Pure Apple stack, no third-party dependencies. ~85 Swift files across the main app, watchOS companion app, and recording widget extension.

## Project Path
`/Users/michael/Documents/💻 Business/Vibe Code Files/Voice memo app premium/xCode VoiceMemoPro/VoiceMemoPro/`

Xcode project: `Sonidea.xcodeproj`

## Tech Stack
- **Language:** Swift (Swift 5.9+)
- **UI:** SwiftUI (iOS 17+ / watchOS 10+ with @Observable macro)
- **Audio:** AVAudioEngine (iOS), AVAudioRecorder/AVAudioPlayer (watchOS), AVFoundation, AVAudioSession
- **Cloud:** CloudKit (shared albums), iCloud Documents (sync fallback)
- **Connectivity:** WatchConnectivity (WCSession) for watch-to-phone recording transfer and theme sync
- **Monetization:** StoreKit 2 subscriptions
- **Other:** SoundAnalysis (auto-icons), MapKit, CoreLocation, ActivityKit (Live Activity), AppIntents

## Architecture
- Central `AppState` class (@Observable) as facade, delegating to stateless repositories
- **Repositories** (stateless enums with static methods on `inout` arrays):
  - `TagRepository` - tag CRUD, merge, toggle, seed defaults
  - `AlbumRepository` - album CRUD, rename, system album management, migrations
  - `ProjectRepository` - project CRUD, versioning, best take, stats
  - `OverdubRepository` - overdub group CRUD, layer management, integrity validation
  - `RecordingRepository` - recording CRUD, trash, restore, batch ops
- **Services**: `SearchService` (stateless search), `DataSafetyManager` (file-based persistence with checksums)
- Key managers: `RecorderManager`, `PlaybackEngine`, `OverdubEngine`, `AudioSessionManager`, `SharedAlbumManager`, `iCloudSyncManager`, `CloudKitSyncEngine`, `SupportManager`, `ProofManager`
- Watch managers: `WatchAppState`, `WatchRecorderManager`, `WatchPlaybackManager`
- Connectivity: `PhoneConnectivityManager` (iOS), `WatchConnectivityService` (watchOS)
- Data persistence: `DataSafetyManager` (primary, file-based with SHA-256 checksums + backup rotation), UserDefaults (fallback), file system (audio), CloudKit (shared albums)
- All models are `Codable` structs

## Key Features
- Recording with live waveform, gain control (-6 to +6dB), limiter, pause/resume, prevent sleep option
- Multi-track overdub (base track + up to 3 layers)
- Waveform editing (trim, split, fade in/out, normalize, noise gate, crossfade cuts) with zoom/pan
- 4-band parametric EQ per recording
- Metronome / click track (synthesized, not recorded; tap tempo, count-in, time signatures)
- Real-time monitoring effects (4-band EQ + compressor, hear while recording, file stays clean)
- Multi-track mixer (per-channel volume, pan, mute, solo) with offline stereo bounce
- Shared Albums via CloudKit (up to 5 participants, role-based permissions)
- iCloud sync across devices
- Auto-icon classification via SoundAnalysis
- Projects & versioning (V1, V2, V3 with best-take marking)
- Albums, Tags, and smart filtering
- Map view of GPS-tagged recordings
- Live Activity / Dynamic Island for active recordings
- Skip silence detection
- Tamper-evident proof receipts (SHA-256 + CloudKit timestamps)
- Multi-format export (Original, WAV, M4A/AAC, ALAC) with format picker + ZIP bulk export
- **Apple Watch companion app** with recording, playback, and auto-sync to iPhone
- **iPad adaptive layout** with optimized sheet presentation and top bar padding

## Apple Watch Companion App
- Record voice memos directly on Apple Watch (AAC mono 44.1kHz/128kbps)
- Playback with +/-10s skip controls and ShareLink
- Movable floating record button (drag to reposition, long-press to reset)
- Button stays in place during recording, icon switches to stop square
- Live waveform animation during recording (28-bar edge-faded display)
- Recordings auto-named "⌚️ Recording 1", "⌚️ Recording 2", etc.
- Recordings automatically transferred to iPhone via WCSession.transferFile
- Auto-imported into "⌚️ Recordings" system album on iPhone (UUID-based dedup)
- Theme synced from iPhone to Watch via applicationContext
- Themed UI matching iPhone palette (all 7 themes supported)

## Watch-to-iPhone Sync Pipeline
1. Watch records audio -> `WatchConnectivityService.transferRecording()` sends file + metadata (uuid, title, duration, createdAt)
2. iPhone receives via `PhoneConnectivityManager.session(_:didReceive file:)`
3. Deduplication check via UUID stored in UserDefaults (`watchImportedUUIDs`)
4. "⌚️ Recordings" system album auto-created on first import (lazy, positioned after Imports)
5. Recording imported via `AppState.importRecording()` -> triggers iCloud sync to iPad
6. Album uses `applewatch` SF Symbol icon with green color in album list

## Subscription Tiers (Pro)
- Monthly: $3.99
- 6-Month: $19.99
- Annual: $29.99
- 14-day free trial with annual plan

## Pro-Gated Features
Edit mode, shared albums, tags, iCloud sync, auto-icons, overdub, projects & versioning, watch auto-sync, metronome/click track, live recording effects, mixer & mixdown

## Temporarily Free Features (for TestFlight testing)
Edit mode, Overdub, and Auto Icons — controlled via `ProFeatureContext.temporarilyFree` set in `ProFeatureGate.swift`. To re-gate behind Pro, remove `.editMode`, `.recordOverTrack`, and/or `.autoIcons` from that set.

**APP STORE CONNECT REMINDER:** Before every submission to App Store Connect, check if `.editMode`, `.recordOverTrack`, and `.autoIcons` should be re-gated behind Pro by removing them from `ProFeatureContext.temporarilyFree` in `ProFeatureGate.swift`. Always ask the user before submitting.

## Free Features (previously Pro)
Recording quality (all presets: Standard, High, Lossless, WAV) — available to all users

## Recording Modes
Mono (default, best for built-in mic), Stereo (best with external stereo mic). Channel count applied via `RecorderManager` engine output format, capped at input device's available channels. Stereo requires an external stereo microphone — with built-in phone mic, recording falls back to mono automatically.

## Themes
7 themes: System, Angst Robot (Ableton-inspired), Cream, Logic Pro, Fruity (FL Studio), Avid (Pro Tools), Dynamite

## Project File Structure

### iOS App (`Sonidea/`)
```
App/           SonideaApp, AppState, Theme, AppearanceMode, SettingsModels
Models/        RecordingItem, Album, Tag, Project, Marker, TimelineItem, OverdubGroup, EditHistory, ProofModels, RecordingActivityAttributes, MixSettings
Views/         ContentView, RecordingsListView, RecordingGridView, RecordingDetailView, CalendarView, JournalView, MapView, ProjectDetailView, OverdubSessionView, TagManagerView, TipJarView, QuickHelpSheet, ShareSheet, SharedAlbumViews, iPadAdaptiveLayout, ExportFormatPicker, MetronomeSettingsView, RecordingEffectsPanel, MixerView
Views/Waveform/ WaveformView, WaveformSampler, EditableWaveformView, ZoomableWaveformEditor, ProWaveformEditor, AudioWaveformExtractor, EQGraphView, AudioEditToolsPanel
Audio/         RecorderManager, PlaybackEngine, PlaybackManager, AudioSessionManager, AudioEditor, AudioExporter, OverdubEngine, SkipSilenceManager, AudioDebug, SilenceDebugStrip, MetronomeEngine, RecordingMonitorEffects, MixdownEngine
Services/      SupportManager, LocationManager, TranscriptionManager, ProofManager, AudioIconClassifier, TrialNudgeManager, ProFeatureGate, PhoneConnectivityManager
CloudSync/     CloudKitSyncEngine, iCloudSyncManager, SharedAlbumManager, CloudSharingSheet, LocationSharingSheet, SensitiveRecordingSheet, SharedAlbum* (activity, comments, map, participants, settings, trash views)
Utilities/     FileHasher, StorageFormatter, IconCatalog, DeepLinks
Intents/       StartRecordingIntent, StopRecordingIntent, RecordingControlWidget
```

### watchOS App (`SonideaWatch Watch App/`)
```
App/           SonideaWatchApp
Models/        WatchRecordingItem, WatchTheme
Managers/      WatchAppState, WatchRecorderManager, WatchPlaybackManager
Views/         WatchContentView, WatchPlaybackView
Services/      WatchConnectivityService
Assets.xcassets/ AppIcon (same Sonidea logo as iOS)
```

## Key Files (by importance)
- `Sonidea/Views/ContentView.swift` - Main navigation, floating record button, album management
- `Sonidea/App/AppState.swift` - Central state container, import/export, album/recording CRUD
- `Sonidea/Views/RecordingDetailView.swift` - Recording editor (largest view file)
- `Sonidea/Audio/RecorderManager.swift` - Core recording via AVAudioEngine
- `Sonidea/Audio/PlaybackEngine.swift` - Playback with EQ and speed control
- `Sonidea/Audio/OverdubEngine.swift` - Multi-track recording engine
- `Sonidea/CloudSync/SharedAlbumManager.swift` - CloudKit sharing
- `Sonidea/CloudSync/CloudKitSyncEngine.swift` / `iCloudSyncManager.swift` - Sync
- `Sonidea/Services/SupportManager.swift` - StoreKit 2 subscriptions
- `Sonidea/Services/PhoneConnectivityManager.swift` - Receives watch recordings, sends theme
- `Sonidea/App/Theme.swift` - Theming system (7 themes)
- `SonideaWatch Watch App/Views/WatchContentView.swift` - Watch main UI, floating record button, recording HUD
- `SonideaWatch Watch App/Views/WatchPlaybackView.swift` - Watch playback with skip controls
- `SonideaWatch Watch App/Services/WatchConnectivityService.swift` - Sends recordings to iPhone

## Core Models
- `RecordingItem` - Recording with metadata, tags, album, location, EQ, versioning, proof
- `Album` - User/system albums with optional CloudKit sharing. System albums: Drafts, Imports, ⌚️ Recordings
- `Tag` - Custom tags with colors (special protected "favorite" tag)
- `Project` - Groups recordings as versions with best-take marking
- `OverdubGroup` - Groups base track with overdub layers
- `Marker` - Cue points within a recording
- `WatchRecordingItem` - Lightweight watch recording model (id, fileURL, duration, title, isTransferred)

## Targets
1. `Sonidea` - Main iOS/iPadOS app
2. `SonideaWatch Watch App` - watchOS companion app (embedded in Sonidea.app/Watch/)
3. `SonideaRecordingWidget` - Live Activity widget for recording controls
4. `SonideaTests` - Unit tests
5. `SonideaUITests` - UI tests

## Bundle IDs
- iOS: `com.iacompa.sonidea`
- watchOS: `com.iacompa.sonidea.watchkitapp`
- Widget: `com.iacompa.sonidea.SonideaRecordingWidget`

## Notes
- Recording quality options: Standard (AAC 128kbps), High (AAC 256kbps), Lossless (ALAC), WAV (PCM 16-bit) — all free
- No MP3 support (Apple uses AAC as lossy codec; AAC is higher quality than MP3 at same bitrate)
- All audio at 44.1kHz (standard) or 48kHz (high/lossless/wav)
- Watch recordings: AAC mono 44.1kHz/128kbps (.m4a)
- Prevent sleep while recording: `UIApplication.shared.isIdleTimerDisabled` toggled on/off in `RecorderManager` (setting defaults to on)
- Transcription copy button: "Copy" in transcription section header copies full transcript to clipboard via `UIPasteboard`
- Crash recovery saves in-progress recording state to UserDefaults
- Offline support with retry queues for CloudKit operations
- iPad uses `sizeClass == .regular` checks for adaptive layout (wider top padding, fullScreenCover for sheets)
- Watch uses PBXFileSystemSynchronizedRootGroup — Xcode auto-syncs with filesystem
- Watch app icon matches iOS app icon (Sonidea waveform logo)
- **watchOS asset catalog rule:** The watch AppIcon.appiconset `Contents.json` must use `"platform": "watchos"` (lowercase). Using `"watchOS"` (camelCase) causes App Store Connect to reject the upload with "Missing Icons" errors. File: `SonideaWatch Watch App/Assets.xcassets/AppIcon.appiconset/Contents.json`. The Contents.json has both a `"platform": "watchos"` entry and a `"platform": "ios"` entry (same PNG) so the asset catalog compiles on both platforms.
- **CRITICAL: xcodebuild for simulator** — Do NOT use `-sdk iphonesimulator` when building the Sonidea scheme. It forces ALL targets (including the Watch app) to compile against the iOS simulator SDK, which breaks WatchKit imports and watchOS-only assets. Instead, use: `xcodebuild -project Sonidea.xcodeproj -scheme Sonidea -destination 'id=<simulator-id>' build` — Xcode automatically picks the correct SDK per target.

## Recent Changes (this session)
- Removed Dual Mono and Spatial recording modes (were not functionally different from Stereo)
- Added migration in `RecordingMode.init(from:)` so saved "dualMono"/"spatial" map to `.stereo`
- Un-gated recording quality — all presets now free for all users
- Added "Prevent Sleep" toggle in Recording settings (defaults on, uses `isIdleTimerDisabled`)
- Added "Copy" button in transcription section to copy full transcript to clipboard
- Watch recordings renamed from "Watch Rec X" to "⌚️ Recording X"
- Updated `generateTitle()` in `WatchAppState` with backward compat for old "Watch Rec" prefix

## Audit Fixes (latest session)
- **Pro gating for Projects**: Added `.projects` case to `ProFeatureContext`; create/add-to-project actions in RecordingDetailView now require Pro
- **Shared album permissions**: `addRecordingToSharedAlbum` checks `canAddRecordings`; `deleteRecordingFromSharedAlbum` checks `canDeleteAnyRecording`
- **CloudKit sync safety**: New synced recordings only appended to state after audio file copy succeeds
- **PlaybackEngine interruption handling**: Pauses on phone call/Siri, resumes when system allows
- **Watch audio session cleanup**: `WatchPlaybackManager` deactivates audio session on stop/finish
- **Watch recording error feedback**: Haptic failure feedback when recording fails to start
- **PhoneConnectivityManager dedup fix**: UUID dedup check moved to main thread to prevent race conditions
- **Waveform cache eviction**: LRU eviction at 20 entries to prevent unbounded memory growth
- **EditableWaveformView latency**: Added 50ms latency compensation to match ProWaveformEditor
- **RecordingGridView iPad**: Adaptive 3-column grid on iPad; sheets converted to iPadSheet
- **RecordingsListView iPad**: Batch/move/tag sheets converted to iPadSheet
- **ProofManager safety**: Replaced force unwrap on FileManager.urls with safe fallback

## Data Safety, Architecture & Testing Overhaul (latest session)

### Data Safety
- **File-based persistence** (`DataSafetyManager.swift`): All metadata (recordings, tags, albums, projects, overdubGroups) now saved to Application Support as JSON wrapped in `SafeEnvelope` with SHA-256 checksum, schema version, timestamp, and item count
- **Atomic writes** via `Data.write(options: .atomic)` — OS-level temp-file + rename prevents partial writes
- **3-slot backup rotation**: Before each write, primary -> backup1 -> backup2 -> backup3 (oldest deleted)
- **Auto-recovery cascade**: Load tries primary -> backups newest-first -> legacy UserDefaults
- **Checksum verification** on every load — SHA-256 of payload must match envelope
- **Dual-write transition**: Both file-based and UserDefaults written during migration period
- **Audio file protection**: `protectAudioFile(at:)` sets `FileProtectionType.completeUntilFirstUserAuthentication` and ensures iCloud backup inclusion after each recording

### Architecture Decomposition
- **AppState** reduced from 2,673-line god object to thin facade (~500 lines of delegation logic)
- Extracted 5 stateless repositories + 1 service, all operating on `inout` arrays with no persistence or sync side effects
- AppState public method signatures remain **identical** — zero view changes required (all 67 `@Environment(AppState.self)` call sites untouched)
- Each AppState method now follows: delegate to repository -> save -> trigger sync
- Shared album methods (~400 lines) remain in AppState due to tight CloudKit async coupling

### Testing
- **~80 unit tests** across 21 test files using Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- **Model tests** (6 files): RecordingItem, Tag, Album, Project, OverdubGroup, SettingsModels — Codable round-trips, migration defaults, computed properties
- **Repository tests** (5 files): Tag, Album, Project, Overdub, Recording — all CRUD operations, edge cases, batch ops
- **Service tests** (8 files): DataSafetyManager, SearchService, StorageFormatter, DateFormatters, DeepLinks, IconCatalog, TrialNudgeManager, FileHasher
- **Audio tests** (1 file): AudioDebug file status verification
- Test infrastructure: `TestHelpers.swift` with factory methods for all models

## Launch-Ready Feature Additions (latest session)

### Code Health
- **Trash methods extracted** to `RecordingRepository`: `permanentlyDelete`, `emptyTrash`, `purgeOldTrashed` now return `PermanentDeleteResult` structs; AppState delegates and handles file I/O
- **SupportManager tests**: ~15 tests for SubscriptionPlan, SubscriptionStatus, state logic, debug overrides, compatibility stubs
- **Trash operation tests**: ~18 tests for permanent delete, empty trash, purge old trashed (including overdub group cleanup)
- **~115 unit tests** total across 23 test files

### Multi-Format Export
- **ExportFormat** enum: Original, WAV, M4A (AAC 256kbps), ALAC
- **Format picker** sheet shown before sharing (ExportFormatPicker.swift)
- `export(recording:format:)` routing method + `convertToM4A`, `convertToALAC` conversion methods
- Generalized `safeFileName(for:format:existingNames:)` replacing WAV-only variant
- Bulk export updated to accept format parameter

### Audio Editing Enhancements
- **Fade in/out**: Linear, S-curve, exponential curves; configurable duration
- **Normalization**: Two-pass peak normalization with configurable target dB
- **Noise gate**: Envelope follower with threshold, attack, release, hold; linked-stereo gating
- **Crossfade cuts**: Smooth splice with configurable crossfade duration
- **AudioEditToolsPanel** sheet in edit mode with parameter controls for each tool
- **FadeCurve** enum with `apply(_ t:)` for curve math

### Metronome / Click Track
- **MetronomeEngine**: Synthesized click via AVAudioSourceNode render callback
- Downbeat (1000 Hz, 15ms) and upbeat (800 Hz, 10ms) sine bursts with exponential decay
- BPM 40–240, time signature (2–8 beats, quarter/eighth), count-in (0/1/2 bars)
- Tap tempo with 8-tap averaging and 2s timeout
- **MetronomeSettingsView** with BPM slider, tap tempo, time signature, count-in, volume
- Click node attached to mainMixerNode (NOT recorded — tap captures from limiter)
- Forces engine recording path when enabled

### Real-Time Recording Effects (Monitoring Only)
- **RecordingMonitorEffects**: 4-band parametric EQ + dynamics processor compressor
- Monitoring chain: Limiter → MonitorMixer → EQ → Compressor → MainMixerNode
- Recording stays clean (tap on limiter is upstream of effects)
- **RecordingEffectsPanel** with EQ sliders, compressor threshold/ratio, monitor volume
- Forces engine recording path when enabled

### Multi-Track Mixer + Mixdown
- **MixSettings** model: per-channel volume (0–1.5), pan (-1 to +1), mute, solo; master volume
- **ChannelMixSettings**: individual channel state with solo/mute logic
- **MixdownEngine**: Offline chunk-by-chunk stereo WAV bounce (no AVAudioEngine offline render needed)
- **MixerView**: Horizontal channel strips with vertical volume faders, pan sliders, M/S buttons
- **OverdubGroup.mixSettings**: Persisted with `decodeIfPresent` migration
- **OverdubEngine.applyMixSettings**: Real-time player volume/pan updates
- Bounce imports result as new recording via `importRecording`

### Pro Feature Gates (new)
- `.metronome`: "Unlock Click Track" (metronome icon)
- `.recordingEffects`: "Unlock Live Effects" (slider.horizontal.3)
- `.mixer`: "Unlock Mixer & Mixdown" (slider.vertical.3)

### New Files (12)
| File | Purpose |
|------|---------|
| `Sonidea/Audio/MetronomeEngine.swift` | Synthesized click track engine |
| `Sonidea/Audio/RecordingMonitorEffects.swift` | Monitoring-only EQ + compressor |
| `Sonidea/Audio/MixdownEngine.swift` | Offline stereo bounce |
| `Sonidea/Models/MixSettings.swift` | Per-channel mix settings |
| `Sonidea/Views/ExportFormatPicker.swift` | Format selection sheet |
| `Sonidea/Views/MetronomeSettingsView.swift` | Click track settings |
| `Sonidea/Views/RecordingEffectsPanel.swift` | Live effects settings |
| `Sonidea/Views/MixerView.swift` | Mixer UI with channel strips |
| `Sonidea/Views/Waveform/AudioEditToolsPanel.swift` | Fade/normalize/gate panel |
| `SonideaTests/Repositories/TrashOperationsTests.swift` | Trash operation tests |
| `SonideaTests/Services/SupportManagerTests.swift` | SupportManager tests |
| `SonideaTests/Audio/AudioExporterTests.swift` | Export format tests |

### Modified Files (8)
| File | Changes |
|------|---------|
| `RecordingRepository.swift` | +PermanentDeleteResult, +3 trash methods |
| `AppState.swift` | Replaced 3 inline trash methods with delegation |
| `AudioExporter.swift` | +ExportFormat, +multi-format conversion, +convertFile router |
| `AudioEditor.swift` | +FadeCurve, +fade, +normalize, +noiseGate, +cutWithCrossfade |
| `RecorderManager.swift` | +metronome, +monitorEffects, +needsEngine logic |
| `OverdubEngine.swift` | +applyMixSettings |
| `OverdubGroup.swift` | +mixSettings with decodeIfPresent migration |
| `RecordingDetailView.swift` | +format picker, +edit tools panel, +fade/normalize/gate actions |
| `OverdubSessionView.swift` | +mixer button, +bounceMix |
| `ProFeatureGate.swift` | +metronome, +recordingEffects, +mixer cases |

## Comprehensive Audit Fixes (latest session)

### iCloud Sync (CloudKitSyncEngine.swift)
- Album `populateCKRecord()` now syncs `createdAt` and `isSystem` fields
- Album `from(ckRecord:)` now decodes `createdAt` (default: `Date()`) and `isSystem` (default: `false`)
- Force unwrap `throw lastError!` replaced with `throw lastError ?? CKError(.internalError)`
- Audio file download race condition: backup/restore pattern prevents data loss on failed copy
- Tag `isProtected` confirmed as computed property (derived from `id == Tag.favoriteTagID`) — no decode needed

### Recording Pipeline (RecorderManager, MetronomeEngine, OverdubEngine, RecordingMonitorEffects)
- **MetronomeEngine**: Replaced local `renderSampleIndex` with `UnsafeMutablePointer<UInt64>` shared via pointer capture for thread-safe render callback state
- **OverdubEngine**: Guard before observer registration removes existing observer first
- **RecorderManager**: Mic permission pre-flight check at start of `startRecording()` (denied/undetermined/granted)
- **RecorderManager**: `fileWriteQueue.sync {}` drain after `audioEngine?.pause()` in pause flow
- **RecorderManager**: Limiter bypass changed from 0dB to +40dB threshold so it never engages
- **RecorderManager**: Gain validation with `max(-6.0, min(6.0, ...))` clamping
- **RecordingMonitorEffects**: `monitorVolume` property now has `didSet { applyMonitorVolume() }`

### Playback + Data Integrity (PlaybackEngine, AppState, RecordingDetailView, SharedAlbumManager)
- **PlaybackEngine**: `currentTime` lower bound check (`if currentTime < 0`) in `updateCurrentTime()`
- **PlaybackEngine**: Skip-to-end calls `handlePlaybackFinished()` instead of restarting from beginning
- **PlaybackEngine**: Interruption handler resumes playback even when `optionsValue` is nil in userInfo
- **RecordingDetailView**: Playback error alert: "OK" stays, "Go Back" dismisses (user choice)
- **RecordingDetailView**: `undoLastEdit()` pushes current state to redo stack before restoring
- **RecordingDetailView**: File cleanup race condition fixed — state saved before old file deleted
- **AppState**: File deletion in trash ops uses `do/catch` with debug logging instead of `try?`
- **SharedAlbumManager**: Cache expiration: 30-day stale file cleanup + 500MB LRU eviction

### Shared Albums + Watch (SonideaApp, SharedAlbumManager, PhoneConnectivityManager, AppState)
- **SonideaApp**: `refreshCachedUserId()` called on app launch and every foreground transition
- **SharedAlbumManager**: New `.downloadFailed` error case for nil asset URLs (was `.recordingNotFound`)
- **PhoneConnectivityManager**: Watch recording `createdAt` extracted from metadata and preserved
- **AppState**: `importRecording()` accepts `createdAt` parameter (default: `Date()`)

### SF Symbol Compatibility (RecordingItem, IconCatalog)
- `pianokeys` (iOS 18+) → `music.note.list` (iOS 16+)
- `guitars.fill` (iOS 17.4+) → `guitars` (iOS 17.0+)
- Guitar + Strings entries merged in IconCatalog to avoid duplicate SF Symbol IDs

### Settings (ContentView)
- Guard clauses on `autoSelectIcon` and `watchSyncEnabled` onChange handlers prevent redundant toggles

## Deep Audit Fixes (file-by-file audit session)

### OOM Prevention
- **AudioWaveformExtractor.detectSilence()**: Converted from single full-file buffer to chunked I/O with pre-computed dBFS array (~2.8MB for 1-hour recording vs ~1.3GB before)
- **AudioEditor.performTrim/performCut**: Converted to chunked 64KB reads/writes (done in prior round)

### Data Integrity
- **RecordingDetailView**: Proof status reset to `.none` when audio is edited (was preserving stale `.proven` status with nil SHA)
- **WatchRecordingItem**: Switched from absolute URL persistence to filename-only with runtime resolution — prevents silent loss of all recording metadata when watchOS sandbox path changes on app update
- **WatchAppState**: Migration path from old absolute-URL format + re-save on load
- **OverdubRepository.validateIntegrity**: Recomputes recording ID set after layer removals to avoid stale snapshot leaving dangling layer references
- **TagRepository.toggleTag**: Now sets `modifiedAt = Date()` so tag changes propagate via iCloud sync
- **AlbumRepository.setAlbum**: Now sets `modifiedAt = Date()` so album assignments propagate via iCloud sync
- **ProjectRepository.removeFromProject/deleteProject**: Now sets `modifiedAt = Date()` on orphaned recordings so changes propagate via iCloud sync

### Thread Safety
- **TranscriptionManager**: Replaced bare `var hasResumed` flag with `NSLock`-protected `safeResume()` function to prevent double-resume of `CheckedContinuation` (recognition callback and cancellation handler can fire from different threads)

### UX Fixes
- **TagManagerView.onMove**: Disabled during active search — filtered indices were being applied to full tag array, corrupting tag order
- **ContentView export functions**: Export errors now show user-visible message via `exportProgress` with 3-second auto-clear
- **RecordingDetailView/TipJarView**: Export errors now logged in DEBUG mode
- **WatchRecordingItem**: DateFormatter instances cached as static properties instead of recreating per access

## Production-Readiness Scan (million-user launch prep)

### Critical Data Loss Fix
- **iCloudSyncManager.applySyncedData**: Was writing synced data ONLY to UserDefaults, bypassing DataSafetyManager. Fixed to write via `DataSafetyFileOps.saveSync()` (primary) + UserDefaults (fallback), matching the app's standard persistence pattern

### Crash Prevention
- **AudioIconClassifier**: Double-resume of `CheckedContinuation` when both `didFailWithError` and `requestDidComplete` fire. Added `hasDelivered` guard flag to `deliverResult()`
- **RecorderManager audio tap**: Two audio tap callbacks passed `AVAudioPCMBuffer` to MainActor Task — buffer can be recycled/freed before Task executes (use-after-free). Fixed: compute peak on audio thread, pass only `Float` to MainActor. Renamed `updateMeterFromBuffer` to `updateMeterWithPeak`
- **OverdubEngine audio tap**: Same buffer use-after-free fix as RecorderManager

### OOM Prevention
- **AudioEditor.removeMultipleSilenceRanges**: Single full-file buffer per keep range → chunked 65536-frame reads
- **WaveformSampler.extractSamples/extractMinMaxSamples**: Full-file buffer (~1.3GB for 1-hour recording) → chunked 65536-frame reads with bucket-based downsampling. Memory now constant ~256KB regardless of file size
- **OverdubEngine.loadFullBuffer**: Added 25M frame cap (~100MB). Files exceeding this fall back to non-looped `scheduleFile`

### Force Unwrap Elimination
- **MixdownEngine**: `AVAudioFormat(...)!` → `guard let` + `throw NSError`
- **AudioEditor**: `combDelays.max()!` → `guard let` + `throw AudioEditorError`

### Thread Safety
- **WatchAppState**: Added `@MainActor` annotation for consistency with all other `@Observable` state managers

### Security & Privacy
- **ProofManager**: Pending queue file now written with `.completeFileProtection`
- **AppState**: OSLog privacy for recording title and album name changed from `.public` to `.private`
- **SharedAlbumManager**: 22 OSLog interpolations of user-generated content (album names, recording titles, participant IDs) annotated with `privacy: .private`

### Internationalization
- **CalendarView + ContentView**: Hardcoded English day-of-week headers (`["S","M","T","W","T","F","S"]`) replaced with locale-aware `Calendar.current.veryShortWeekdaySymbols` + `firstWeekday` rotation

### Performance
- **RecordingsListView**: Added `.onChange(of: appState.recordingsContentVersion)` observer so cached grouped recordings invalidate on content changes (not just count changes)
- **CalendarView**: `recordingsByDay` converted from computed property to `@State` with `onChange` invalidation — no longer regroups all recordings on every render
- **JournalView**: `timelineGroups` converted from computed property to `@State` with `onChange` invalidation — no longer rebuilds full timeline on every render
- **MapView**: `allSpots` converted from computed property to `@State` with `onChange` invalidation — no longer clusters all GPS recordings on every render
- **WaveformSampler cache**: Moved from UserDefaults to Caches directory (`Library/Caches/WaveformCache/`). Added 2-second debounce on writes. Legacy UserDefaults keys cleaned up on first launch

### Current Assessment (vs Apple Voice Memos)

**Feature set: 10/10.** Sonidea is a full-featured mobile DAW disguised as a voice memo app. Multi-track overdub with per-channel mixer, offline bounce, metronome with count-in, real-time monitoring effects (EQ + compressor), fade/normalize/noise gate editing, multi-format export (WAV/M4A/ALAC), shared albums via CloudKit, project versioning, GPS tagging, auto-icon classification, tamper-proof receipts, 7 themes, Watch companion.

**Code health: 9.5/10, up from 9/10.**
- Three rounds of audits: 11-agent initial + 9-agent deep + 5-agent production-readiness scan
- 65+ fixes applied across all subsystems
- All critical data-loss, crash, and OOM paths resolved
- All audio buffer lifecycle issues fixed (no buffer references cross isolation boundaries)
- All force unwraps in audio pipeline eliminated
- User-generated content privacy-annotated in all OSLog statements
- Locale-aware date formatting throughout
- Expensive computed properties cached with proper invalidation
- Waveform cache moved from UserDefaults to Caches with debounce
- ~115 tests across 23 test files
- Both iOS and watchOS targets build successfully (verified)

## iCloud Sync Bulletproofing (latest session)

### Phase 1 — Quick Wins (12 fixes)
- **`try?` eliminated**: All 9 tag/album/project sync triggers in iCloudSyncManager now use `do/catch` with error logging instead of silently dropping errors
- **changeToken ordering**: Token now persisted AFTER `applyRemoteChanges()` succeeds (was before — crash = permanent record loss)
- **fetchChanges() returns Bool**: `performFullSync()` only shows "Synced" status if fetch succeeded; shows error otherwise
- **syncOnForeground()**: Now calls `performFullSync()` (was only `fetchChanges()` — failed uploads never retried)
- **CKError rate limit handling**: `withRetry` checks for `.requestRateLimited` / `.zoneBusy` and uses `retryAfterSeconds` delay
- **CKError quota exceeded**: Upload loop stops early when quota exceeded; user sees "iCloud storage full" error
- **Re-upload storm prevention**: Downloaded recordings marked as synced via `markSynced()` so they aren't re-uploaded
- **Periodic sync progress saves**: `lastSyncedDates` saved every 10 items during full sync (crash-safe)
- **File-pruning guard**: `loadRecordings()` skips background file-pruning when sync is active (prevents deleting recordings whose audio hasn't downloaded yet)
- **changeTokenExpired handling**: Resets token and retries with full fetch on expired token
- **CKContainer stored property**: Replaced computed property with stored `let` (was creating new instance on every access)
- **Dead code removed**: `triggerSyncForAudioEdit` (never called) removed from AppState extension

### Phase 2 — OverdubGroup Sync
- **New record type**: `overdubGroup` added to `SonideaRecordType` enum
- **CKRecord serialization**: `OverdubGroup` extension with `populateCKRecord`, `toCKRecord`, `from(ckRecord:)` (layer IDs and mixSettings as JSON)
- **Save/delete methods**: `saveOverdubGroup()`, `deleteOverdubGroup()` in CloudKitSyncEngine
- **Remote change handling**: `applyRemoteChanges()` processes overdub group records (create/update/delete)
- **Sync triggers**: `onOverdubGroupCreated/Updated/Deleted` in iCloudSyncManager
- **AppState wiring**: `createOverdubGroup`, `addLayerToOverdubGroup`, `removeOverdubLayer`, `removeLayerFromOverdubGroup`, `updateLayerOffset` all trigger sync
- **Full sync upload**: Overdub groups included in `performFullSync()` upload loop
- **SyncableData updated**: `overdubGroups` field added with `decodeIfPresent` migration; `applySyncedData` persists via DataSafetyFileOps

### Phase 3 — Resilience Infrastructure
- **Persistent retry queue**: `PendingSyncOperation` struct with operationType, recordType, recordId, retryCount. Stored in UserDefaults. Failed individual sync triggers queue operations. `drainPendingOperations()` runs at start of every `performFullSync()`. Operations dropped after 5 retries or 7 days.
- **All sync triggers wired**: Every `on*Created/Updated/Deleted` method queues on failure instead of just logging
- **Large file warning**: `saveRecording()` logs warning for files >200MB
- **BGProcessingTask**: Registered in `AppDelegate.didFinishLaunchingWithOptions`. `scheduleBackgroundSync()` called when app backgrounds with sync enabled. Handler calls `performFullSync()`.
- **beginBackgroundTask**: `onRecordingCreated` wraps upload in `UIApplication.shared.beginBackgroundTask` for ~30s extra background time
- **iCloud account change handling**: `CKAccountChanged` notification observer. On account change: clears changeToken, lastSyncedDates, zone/subscription flags; re-runs full setup. On account unavailable: shows `.accountUnavailable` status.

### Files Modified
| File | Changes |
|------|---------|
| `CloudKitSyncEngine.swift` | All Phase 1 engine fixes + Phase 2 overdub group support + Phase 3 retry queue, BGTask, account changes |
| `iCloudSyncManager.swift` | `try?` → `do/catch`, retry queue wiring, overdub group triggers, `beginBackgroundTask`, `scheduleBackgroundSync`, `SyncableData.overdubGroups` |
| `AppState.swift` | File-pruning sync guard, overdub group sync triggers, dead code removal |
| `SonideaApp.swift` | BGTaskScheduler registration, background sync scheduling on app backgrounding |

## CRITICAL: iOS 26 Padding Bug — DO NOT USE .padding() for horizontal margins in RecordingDetailView

### The Bug
On iOS 26 (Tahoe), `.padding()` on a VStack inside a ScrollView inside a NavigationStack **presented as a sheet** does **NOT** reduce the VStack's content width. Content renders edge-to-edge no matter what. This is a confirmed SwiftUI regression.

### What DOES NOT WORK (do not attempt these again):
- `.padding(.horizontal, N)` on the VStack — **BROKEN**, any value, even 32pt, VStack still renders full width
- `.padding()` (default) on the VStack — **BROKEN**
- `.scenePadding(.horizontal)` on the VStack — **BROKEN**
- `.contentMargins(.horizontal, 16, for: .scrollContent)` on the ScrollView — **BROKEN**
- `.safeAreaPadding(.horizontal, 16)` on the ScrollView — **BROKEN**
- `.padding(.horizontal, N)` on the ScrollView itself — **BROKEN**

A debug `.border()` placed before `.padding(.horizontal, 32)` confirmed the VStack occupies the full screen width despite the padding modifier being present. This was verified with screenshots.

### What DOES WORK (the only fix):
Use `GeometryReader` to measure the available width, then constrain the VStack with an explicit `.frame(width:)`:
```swift
GeometryReader { outerProxy in
    ZStack {
        palette.background.ignoresSafeArea()
        ScrollView {
            VStack(spacing: 24) { ... }
                .frame(width: max(0, outerProxy.size.width - 32))
                .padding(.vertical, 16)
        }
    }
}
```
**This is the ONLY approach that constrains horizontal content width in sheet-presented NavigationStack > ScrollView > VStack on iOS 26.** Do not replace this with `.padding()` — it will silently break and content will go edge-to-edge again.

### Layout Rules for RecordingDetailView
- The `GeometryReader` + `.frame(width:)` provides 16pt margins on each side (32pt total subtracted)
- Do NOT add `.padding(.horizontal)` to the VStack — it does nothing
- Child views that need extra inward spacing should use their own `.padding(.horizontal, N)`
- Playback controls use `HStack(spacing: 12)` with NO Spacers — buttons are grouped together, not pushed to edges
- The `.padding(.vertical, 16)` on the VStack DOES work correctly (only horizontal is broken)

## Bluetooth Recording & Metronome Bug Fixes (latest session)

### OverdubEngine Fixes (error 560226676 — "could not create recording file")
- **AAC bitrate scaling**: `recordingSettings(for:)` now caps bitrate relative to sample rate (`maxBitratePerChannel = max(32000, Int(sampleRate) * 8)`). With Bluetooth HFP at 8kHz, bitrate caps to 64kbps instead of rejected 128kbps. Matches RecorderManager pattern.
- **Input format resolution**: Replaced stale `inputNode.outputFormat(forBus: 0)` with 3-tier fallback: (1) `inputNode.inputFormat(forBus: 0)` — actual hardware format, (2) `outputFormat` — fallback, (3) construct from `session.sampleRate` — last resort. Prevents format mismatch after engine stop.
- **Stored AppSettings**: `prepare()` now stores `settings` in `storedAppSettings` property for use in `startRecording()`.
- **Preferred input reapplication**: After Bluetooth HFP route stabilization polling, calls `refreshAvailableInputs()` and `applyPreferredInput(from: storedAppSettings)` to honor mic source selection.

### AudioSessionManager Fixes
- **configureForOverdub()**: Now sets `lastAppliedSettings = settings` so route-change handler can reapply preferred input during overdub sessions.
- **configureForOverdub()**: Added `applyPreferredInput(from: settings)` BEFORE session activation (matching double-apply pattern in configureForRecording).

### RecorderManager Fixes ("no audio captured" with metronome)
- **Buffer write counting**: New `bufferWriteCount` and `lastWriteErrorMessage` properties track successful writes and last error.
- **Post-start validation**: 1.5-second delayed check after engine starts — if `bufferWriteCount == 0`, shows actionable error ("No audio input detected. Check your microphone connection or try disconnecting Bluetooth.") and logs full diagnostics.
- **Enhanced "no audio captured" error**: Now logs full diagnostics via `AudioDiagnostics.logNoAudioCaptured()` and shows context-aware error message (mentions Bluetooth/mic if zero buffers written).

### Always-On Diagnostic Logging
- **AudioDiagnostics enum** (in AudioSessionManager.swift): Two static methods that log in BOTH Debug and Release builds (critical for TestFlight):
  - `logRecordingStart()`: File URL, directory, free space, session state (category, mode, sampleRate, IOBufferDuration, inputAvailable, preferredInput), route (all inputs + outputs), engine state (formats)
  - `logNoAudioCaptured()`: File size, buffer count, write error count, last error, session state, route
- Both RecorderManager and OverdubEngine call `logRecordingStart()` at engine start
- RecorderManager metronome logging now always-on (not DEBUG-only): BPM, volume, mixer volume, output format, output route devices
- MetronomeEngine logs in `createSourceNode()` and `start()`: sample rate, format, BPM, volume, sourceNode status

### Files Modified (4)
| File | Changes |
|------|---------|
| `AudioSessionManager.swift` | +lastAppliedSettings in configureForOverdub, +pre-activation applyPreferredInput, +AudioDiagnostics enum |
| `OverdubEngine.swift` | +storedAppSettings, +AAC bitrate scaling, +3-tier input format resolution, +BT preferred input reapplication, +diagnostic logging |
| `RecorderManager.swift` | +bufferWriteCount/lastWriteErrorMessage, +post-start validation, +enhanced no-audio error, +always-on diagnostics |
| `MetronomeEngine.swift` | +diagnostic logging in createSourceNode() and start() |

**Remaining work:**
- Shared album methods (~400 lines) still live directly in AppState due to CloudKit async coupling
- No integration tests or UI tests
- ShareSheet iPad popover configuration (not confirmed as an issue when presented via SwiftUI .sheet)
- Watch: no audio session interruption handling, no crash recovery for in-progress recordings

**Post-launch idea (pending user feedback):**
- **Auto-icon learning from corrections**: When a user overrides an auto-assigned icon, store the correction locally (top SoundAnalysis labels + rejected icon + chosen icon) in a UserDefaults-backed bias table. Apply confidence offsets (+0.10 per positive match, -0.05 per rejection) during future classifications. Purely on-device, no data leaves the phone. Needs ~10-20 corrections before it's useful — only worth building if users actually interact with icon selection enough to generate that data.

## Logic Pro-Style Knob EQ Controls (latest session)

### Overview
Replaced slider-based EQ band controls with Logic Pro-style rotary knobs in `EQGraphView.swift`. The interactive EQ graph (draggable band points) is unchanged. The slider panel below is now a row of 3 knobs (Freq, Gain, Q) per band with color-coded band selector tabs.

### New Views
- **`EQKnob`**: 270-degree arc knob (~56pt diameter) with background track, value arc, and indicator dot. Vertical drag gesture (up = increase, down = decrease, ~300pt for full range). `isLogarithmic` flag for frequency knob (log10 scale).
- **`EQBandTab`**: Color-coded capsule pill button for band selection (filled when selected, tinted when not)
- **`Arc`** (private): `Shape` struct for drawing arc paths used by `EQKnob`

### Changes to `ParametricEQView`
- `selectedBand` default changed from `nil` to `0` — knobs always visible on load
- `body` now shows `bandTabs` (4 color-coded pill buttons) + `knobControls(for:)` (3 knobs in HStack)
- Band point `onTapGesture` always selects (never deselects to nil)
- Added `bandColors` static array `[.red, .orange, .green, .blue]` shared between tabs and knobs

### Removed
- `LogSlider` struct (replaced by `EQKnob` with `isLogarithmic: true`)
- `bandControls(for:)` method (old Freq/Gain/Q slider layout)

### File Modified (1)
| File | Changes |
|------|---------|
| `EQGraphView.swift` | -LogSlider, -bandControls(for:), +EQKnob, +EQBandTab, +Arc, +bandTabs, +knobControls(for:), selectedBand default 0 |

## Knob Controls for All Audio Effects + Haptics (latest session)

### Knob Sensitivity Fix
- **Bug**: Drag gesture read `normalized` (computed from current `value`) each frame, but `value` was already updated by previous frames, creating exponential/compounding sensitivity — moving 1cm would jump to 100%.
- **Fix**: Added `@State private var dragStartNormalized: Double?` that captures the starting normalized value once per drag gesture, then computes delta from that fixed base. Reset on `.onEnded`.
- **Sensitivity**: 500pt vertical drag for full range (was 150pt, then 300pt).

### Haptic Feedback
- 20 detent positions across the knob range
- `UIImpactFeedbackGenerator(style: .light)` fires when crossing a detent boundary
- `@State private var lastDetent: Int` tracks current detent to avoid repeat haptics

### Compression Knobs (`AudioEditToolsPanel.swift`)
- Replaced `compressControls` sliders with 3 `EQKnob` views in HStack: Gain, Reduction, Mix
- All knobs use `palette.accent` color

### Echo Knobs (`AudioEditToolsPanel.swift`)
- Replaced `echoControls` sliders with 4 `EQKnob` views in 2x2 grid
- Top row: Delay (0.01-1.0s) + Feedback (0-0.9)
- Bottom row: Damping (0-1.0) + Wet/Dry (0-1.0)

### Reverb Knobs (`AudioEditToolsPanel.swift`)
- Replaced `reverbControls` sliders with 5 `EQKnob` views in 3+2 layout
- Top row: Room Size (0-1.0) + Pre-Delay (0-0.1s) + Decay (0.1-5.0s)
- Bottom row: Damping (0-1.0) + Wet/Dry (0-1.0) + spacer

### Band Tabs Removed
- Removed Low/Low-Mid/Hi-Mid/High band selector tabs from EQ view
- Band selection via tapping points on graph only

### Toast Notifications Removed for Effects
- Removed "effect applied/removed" toast notifications from all effect operations (compression, reverb, echo, fade, normalize, noise gate)
- Kept toast notifications for Trim and Cut operations only (less frequent, more destructive)

## Icon Consistency & Source Tracking (latest session)

### Icon Rendering Unified Across Views
- **Problem**: Icons rendered differently in recordings list, detail panel, and icon picker. Default dark gray (`#3A3A3C`) icons were invisible on dark themes.
- **Solution**: Standardized all icon views to use `palette.surface` background with `palette.textPrimary` foreground (for default icons) or custom color (for user-set colors).

### Changes
- **`RecordingIconTile`** (RecordingsListView.swift): Background changed to `palette.surface`, foreground to `palette.textPrimary` (or custom `iconColorHex` color), border to `palette.stroke`
- **`TopBarIconItem`** (RecordingDetailView.swift): Added `hasCustomColor: Bool` flag. Default icons use `palette.textPrimary` on `palette.surface`. Custom-colored icons use their actual color. Removed luminance-based chip background logic.
- **`TopBarSuggestedIcons`**: Updated to pass `hasCustomColor` parameter through to `TopBarIconItem`
- **`MainIconGridItem`**: Selected icon now uses `palette.accent` background instead of `tintColor` (which could be invisible dark gray)
- **Star badge**: Uses `palette.accent` background

### Icon Source Note in Picker
- **`IconPickerSheet`**: Added `iconSource: IconSource?` and `hasIconName: Bool` parameters
- Shows contextual note below instruction text: "Default icon" (gray), "AI-selected icon" (purple), or "User-selected icon" (blue)
- Each note has matching SF Symbol icon (circle.dashed, sparkles, hand.tap)

### Auto Icons Temporarily Free
- Added `.autoIcons` to `ProFeatureContext.temporarilyFree` set for TestFlight testing
- **REMINDER**: Re-gate `.autoIcons` behind Pro before App Store submission

### Files Modified
| File | Changes |
|------|---------|
| `RecordingsListView.swift` | `RecordingIconTile` icon styling unified with palette |
| `RecordingDetailView.swift` | `TopBarIconItem` + `MainIconGridItem` + `IconPickerSheet` updates |
| `AudioEditToolsPanel.swift` | Compression, echo, reverb controls converted to knobs |
| `EQGraphView.swift` | Band tabs removed, knob sensitivity fix, haptic feedback |
| `ProFeatureGate.swift` | `.autoIcons` added to `temporarilyFree` |
