//
//  SupportManager.swift
//  Sonidea
//
//  Manages tip jar, supporter status, ask prompts, and local metrics.
//  All state persisted in UserDefaults for simplicity.
//

import Foundation
import StoreKit
import Observation

// MARK: - Tip Tier Definition

struct TipTier: Identifiable {
    let id: String
    let productID: String
    let title: String
    let amount: String
    let impact: String

    // Main tier rows displayed in the Tip Jar (4 core tiers only)
    static let allTiers: [TipTier] = [
        TipTier(id: "coffee", productID: "com.iacompa.sonidea.tip.002", title: "Coffee", amount: "$2", impact: "Keeps the project moving."),
        TipTier(id: "feature", productID: "com.iacompa.sonidea.tip.005", title: "Fuel a Feature", amount: "$5", impact: "Helps ship the next update."),
        TipTier(id: "studio", productID: "com.iacompa.sonidea.tip.010", title: "Studio Support", amount: "$10", impact: "Supports reliability + polish."),
        TipTier(id: "patron", productID: "com.iacompa.sonidea.tip.025", title: "Patron", amount: "$25", impact: "Backs major improvements.")
    ]

    // All 106 supported amounts: $1-$100 (100 products) + 6 approved larger amounts
    static let supportedAmounts: [Int] = {
        var amounts = Array(1...100)  // $1 to $100, every dollar
        amounts.append(contentsOf: approvedLargerAmounts)
        return amounts
    }()

    // Custom amount range (typed in TextField)
    static let customAmountRange: ClosedRange<Int> = 1...100

    // Approved larger amounts (selectable via dropdown only)
    static let approvedLargerAmounts: [Int] = [125, 150, 200, 250, 300, 500]

    // Check if an amount is a valid custom amount ($1-$100)
    static func isValidCustomAmount(_ amount: Int) -> Bool {
        customAmountRange.contains(amount)
    }

    // Check if an amount is an approved larger amount
    static func isApprovedLargerAmount(_ amount: Int) -> Bool {
        approvedLargerAmounts.contains(amount)
    }

    // Check if an amount is supported (can be purchased)
    static func isSupported(_ amount: Int) -> Bool {
        supportedAmounts.contains(amount)
    }

    // Product ID for a given amount (3-digit zero-padded format)
    // Returns nil if amount is not supported
    static func productID(for amount: Int) -> String? {
        guard isSupported(amount) else { return nil }
        return String(format: "com.iacompa.sonidea.tip.%03d", amount)
    }

    // All product IDs for loading (106 total)
    static var allProductIDs: Set<String> {
        Set(supportedAmounts.compactMap { productID(for: $0) })
    }
}

// MARK: - Roadmap Item

struct RoadmapItem: Identifiable {
    let id = UUID()
    let title: String
}

let roadmapItems: [RoadmapItem] = [
    RoadmapItem(title: "AI-powered track analysis that automatically tags recordings"),
    RoadmapItem(title: "VST3/AU Plugin for easy imports to your DAW"),
    RoadmapItem(title: "Android release"),
    RoadmapItem(title: "More themes"),
    RoadmapItem(title: "Make the best audio capture app in the world")
]

// MARK: - Ask Prompt Trigger

enum AskPromptTrigger {
    case recordingSaved
    case exportSuccess
    case transcriptionSuccess
}

// MARK: - Support Manager

@MainActor
@Observable
final class SupportManager {

    // MARK: - Published State

    var shouldShowAskPromptSheet = false
    var shouldShowThankYouToast = false
    var isPurchasing = false
    var purchaseError: String?
    var products: [Product] = []
    var isLoadingProducts = true

    // MARK: - Supporter Status

