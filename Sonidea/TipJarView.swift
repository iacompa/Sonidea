//
//  TipJarView.swift
//  Sonidea
//
//  Subscription and upgrade page. Shows plans, trial status, and roadmap.
//

import SwiftUI
import StoreKit

struct TipJarView: View {
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
                // Trial is now handled via StoreKit intro offer (shows as subscribed)
                EmptyView()

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
        case .monthly: return [.sixMonth, .annual]
        case .sixMonth: return [.annual]
        case .annual: return []
        }
    }

    private var plansSection: some View {
        VStack(spacing: 12) {
            Text(manager.isSubscribed ? "Upgrade Your Plan" : "Choose a Plan")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(visiblePlans, id: \.self) { plan in
                PlanCard(plan: plan, isBestValue: plan == .annual) {
                    Task {
                        await manager.purchase(plan: plan)
                    }
                }

                if plan == .annual && manager.isAnnualTrialEligible {
                    Text("Cancel anytime during the 14-day trial. You'll be charged after the trial ends unless you cancel at least 24 hours before.")
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

    // MARK: - Features

    private var featuresSection: some View {
        VStack(spacing: 16) {
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
                    FeatureCheckRow(icon: "square.and.arrow.up.fill", text: "Export in all formats", included: true)
                }
                .padding(.vertical, 4)
            }
            .background(palette.cardBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(palette.accent.opacity(0.2), lineWidth: 1)
            )
        }
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

    private var isAnnualWithTrial: Bool {
        plan == .annual && appState.supportManager.isAnnualTrialEligible
    }

    private var taglineText: String {
        if isAnnualWithTrial {
            let price = appState.supportManager.priceForPlan(plan) ?? plan.description
            return "14 days free, then \(price)/year"
        }
        return plan.tagline
    }

    private var buttonText: String {
        if isAnnualWithTrial {
            return "Try 14 days free"
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
                    Text(taglineText)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
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

// MARK: - Paywall View (shown when trial expired)

struct PaywallView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    @State private var showSubscription = false
    @State private var isExporting = false
    @State private var showShareSheet = false
    @State private var exportedZIPURL: URL?

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

                Text("Subscribe to continue using Sonidea, or export your recordings.")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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
                    exportAllRecordings()
                } label: {
                    HStack {
                        Image(systemName: "square.and.arrow.up")
                        Text("Export All Recordings")
                    }
                    .font(.headline)
                    .foregroundColor(palette.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(palette.cardBackground)
                    .cornerRadius(14)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(palette.accent.opacity(0.3), lineWidth: 1)
                    )
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
            TipJarView()
                .environment(appState)
                .environment(\.themePalette, palette)
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedZIPURL {
                ShareSheet(items: [url])
            }
        }
    }

    private func exportAllRecordings() {
        isExporting = true
        Task {
            do {
                let zipURL = try await AudioExporter.shared.exportRecordings(
                    appState.activeRecordings,
                    scope: .all,
                    albumLookup: { appState.album(for: $0) },
                    tagsLookup: { appState.tags(for: $0) }
                )
                exportedZIPURL = zipURL
                isExporting = false
                showShareSheet = true
            } catch {
                isExporting = false
            }
        }
    }
}

#Preview {
    TipJarView()
        .environment(AppState())
}
