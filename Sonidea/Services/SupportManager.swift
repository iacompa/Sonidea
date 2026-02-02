//
//  SupportManager.swift
//  Sonidea
//
//  Manages subscriptions, trial status, and paywall logic.
//  14-day free trial available with annual plan subscription (via App Store intro offer).
//

import Foundation
import StoreKit
import Observation
import UserNotifications

// MARK: - Subscription Plan

enum SubscriptionPlan: String, CaseIterable {
    case monthly = "0144030"
    case annual = "01440365"

    var displayName: String {
        switch self {
        case .monthly: return "Monthly"
        case .annual: return "Annual"
        }
    }

    var description: String {
        switch self {
        case .monthly: return "$3.99/month"
        case .annual: return "$29.99/year"
        }
    }

    var tagline: String {
        switch self {
        case .monthly: return "Less than a coffee ☕"
        case .annual: return "Best Value"
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
    RoadmapItem(title: "VST3/AU Plugin for DAW imports", icon: "puzzlepiece.extension"),
    RoadmapItem(title: "More themes", icon: "paintpalette"),
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
    var productsLoadFailed = false

    /// Callback invoked when Pro access is lost (trial expired or subscription cancelled)
    var onProAccessLost: (() -> Void)?

    #if DEBUG
    /// Debug override: nil = normal behavior, true = force pro, false = force free
    var debugProOverride: Bool? = nil
    #endif

    // MARK: - Subscription State
    // Note: Trials are handled by StoreKit via intro offers on the annual plan.
    // When user is in a trial, they appear as subscribed in StoreKit transactions.
    // StoreKit's isEligibleForIntroOffer prevents multiple trials automatically.

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
        isSubscribed
    }

    var canUseProFeatures: Bool {
        #if DEBUG
        if let override = debugProOverride { return override }
        #endif
        return isSubscribed
    }

    var subscriptionStatus: SubscriptionStatus {
        if isSubscribed {
            if isOnTrial {
                return .trial
            }
            if let plan = currentPlan {
                return .subscribed(plan)
            }
            return .trial // Subscribed but no plan = likely trial
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
        static let isSubscribed = "subscription.isSubscribed"
        static let currentPlan = "subscription.currentPlan"
        static let sharedAlbumWarningScheduled = "subscription.sharedAlbumWarningScheduled"
        static let sharedAlbumRemovalScheduled = "subscription.sharedAlbumRemovalScheduled"
        static let isOnTrial = "subscription.isOnTrial"
        static let trialStartDate = "subscription.trialStartDate"
        static let trialEndDate = "subscription.trialEndDate"
    }

    // MARK: - Trial State

    var isOnTrial: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.isOnTrial) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.isOnTrial) }
    }

    var trialStartDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.trialStartDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.trialStartDate) }
    }

    var trialEndDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.trialEndDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.trialEndDate) }
    }

    // MARK: - Shared Album Trial Warning

    /// Whether we've scheduled the shared album warning notification
    var sharedAlbumWarningScheduled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.sharedAlbumWarningScheduled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.sharedAlbumWarningScheduled) }
    }

    /// Whether we've scheduled the shared album removal notification
    var sharedAlbumRemovalScheduled: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.sharedAlbumRemovalScheduled) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.sharedAlbumRemovalScheduled) }
    }

    // MARK: - Intro Offers
    // Trials are configured in App Store Connect as intro offers.
    // StoreKit automatically prevents multiple trials via isEligibleForIntroOffer.

    var isAnnualTrialEligible: Bool = false
    var annualIntroOfferDuration: String?
    var annualIntroOfferPrice: String?

    var isMonthlyTrialEligible: Bool = false
    var monthlyIntroOfferDuration: String?
    var monthlyIntroOfferPrice: String?

    // MARK: - Transaction listener

    private var transactionListener: Task<Void, Never>?

    // Note: transactionListener runs for app lifetime (SupportManager is a singleton
    // owned by AppState). No deinit needed — Task is automatically cancelled when
    // the process exits. Cannot cancel from deinit because @MainActor properties
    // are inaccessible from nonisolated deinit.

    // MARK: - Initialization

    init() {
        // Trial is now only available via annual plan intro offer (configured in App Store Connect)
        // No automatic trial on first launch - users must subscribe to annual plan to get 14-day trial

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

    // MARK: - StoreKit

    func loadProducts() async {
        isLoadingProducts = true
        do {
            products = try await Product.products(for: SubscriptionPlan.allProductIDs)
            productsLoadFailed = false
            await updateAnnualIntroOfferEligibility()
            await updateMonthlyIntroOfferEligibility()
            isLoadingProducts = false
        } catch {
            print("[SupportManager] Failed to load products: \(error)")
            productsLoadFailed = true
            isLoadingProducts = false
        }
    }

    func retryLoadProducts() {
        Task {
            await loadProducts()
        }
    }

    func updateAnnualIntroOfferEligibility() async {
        guard let annualProduct = products.first(where: { $0.id == SubscriptionPlan.annual.rawValue }),
              let subscription = annualProduct.subscription else {
            isAnnualTrialEligible = false
            return
        }

        let eligible = await subscription.isEligibleForIntroOffer
        isAnnualTrialEligible = eligible

        if eligible, let introOffer = subscription.introductoryOffer {
            annualIntroOfferPrice = introOffer.displayPrice
            let period = introOffer.period
            let value = period.value
            switch period.unit {
            case .day: annualIntroOfferDuration = "\(value)-day"
            case .week: annualIntroOfferDuration = "\(value)-week"
            case .month: annualIntroOfferDuration = "\(value)-month"
            case .year: annualIntroOfferDuration = "\(value)-year"
            @unknown default: annualIntroOfferDuration = nil
            }
        } else {
            annualIntroOfferDuration = nil
            annualIntroOfferPrice = nil
        }
    }

    func updateMonthlyIntroOfferEligibility() async {
        guard let monthlyProduct = products.first(where: { $0.id == SubscriptionPlan.monthly.rawValue }),
              let subscription = monthlyProduct.subscription else {
            isMonthlyTrialEligible = false
            return
        }

        let eligible = await subscription.isEligibleForIntroOffer
        isMonthlyTrialEligible = eligible

        if eligible, let introOffer = subscription.introductoryOffer {
            monthlyIntroOfferPrice = introOffer.displayPrice
            let period = introOffer.period
            let value = period.value
            switch period.unit {
            case .day: monthlyIntroOfferDuration = "\(value)-day"
            case .week: monthlyIntroOfferDuration = "\(value)-week"
            case .month: monthlyIntroOfferDuration = "\(value)-month"
            case .year: monthlyIntroOfferDuration = "\(value)-year"
            @unknown default: monthlyIntroOfferDuration = nil
            }
        } else {
            monthlyIntroOfferDuration = nil
            monthlyIntroOfferPrice = nil
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
            let wasSubscribed = isSubscribed
            isSubscribed = false
            currentPlanRawValue = nil

            // Notify if Pro access was lost
            if wasSubscribed {
                onProAccessLost?()
            }
        }
    }

    private func handleVerifiedTransaction(_ transaction: Transaction) async {
        if transaction.revocationDate != nil {
            // Subscription revoked
            if currentPlanRawValue == transaction.productID {
                isSubscribed = false
                currentPlanRawValue = nil
                isOnTrial = false
                onProAccessLost?()
            }
        } else {
            // Check if subscription has expired
            if let expirationDate = transaction.expirationDate, expirationDate < Date() {
                // Subscription has expired
                let wasSubscribed = isSubscribed
                isSubscribed = false
                currentPlanRawValue = nil
                isOnTrial = false
                if wasSubscribed {
                    onProAccessLost?()
                }
                return
            }
            isSubscribed = true
            currentPlanRawValue = transaction.productID

            // Detect introductory offer (trial period)
            if transaction.offerType == .introductory {
                if !isOnTrial {
                    isOnTrial = true
                    trialStartDate = transaction.purchaseDate
                    trialEndDate = transaction.expirationDate
                }
            } else {
                // Paid subscription (not intro offer) — clear trial state
                isOnTrial = false
            }
        }
    }

    func purchase(plan: SubscriptionPlan) async {
        guard let product = products.first(where: { $0.id == plan.rawValue }) else {
            if productsLoadFailed {
                purchaseError = "Subscription options could not be loaded. Please check your internet connection and try again."
            } else if products.isEmpty && !isLoadingProducts {
                purchaseError = "Subscription products are temporarily unavailable. Please try again later."
            } else {
                purchaseError = "Products are still loading. Try again in a moment."
            }
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

    // MARK: - Shared Album Subscription Warning (legacy stubs)
    // Note: Trial warnings are no longer needed since trials are handled by StoreKit.
    // These methods are kept as stubs for compatibility.

    func scheduleSharedAlbumTrialWarnings() {
        // No-op: trials are now handled by StoreKit intro offers
    }

    func cancelSharedAlbumTrialWarnings() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [
            "sharedAlbum.trialWarning",
            "sharedAlbum.trialFinalWarning"
        ])
        sharedAlbumWarningScheduled = false
        sharedAlbumRemovalScheduled = false
    }

    func resetSharedAlbumWarningFlags() {
        sharedAlbumWarningScheduled = false
        sharedAlbumRemovalScheduled = false
    }
}
