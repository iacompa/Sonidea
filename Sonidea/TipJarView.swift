//
//  TipJarView.swift
//  Sonidea
//
//  Full tip jar UI with tiers, story, roadmap, and supporter perks.
//

import SwiftUI

struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var showCustomAmountSheet = false

    private var supportManager: SupportManager {
        appState.supportManager
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Supporter badge (if tipped before)
                    if supportManager.hasTippedBefore {
                        supporterBadge
                    }

                    // Story/Mission Card
                    storyCard

                    // Tip Tiers
                    tiersSection

                    // Custom Amount
                    customAmountRow

                    // Supporter Perks
                    perksSection

                    // Roadmap Preview
                    roadmapSection

                    // Thank you footer
                    thankYouFooter

                    #if DEBUG
                    debugSection
                    #endif
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Support Sonidea")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                supportManager.onTipJarOpened()
            }
            .sheet(isPresented: $showCustomAmountSheet) {
                CustomAmountSheet()
            }
            .alert("Purchase Error", isPresented: .constant(supportManager.purchaseError != nil)) {
                Button("OK") {
                    appState.supportManager.purchaseError = nil
                }
            } message: {
                Text(supportManager.purchaseError ?? "")
            }
        }
    }

    // MARK: - Supporter Badge

    private var supporterBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: "heart.fill")
                .foregroundColor(.pink)
            Text("Supporter")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.pink)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.pink.opacity(0.15))
        .cornerRadius(20)
    }

    // MARK: - Story Card

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)
                Text("Free forever. Your tips fund updates.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            Text("Sonidea helps artists capture ideas fast.")
                .font(.body)

            Text("It will stay free forever.")
                .font(.body)

            Text("Tips help ship updates and improve reliability.")
                .font(.body)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }

    // MARK: - Tip Tiers

    private var tiersSection: some View {
        VStack(spacing: 12) {
            ForEach(TipTier.allTiers) { tier in
                TipTierButton(tier: tier) {
                    purchaseTier(tier)
                }
                .disabled(supportManager.isPurchasing)
            }
        }
    }

    private func purchaseTier(_ tier: TipTier) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        supportManager.incrementTierTapCount(tierId: tier.id)

        Task {
            await supportManager.purchase(productID: tier.productID)
        }
    }

    // MARK: - Custom Amount

    private var customAmountRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCustomAmountSheet = true
        } label: {
            HStack {
                Image(systemName: "plus.circle")
                    .foregroundColor(.accentColor)
                Text("Other amount...")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Perks Section

    private var perksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supporter Perks")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                PerkRow(icon: "star.fill", color: .yellow, text: "Supporter badge (subtle)")
                PerkRow(icon: "hammer.fill", color: .orange, text: "Early TestFlight builds")
                PerkRow(icon: "hand.raised.fill", color: .blue, text: "Vote on next feature")
                PerkRow(icon: "person.2.fill", color: .purple, text: "Name on Supporters wall (optional)")
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Roadmap Section

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What I'm building next")
                .font(.headline)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(roadmapItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundColor(.accentColor)
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }

    // MARK: - Thank You Footer

    private var thankYouFooter: some View {
        Text("Thank you for keeping Sonidea free.")
            .font(.footnote)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }

    // MARK: - Debug Section

    #if DEBUG
    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Debug Info")
                .font(.headline)
                .foregroundColor(.red)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 6) {
                Text("Active Days: \(supportManager.activeDaysTotal)")
                Text("Streak: \(supportManager.activeDaysStreak)")
                Text("Has Tipped: \(supportManager.hasTippedBefore ? "Yes" : "No")")
                Text("Tip Jar Opens: \(supportManager.tipJarOpenedCount)")
                Text("Purchases: \(supportManager.tipPurchaseSuccessCount)")
                Text("Ask Shown: \(supportManager.askPromptShownCount)")
                Text("Ask Dismissed: \(supportManager.askPromptDismissedCount)")
                Text("Ask Accepted: \(supportManager.askPromptAcceptedCount)")
                Text("Products Loaded: \(supportManager.products.count)")

                Divider()

                Button("Reset All Metrics") {
                    supportManager.debugResetAllMetrics()
                }
                .foregroundColor(.red)

                Button("Set Streak to 7") {
                    supportManager.debugSetStreak(7)
                }

                Button("Trigger Ask Prompt") {
                    supportManager.debugTriggerAskPrompt()
                }
            }
            .font(.caption)
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
        }
    }
    #endif
}

// MARK: - Tip Tier Button

struct TipTierButton: View {
    let tier: TipTier
    let action: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text(tier.impact)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                // Show actual price if available, fallback to display amount
                Text(appState.supportManager.priceForProduct(tier.productID) ?? tier.amount)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.accentColor)
            }
            .padding()
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Perk Row

struct PerkRow: View {
    let icon: String
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 24)
            Text(text)
                .font(.subheadline)
                .foregroundColor(.primary)
        }
    }
}

// MARK: - Custom Amount Sheet

struct CustomAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Text("Choose an amount")
                    .font(.headline)
                    .padding(.top)

                // Quick chips
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(TipTier.customChips, id: \.id) { chip in
                        CustomChipButton(
                            amount: appState.supportManager.priceForProduct(chip.productID) ?? chip.amount,
                            productID: chip.productID
                        ) {
                            purchaseCustom(productID: chip.productID)
                        }
                    }
                }
                .padding(.horizontal)

                Spacer()

                Text("Every tip helps, no matter the size.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .padding(.bottom)
            }
            .navigationTitle("Other Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func purchaseCustom(productID: String) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            await appState.supportManager.purchase(productID: productID)
            if appState.supportManager.purchaseError == nil {
                dismiss()
            }
        }
    }
}

struct CustomChipButton: View {
    let amount: String
    let productID: String
    let action: () -> Void

    @Environment(AppState.self) private var appState

    var body: some View {
        Button(action: action) {
            Text(amount)
                .font(.headline)
                .fontWeight(.semibold)
                .foregroundColor(.accentColor)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color(.systemBackground))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .disabled(appState.supportManager.isPurchasing)
    }
}

// MARK: - Ask Prompt Sheet

struct AskPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    let onSupport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(Color(.systemGray4))
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Icon
            Image(systemName: "heart.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.pink)

            // Title
            Text("Keep Sonidea free")
                .font(.title3)
                .fontWeight(.semibold)

            // Body
            Text("If Sonidea helps you capture ideas, consider leaving a tip.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    appState.supportManager.acceptAskPrompt()
                    dismiss()
                    onSupport()
                } label: {
                    Text("Support Sonidea")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.accentColor)
                        .cornerRadius(12)
                }

                Button {
                    appState.supportManager.dismissAskPrompt()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemBackground))
    }
}

// MARK: - Preview

#Preview {
    TipJarView()
        .environment(AppState())
}
