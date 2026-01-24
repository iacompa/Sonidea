//
//  TipJarView.swift
//  Sonidea
//
//  Tip jar UI with 4 core tiers + "Other amount..." for custom tips.
//  Uses 106 consumable IAP products ($1-$100 + 6 approved larger amounts).
//

import SwiftUI
import StoreKit

struct TipJarView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

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

                    // Tip Tiers (4 core tiers only)
                    tiersSection

                    // Other Amount row (styled like tier cards)
                    otherAmountButton

                    // Supporter Perks
                    perksSection

                    // Roadmap Preview
                    roadmapSection

                    // Suggestions Link
                    suggestionsButton

                    // Review Button
                    reviewButton

                    // Thank you footer
                    thankYouFooter
                }
                .padding()
            }
            .background(palette.groupedBackground)
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
                    .environment(appState)
                    .environment(\.themePalette, palette)
                    .preferredColorScheme(appState.selectedTheme.forcedColorScheme)
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
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.caption)
                .foregroundColor(.orange)
            Text("Supporter")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(palette.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background(palette.inputBackground)
        .cornerRadius(16)
    }

    // MARK: - Story Card

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform.circle.fill")
                    .font(.title2)
                    .foregroundColor(palette.accent)
                Text("Free forever — powered by tips.")
                    .font(.subheadline)
                    .foregroundColor(palette.textSecondary)
            }

            Text("Sonidea helps artists capture ideas fast.")
                .font(.body)
                .foregroundColor(palette.textPrimary)

            Text("It will be free forever.")
                .font(.body)
                .fontWeight(.medium)
                .foregroundColor(palette.textPrimary)

            Text("If it's saved you even one idea, a tip helps keep the app polished, reliable, and improving.")
                .font(.callout)
                .foregroundColor(palette.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.cardBackground)
        .cornerRadius(12)
    }

    // MARK: - Tip Tiers (4 core tiers only)

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

    // MARK: - Other Amount Button (styled like tier cards)

    private var otherAmountButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCustomAmountSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other amount…")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    Text("Choose any tip amount you'd like.")
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
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
        .accessibilityLabel("Other amount")
        .accessibilityHint("Opens a sheet to choose any custom tip amount")
    }

    // MARK: - Perks Section

    private var perksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Supporter Perks")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                PerkRow(icon: "hand.raised.fill", color: .blue, text: "Vote for next feature")
                PerkRow(icon: "person.2.fill", color: .purple, text: "Name on Supporters wall (coming soon)")
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Roadmap Section

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What we're adding next")
                .font(.headline)
                .foregroundColor(palette.textPrimary)
                .padding(.horizontal, 4)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(roadmapItems) { item in
                    HStack(spacing: 12) {
                        Image(systemName: "circle")
                            .font(.caption2)
                            .foregroundColor(palette.accent)
                        Text(item.title)
                            .font(.subheadline)
                            .foregroundColor(palette.textPrimary)
                    }
                }
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Suggestions Button (styled like tier cards)

    private var suggestionsButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if let url = URL(string: "https://forms.gle/wtBwxDbjACds9dxt9") {
                openURL(url)
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Send us app suggestions")
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    Text("Got an idea or found something annoying? Tell us — it helps a lot.")
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

    // MARK: - Review Button

    private var reviewButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            requestReview()
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

    private func requestReview() {
        if let windowScene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene {
            SKStoreReviewController.requestReview(in: windowScene)
        }
    }

    // MARK: - Thank You Footer

    private var thankYouFooter: some View {
        Text("Thank you for keeping Sonidea free.")
            .font(.footnote)
            .foregroundColor(palette.textSecondary)
            .multilineTextAlignment(.center)
            .padding(.top, 8)
    }
}

// MARK: - Tip Tier Button

struct TipTierButton: View {
    let tier: TipTier
    let action: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(tier.title)
                        .font(.headline)
                        .foregroundColor(palette.textPrimary)
                    Text(tier.impact)
                        .font(.caption)
                        .foregroundColor(palette.textSecondary)
                }

                Spacer()

                Text(appState.supportManager.priceForProduct(tier.productID) ?? tier.amount)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(palette.accent)
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
        .accessibilityLabel("\(tier.title), \(tier.amount)")
        .accessibilityHint(tier.impact)
    }
}

// MARK: - Perk Row

struct PerkRow: View {
    @Environment(\.themePalette) private var palette
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
                .foregroundColor(palette.textPrimary)
        }
    }
}

// MARK: - Custom Amount Sheet

