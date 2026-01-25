//
//  RecorderManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//

import AVFoundation
import CoreLocation
import Foundation
import Observation

// MARK: - Recording State

enum RecordingState: Equatable {
    case idle
    case recording
    case paused

    var isActive: Bool {
        self != .idle
    }
}

@MainActor
@Observable
final class RecorderManager: NSObject {
    // MARK: - Observable State

    var recordingState: RecordingState = .idle
    var currentDuration: TimeInterval = 0
    var liveMeterSamples: [Float] = []
    var qualityPreset: RecordingQualityPreset = .high

    // Reference to app settings (set by AppState)
    var appSettings: AppSettings = .default

    /// Duration accumulated before current recording segment (for pause/resume)
    private var accumulatedDuration: TimeInterval = 0
    /// Start time of current recording segment
    private var segmentStartTime: Date?
    /// Recording start date (for Live Activity timer)
    private var recordingStartDate: Date?
    /// Current recording ID (for Live Activity)
    private var currentRecordingId: String?

    // Convenience computed properties
    var isRecording: Bool { recordingState == .recording }
    var isPaused: Bool { recordingState == .paused }
    var isActive: Bool { recordingState.isActive }

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentFileURL: URL?
    private var wasRecordingBeforeInterruption = false

    // Crash recovery: key for UserDefaults
    private let inProgressRecordingKey = "inProgressRecordingPath"

    private let maxLiveSamples = 60

    // Location tracking
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?
    private var currentLocationLabel: String = ""

    // Callback for when recording should be stopped and saved (from Live Activity)
    var onStopAndSaveRequested: (() -> Void)?

    override init() {
        super.init()
        setupInterruptionHandling()
        setupLocationManager()
        setupIntentNotificationHandling()
    }

    // MARK: - Intent Notification Handling

    private func setupIntentNotificationHandling() {
        // Handle stop recording request from Live Activity
        NotificationCenter.default.addObserver(
            forName: .stopRecordingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onStopAndSaveRequested?()
            }
        }

