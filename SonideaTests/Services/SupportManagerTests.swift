//
//  SupportManagerTests.swift
//  SonideaTests
//
//  Tests for SupportManager: subscription plans, status logic, debug overrides.
//

import Testing
import Foundation
@testable import Sonidea

struct SupportManagerTests {

    // MARK: - SubscriptionPlan

    @Test @MainActor func planRawValues() {
        #expect(SubscriptionPlan.monthly.rawValue == "0144030")
        #expect(SubscriptionPlan.annual.rawValue == "01440365")
    }

    @Test @MainActor func planDisplayNames() {
        #expect(SubscriptionPlan.monthly.displayName == "Monthly")
        #expect(SubscriptionPlan.annual.displayName == "Annual")
    }

    @Test @MainActor func planDescriptions() {
        #expect(SubscriptionPlan.monthly.description == "$3.99/month")
        #expect(SubscriptionPlan.annual.description == "$29.99/year")
    }

    @Test @MainActor func planTaglinesNotEmpty() {
        for plan in SubscriptionPlan.allCases {
            #expect(!plan.tagline.isEmpty)
        }
    }

    @Test @MainActor func allProductIDs() {
        let ids = SubscriptionPlan.allProductIDs
        #expect(ids.count == 2)
        #expect(ids.contains("0144030"))
        #expect(ids.contains("01440365"))
    }

    // MARK: - SubscriptionStatus

    @Test @MainActor func subscriptionStatusSubscribed() {
        let status = SubscriptionStatus.subscribed(.monthly)
        if case .subscribed(let plan) = status {
            #expect(plan == .monthly)
        } else {
            Issue.record("Expected subscribed status")
        }
    }

    @Test @MainActor func subscriptionStatusExpired() {
        let status = SubscriptionStatus.expired
        if case .expired = status {
            // pass
        } else {
            Issue.record("Expected expired status")
        }
    }

    @Test @MainActor func subscriptionStatusTrial() {
        let status = SubscriptionStatus.trial
        if case .trial = status {
            // pass
        } else {
            Issue.record("Expected trial status")
        }
    }

    // MARK: - State Logic (via UserDefaults)

    @Test @MainActor func canUseProFeaturesWhenSubscribed() {
        let manager = SupportManager()
        let savedIsSubscribed = manager.isSubscribed
        let savedPlan = manager.currentPlanRawValue
        defer {
            manager.isSubscribed = savedIsSubscribed
            manager.currentPlanRawValue = savedPlan
        }

        manager.isSubscribed = true
        manager.currentPlanRawValue = SubscriptionPlan.monthly.rawValue
        #expect(manager.canUseProFeatures)
        #expect(manager.isFullAccessUnlocked)
    }

    @Test @MainActor func cannotUseProFeaturesWhenNotSubscribed() {
        let manager = SupportManager()
        let savedIsSubscribed = manager.isSubscribed
        let savedPlan = manager.currentPlanRawValue
        defer {
            manager.isSubscribed = savedIsSubscribed
            manager.currentPlanRawValue = savedPlan
        }

        manager.isSubscribed = false
        manager.currentPlanRawValue = nil
        #expect(!manager.canUseProFeatures)
    }

    @Test @MainActor func subscriptionStatusReflectsState() {
        let manager = SupportManager()
        let savedIsSubscribed = manager.isSubscribed
        let savedPlan = manager.currentPlanRawValue
        defer {
            manager.isSubscribed = savedIsSubscribed
            manager.currentPlanRawValue = savedPlan
        }

        manager.isSubscribed = true
        manager.currentPlanRawValue = SubscriptionPlan.annual.rawValue
        if case .subscribed(.annual) = manager.subscriptionStatus {
            // pass
        } else {
            Issue.record("Expected annual subscription status")
        }
    }

    @Test @MainActor func currentPlanReturnsNilWhenNoSubscription() {
        let manager = SupportManager()
        let savedPlan = manager.currentPlanRawValue
        defer { manager.currentPlanRawValue = savedPlan }

        manager.currentPlanRawValue = nil
        #expect(manager.currentPlan == nil)
    }

    @Test @MainActor func currentPlanParsesRawValue() {
        let manager = SupportManager()
        let savedPlan = manager.currentPlanRawValue
        defer { manager.currentPlanRawValue = savedPlan }

        manager.currentPlanRawValue = "0144030"
        #expect(manager.currentPlan == .monthly)

        manager.currentPlanRawValue = "01440365"
        #expect(manager.currentPlan == .annual)

        manager.currentPlanRawValue = "invalid"
        #expect(manager.currentPlan == nil)
    }

    @Test @MainActor func expiredStatusWhenNotSubscribed() {
        let manager = SupportManager()
        let savedIsSubscribed = manager.isSubscribed
        let savedPlan = manager.currentPlanRawValue
        defer {
            manager.isSubscribed = savedIsSubscribed
            manager.currentPlanRawValue = savedPlan
        }

        manager.isSubscribed = false
        manager.currentPlanRawValue = nil
        if case .expired = manager.subscriptionStatus {
            // pass
        } else {
            Issue.record("Expected expired status when not subscribed")
        }
    }

    // MARK: - Debug Override

    #if DEBUG
    @Test @MainActor func debugOverrideForcesPro() {
        let manager = SupportManager()
        let savedIsSubscribed = manager.isSubscribed
        defer {
            manager.debugProOverride = nil
            manager.isSubscribed = savedIsSubscribed
        }

        manager.isSubscribed = false
        manager.debugProOverride = true
        #expect(manager.canUseProFeatures)
    }

    @Test @MainActor func debugOverrideForceFree() {
        let manager = SupportManager()
        let savedIsSubscribed = manager.isSubscribed
        defer {
            manager.debugProOverride = nil
            manager.isSubscribed = savedIsSubscribed
        }

        manager.isSubscribed = true
        manager.debugProOverride = false
        #expect(!manager.canUseProFeatures)
    }
    #endif

    // MARK: - Compatibility Stubs

    @Test @MainActor func compatibilityStubsDoNotCrash() {
        let manager = SupportManager()
        manager.registerActiveDayIfNeeded()
        manager.setRecordingState(true)
        manager.setRecordingState(false)
        manager.onRecordingSaved(totalRecordings: 5)
        manager.onExportSuccess(totalRecordings: 5)
        manager.onTranscriptionSuccess(totalRecordings: 5)
        // No crash = pass
    }

    // MARK: - Roadmap Items

    @Test @MainActor func roadmapItemsNotEmpty() {
        #expect(!roadmapItems.isEmpty)
        for item in roadmapItems {
            #expect(!item.title.isEmpty)
            #expect(!item.icon.isEmpty)
        }
    }
}
