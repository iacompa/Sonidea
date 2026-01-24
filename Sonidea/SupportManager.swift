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

    static let allTiers: [TipTier] = [
        TipTier(id: "coffee", productID: "com.iacompa.sonidea.tip.coffee", title: "Coffee", amount: "$2", impact: "Keeps the project moving."),
        TipTier(id: "feature", productID: "com.iacompa.sonidea.tip.feature", title: "Fuel a Feature", amount: "$5", impact: "Helps ship the next update."),
        TipTier(id: "studio", productID: "com.iacompa.sonidea.tip.studio", title: "Studio Support", amount: "$10", impact: "Supports reliability + polish."),
        TipTier(id: "patron", productID: "com.iacompa.sonidea.tip.patron", title: "Patron", amount: "$25", impact: "Backs major improvements.")
    ]

    // Additional fixed amounts for custom tip sheet
    static let customChips: [(id: String, productID: String, amount: String)] = [
        ("tip1", "com.iacompa.sonidea.tip.custom1", "$1"),
        ("tip3", "com.iacompa.sonidea.tip.custom3", "$3"),
        ("tip7", "com.iacompa.sonidea.tip.custom7", "$7"),
        ("tip15", "com.iacompa.sonidea.tip.custom15", "$15")
    ]
}

// MARK: - Roadmap Item

struct RoadmapItem: Identifiable {
    let id = UUID()
    let title: String
}

let roadmapItems: [RoadmapItem] = [
    RoadmapItem(title: "Import from Files"),
    RoadmapItem(title: "Smarter Drafts organization"),
    RoadmapItem(title: "More pro recording polish")
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
    var isPurchasing = false
    var purchaseError: String?
    var products: [Product] = []
    var isLoadingProducts = true

    // MARK: - Supporter Status

    var hasTippedBefore: Bool {
        get { UserDefaults.standard.bool(forKey: Keys.hasTippedBefore) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.hasTippedBefore) }
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

        let productIDs = TipTier.allTiers.map { $0.productID } + TipTier.customChips.map { $0.productID }

        do {
            products = try await Product.products(for: Set(productIDs))
            isLoadingProducts = false
        } catch {
            print("Failed to load products: \(error)")
            isLoadingProducts = false
        }
    }

    // MARK: - Purchase

    func purchase(productID: String) async {
        guard let product = products.first(where: { $0.id == productID }) else {
            purchaseError = "Product not available"
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
                    // Mark as tipped
                    hasTippedBefore = true
                    lastTipDate = Date()
                    tipPurchaseSuccessCount += 1

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
    #endif
}
