//
//  TrialNudgeManagerTests.swift
//  SonideaTests
//
//  Tests for TrialNudge enum and TrialNudgeManager logic.
//

import Testing
import Foundation
@testable import Sonidea

struct TrialNudgeManagerTests {

    // MARK: - TrialNudge Properties

    @Test func day1NudgeProperties() {
        let nudge = TrialNudge.day1Welcome
        #expect(nudge.dayOffset == 0)
        #expect(nudge.dayRange == 0...1)
        #expect(!nudge.title.isEmpty)
        #expect(!nudge.ctaLabel.isEmpty)
        #expect(nudge.iconName == "star.fill")
    }

    @Test func day3NudgeProperties() {
        let nudge = TrialNudge.day3Features
        #expect(nudge.dayOffset == 2)
        #expect(nudge.dayRange == 2...3)
    }

    @Test func day5NudgeProperties() {
        let nudge = TrialNudge.day5Stats
        #expect(nudge.dayOffset == 4)
        #expect(nudge.dayRange == 4...5)
    }

    @Test func day6NudgeProperties() {
        let nudge = TrialNudge.day6Ending
        #expect(nudge.dayOffset == 5)
        #expect(nudge.dayRange == 5...6)
        #expect(nudge.secondaryCTALabel != nil)
        #expect(nudge.secondaryCTAAction == .createSharedAlbum)
    }

    @Test func nudgeMessageIncludesRecordingCount() {
        let msg = TrialNudge.day5Stats.message(recordingCount: 5)
        #expect(msg.contains("5"))
    }

    @Test func nudgeMessageSingularRecording() {
        let msg = TrialNudge.day5Stats.message(recordingCount: 1)
        #expect(msg.contains("1 memo"))
        #expect(!msg.contains("memos"))
    }

    // MARK: - No Nudge Without Trial Date

    @Test @MainActor func noNudgeWithoutTrialDate() {
        let manager = TrialNudgeManager()
        let nudge = manager.nextNudgeToShow(trialStartDate: nil)
        #expect(nudge == nil)
    }

    // MARK: - canShowNudge Conditions

    @Test @MainActor func canShowNudgeWhenIdle() {
        let manager = TrialNudgeManager()
        #expect(manager.canShowNudge(isRecording: false, isPlayingBack: false))
    }

    @Test @MainActor func cannotShowNudgeWhileRecording() {
        let manager = TrialNudgeManager()
        #expect(!manager.canShowNudge(isRecording: true, isPlayingBack: false))
    }

    @Test @MainActor func cannotShowNudgeWhilePlaying() {
        let manager = TrialNudgeManager()
        #expect(!manager.canShowNudge(isRecording: false, isPlayingBack: true))
    }

    @Test @MainActor func cannotShowNudgeWhileRecordingAndPlaying() {
        let manager = TrialNudgeManager()
        #expect(!manager.canShowNudge(isRecording: true, isPlayingBack: true))
    }

    // MARK: - CTA Actions

    @Test func day1CTAIsOpenGuide() {
        #expect(TrialNudge.day1Welcome.ctaAction == .openGuide)
    }

    @Test func day3CTAIsOpenOverdub() {
        #expect(TrialNudge.day3Features.ctaAction == .openOverdub)
    }

    @Test func day5CTAIsDismiss() {
        #expect(TrialNudge.day5Stats.ctaAction == .dismiss)
    }

    @Test func day6CTAIsOpenPaywall() {
        #expect(TrialNudge.day6Ending.ctaAction == .openPaywall)
    }

    // MARK: - All Cases

    @Test func allCasesHaveFourNudges() {
        #expect(TrialNudge.allCases.count == 4)
    }

    // MARK: - Only Day6 Has Secondary CTA

    @Test func onlyDay6HasSecondaryCTA() {
        for nudge in TrialNudge.allCases {
            if nudge == .day6Ending {
                #expect(nudge.secondaryCTALabel != nil)
            } else {
                #expect(nudge.secondaryCTALabel == nil)
            }
        }
    }
}
