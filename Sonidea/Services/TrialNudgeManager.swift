//
//  TrialNudgeManager.swift
//  Sonidea
//
//  Manages in-app nudge messaging during the 14-day trial period (annual plan intro offer).
//

import Foundation
import Observation
import SwiftUI

// MARK: - Trial Nudge CTA Action

enum TrialNudgeCTA {
    case openGuide
    case openOverdub
    case openExport
    case viewStats
    case createSharedAlbum
    case openPaywall
    case dismiss
}

// MARK: - Trial Nudge

enum TrialNudge: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case day1Welcome
    case day3Features
    case day5Stats
    case day6Ending

    var dayOffset: Int {
        switch self {
        case .day1Welcome: return 0
        case .day3Features: return 2
        case .day5Stats: return 4
        case .day6Ending: return 5
        }
    }

    /// Range of trial days (0-indexed) during which this nudge can appear
    var dayRange: ClosedRange<Int> {
        switch self {
        case .day1Welcome: return 0...1
        case .day3Features: return 2...3
        case .day5Stats: return 4...5
        case .day6Ending: return 5...6
        }
    }

    var title: String {
        switch self {
        case .day1Welcome: return "Welcome to Sonidea Pro!"
        case .day3Features: return "Try Overdub & Export"
        case .day5Stats: return "You're making progress!"
        case .day6Ending: return "Trial ends tomorrow"
        }
    }

    func message(recordingCount: Int) -> String {
        switch self {
        case .day1Welcome:
            return "Your 14-day trial gives you full access to all features. Tap to see what you can do."
        case .day3Features:
            return "Layer recordings with overdub or export your work in any format."
        case .day5Stats:
            return "You've recorded \(recordingCount) memo\(recordingCount == 1 ? "" : "s") so far. Keep capturing your ideas."
        case .day6Ending:
            return "Subscribe to keep full access, or invite friends to a Shared Album."
        }
    }

    var ctaLabel: String {
        switch self {
        case .day1Welcome: return "Quick Start Guide"
        case .day3Features: return "Try Overdub"
        case .day5Stats: return "Keep Recording"
        case .day6Ending: return "Manage Subscription"
        }
    }

    var ctaAction: TrialNudgeCTA {
        switch self {
        case .day1Welcome: return .openGuide
        case .day3Features: return .openOverdub
        case .day5Stats: return .dismiss
        case .day6Ending: return .openPaywall
        }
    }

    var secondaryCTALabel: String? {
        switch self {
        case .day6Ending: return "Invite to Shared Album"
        default: return nil
        }
    }

    var secondaryCTAAction: TrialNudgeCTA? {
        switch self {
        case .day6Ending: return .createSharedAlbum
        default: return nil
        }
    }

    var iconName: String {
        switch self {
        case .day1Welcome: return "star.fill"
        case .day3Features: return "waveform.path.badge.plus"
        case .day5Stats: return "chart.bar.fill"
        case .day6Ending: return "clock.badge.exclamationmark"
        }
    }
}

// MARK: - Trial Nudge Manager

@MainActor
@Observable
final class TrialNudgeManager {

    // MARK: - Persisted State

    private let shownNudgeKeysKey = "trialNudge.shownKeys"
    private let lastNudgeShownDateKey = "trialNudge.lastShownDate"

    private var shownNudgeKeys: Set<String> {
        get {
            let array = UserDefaults.standard.stringArray(forKey: shownNudgeKeysKey) ?? []
            return Set(array)
        }
        set {
            UserDefaults.standard.set(Array(newValue), forKey: shownNudgeKeysKey)
        }
    }

    private var lastNudgeShownDate: Date? {
        get { UserDefaults.standard.object(forKey: lastNudgeShownDateKey) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: lastNudgeShownDateKey) }
    }

    // MARK: - Methods

    func nextNudgeToShow(trialStartDate: Date?, now: Date = Date()) -> TrialNudge? {
        guard let start = trialStartDate else { return nil }

        let trialDay = Calendar.current.dateComponents([.day], from: start, to: now).day ?? 0

        // Enforce max 1 nudge per day
        if let lastShown = lastNudgeShownDate,
           Calendar.current.isDate(lastShown, inSameDayAs: now) {
            return nil
        }

        // Find the first nudge matching current day that hasn't been shown
        for nudge in TrialNudge.allCases {
            if nudge.dayRange.contains(trialDay) && !shownNudgeKeys.contains(nudge.rawValue) {
                return nudge
            }
        }

        return nil
    }

    func markShown(_ nudge: TrialNudge) {
        var keys = shownNudgeKeys
        keys.insert(nudge.rawValue)
        shownNudgeKeys = keys
        lastNudgeShownDate = Date()
    }

    func canShowNudge(isRecording: Bool, isPlayingBack: Bool) -> Bool {
        !isRecording && !isPlayingBack
    }
}

// MARK: - Trial Nudge Sheet View

struct TrialNudgeSheet: View {
    let nudge: TrialNudge
    let recordingCount: Int
    let onCTA: (TrialNudgeCTA) -> Void
    let onDismiss: () -> Void

    @Environment(\.themePalette) private var palette

    var body: some View {
        VStack(spacing: 16) {
            // Icon
            Image(systemName: nudge.iconName)
                .font(.system(size: 36))
                .foregroundStyle(palette.accent)
                .padding(.top, 24)

            // Title
            Text(nudge.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(palette.textPrimary)

            // Message
            Text(nudge.message(recordingCount: recordingCount))
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 24)

            Spacer(minLength: 16)

            // Primary CTA
            Button {
                onCTA(nudge.ctaAction)
            } label: {
                Text(nudge.ctaLabel)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(palette.accent)
            .padding(.horizontal, 24)

            // Secondary CTA (day6Ending only)
            if let secondaryLabel = nudge.secondaryCTALabel,
               let secondaryAction = nudge.secondaryCTAAction {
                Button {
                    onCTA(secondaryAction)
                } label: {
                    Text(secondaryLabel)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.accent)
                }
            }

            // Dismiss
            Button {
                onDismiss()
            } label: {
                Text("Not now")
                    .font(.subheadline)
                    .foregroundStyle(palette.textTertiary)
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity)
        .background(palette.sheetBackground)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }
}