    var hasTippedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasTippedBefore) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasTippedBefore) }
    }

    var hasShownSupporterThankYou: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasShownSupporterThankYou) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasShownSupporterThankYou) }
    }

    var lastTipDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastTipDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastTipDate) }
    }

    var supporterDisplayName: String {
        get { UserDefaults.standard.string(forKey: Keys.supporterDisplayName) ?? "" }
        set { UserDefaults.standard.set(newValue, forKey: Keys.supporterDisplayName) }
    }

    var showNameOnWall: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.showNameOnWall) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.showNameOnWall) }
    }

    // MARK: - Active Days Tracking

    var activeDaysTotal: Int {
        get { UserDefaults.standard.integer(forKey: Keys.activeDaysTotal) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.activeDaysTotal) }
    }

    var activeDaysStreak: Int {
        get { UserDefaults.standard.integer(forKey: Keys.activeDaysStreak) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.activeDaysStreak) }
    }

    var lastActiveDay: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastActiveDay) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastActiveDay) }
    }

    // MARK: - Ask Prompt State

    var lastAskPromptDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastAskPromptDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastAskPromptDate) }
    }

    var nextAskStreakTarget: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: Keys.nextAskStreakTarget)
            return val > 0 ? val : 7 // Default to 7 for first ask
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.nextAskStreakTarget) }
    }

    var nextRecordingCountTarget: Int {
        get {
            let val = UserDefaults.standard.integer(forKey: Keys.nextRecordingCountTarget)
            return val > 0 ? val : 20 // Default to 20 for first threshold
        }
        set { UserDefaults.standard.set(newValue, forKey: Keys.nextRecordingCountTarget) }
    }

    var hasShownFirstAsk: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasShownFirstAsk) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasShownFirstAsk) }
    }

    // MARK: - Feature Usage Tracking

    var hasUsedExport: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasUsedExport) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasUsedExport) }
    }

    var hasUsedTranscription: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasUsedTranscription) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasUsedTranscription) }
    }

    // MARK: - Metrics

    var tipJarOpenedCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.tipJarOpenedCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.tipJarOpenedCount) }
    }

    var tipPurchaseSuccessCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.tipPurchaseSuccessCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.tipPurchaseSuccessCount) }
    }

    var askPromptShownCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.askPromptShownCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.askPromptShownCount) }
    }

    var askPromptDismissedCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.askPromptDismissedCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.askPromptDismissedCount) }
    }

    var askPromptAcceptedCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.askPromptAcceptedCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.askPromptAcceptedCount) }
    }

    // Per-tier tap counts stored as dictionary
    func incrementTierTapCount(tierId: String) {
        var counts = tierTapCounts
        counts[tierId, default: 0] += 1
        UserDefaults.standard.set(counts, forKey: Keys.tipTierTappedCounts)
    }

    var tierTapCounts: [String: Int] {
        UserDefaults.standard.dictionary(forKey: Keys.tipTierTappedCounts) as? [String: Int] ?? [:]
    }

    // MARK: - Private State

    private var askPromptTask: Task<Void, Never>?
    private var isCurrentlyRecording = false

    // MARK: - Keys

    private enum Keys {
        static let hasTippedBefore = "support.hasTippedBefore"
        static let hasShownSupporterThankYou = "support.hasShownSupporterThankYou"
        static let lastTipDate = "support.lastTipDate"
        static let supporterDisplayName = "support.displayName"
        static let showNameOnWall = "support.showNameOnWall"

        static let activeDaysTotal = "support.activeDaysTotal"
        static let activeDaysStreak = "support.activeDaysStreak"
        static let lastActiveDay = "support.lastActiveDay"

        static let lastAskPromptDate = "support.lastAskPromptDate"
        static let nextAskStreakTarget = "support.nextAskStreakTarget"
        static let nextRecordingCountTarget = "support.nextRecordingCountTarget"
        static let hasShownFirstAsk = "support.hasShownFirstAsk"

        static let hasUsedExport = "support.hasUsedExport"
        static let hasUsedTranscription = "support.hasUsedTranscription"

        static let tipJarOpenedCount = "metrics.tipJarOpenedCount"
        static let tipTierTappedCounts = "metrics.tipTierTappedCounts"
        static let tipPurchaseSuccessCount = "metrics.tipPurchaseSuccessCount"
        static let askPromptShownCount = "metrics.askPromptShownCount"
        static let askPromptDismissedCount = "metrics.askPromptDismissedCount"
        static let askPromptAcceptedCount = "metrics.askPromptAcceptedCount"

        // Debug overrides
        static let debugActiveDaysOverride = "debug.activeDaysOverride"
        static let debugStreakOverride = "debug.streakOverride"
    }

    // MARK: - Initialization

    init() {
        Task {
            await loadProducts()
        }
    }

    // MARK: - StoreKit Product Loading

    func loadProducts() async {
        isLoadingProducts = true

        do {
            products = try await Product.products(for: TipTier.allProductIDs)
            isLoadingProducts = false
        } catch {
            print("Failed to load products: \(error)")
            isLoadingProducts = false
        }
    }

    // MARK: - Purchase

    func purchase(productID: String) async {
        guard let product = products.first(where: { $0.id == productID }) else {
            purchaseError = "Tip options are still loading. Try again in a moment."
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
                    // Check if this is the first tip (before marking as tipped)
                    let isFirstTip = !hasTippedBefore

                    // Mark as tipped
                    hasTippedBefore = true
                    lastTipDate = Date()
                    tipPurchaseSuccessCount += 1

                    // Trigger thank you toast if first time
                    if isFirstTip && !hasShownSupporterThankYou {
                        shouldShowThankYouToast = true
                        hasShownSupporterThankYou = true
                    }

                    // Finish the transaction
                    await transaction.finish()

                case .unverified(_, let error):
                    purchaseError = "Purchase verification failed: \(error.localizedDescription)"
                }

            case .userCancelled:
                // User cancelled - no error
                break

            case .pending:
                purchaseError = "Purchase pending approval"

            @unknown default:
                purchaseError = "Unknown purchase result"
            }
        } catch {
            purchaseError = error.localizedDescription
        }

        isPurchasing = false
    }

    func priceForProduct(_ productID: String) -> String? {
        products.first { $0.id == productID }?.displayPrice
    }

    // Get price for a specific dollar amount (exact match only)
    func priceForAmount(_ amount: Int) -> String? {
        guard let productID = TipTier.productID(for: amount) else { return nil }
        return priceForProduct(productID)
    }

    // MARK: - Active Day Registration

    func registerActiveDayIfNeeded() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Check debug override
        #if DEBUG
        if let override = UserDefaults.standard.object(forKey: Keys.debugActiveDaysOverride) as? Int, override > 0 {
            activeDaysTotal = override
        }
        if let streakOverride = UserDefaults.standard.object(forKey: Keys.debugStreakOverride) as? Int, streakOverride > 0 {
            activeDaysStreak = streakOverride
        }
        #endif

        guard let lastActive = lastActiveDay else {
            // First active day
            activeDaysTotal = 1
            activeDaysStreak = 1
            lastActiveDay = today
            return
        }

        let lastActiveStart = calendar.startOfDay(for: lastActive)

        if lastActiveStart == today {
            // Already registered today
            return
        }

        let daysSinceLast = calendar.dateComponents([.day], from: lastActiveStart, to: today).day ?? 0

        if daysSinceLast == 1 {
            // Consecutive day - increment streak
            activeDaysStreak += 1
            activeDaysTotal += 1
        } else {
            // Streak broken - reset streak, increment total
            activeDaysStreak = 1
            activeDaysTotal += 1
        }

        lastActiveDay = today
    }

    // MARK: - Recording State

    func setRecordingState(_ isRecording: Bool) {
        isCurrentlyRecording = isRecording
        if isRecording {
            // Cancel any pending ask prompt
            askPromptTask?.cancel()
            askPromptTask = nil
        }
    }

    // MARK: - Event Hooks

    func onRecordingSaved(totalRecordings: Int) {
        scheduleAskPromptIfEligible(trigger: .recordingSaved, totalRecordings: totalRecordings)
    }

    func onExportSuccess(totalRecordings: Int) {
        hasUsedExport = true
        scheduleAskPromptIfEligible(trigger: .exportSuccess, totalRecordings: totalRecordings)
    }

    func onTranscriptionSuccess(totalRecordings: Int) {
        hasUsedTranscription = true
        scheduleAskPromptIfEligible(trigger: .transcriptionSuccess, totalRecordings: totalRecordings)
    }

    func onTipJarOpened() {
        tipJarOpenedCount += 1
    }

    // MARK: - Thank You Toast

    func dismissThankYouToast() {
        shouldShowThankYouToast = false
    }

    // MARK: - Ask Prompt Logic

    private func scheduleAskPromptIfEligible(trigger: AskPromptTrigger, totalRecordings: Int) {
        // Never show if already tipped
        guard !hasTippedBefore else { return }

        // Never show while recording
        guard !isCurrentlyRecording else { return }

        // Check cooldown (14 days)
        if let lastAsk = lastAskPromptDate {
            let daysSinceLastAsk = Calendar.current.dateComponents([.day], from: lastAsk, to: Date()).day ?? 0
            if daysSinceLastAsk < 14 {
                return
            }
        }

        // Determine eligibility
        var shouldShow = false

        if !hasShownFirstAsk {
            // First ask: streak >= 7 AND (10+ recordings OR used high-value feature)
            let hasEnoughRecordings = totalRecordings >= 10
            let hasUsedHighValueFeature = hasUsedExport || hasUsedTranscription

            if activeDaysStreak >= 7 && (hasEnoughRecordings || hasUsedHighValueFeature) {
                shouldShow = true
            }
        } else {
            // Subsequent asks: streak-based OR recording-count-based

            // Streak-based: streak reaches target
            if activeDaysStreak >= nextAskStreakTarget {
                shouldShow = true
            }

            // Recording-count-based: total recordings reaches target
            if totalRecordings >= nextRecordingCountTarget {
                shouldShow = true
            }
        }

        guard shouldShow else { return }

        // Schedule with random delay (8-25 seconds)
        let delay = Double.random(in: 8...25)

        askPromptTask?.cancel()
        askPromptTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

            // Check again that we're not recording and task wasn't cancelled
            guard !Task.isCancelled, !isCurrentlyRecording else { return }

            showAskPrompt()
        }
    }

    private func showAskPrompt() {
        shouldShowAskPromptSheet = true
        askPromptShownCount += 1
        lastAskPromptDate = Date()

        if !hasShownFirstAsk {
            hasShownFirstAsk = true
            // Set next streak target: random 8-10
            nextAskStreakTarget = Int.random(in: 8...10)
        } else {
            // Set next targets
            nextAskStreakTarget = activeDaysStreak + Int.random(in: 8...10)
        }

        // Set next recording count target: current + random 18-24
        let currentRecordingTarget = nextRecordingCountTarget
        nextRecordingCountTarget = currentRecordingTarget + Int.random(in: 18...24)
    }

    func dismissAskPrompt() {
        shouldShowAskPromptSheet = false
        askPromptDismissedCount += 1
    }

    func acceptAskPrompt() {
        shouldShowAskPromptSheet = false
        askPromptAcceptedCount += 1
    }

    // MARK: - Debug Helpers

    #if DEBUG
    func debugSetActiveDays(_ days: Int) {
        UserDefaults.standard.set(days, forKey: Keys.debugActiveDaysOverride)
        activeDaysTotal = days
    }

    func debugSetStreak(_ streak: Int) {
        UserDefaults.standard.set(streak, forKey: Keys.debugStreakOverride)
        activeDaysStreak = streak
    }

    func debugResetAllMetrics() {
        let keysToReset = [
            Keys.hasTippedBefore,
            Keys.hasShownSupporterThankYou,
            Keys.lastTipDate,
            Keys.activeDaysTotal,
            Keys.activeDaysStreak,
            Keys.lastActiveDay,
            Keys.lastAskPromptDate,
            Keys.nextAskStreakTarget,
            Keys.nextRecordingCountTarget,
            Keys.hasShownFirstAsk,
            Keys.hasUsedExport,
            Keys.hasUsedTranscription,
            Keys.tipJarOpenedCount,
            Keys.tipTierTappedCounts,
            Keys.tipPurchaseSuccessCount,
            Keys.askPromptShownCount,
            Keys.askPromptDismissedCount,
            Keys.askPromptAcceptedCount,
            Keys.debugActiveDaysOverride,
            Keys.debugStreakOverride
        ]

        for key in keysToReset {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    func debugTriggerAskPrompt() {
        showAskPrompt()
    }

    func debugTriggerThankYou() {
        shouldShowThankYouToast = true
    }
    #endif
}
