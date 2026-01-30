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

### Current Assessment (vs Apple Voice Memos)

**Feature set: 10/10.** Sonidea is a full-featured mobile DAW disguised as a voice memo app. Multi-track overdub with per-channel mixer, offline bounce, metronome with count-in, real-time monitoring effects (EQ + compressor), fade/normalize/noise gate editing, multi-format export (WAV/M4A/ALAC), shared albums via CloudKit, project versioning, GPS tagging, auto-icon classification, tamper-proof receipts, 7 themes, Watch companion.

**Code health: 8/10, up from 7.5/10.**
- All trash operations extracted to repository (zero inline overdub cleanup in AppState)
- SupportManager tested
- ~115 tests across 23 test files

**Remaining work:**
- Build and run all tests in Xcode (Cmd+B, Cmd+U) — new features have not been compiled yet
- Shared album methods (~400 lines) still live directly in AppState due to CloudKit async coupling
- No integration tests or UI tests
- `setAlbum(_:for:)` behavior change from previous session should be verified
