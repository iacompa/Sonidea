//
//  WatchPlaybackManager.swift
//  SonideaWatch Watch App
//
//  AVAudioPlayer wrapper for watchOS playback with ±10s skip.
//

import AVFoundation
import Foundation

@MainActor
@Observable
class WatchPlaybackManager: NSObject, AVAudioPlayerDelegate {

    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var wasPlayingBeforeInterruption = false
    private var interruptionObserver: NSObjectProtocol?
    private var routeChangeObserver: NSObjectProtocol?

    // MARK: - Load

    func load(url: URL) {
        stop()
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            player = try AVAudioPlayer(contentsOf: url)
            player?.delegate = self
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0

            setupInterruptionHandling()
            setupRouteChangeHandling()
        } catch {
            #if DEBUG
            print("WatchPlayback: Failed to load: \(error)")
            #endif
        }
    }

    // MARK: - Transport

    func play() {
        player?.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        wasPlayingBeforeInterruption = false
        stopTimer()
        removeObservers()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Skip

    func skip(seconds: TimeInterval) {
        guard let player else { return }
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.currentTime = newTime
        currentTime = newTime
    }

    // MARK: - Seek

    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clampedTime = max(0, min(player.duration, time))
        player.currentTime = clampedTime
        currentTime = clampedTime
    }

    // MARK: - Interruption Handling

    private func setupInterruptionHandling() {
        guard interruptionObserver == nil else { return }
        interruptionObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleInterruption(notification)
            }
        }
    }

    private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            if isPlaying {
                wasPlayingBeforeInterruption = true
                pause()
            }
        case .ended:
            if wasPlayingBeforeInterruption {
                wasPlayingBeforeInterruption = false
                if let optionsValue = userInfo[AVAudioSessionInterruptionOptionKey] as? UInt {
                    let options = AVAudioSession.InterruptionOptions(rawValue: optionsValue)
                    if options.contains(.shouldResume) {
                        play()
                    }
                } else {
                    play()
                }
            }
        @unknown default:
            break
        }
    }

    // MARK: - Route Change Handling

    private func setupRouteChangeHandling() {
        guard routeChangeObserver == nil else { return }
        routeChangeObserver = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleRouteChange(notification)
            }
        }
    }

    private func handleRouteChange(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let reasonValue = userInfo[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else {
            return
        }

        switch reason {
        case .oldDeviceUnavailable:
            if isPlaying {
                pause()
            }
        default:
            break
        }
    }

    // MARK: - Observer Cleanup

    private func removeObservers() {
        if let observer = interruptionObserver {
            NotificationCenter.default.removeObserver(observer)
            interruptionObserver = nil
        }
        if let observer = routeChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            routeChangeObserver = nil
        }
    }

    // MARK: - Timer

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self, let player = self.player else { return }
            self.currentTime = player.currentTime
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        isPlaying = false
        currentTime = 0
        stopTimer()
        removeObservers()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
