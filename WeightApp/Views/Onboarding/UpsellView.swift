//
//  UpsellView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import SwiftUI
import SwiftData
import StoreKit

struct UpsellView: View {
    let initialPage: Int
    let onComplete: (Bool) -> Void  // Bool indicates whether user subscribed

    init(initialPage: Int = 0, onComplete: @escaping (Bool) -> Void) {
        self.initialPage = initialPage
        self.onComplete = onComplete
        self._currentPage = State(initialValue: initialPage)
    }

    @Environment(\.modelContext) private var modelContext
    @StateObject private var purchaseService = PurchaseService.shared
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var currentPage: Int
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @Environment(\.openURL) private var openURL

    // Entrance animation states
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
    @State private var badgeGlow: Double = 0
    @State private var carouselOpacity: Double = 0
    @State private var pricingOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    private enum SubscriptionPlan {
        case monthly
        case yearly
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(white: 0.12), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Section
                headerSection
                    .padding(.top, 52)
                    .task {
                        await purchaseService.loadProducts()
                    }

                Spacer()
                    .frame(height: 20)

                // Benefits Carousel
                benefitsCarousel
                    .opacity(carouselOpacity)

                Spacer()
                    .frame(height: 20)

                // Pricing Section
                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(pricingOpacity)

                Spacer()
                    .frame(minHeight: 8)

                // Subscribe Button
                subscribeButton
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                    .opacity(ctaOpacity)

                // Plan-specific subtitle
                Text(selectedPlan == .yearly
                     ? "7 days free, then \(SubscriptionConfig.yearlyDisplayPrice)/year. Cancel anytime."
                     : "\(SubscriptionConfig.monthlyDisplayPrice)/month. Cancel anytime.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 16)
                    .opacity(ctaOpacity)

                // Footer Links
                footerLinks
                    .padding(.bottom, 16)
                    .opacity(ctaOpacity)
            }

            // X dismiss button (top-right overlay)
            dismissButton
                .opacity(ctaOpacity)
        }
        .onAppear {
            // 0.0s — Logo springs in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // 0.2s — Badge fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                titleOpacity = 1.0
            }

            // 0.5s — Badge glow pulses
            withAnimation(.easeInOut(duration: 1.2).delay(0.5).repeatForever(autoreverses: true)) {
                badgeGlow = 1.0
            }

            // 0.4s — Carousel container fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                carouselOpacity = 1.0
            }

            // 0.8s — Pricing section fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.8)) {
                pricingOpacity = 1.0
            }

            // 1.0s — Subscribe button + X fades in
            withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
                ctaOpacity = 1.0
            }
        }
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            onComplete(false)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
                .padding(14)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 8)
        .padding(.top, 24)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 10) {
            // App logo
            Image("LiftTheBullIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(Color.appLogoColor)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

            // "GO PREMIUM" badge
            Text("GO PREMIUM")
                .font(.system(size: 13, weight: .semibold))
                .tracking(3)
                .foregroundStyle(.white)
                .padding(.horizontal, 22)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.appAccent.opacity(badgeGlow * 0.3), radius: 10, x: 0, y: 0)
                .opacity(titleOpacity)
        }
    }

    // MARK: - Benefits Carousel

    private let totalPages = SubscriptionConfig.premiumFeatures.count + 1

    private var benefitsCarousel: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                OverviewFeatureCard()
                    .padding(.horizontal, 20)
                    .tag(0)

                ForEach(0..<SubscriptionConfig.premiumFeatures.count, id: \.self) { index in
                    let feature = SubscriptionConfig.premiumFeatures[index]
                    if feature.title == "Progress Card" {
                        ProgressCardFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index + 1)
                    } else {
                        FeatureCard(
                            icon: feature.icon,
                            title: feature.title,
                            description: feature.description,
                            accentColor: feature.color
                        )
                        .padding(.horizontal, 20)
                        .tag(index + 1)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 310)

            // Page indicators overlaid at the bottom of the cards
            HStack(spacing: 8) {
                ForEach(0..<totalPages, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 12)
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 16) {
            // Yearly plan with "7 DAYS FREE" notch
            VStack(alignment: .leading, spacing: 0) {
                // Notch tab — left-aligned
                Text("7 DAYS FREE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.appAccent)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    .padding(.leading, 24)

                // Yearly plan card
                PlanCard(
                    isSelected: selectedPlan == .yearly,
                    title: "Yearly",
                    price: SubscriptionConfig.yearlyDisplayPrice,
                    priceSubtitle: "(\(SubscriptionConfig.yearlyPerMonthPrice)/mo)",
                    badge: SubscriptionConfig.bestValueBadge,
                    onTap: { selectedPlan = .yearly }
                )
            }

            // Monthly plan
            PlanCard(
                isSelected: selectedPlan == .monthly,
                title: "Monthly",
                price: SubscriptionConfig.monthlyDisplayPrice,
                priceSubtitle: nil,
                badge: nil,
                onTap: { selectedPlan = .monthly }
            )
        }
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await handlePurchase()
                }
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Text(selectedPlan == .yearly ? "Start Free Trial" : "Subscribe Now")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .padding(.horizontal, 32)

            if let errorMessage {
                Text(errorMessage)
                    .font(.inter(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private func handlePurchase() async {
        let product: Product?
        switch selectedPlan {
        case .monthly:
            product = purchaseService.monthlyProduct
        case .yearly:
            product = purchaseService.yearlyProduct
        }

        guard let product else {
            errorMessage = "Product not available. Please try again."
            return
        }

        isProcessing = true
        errorMessage = nil

        do {
            let userId = KeychainService.shared.getUserId()
            let transaction = try await purchaseService.purchase(product, userId: userId)

            guard let transaction else {
                // User cancelled — not an error
                isProcessing = false
                return
            }

            // Send transaction to backend
            let originalId = String(transaction.originalID)
            let response = try await EntitlementsService.shared.processTransactions(
                originalTransactionIds: [originalId]
            )

            // Update local premium status
            await EntitlementsService.shared.updateLocalEntitlements(
                from: response,
                context: modelContext
            )

            isProcessing = false
            onComplete(true)
        } catch {
            isProcessing = false
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: 16) {
            Button("Terms and Conditions") {
                openURL(SubscriptionConfig.termsURL)
            }
            .font(.inter(size: 12))
            .foregroundStyle(.white.opacity(0.5))

            Text("|")
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))

            Button("Privacy Policy") {
                openURL(SubscriptionConfig.privacyURL)
            }
            .font(.inter(size: 12))
            .foregroundStyle(.white.opacity(0.5))
        }
    }
}