struct CustomAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    @FocusState private var isTextFieldFocused: Bool

    // Text input state
    @State private var amountText: String = ""

    // Dropdown state
    @State private var approvedExpanded: Bool = false

    // Derived amount value (nil if invalid/empty)
    private var amountValue: Int? {
        guard !amountText.isEmpty else { return nil }
        return Int(amountText)
    }

    // Validation
    private var isValidCustom: Bool {
        guard let value = amountValue else { return false }
        return TipTier.isValidCustomAmount(value)
    }

    private var isApprovedLarge: Bool {
        guard let value = amountValue else { return false }
        return TipTier.isApprovedLargerAmount(value)
    }

    private var canTip: Bool {
        isValidCustom || isApprovedLarge
    }

    // Show "for larger tips" message when typed value > 100 and not an approved amount
    private var showLargerTipsMessage: Bool {
        guard let value = amountValue else { return false }
        return value > 100 && !isApprovedLarge
    }

    // Display amount (0 if empty/invalid)
    private var displayAmount: Int {
        amountValue ?? 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Large amount display
                    Text("$\(displayAmount)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .foregroundColor(canTip ? palette.textPrimary : palette.textSecondary)
                        .contentTransition(.numericText())
                        .animation(.spring(response: 0.3), value: displayAmount)
                        .padding(.top, 24)

                    // Text input field
                    VStack(spacing: 8) {
                        HStack {
                            Text("$")
                                .font(.title2)
                                .fontWeight(.medium)
                                .foregroundColor(palette.textSecondary)

                            TextField("Enter amount", text: $amountText)
                                .font(.title2)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.leading)
                                .foregroundColor(palette.textPrimary)
                                .focused($isTextFieldFocused)
                                .onChange(of: amountText) { _, newValue in
                                    // Strip non-digits
                                    let filtered = newValue.filter { $0.isNumber }
                                    if filtered != newValue {
                                        amountText = filtered
                                    }
                                }
                                .accessibilityLabel("Enter tip amount")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(palette.inputBackground)
                        .cornerRadius(12)

                        Text("Enter dollar amount (USD) $1–$100")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                    .padding(.horizontal)

                    // "For larger tips" message
                    if showLargerTipsMessage {
                        Text("For larger tips, choose an approved amount below.")
                            .font(.subheadline)
                            .foregroundColor(palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity)
                    }

                    // Approved larger amounts dropdown
                    approvedAmountsSection
                        .padding(.horizontal)

                    Spacer(minLength: 40)

                    // CTA Button
                    VStack(spacing: 12) {
                        Button {
                            purchaseAmount()
                        } label: {
                            HStack {
                                if appState.supportManager.isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Tip $\(displayAmount)")
                                        .font(.headline)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(canTip ? palette.accent : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(!canTip || appState.supportManager.isPurchasing)
                        .accessibilityLabel("Tip $\(displayAmount)")

                        Button("Cancel") {
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                        .frame(height: 44)
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .background(palette.background)
            .navigationTitle("Other Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        isTextFieldFocused = false
                    }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: showLargerTipsMessage)
            .animation(.easeInOut(duration: 0.25), value: approvedExpanded)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Approved Larger Amounts Section

    private var approvedAmountsSection: some View {
        VStack(spacing: 0) {
            // Disclosure button
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                approvedExpanded.toggle()
            } label: {
                HStack {
                    Text("Approved larger amounts")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(palette.textPrimary)

                    Spacer()

                    Image(systemName: approvedExpanded ? "chevron.up" : "chevron.down")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
                }
                .padding()
                .background(palette.cardBackground)
                .cornerRadius(approvedExpanded ? 12 : 12)
            }
            .buttonStyle(.plain)

            // Expanded content
            if approvedExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    // Info line
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                        Text("These are the approved amounts we can accept for larger tips.")
                            .font(.caption)
                            .foregroundColor(palette.textTertiary)
                    }
                    .padding(.horizontal, 4)

                    // Amount pills
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 10) {
                        ForEach(TipTier.approvedLargerAmounts, id: \.self) { amount in
                            ApprovedAmountPill(
                                amount: amount,
                                isSelected: amountValue == amount
                            ) {
                                selectApprovedAmount(amount)
                            }
                        }
                    }
                }
                .padding()
                .background(palette.inputBackground)
                .cornerRadius(12)
                .padding(.top, -8)
            }
        }
    }

    // MARK: - Actions

    private func selectApprovedAmount(_ amount: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        amountText = "\(amount)"
        isTextFieldFocused = false
    }

    private func purchaseAmount() {
        guard canTip, let amount = amountValue else { return }

        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isTextFieldFocused = false

        guard let productID = TipTier.productID(for: amount) else { return }

        Task {
            await appState.supportManager.purchase(productID: productID)
            if appState.supportManager.purchaseError == nil {
                dismiss()
            }
        }
    }
}

// MARK: - Approved Amount Pill

struct ApprovedAmountPill: View {
    @Environment(\.themePalette) private var palette
    let amount: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("$\(amount)")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : palette.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(isSelected ? palette.accent : palette.cardBackground)
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.clear : palette.accent.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("$\(amount)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - Ask Prompt Sheet

struct AskPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette

    let onSupport: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            // Handle bar
            RoundedRectangle(cornerRadius: 2.5)
                .fill(palette.stroke)
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
                .foregroundColor(palette.textPrimary)

            // Body
            Text("If Sonidea helps you capture ideas, consider leaving a tip.")
                .font(.subheadline)
                .foregroundColor(palette.textSecondary)
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
                        .background(palette.accent)
                        .cornerRadius(12)
                }

                Button {
                    appState.supportManager.dismissAskPrompt()
                    dismiss()
                } label: {
                    Text("Not now")
                        .font(.subheadline)
                        .foregroundColor(palette.textSecondary)
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
