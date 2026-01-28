//
//  SupportManager.swift
//  Sonidea
//
//  Manages subscriptions, trial status, and paywall logic.
//  Provides 30-day free trial, then requires monthly/annual/lifetime subscription.
//

import Foundation
import StoreKit
import Observation

// MARK: - Subscription Plan

enum SubscriptionPlan: String, CaseIterable {
    case monthly = "com.iacompa.sonidea.sub.monthly"
    case annual = "com.iacompa.sonidea.sub.annual"
    case lifetime = "com.iacompa.sonidea.lifetime"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        case .lifetime: return "Lifetime"
        }
    }

    var description: String {
        switch self {
        case .monthly: return "$1.99/month"
        case .annual: return "$19.99/year"
        case .lifetime: return "$99.99 one-time"
        }
    }

    var tagline: String {
        switch self {
        case .monthly: return "Flexible"
        case .annual: return "Best Value"
        case .lifetime: return "Pay Once"
        }
    }

    static var allProductIDs: Set<String> {
        Set(allCases.map(\.rawValue))
    }
}

// MARK: - Subscription Status

enum SubscriptionStatus {
    case trial
    case subscribed(SubscriptionPlan)
    case expired
}

// MARK: - Roadmap Item

struct RoadmapItem: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let isNew: Bool

    init(title: String, icon: String = "circle", isNew: Bool = false) {
        self.title = title
        self.icon = icon
        self.isNew = isNew
    }
}

let roadmapItems: [RoadmapItem] = [
    RoadmapItem(title: "AI-powered track analysis & auto-tagging", icon: "sparkles", isNew: true),
    RoadmapItem(title: "VST3/AU Plugin for DAW imports", icon: "puzzlepiece.extension"),
    RoadmapItem(title: "Android release", icon: "iphone.and.arrow.forward"),
    RoadmapItem(title: "More themes", icon: "paintpalette"),
    RoadmapItem(title: "Advanced waveform editing", icon: "waveform.path.ecg"),
]

// MARK: - Subscription Manager

@MainActor
@Observable
final class SupportManager {

    // MARK: - Published State

    var isPurchasing = false
    var purchaseError: String?
    var products: [Product] = []
    var isLoadingProducts = true

    // MARK: - Trial

    var trialStartDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.trialStartDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.trialStartDate) }
    }

    var isTrialActive: Bool {
        guard let start = trialStartDate else { return false }
        return Date().timeIntervalSince(start) < 30 * 24 * 60 * 60
    }

    var trialDaysRemaining: Int {
        guard let start = trialStartDate else { return 0 }
        let elapsed = Date().timeIntervalSince(start)
        let remaining = (30 * 24 * 60 * 60) - elapsed
        return max(0, Int(ceil(remaining / (24 * 60 * 60))))
    }

    // MARK: - Subscription State

    var isSubscribed: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isSubscribed) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isSubscribed) }
    }

    var currentPlanRawValue: String? {
        get { UserDefaults.standard.string(forKey: Keys.currentPlan) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.currentPlan) }
    }

    var currentPlan: SubscriptionPlan? {
        guard let raw = currentPlanRawValue else { return nil }
        return SubscriptionPlan(rawValue: raw)
    }

    var isFullAccessUnlocked: Bool {
        isTrialActive || isSubscribed
    }

    var subscriptionStatus: SubscriptionStatus {
        if isSubscribed, let plan = currentPlan {
            return .subscribed(plan)
        } else if isTrialActive {
            return .trial
        } else {
            return .expired
        }
    }

    // Legacy compatibility
    var hasTippedBefore: Bool { isSubscribed }

    // Unused but kept for compatibility - no-op
    var shouldShowAskPromptSheet = false
    var shouldShowThankYouToast = false

    // MARK: - Keys

    private enum Keys {
        static let trialStartDate = "subscription.trialStartDate"
        static let isSubscribed = "subscription.isSubscribed"
        static let currentPlan = "subscription.currentPlan"
    }

    // MARK: - Transaction listener

    private var transactionListener: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        // Start trial on first launch
        if trialStartDate == nil {
            trialStartDate = Date()
        }

        // Listen for transaction updates
        transactionListener = Task {
            for await result in Transaction.updates {
                if case .verified(let transaction) = result {
                    await handleVerifiedTransaction(transaction)
                    await transaction.finish()
                }
            }
        }

        Task {
            await loadProducts()
            await checkCurrentEntitlements()
        }
    }

    nonisolated deinit {
    }

    // MARK: - StoreKit

    func loadProducts() async {
        isLoadingProducts = true
        do {
            products = try await Product.products(for: SubscriptionPlan.allProductIDs)
            isLoadingProducts = false
        } catch {
            print("Failed to load products: \(error)")
            isLoadingProducts = false
        }
    }

    func checkCurrentEntitlements() async {
        var foundActive = false

        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                if transaction.revocationDate == nil {
                    foundActive = true
                    isSubscribed = true
                    currentPlanRawValue = transaction.productID
                }
            }
        }

        if !foundActive {
            // Check if lifetime was purchased (non-consumable persists differently)
            // Keep subscribed if previously verified and no revocation
            if currentPlan != .lifetime {
                isSubscribed = false
                currentPlanRawValue = nil
            }
        }
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if transaction.revocationDate != nil {
            // Subscription revoked
            if currentPlanRawValue == transaction.productID {
                isSubscribed = false
                currentPlanRawValue = nil
            }
        } else {
            isSubscribed = true
            currentPlanRawValue = transaction.productID
        }
    }

    func purchase(plan: SubscriptionPlan) async {
        guard let product = products.first(where: { $0.id == plan.rawValue }) else {
            purchaseError = "Products are still loading. Try again in a moment."
            return
        }

        isPurchasing = true
        purchaseError = nil

        do {
            let result = try await product.purchase()

            switch result {
            case .success(let verification):
                switch verification {
                case .verified(let transaction):
                    isSubscribed = true
                    currentPlanRawValue = plan.rawValue
                    await transaction.finish()
                case .unverified(_, let error):
                    purchaseError = "Purchase verification failed: \(error.localizedDescription)"
                }
            case .userCancelled:
                break
            case .pending:
                purchaseError = "Purchase pending approval."
            @unknown default:
                purchaseError = "Unknown purchase result."
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isPurchasing = false
    }

    func restorePurchases() async {
        isPurchasing = true
        purchaseError = nil

        do {
            try await AppStore.sync()
            await checkCurrentEntitlements()
        } catch {
            purchaseError = "Could not restore purchases: \(error.localizedDescription)"
        }

        isPurchasing = false
    }

    func priceForPlan(_ plan: SubscriptionPlan) -> String? {
        products.first { $0.id == plan.rawValue }?.displayPrice
    }

    // MARK: - Compatibility stubs (called by AppState)

    func registerActiveDayIfNeeded() {}
    func setRecordingState(_ isRecording: Bool) {}
    func onRecordingSaved(totalRecordings: Int) {}
    func onExportSuccess(totalRecordings: Int) {}
    func onTranscriptionSuccess(totalRecordings: Int) {}
}
