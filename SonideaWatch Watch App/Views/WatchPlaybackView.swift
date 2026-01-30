//
//  WatchPlaybackView.swift
//  SonideaWatch Watch App
//
//  Playback view with ±10s skip, progress bar, and share.
//  Styled to match the iPhone app's aesthetic.
//

import SwiftUI

struct WatchPlaybackView: View {
    let recording: WatchRecordingItem
    @Environment(\.watchPalette) private var palette
    @State private var playback = WatchPlaybackManager()
    @State private var isScrubbing = false
    @State private var scrubTime: TimeInterval = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Title
                Text(recording.title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(palette.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                // Scrubbable progress bar
                GeometryReader { geo in
                    let barWidth = geo.size.width
                    let displayTime = isScrubbing ? scrubTime : playback.currentTime
                    let progress = playback.duration > 0 ? displayTime / playback.duration : 0
                    let fillWidth = barWidth * progress
                    let handleX = min(max(fillWidth, 6), barWidth - 6)

                    ZStack(alignment: .leading) {
                        // Track background
                        Capsule()
                            .fill(palette.surface)
                            .frame(height: 5)

                        // Filled portion
                        Capsule()
                            .fill(palette.accent)
                            .frame(width: fillWidth, height: 5)

                        // Scrub handle
                        Circle()
                            .fill(palette.accent)
                            .frame(width: isScrubbing ? 16 : 12, height: isScrubbing ? 16 : 12)
                            .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                            .position(x: handleX, y: geo.size.height / 2)
                            .animation(.easeOut(duration: 0.1), value: isScrubbing)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                if !isScrubbing { isScrubbing = true }
                                let fraction = max(0, min(1, value.location.x / barWidth))
                                scrubTime = fraction * playback.duration
                            }
                            .onEnded { value in
                                let fraction = max(0, min(1, value.location.x / barWidth))
                                let seekTo = fraction * playback.duration
                                playback.seek(to: seekTo)
                                isScrubbing = false
                            }
                    )
                }
                .frame(height: 20)
                .padding(.horizontal, 4)

                // Time labels
                HStack {
                    Text(formatTime(isScrubbing ? scrubTime : playback.currentTime))
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(palette.liveRecordingAccent)
                    Spacer()
                    let remaining = isScrubbing
                        ? max(0, playback.duration - scrubTime)
                        : max(0, playback.duration - playback.currentTime)
                    Text("-" + formatTime(remaining))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 4)

                // Transport controls
                HStack(spacing: 20) {
                    Button {
                        playback.skip(seconds: -10)
                    } label: {
                        Image(systemName: "gobackward.10")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(palette.accent)
                    }
                    .buttonStyle(.plain)

                    Button {
                        playback.togglePlayPause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(palette.accent)
                                .frame(width: 44, height: 44)
                            Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(palette.background)
                                .offset(x: playback.isPlaying ? 0 : 2)
                        }
                    }
                    .buttonStyle(.plain)

                    Button {
                        playback.skip(seconds: 10)
                    } label: {
                        Image(systemName: "goforward.10")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundColor(palette.accent)
                    }
                    .buttonStyle(.plain)
                }

                // Share button
                ShareLink(item: recording.fileURL) {
                    HStack(spacing: 4) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                        Text("Share")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(palette.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(palette.accent.opacity(0.15))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
            .padding(.horizontal, 4)
        }
        .background(palette.background.ignoresSafeArea())
        .onAppear {
            playback.load(url: recording.fileURL)
        }
        .onDisappear {
            playback.stop()
        }
    }

    // MARK: - Helpers

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
