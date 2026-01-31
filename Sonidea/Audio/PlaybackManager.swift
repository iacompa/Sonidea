//
//  PlaybackManager.swift
//  Sonidea
//
//  Created by Michael Ramos on 1/22/26.
//
//  NOTE: This file is UNUSED. The app uses PlaybackEngine instead.
//  Kept in the project to avoid Xcode project file issues.
//  Safe to remove in a future cleanup pass.
//

import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class PlaybackManager: NSObject {
    var isPlaying = false
    var currentTime: TimeInterval = 0
    var duration: TimeInterval = 0

    private var audioPlayer: AVAudioPlayer?
    private var timer: Timer?

    override init() {
        super.init()
    }

    func load(url: URL) {
        stop()
        do {
            try AudioSessionManager.shared.configureForPlayback()

            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.delegate = self
            audioPlayer?.prepareToPlay()
            duration = audioPlayer?.duration ?? 0
            currentTime = 0
        } catch {
            #if DEBUG
            print("Failed to load audio: \(error)")
            #endif
        }
    }

    func play() {
        guard let player = audioPlayer else { return }
        try? AudioSessionManager.shared.configureForPlayback()
        player.play()
        isPlaying = true
        startTimer()
    }

    func pause() {
        audioPlayer?.pause()
        isPlaying = false
        stopTimer()
    }

    func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        currentTime = 0
        duration = 0
        stopTimer()
        AudioSessionManager.shared.deactivatePlayback()
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func seek(to time: TimeInterval) {
        audioPlayer?.currentTime = time
        currentTime = time
    }

    private func startTimer() {
        // Use .common mode so timer continues during scroll tracking
        let newTimer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let player = self.audioPlayer else { return }
                self.currentTime = player.currentTime
            }
        }
        RunLoop.main.add(newTimer, forMode: .common)
        timer = newTimer
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

extension PlaybackManager: @preconcurrency AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopTimer()
            AudioSessionManager.shared.deactivatePlayback()
        }
    }
}
