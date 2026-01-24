//
//  TipJarView.swift
//  Sonidea
//
//  Full tip jar UI with tiers, story, roadmap, and supporter perks.
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

                    // Tip Tiers
                    tiersSection

                    // Custom Amount
                    customAmountButton

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

    // MARK: - Custom Amount Button (styled like tier cards)

    private var customAmountButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showCustomAmountSheet = true
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Other amount")
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
                PerkRow(icon: "person.2.fill", color: .purple, text: "Name on Supporters wall (optional)")
            }
            .padding()
            .background(palette.cardBackground)
            .cornerRadius(12)
        }
    }

    // MARK: - Roadmap Section

    private var roadmapSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What I'm building next")
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
        // Try to get the active window scene for the review request
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

                // Show actual price if available, fallback to display amount
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

// MARK: - Custom Amount Sheet (Any Amount with Slider Quick-Pick)

struct CustomAmountSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(\.themePalette) private var palette
    @FocusState private var isTextFieldFocused: Bool

    // The actual typed amount (can be any value >= 1)
    @State private var typedAmount: Int = 10
    @State private var textInput: String = "10"

    // Slider value (1-100 range, quick pick only)
    @State private var sliderValue: Double = 10

    // Whether to show the slider (hide for amounts > 100)
    private var showSlider: Bool {
        typedAmount <= 100
    }

    // For amounts 1-100, we support exact dollars. Above 100, we snap to nearest tier.
    private var actualChargeAmount: Int {
        TipTier.nearestSupportedAmount(to: typedAmount)
    }

    // Only show rounding notice for amounts > 100 that need snapping
    private var needsRoundingNotice: Bool {
        typedAmount > 100 && typedAmount != actualChargeAmount
    }

    private var displayPrice: String {
        appState.supportManager.priceForAmount(actualChargeAmount) ?? "$\(actualChargeAmount)"
    }

    private var isValidAmount: Bool {
        typedAmount >= 1
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Large amount display (shows what user typed - exact for $1-$100)
                    VStack(spacing: 6) {
                        Text("$\(typedAmount)")
                            .font(.system(size: 56, weight: .bold, design: .rounded))
                            .foregroundColor(palette.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.spring(response: 0.3), value: typedAmount)

                        if needsRoundingNotice && isValidAmount {
                            Text("Will charge $\(actualChargeAmount) (nearest available)")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .transition(.opacity)
                        }
                    }
                    .padding(.top, 8)
                    .animation(.easeInOut(duration: 0.2), value: needsRoundingNotice)

                    // Manual entry field (primary input)
                    HStack {
                        Text("$")
                            .font(.title2)
                            .foregroundColor(palette.textSecondary)

                        TextField("Amount", text: $textInput)
                            .font(.title2)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .foregroundColor(palette.textPrimary)
                            .frame(width: 100)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 14)
                            .background(palette.inputBackground)
                            .cornerRadius(10)
                            .focused($isTextFieldFocused)
                            .onChange(of: textInput) { _, newValue in
                                handleTextInput(newValue)
                            }
                            .accessibilityLabel("Enter tip amount")
                    }

                    // Quick pick chips
                    quickPickChips
                        .padding(.horizontal)

                    // Slider (only shown for amounts <= 100)
                    if showSlider {
                        VStack(spacing: 8) {
                            Text("Quick pick")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)

                            Slider(value: $sliderValue, in: 1...100, step: 1) {
                                Text("Amount")
                            } minimumValueLabel: {
                                Text("$1")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            } maximumValueLabel: {
                                Text("$100")
                                    .font(.caption)
                                    .foregroundColor(palette.textSecondary)
                            }
                            .tint(palette.accent)
                            .onChange(of: sliderValue) { _, newValue in
                                let intValue = Int(newValue)
                                typedAmount = intValue
                                textInput = "\(intValue)"
                            }
                            .accessibilityLabel("Tip amount slider")
                            .accessibilityValue("$\(Int(sliderValue))")
                        }
                        .padding(.horizontal)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Info note for amounts over $100
                    if !showSlider {
                        HStack(spacing: 8) {
                            Image(systemName: "info.circle")
                                .font(.caption)
                                .foregroundColor(palette.accent)
                            Text("Amounts over $100 will be rounded to the nearest available tier.")
                                .font(.caption)
                                .foregroundColor(palette.textSecondary)
                                .multilineTextAlignment(.leading)
                        }
                        .padding()
                        .background(palette.inputBackground)
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }

                    Spacer(minLength: 20)

                    // Buttons
                    VStack(spacing: 12) {
                        // Tip button (styled like tier buttons)
                        Button {
                            purchaseAmount()
                        } label: {
                            HStack {
                                if appState.supportManager.isPurchasing {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Tip \(displayPrice)")
                                        .font(.headline)
                                }
                            }
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                            .background(isValidAmount ? palette.accent : Color.gray)
                            .cornerRadius(12)
                        }
                        .disabled(!isValidAmount || appState.supportManager.isPurchasing)
                        .accessibilityLabel("Tip \(displayPrice)")

                        // Cancel button
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
                .padding(.top)
            }
            .background(palette.background)
            .navigationTitle("Other Amount")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .keyboard) {
                    Button("Done") {
                        isTextFieldFocused = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Quick Pick Chips

    private var quickPickChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(TipTier.quickPickAmounts, id: \.self) { amount in
                    QuickPickChip(
                        amount: amount,
                        isSelected: typedAmount == amount
                    ) {
                        selectQuickPick(amount)
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Actions

    private func handleTextInput(_ newValue: String) {
        // Sanitize input: only digits
        let filtered = newValue.filter { $0.isNumber }
        if filtered != newValue {
            textInput = filtered
        }

        // Parse value (no upper limit)
        if let value = Int(filtered), value >= 1 {
            typedAmount = value
            // Update slider if within range
            if value <= 100 {
                sliderValue = Double(value)
            }
        } else if filtered.isEmpty {
            typedAmount = 0 // Invalid state, button will be disabled
        }
    }

    private func selectQuickPick(_ amount: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        typedAmount = amount
        textInput = "\(amount)"
        if amount <= 100 {
            sliderValue = Double(amount)
        }
        isTextFieldFocused = false
    }

    private func purchaseAmount() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        isTextFieldFocused = false

        let productID = TipTier.productID(for: actualChargeAmount)

        Task {
            await appState.supportManager.purchase(productID: productID)
            if appState.supportManager.purchaseError == nil {
                dismiss()
            }
        }
    }
}

// MARK: - Quick Pick Chip

struct QuickPickChip: View {
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
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? palette.accent : palette.inputBackground)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
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
