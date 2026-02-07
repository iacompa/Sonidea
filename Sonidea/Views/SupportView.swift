//
//  SupportView.swift
//  Sonidea
//
//  Subscription and upgrade page. Shows plans, trial status, and roadmap.
//

import SwiftUI
import StoreKit

struct SupportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var showPurchaseError = false

    private var manager: SupportManager {
        appState.supportManager
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Status banner
                    statusBanner

                    // Plan cards
                    plansSection

                    // Features list
                    featuresSection

                    // Roadmap
                    roadmapSection

                    // Restore purchases
                    restoreButton

                    // Legal compliance footer
                    legalFooter

                    // Suggestions & Review
                    suggestionsButton
                    reviewButton
                }
                .padding()
            }
            .background(palette.groupedBackground)
            .navigationTitle("Sonidea Pro")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(palette.accent)
                }
            }
            .onChange(of: manager.purchaseError) { _, newValue in
                showPurchaseError = newValue != nil
            }
            .alert("Purchase Error", isPresented: $showPurchaseError) {
                Button("OK") {
                    appState.supportManager.purchaseError = nil
                }
            } message: {
                Text(manager.purchaseError ?? "")
            }
        }
    }

    // MARK: - Status Banner

    private var statusBanner: some View {
        Group {
            switch manager.subscriptionStatus {
            case .trial:
                trialBanner

            case .subscribed(let plan):
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                        Text("\(plan.displayName) Pro")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(palette.textPrimary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .background(Color.green.opacity(0.1))
                .cornerRadius(12)

            case .expired:
                HStack(spacing: 8) {
                    Image(systemName: "star.circle.fill")
                        .foregroundColor(palette.accent)
                    Text("Upgrade to unlock Pro features")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(palette.accent.opacity(0.1))
                .cornerRadius(12)
            }
        }
    }

    private var trialBanner: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.orange)
                Text("Free Trial Active")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.textPrimary)
            }
            if let endDate = manager.trialEndDate {
                let daysLeft = max(0, Calendar.current.dateComponents([.day], from: Date(), to: endDate).day ?? 0)
                Text(daysLeft == 1 ? "1 day remaining" : "\(daysLeft) days remaining")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(12)
    }

    // MARK: - Plans

    @State private var showAllPlans = false

    /// Plans visible based on current subscription
    private var visiblePlans: [SubscriptionPlan] {
        guard let current = manager.currentPlan, manager.isSubscribed else {
            // Free / trial — show all
            return SubscriptionPlan.allCases
        }
        if showAllPlans { return SubscriptionPlan.allCases }
        // Only show higher tiers
        switch current {
        case .monthly: return [.annual]
        case .annual: return []
        }
    }

    private var plansSection: some View {
        VStack(spacing: 12) {
            Text(manager.isSubscribed ? "Upgrade Your Plan" : "Choose a Plan")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if manager.productsLoadFailed {
                VStack(spacing: 8) {
                    Text("Could not load subscription options.")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                    Button {
                        manager.retryLoadProducts()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundColor(palette.accent)
                    }
                }
                .padding(.vertical, 12)
            } else if manager.isLoadingProducts {
                ProgressView()
                    .padding(.vertical, 12)
            } else if manager.products.isEmpty {
                Text("Subscriptions temporarily unavailable. Please try again later.")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .padding(.vertical, 12)
            } else {
                ForEach(visiblePlans, id: \.self) { plan in
                    PlanCard(plan: plan, isBestValue: plan == .annual) {
                        Task {
                            await manager.purchase(plan: plan)
                        }
                    }

                    if plan == .monthly && manager.isMonthlyTrialEligible,
                       let duration = manager.monthlyIntroOfferDuration {
                        Text("Cancel anytime during the \(duration) trial. You'll be charged after the trial ends unless you cancel at least 24 hours before.")
                            .font(.system(size: 10))
                            .foregroundColor(palette.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.top, -4)
                    }

                    if plan == .annual && manager.isAnnualTrialEligible,
                       let duration = manager.annualIntroOfferDuration {
                        Text("Cancel anytime during the \(duration) trial. You'll be charged after the trial ends unless you cancel at least 24 hours before.")
                            .font(.system(size: 10))
                            .foregroundColor(palette.textSecondary)
                            .padding(.horizontal, 4)
                            .padding(.top, -4)
                    }
                }

                // "See other plans" for subscribed users who haven't expanded (not on annual)
                if manager.isSubscribed && manager.currentPlan != .annual && !showAllPlans {
                    Button {
                        withAnimation { showAllPlans = true }
                    } label: {
                        Text("See all plans")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                    }
                }
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 16) {
            // Feature-loss list when not subscribed
            if case .expired = manager.subscriptionStatus {
                featureLossSection
            }

            // Price anchoring
            if !manager.isSubscribed {
                priceAnchoringSection
            }

            // Free tier
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "gift.fill")
                        .font(.subheadline)
                        .foregroundColor(.green)
                    Text("Free Forever")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color.green.opacity(0.08))

                VStack(spacing: 0) {
                    FeatureCheckRow(icon: "mic.fill", text: "Unlimited recordings", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "play.fill", text: "Full playback", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "magnifyingglass", text: "Search & organize", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "map.fill", text: "Map view", included: true)
                }
                .padding(.vertical, 4)
            }
            .background(palette.cardBackground)
            .cornerRadius(12)

            // Pro tier
            VStack(spacing: 0) {
                HStack {
                    Image(systemName: "star.fill")
                        .font(.subheadline)
                        .foregroundColor(palette.accent)
                    Text("Pro")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(palette.textPrimary)
                    Spacer()
                    Text("Everything in Free, plus:")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(palette.accent.opacity(0.08))

                VStack(spacing: 0) {
                    FeatureCheckRow(icon: "waveform", text: "Pro waveform editor", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "person.2.fill", text: "Shared albums & collaboration", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "tag.fill", text: "Tags & smart filtering", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "icloud.fill", text: "iCloud sync", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "sparkles", text: "Auto-select icons", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "square.on.square", text: "Multi-track overdub", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "slider.vertical.3", text: "Mixer & mixdown", included: true)
                    Divider().padding(.leading, 52)
                    FeatureCheckRow(icon: "slider.horizontal.3", text: "Live recording effects", included: true)
                }
                .padding(.vertical, 4)

                // Export demoted to small text
                Text("Plus: export in WAV, M4A, ALAC formats")
                    .font(.system(size: 11))
                    .foregroundColor(palette.textTertiary)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
            }
            .background(palette.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.accent.opacity(0.2), lineWidth: 1)
            )
        }
    }

    // MARK: - Feature Loss

    private var featureLossSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundColor(.orange)
                Text("You're missing out on")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.orange.opacity(0.08))

            VStack(spacing: 0) {
                FeatureLossRow(icon: "waveform", text: "Pro waveform editor")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "person.2.fill", text: "Shared albums")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "tag.fill", text: "Tags & filtering")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "icloud.fill", text: "iCloud sync")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "square.on.square", text: "Multi-track overdub")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "sparkles", text: "Auto-select icons")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "slider.vertical.3", text: "Mixer & mixdown")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "music.note", text: "Metronome & click track")
            }
            .padding(.vertical, 4)
        }
        .background(palette.cardBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - Price Anchoring

    private var priceAnchoringSection: some View {
        VStack(spacing: 6) {
            // TODO: Replace with localized StoreKit prices (e.g. annual displayPrice / 12)
            Text("Just $2.50/month")
                .font(.title3.weight(.bold))
                .foregroundColor(palette.accent)
            // TODO: Replace with localized StoreKit prices
            Text("with the annual plan ($29.99/year)")
                .font(.caption)
                .foregroundColor(palette.textSecondary)
            // TODO: Replace with localized StoreKit prices
            Text("Monthly: $3.99/month ($47.88/year)")
                .font(.caption)
                .foregroundColor(palette.textTertiary)
                .strikethrough(true, color: palette.textTertiary)
        }
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(palette.accent.opacity(0.05))
        .cornerRadius(12)
    }

    // MARK: - Roadmap

    private var roadmapSection: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "road.lanes")
                    .font(.subheadline)
                    .foregroundColor(palette.accent)
                Text("Coming Soon")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.textPrimary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(palette.accent.opacity(0.05))

            VStack(spacing: 0) {
                ForEach(Array(roadmapItems.enumerated()), id: \.element.id) { index, item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.system(size: 14))
                            .foregroundColor(palette.accent)
                            .frame(width: 24)
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                        Spacer()
                        if item.isNew {
                            Text("NEW")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(palette.accent)
                                .cornerRadius(4)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < roadmapItems.count - 1 {
                        Divider().padding(.leading, 52)
                    }
                }
            }
        }
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Restore

    private var restoreButton: some View {
        Button {
            Task {
                await manager.restorePurchases()
            }
        } label: {
            HStack {
                if manager.isPurchasing {
                    ProgressView()
                        .tint(palette.textSecondary)
                        .padding(.trailing, 4)
                }
                Text("Restore Purchases")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
        }
        .disabled(manager.isPurchasing)
    }

    // MARK: - Legal Footer

    private var legalFooter: some View {
        VStack(spacing: 10) {
            Text("Subscriptions automatically renew unless cancelled at least 24 hours before the end of the current period. You can manage and cancel subscriptions in your device's Settings > [your name] > Subscriptions.")
                .font(.system(size: 10))
                .foregroundColor(palette.textSecondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 16) {
                Button("Privacy Policy") {
                    if let url = URL(string: "https://www.notion.so/sonidea/Sonidea-Privacy-Policy-2f72934c965380a3bafaf7967e2295df") {
                        openURL(url)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(palette.accent)

                Button("Terms of Use") {
                    if let url = URL(string: "https://sonidea.notion.site/Sonidea-Terms-and-Conditions-2fb2934c965380fe8461ef99bab80490") {
                        openURL(url)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(palette.accent)

                Button("Manage Subscription") {
                    if let url = URL(string: "itms-apps://apps.apple.com/account/subscriptions") {
                        openURL(url)
                    }
                }
                .font(.system(size: 11))
                .foregroundColor(palette.accent)
            }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Suggestions

    private var suggestionsButton: some View {
        Button {
            if let url = URL(string: "https://forms.gle/wtBwxDbjACds9dxt9") {
                openURL(url)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send us app suggestions")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    Text("Got an idea or found something annoying? Tell us.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Review

    private var reviewButton: some View {
        Button {
            if let windowScene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
                SKStoreReviewController.requestReview(in: windowScene)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review Sonidea")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    Text("If it helped you capture a great idea, a review means a lot.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                        .lineLimit(2)
                }
                Spacer()
                Image(systemName: "star")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.accent.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Plan Card

struct PlanCard: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let plan: SubscriptionPlan
    let isBestValue: Bool
    let action: () -> Void

    private var hasTrialOffer: Bool {
        switch plan {
        case .annual: return appState.supportManager.isAnnualTrialEligible
        case .monthly: return appState.supportManager.isMonthlyTrialEligible
        }
    }

    private var trialDuration: String? {
        switch plan {
        case .annual: return appState.supportManager.annualIntroOfferDuration
        case .monthly: return appState.supportManager.monthlyIntroOfferDuration
        }
    }

    private var taglineText: String {
        plan.tagline
    }

    private var buttonText: String {
        if hasTrialOffer, let duration = trialDuration {
            return "Try \(duration) free"
        }
        return appState.supportManager.priceForPlan(plan) ?? plan.description
    }

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(plan.displayName)
                            .font(.headline)
                            .foregroundColor(palette.textPrimary)
                        if isBestValue {
                            Text("BEST VALUE")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .cornerRadius(4)
                        }
                    }
                    HStack(spacing: 6) {
                        Text(taglineText)
                            .font(.caption)
                            .foregroundColor(palette.textSecondary)
                        if hasTrialOffer, let duration = trialDuration {
                            Text("\(duration) free trial")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(palette.accent)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(palette.accent.opacity(0.12))
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()

                Text(buttonText)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.accent)
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isBestValue ? Color.green : palette.accent.opacity(0.3), lineWidth: isBestValue ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.supportManager.isPurchasing)
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    @Environment(\.themePalette) private var palette
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(palette.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
        }
    }
}

struct FeatureCheckRow: View {
    @Environment(\.themePalette) private var palette
    let icon: String
    let text: String
    let included: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(palette.accent)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Image(systemName: included ? "checkmark" : "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(included ? .green : palette.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

struct FeatureLossRow: View {
    @Environment(\.themePalette) private var palette
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(.orange)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(palette.textPrimary)
            Spacer()
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

// MARK: - Paywall View (shown when trial expired)

struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var showSubscription = false
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportedZIPURL: URL?
    @State private var showBulkFormatPicker = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "lock.fill")
                .font(.system(size: 56))
                .foregroundColor(palette.textSecondary)

            VStack(spacing: 8) {
                Text("Your Free Trial Has Ended")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(palette.textPrimary)

                Text("Subscribe to keep these features:")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            // Feature-loss list with icons
            VStack(spacing: 0) {
                FeatureLossRow(icon: "waveform", text: "Pro waveform editor")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "person.2.fill", text: "Shared albums")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "tag.fill", text: "Tags & filtering")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "icloud.fill", text: "iCloud sync")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "square.on.square", text: "Multi-track overdub")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "sparkles", text: "Auto-select icons")
                Divider().padding(.leading, 52)
                FeatureLossRow(icon: "slider.vertical.3", text: "Mixer & mixdown")
            }
            .padding(.vertical, 4)
            .background(palette.cardBackground)
            .cornerRadius(12)
            .padding(.horizontal, 24)

            // Price anchoring
            // TODO: Replace with localized StoreKit prices
            VStack(spacing: 4) {
                Text("Just $2.50/month")
                    .font(.title3.weight(.bold))
                    .foregroundColor(palette.accent)
                Text("with the annual plan")
                    .font(.caption)
                    .foregroundColor(palette.textSecondary)
            }

            VStack(spacing: 14) {
                Button {
                    showSubscription = true
                } label: {
                    Text("View Plans")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(palette.accent)
                        .cornerRadius(14)
                }

                Button {
                    Task {
                        await appState.supportManager.restorePurchases()
                    }
                } label: {
                    Text("Restore Purchases")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }

                // Export demoted to small text link
                Button {
                    showBulkFormatPicker = true
                } label: {
                    Text("Export all recordings")
                        .font(.caption)
                        .foregroundColor(palette.textTertiary)
                        .underline()
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .background(palette.background)
        .overlay {
            if isExporting {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 12) {
                            ProgressView()
                                .tint(.white)
                            Text("Preparing export...")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                    }
            }
        }
        .sheet(isPresented: $showSubscription) {
            SupportView()
                .environment(appState)
                .environment(\.themePalette, palette)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedZIPURL {
                ShareSheet(items: [url])
            }
        }
        .sheet(isPresented: $showBulkFormatPicker) {
            BulkExportFormatPicker { formats in
                exportAllRecordings(formats: formats)
            }
        }
    }

    private func exportAllRecordings(formats: Set<ExportFormat>) {
        isExporting = true
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    appState.activeRecordings,
                    scope: .all,
                    formats: formats,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                await MainActor.run {
                    exportedZIPURL = zipURL
                    isExporting = false
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                }
                #if DEBUG
                print("Export failed: \(error.localizedDescription)")
                #endif
            }
        }
    }
}

#Preview {
    SupportView()
        .environment(AppState())
}
