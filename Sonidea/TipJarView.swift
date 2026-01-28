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
            .alert("Purchase Error", isPresented: .constant(manager.purchaseError != nil)) {
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
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.blue)
                    Text("\(manager.trialDaysRemaining) days left in free trial")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)

            case .subscribed(let plan):
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.green)
                    Text("Subscribed — \(plan.displayName)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
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

    private var plansSection: some View {
        VStack(spacing: 12) {
            Text("Choose a Plan")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(SubscriptionPlan.allCases, id: \.self) { plan in
                PlanCard(plan: plan, isBestValue: plan == .annual) {
                    Task {
                        await manager.purchase(plan: plan)
                    }
                }

                if plan == .annual && manager.isAnnualTrialEligible {
                    Text("Cancel anytime. Trial converts to yearly unless canceled at least 24 hours before the end.")
                        .font(.system(size: 10))
                        .foregroundColor(palette.textSecondary)
                        .padding(.horizontal, 4)
                        .padding(.top, -4)
                }
            }
        }
    }

    // MARK: - Features

    private var featuresSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Free Forever")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "mic.fill", text: "Unlimited recordings")
                FeatureRow(icon: "play.fill", text: "Full playback")
                FeatureRow(icon: "magnifyingglass", text: "Search & organize")
                FeatureRow(icon: "map.fill", text: "Map view")
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)

            Text("Pro Features")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 4)
                .padding(.top, 4)

            VStack(alignment: .leading, spacing: 10) {
                FeatureRow(icon: "waveform", text: "Pro waveform editor")
                FeatureRow(icon: "person.2.fill", text: "Shared albums & collaboration")
                FeatureRow(icon: "tag.fill", text: "Tags & smart filtering")
                FeatureRow(icon: "icloud.fill", text: "iCloud sync")
                FeatureRow(icon: "sparkles", text: "Auto-select icons")
                FeatureRow(icon: "square.on.square", text: "Multi-track overdub")
                FeatureRow(icon: "paintpalette.fill", text: "All themes")
                FeatureRow(icon: "square.and.arrow.up.fill", text: "Export in all formats")
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Roadmap

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming Soon")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(roadmapItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: item.icon)
                            .font(.caption)
                            .foregroundColor(palette.accent)
                            .frame(width: 20)
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
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
                }
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
        }
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
            return "7-day free trial, then \(price)/year"
        }
        return plan.tagline
    }

    private var buttonText: String {
        if isAnnualWithTrial {
            return "Start 7-day free trial"
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