        // Handle pause request from Live Activity
        NotificationCenter.default.addObserver(
            forName: .pauseRecordingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.pauseRecording()
            }
        }

        // Handle resume request from Live Activity
        NotificationCenter.default.addObserver(
            forName: .resumeRecordingRequested,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.resumeRecording()
            }
        }
    }

    /// Check and consume pending stop recording request (from Live Activity intent when app was backgrounded)
    func consumePendingStopRequest() -> Bool {
        let pending = UserDefaults.standard.bool(forKey: StopRecordingIntent.pendingStopKey)
        if pending {
            UserDefaults.standard.set(false, forKey: StopRecordingIntent.pendingStopKey)
            return true
        }
        return false
    }

    // MARK: - Location Setup

    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    private func requestLocationIfNeeded() {
        let status = locationManager.authorizationStatus

        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        default:
            // Permission denied or restricted
            currentLocation = nil
            currentLocationLabel = ""
        }
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        AudioSessionManager.shared.onInterruptionBegan = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.recordingState == .recording else { return }
                self.wasRecordingBeforeInterruption = true
                self.pauseRecording()
            }
        }

        AudioSessionManager.shared.onInterruptionEnded = { [weak self] shouldResume in
            Task { @MainActor in
                guard let self = self, self.wasRecordingBeforeInterruption else { return }
                self.wasRecordingBeforeInterruption = false
                if shouldResume {
                    self.resumeRecording()
                }
            }
        }

        AudioSessionManager.shared.onRouteChange = { [weak self] in
            Task { @MainActor in
                // Route changed - keep recording stable if possible
                // The recording will continue with whatever input is available
                self?.audioRecorder?.updateMeters()
            }
        }

        // Handle rare media services reset (system audio crash recovery)
        // Safely finalize any in-progress recording to prevent data loss
        AudioSessionManager.shared.onMediaServicesReset = { [weak self] in
            Task { @MainActor in
                guard let self = self, self.recordingState.isActive else { return }
                // Stop recording immediately - audio system is being rebuilt
                // This saves whatever was recorded up to this point
                _ = self.stopRecording()
            }
        }
    }

    // MARK: - Recording Control

    func startRecording() {
        guard recordingState == .idle else { return }

        do {
            try AudioSessionManager.shared.configureForRecording(
                quality: qualityPreset,
                settings: appSettings
            )
        } catch {
            print("Failed to set up audio session: \(error)")
            return
        }

        // Request location at start of recording
        requestLocationIfNeeded()

        let fileURL = generateFileURL(for: qualityPreset)
        currentFileURL = fileURL

        let settings = recordingSettings(for: qualityPreset)

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()
            recordingState = .recording
            let startDate = Date()
            segmentStartTime = startDate
            recordingStartDate = startDate
            accumulatedDuration = 0
            currentDuration = 0
            liveMeterSamples = []
            startTimer()

            // Track in-progress recording for crash recovery
            markRecordingInProgress(fileURL)

            // Start Live Activity
            currentRecordingId = UUID().uuidString
            RecordingLiveActivityManager.shared.startActivity(
                recordingId: currentRecordingId!,
                startDate: startDate
            )
        } catch {
            print("Failed to start recording: \(error)")
        }
    }

    /// Stop recording and return raw data for saving
    func stopRecording() -> RawRecordingData? {
        guard recordingState.isActive, let recorder = audioRecorder, let fileURL = currentFileURL else {
            print("⚠️ [RecorderManager] stopRecording called but no active recording")
            return nil
        }

        print("🎙️ [RecorderManager] Stopping recording: \(fileURL.lastPathComponent)")

        // Update duration one final time if recording (not paused)
        if recordingState == .recording, let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }

        // Stop the recorder - this finalizes the file
        recorder.stop()
        stopTimer()

        // CRITICAL: Verify the file was written successfully
        // AVAudioRecorder.stop() is synchronous but file system may lag
        let fileManager = FileManager.default
        var fileVerified = false
        var retryCount = 0
        let maxRetries = 10

        while !fileVerified && retryCount < maxRetries {
            if fileManager.fileExists(atPath: fileURL.path) {
                do {
                    let attrs = try fileManager.attributesOfItem(atPath: fileURL.path)
                    if let size = attrs[.size] as? Int64, size > 100 {
                        fileVerified = true
                        print("✅ [RecorderManager] File verified: \(size) bytes after \(retryCount) retries")
                    }
                } catch {
                    print("⚠️ [RecorderManager] Error checking file attributes: \(error.localizedDescription)")
                }
            }

            if !fileVerified {
                retryCount += 1
                // Small delay to let file system catch up
                Thread.sleep(forTimeInterval: 0.05)
            }
        }

        if !fileVerified {
            print("❌ [RecorderManager] File verification failed after \(maxRetries) retries")
            AudioDebug.logFileInfo(url: fileURL, context: "RecorderManager.stopRecording - verification failed")
        }

        let duration = accumulatedDuration
        let createdAt = Date()

        // Capture location data
        let latitude = currentLocation?.coordinate.latitude
        let longitude = currentLocation?.coordinate.longitude
        let locationLabel = currentLocationLabel

        // End Live Activity
        RecordingLiveActivityManager.shared.endActivity()

        resetState()
        clearInProgressRecording()

        // Log final file info for debugging
        AudioDebug.logFileInfo(url: fileURL, context: "RecorderManager.stopRecording - final")

        return RawRecordingData(
            fileURL: fileURL,
            createdAt: createdAt,
            duration: duration,
            latitude: latitude,
            longitude: longitude,
            locationLabel: locationLabel
        )
    }

    /// Pause recording safely - flushes audio buffer to prevent data loss
    func pauseRecording() {
        guard recordingState == .recording, let recorder = audioRecorder else { return }

        // Accumulate duration from this segment
        if let startTime = segmentStartTime {
            accumulatedDuration += Date().timeIntervalSince(startTime)
        }
        segmentStartTime = nil

        // Pause the recorder - this flushes the audio buffer to disk
        recorder.pause()
        stopTimer()
        recordingState = .paused

        // Update Live Activity to show paused state
        RecordingLiveActivityManager.shared.updateActivity(
            isRecording: false,
            pausedDuration: accumulatedDuration
        )
    }

    /// Resume recording after pause
    func resumeRecording() {
        guard recordingState == .paused, let recorder = audioRecorder else { return }

        recorder.record()
        segmentStartTime = Date()
        recordingState = .recording
        startTimer()

        // Update Live Activity to show recording state
        RecordingLiveActivityManager.shared.updateActivity(
            isRecording: true,
            pausedDuration: nil
        )
    }

    /// Discard the current recording without saving
    func discardRecording() {
        guard recordingState.isActive, let fileURL = currentFileURL else { return }

        audioRecorder?.stop()
        stopTimer()

        // Delete the audio file
        try? FileManager.default.removeItem(at: fileURL)

        // End Live Activity
        RecordingLiveActivityManager.shared.endActivity()

        resetState()
        clearInProgressRecording()
    }

    /// Reset all recording state
    private func resetState() {
        recordingState = .idle
        currentDuration = 0
        accumulatedDuration = 0
        segmentStartTime = nil
        recordingStartDate = nil
        currentRecordingId = nil
        audioRecorder = nil
        currentFileURL = nil
        liveMeterSamples = []
        wasRecordingBeforeInterruption = false
        currentLocation = nil
        currentLocationLabel = ""
    }

    // MARK: - Crash Recovery

    private func markRecordingInProgress(_ fileURL: URL) {
        UserDefaults.standard.set(fileURL.path, forKey: inProgressRecordingKey)
    }

    private func clearInProgressRecording() {
        UserDefaults.standard.removeObject(forKey: inProgressRecordingKey)
    }

    /// Check for and recover any in-progress recording from a crash
    /// Returns the file URL if a recoverable recording exists
    func checkForRecoverableRecording() -> URL? {
        guard let path = UserDefaults.standard.string(forKey: inProgressRecordingKey) else {
            return nil
        }

        let fileURL = URL(fileURLWithPath: path)

        // Verify the file exists and has content
        guard FileManager.default.fileExists(atPath: path) else {
            clearInProgressRecording()
            return nil
        }

        // Check file has meaningful content (> 1KB)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int,
           size > 1024 {
            return fileURL
        }

        // File too small, likely corrupted
        try? FileManager.default.removeItem(at: fileURL)
        clearInProgressRecording()
        return nil
    }

    /// Clear the recoverable recording marker without recovering
    func dismissRecoverableRecording() {
        if let path = UserDefaults.standard.string(forKey: inProgressRecordingKey) {
            try? FileManager.default.removeItem(atPath: path)
        }
        clearInProgressRecording()
    }

    // MARK: - Quality Settings

    private func recordingSettings(for preset: RecordingQualityPreset) -> [String: Any] {
        // Use actual sample rate from audio session (may differ from requested)
        let effectiveSampleRate = AudioSessionManager.shared.actualSampleRate

        switch preset {
        case .standard:
            // AAC, 44.1kHz, ~128kbps
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: min(effectiveSampleRate, 44100),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 128000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]

        case .high:
            // AAC, 48kHz, ~256kbps
            return [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: min(effectiveSampleRate, 48000),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 256000,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]

        case .lossless:
            // Apple Lossless (ALAC), 48kHz
            // Falls back gracefully if ALAC encoding fails
            return [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: min(effectiveSampleRate, 48000),
                AVNumberOfChannelsKey: 1,
                AVEncoderBitDepthHintKey: 16,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]

        case .wav:
            // Linear PCM (WAV), 48kHz, 16-bit
            return [
                AVFormatIDKey: Int(kAudioFormatLinearPCM),
                AVSampleRateKey: min(effectiveSampleRate, 48000),
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false,
                AVEncoderAudioQualityKey: AVAudioQuality.max.rawValue
            ]
        }
    }

    // MARK: - Helpers

    private func generateFileURL(for preset: RecordingQualityPreset) -> URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let filename = "recording_\(formatter.string(from: Date())).\(preset.fileExtension)"
        return documentsPath.appendingPathComponent(filename)
    }

    /// Legacy method for backwards compatibility
    private func generateFileURL() -> URL {
        generateFileURL(for: qualityPreset)
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.recordingState == .recording else { return }

                // Calculate total duration: accumulated + current segment
                if let startTime = self.segmentStartTime {
                    self.currentDuration = self.accumulatedDuration + Date().timeIntervalSince(startTime)
                }
                self.updateMeterSamples()
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func updateMeterSamples() {
        guard let recorder = audioRecorder, recordingState == .recording else { return }

        recorder.updateMeters()

        // Get average power in dB (typically -160 to 0)
        let dB = recorder.averagePower(forChannel: 0)

        // Convert dB to normalized value (0...1)
        // dB ranges from about -60 (silence) to 0 (max)
        // We'll use -50 as practical minimum for better visual range
        let minDB: Float = -50
        let maxDB: Float = 0

        let clampedDB = max(minDB, min(maxDB, dB))
        let normalized = (clampedDB - minDB) / (maxDB - minDB)

        // Add to rolling buffer
        liveMeterSamples.append(normalized)

        // Keep only the most recent samples
        if liveMeterSamples.count > maxLiveSamples {
            liveMeterSamples.removeFirst()
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension RecorderManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }

        Task { @MainActor in
            self.currentLocation = location

            // Reverse geocode to get a label
            let geocoder = CLGeocoder()
            do {
                let placemarks = try await geocoder.reverseGeocodeLocation(location)
                if let placemark = placemarks.first {
                    // Build a location label from placemark
                    var labelParts: [String] = []
                    if let name = placemark.name {
                        labelParts.append(name)
                    }
                    if let locality = placemark.locality {
                        labelParts.append(locality)
                    }
                    self.currentLocationLabel = labelParts.joined(separator: ", ")
                }
            } catch {
                // Use coordinates as fallback label
                self.currentLocationLabel = String(format: "%.4f, %.4f", location.coordinate.latitude, location.coordinate.longitude)
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let status = manager.authorizationStatus
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                if self.recordingState.isActive {
                    manager.requestLocation()
                }
            }
        }
    }
}