// MARK: - Overview Feature Card

private struct OverviewFeatureCard: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("WHAT YOU GET")
                .font(.bebasNeue(size: 18))
                .foregroundStyle(Color.appAccent)
                .tracking(2)

            Rectangle()
                .fill(Color.appAccent)
                .frame(width: 40, height: 2)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(SubscriptionConfig.premiumFeatures, id: \.title) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(feature.color)
                            .frame(width: 20, height: 20)
                            .background(
                                Circle()
                                    .fill(feature.color.opacity(0.15))
                            )

                        Text(feature.title)
                            .font(.interSemiBold(size: 14))
                            .foregroundStyle(.white)
                    }
                }
            }

            Spacer()

            HStack(spacing: 4) {
                Text("Swipe to learn more")
                    .font(.inter(size: 11))
                    .foregroundStyle(.white.opacity(0.35))
                Image(systemName: "chevron.right")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 276)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.appAccent.opacity(0.15), lineWidth: 1)
                )
        )
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let accentColor: Color

    var body: some View {
        VStack(spacing: 14) {
            // Icon with colored circle background and glow
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(accentColor)
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .fill(accentColor.opacity(0.18))
                )
                .shadow(color: accentColor.opacity(0.3), radius: 12, x: 0, y: 4)

            Text(title)
                .font(.interSemiBold(size: 16))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.inter(size: 13))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .lineLimit(4)

            Spacer()

            // Accent divider
            Rectangle()
                .fill(accentColor.opacity(0.25))
                .frame(height: 1)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 276)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(
                    LinearGradient(
                        colors: [accentColor.opacity(0.08), Color(white: 0.10)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Progress Card Feature Card

private struct ProgressCardFeatureCard: View {
    private let accentColor: Color = .setPR

    var body: some View {
        HStack(spacing: 0) {
            // Left side — marketing text
            VStack(spacing: 0) {
                // Header block — icon, premium, progress card, divider
                // Pinned toward top, aligned with image top
                Spacer().frame(height: 28)

                Image(systemName: "square.and.arrow.up.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                Spacer().frame(height: 8)

                Text("PREMIUM")
                    .font(.inter(size: 9))
                    .tracking(3)
                    .foregroundStyle(accentColor.opacity(0.7))

                Text("Progress Card")
                    .font(.bebasNeue(size: 26))
                    .foregroundStyle(.white)

                Spacer().frame(height: 5)

                Rectangle()
                    .fill(accentColor)
                    .frame(width: 24, height: 2)

                // Bullet points — centered in remaining space
                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    featureItem(icon: "trophy.fill", text: "Personal Records", color: .setPR)
                    featureItem(icon: "chart.bar.fill", text: "Strength Tiers", color: .setEasy)
                    featureItem(icon: "flame.fill", text: "Intensity Breakdown", color: .setNearMax)
                    featureItem(icon: "figure.strengthtraining.traditional", text: "Volume & Frequency", color: .setModerate)
                    featureItem(icon: "square.and.arrow.up.fill", text: "Shareable Image", color: .setHard)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — progress card image in black container
            // Shadow/glow behind the entire container
            Image("IdealizedProgressCard")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 230)
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black)
                        .shadow(color: accentColor.opacity(0.2), radius: 16, x: -2, y: 0)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 276)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func featureItem(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.inter(size: 11))
                .foregroundStyle(.white.opacity(0.7))
        }
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let isSelected: Bool
    let title: String
    let price: String
    let priceSubtitle: String?
    let badge: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                Circle()
                    .strokeBorder(isSelected ? Color.appAccent : Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.appAccent : Color.clear)
                            .frame(width: 12, height: 12)
                    )

                // Price (prominent)
                Text(price)
                    .font(.bebasNeue(size: 22))
                    .foregroundStyle(.white)

                // Title + per-month subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.interSemiBold(size: 14))
                        .foregroundStyle(.white)

                    if let priceSubtitle {
                        Text(priceSubtitle)
                            .font(.inter(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Badge (right side)
                if let badge {
                    Text(badge)
                        .font(.interSemiBold(size: 9))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.appAccent)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
