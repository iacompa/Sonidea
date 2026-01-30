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
- Central `AppState` class (@Observable) as single source of truth
- Key managers: `RecorderManager`, `PlaybackEngine`, `OverdubEngine`, `AudioSessionManager`, `SharedAlbumManager`, `iCloudSyncManager`, `CloudKitSyncEngine`, `SupportManager`, `ProofManager`
- Watch managers: `WatchAppState`, `WatchRecorderManager`, `WatchPlaybackManager`
- Connectivity: `PhoneConnectivityManager` (iOS), `WatchConnectivityService` (watchOS)
- Data persistence: UserDefaults (settings/state), file system (audio), CloudKit (shared albums)
- All models are `Codable` structs

## Key Features
- Recording with live waveform, gain control (-6 to +6dB), limiter, pause/resume
- Multi-track overdub (base track + up to 3 layers)
- Waveform editing (trim, split) with zoom/pan
- 4-band parametric EQ per recording
- Shared Albums via CloudKit (up to 5 participants, role-based permissions)
- iCloud sync across devices
- Auto-icon classification via SoundAnalysis
- Projects & versioning (V1, V2, V3 with best-take marking)
- Albums, Tags, and smart filtering
- Map view of GPS-tagged recordings
- Live Activity / Dynamic Island for active recordings
- Skip silence detection
- Tamper-evident proof receipts (SHA-256 + CloudKit timestamps)
- Export to WAV/ZIP with manifests
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
Edit mode, shared albums, tags, iCloud sync, auto-icons, overdub, projects & versioning, watch auto-sync

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
Models/        RecordingItem, Album, Tag, Project, Marker, TimelineItem, OverdubGroup, EditHistory, ProofModels, RecordingActivityAttributes
Views/         ContentView, RecordingsListView, RecordingGridView, RecordingDetailView, CalendarView, JournalView, MapView, ProjectDetailView, OverdubSessionView, TagManagerView, TipJarView, QuickHelpSheet, ShareSheet, SharedAlbumViews, iPadAdaptiveLayout
Views/Waveform/ WaveformView, WaveformSampler, EditableWaveformView, ZoomableWaveformEditor, ProWaveformEditor, AudioWaveformExtractor, EQGraphView
Audio/         RecorderManager, PlaybackEngine, PlaybackManager, AudioSessionManager, AudioEditor, AudioExporter, OverdubEngine, SkipSilenceManager, AudioDebug, SilenceDebugStrip
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
- Recording quality options: Standard (AAC 128kbps), High (AAC 256kbps), Lossless (ALAC), WAV (PCM 16-bit)
- All audio at 44.1kHz (standard) or 48kHz (high/lossless/wav)
- Watch recordings: AAC mono 44.1kHz/128kbps (.m4a)
- Crash recovery saves in-progress recording state to UserDefaults
- Offline support with retry queues for CloudKit operations
- iPad uses `sizeClass == .regular` checks for adaptive layout (wider top padding, fullScreenCover for sheets)
- Watch uses PBXFileSystemSynchronizedRootGroup — Xcode auto-syncs with filesystem
- Watch app icon matches iOS app icon (Sonidea waveform logo)
