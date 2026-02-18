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
    let onComplete: (Bool) -> Void  // Bool indicates whether user subscribed

    @Environment(\.modelContext) private var modelContext
    @StateObject private var purchaseService = PurchaseService.shared
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isProcessing = false
    @State private var errorMessage: String?

    // Entrance animation states
    @State private var logoScale: CGFloat = 0.5
    @State private var logoOpacity: Double = 0
    @State private var titleOpacity: Double = 0
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
                    .padding(.top, 60)
                    .task {
                        await purchaseService.loadProducts()
                    }

                Spacer()
                    .frame(height: 28)

                // Benefits Carousel
                benefitsCarousel
                    .padding(.horizontal, 20)
                    .opacity(carouselOpacity)

                Spacer()
                    .frame(height: 28)

                // Pricing Section
                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(pricingOpacity)

                Spacer()

                // Subscribe Button
                subscribeButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                    .opacity(ctaOpacity)

                // Cancel anytime text
                Text(SubscriptionConfig.cancelAnytimeText)
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 16)
                    .opacity(ctaOpacity)

                // Footer Links
                footerLinks
                    .padding(.bottom, 16)
                    .opacity(ctaOpacity)

                // Skip option
                skipButton
                    .padding(.bottom, 50)
                    .opacity(ctaOpacity)
            }
        }
        .onAppear {
            // 0.0s — Logo springs in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                logoScale = 1.0
                logoOpacity = 1.0
            }

            // 0.2s — Title fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.2)) {
                titleOpacity = 1.0
            }

            // 0.4s — Carousel container fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                carouselOpacity = 1.0
            }

            // 0.8s — Pricing section fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.8)) {
                pricingOpacity = 1.0
            }

            // 1.0s — Subscribe button fades in
            withAnimation(.easeOut(duration: 0.4).delay(1.0)) {
                ctaOpacity = 1.0
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // App logo
            Image("LiftTheBullIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundStyle(Color.appLogoColor)
                .scaleEffect(logoScale)
                .opacity(logoOpacity)

            VStack(spacing: 4) {
                Text(SubscriptionConfig.upsellTitle)
                    .font(.bebasNeue(size: 36))
                    .foregroundStyle(.white)

                Text(SubscriptionConfig.upsellSubtitle)
                    .font(.inter(size: 15))
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(titleOpacity)
        }
    }

    // MARK: - Benefits Carousel

    private var benefitsCarousel: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(0..<SubscriptionConfig.premiumFeatures.count, id: \.self) { index in
                    let feature = SubscriptionConfig.premiumFeatures[index]
                    FeatureCard(
                        icon: feature.icon,
                        title: feature.title,
                        description: feature.description,
                        animationDelay: 0.6 + Double(index) * 0.1
                    )
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 12) {
            // Yearly plan (emphasized)
            PlanCard(
                isSelected: selectedPlan == .yearly,
                badge: SubscriptionConfig.bestValueBadge,
                title: "Yearly",
                price: SubscriptionConfig.yearlyDisplayPrice,
                priceSubtitle: "(\(SubscriptionConfig.yearlyPerMonthPrice)/month)",
                trialText: SubscriptionConfig.freeTrialBadge,
                onTap: { selectedPlan = .yearly }
            )

            // Monthly plan
            PlanCard(
                isSelected: selectedPlan == .monthly,
                badge: nil,
                title: "Monthly",
                price: SubscriptionConfig.monthlyDisplayPrice,
                priceSubtitle: nil,
                trialText: nil,
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
                        Text("Subscribe Now")
                            .font(.interSemiBold(size: 14))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.appAccent)
                .cornerRadius(10)
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
            await EntitlementsService.shared.updateLocalEntitlement(
                from: response,
                transactionId: originalId,
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
            Link("Terms of Service", destination: SubscriptionConfig.termsOfServiceURL)
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))

            Text("|")
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))

            Link("Privacy Policy", destination: SubscriptionConfig.privacyPolicyURL)
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Skip Button

    private var skipButton: some View {
        Button {
            onComplete(false)
        } label: {
            HStack(spacing: 4) {
                Text("Continue with Free")
                    .font(.inter(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }
}

// MARK: - Feature Card

private struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let animationDelay: Double

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(Color.appAccent)

            Text(title)
                .font(.interSemiBold(size: 13))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.inter(size: 11))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(width: 130, height: 140)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .scaleEffect(isVisible ? 1.0 : 0.9)
        .opacity(isVisible ? 1.0 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(animationDelay)) {
                isVisible = true
            }
        }
    }
}

// MARK: - Plan Card

private struct PlanCard: View {
    let isSelected: Bool
    let badge: String?
    let title: String
    let price: String
    let priceSubtitle: String?
    let trialText: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    // Badge (if any)
                    if let badge = badge {
                        Text(badge)
                            .font(.interSemiBold(size: 10))
                            .foregroundStyle(.black)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.appAccent)
                            )
                    }

                    Spacer()

                    // Selection indicator
                    Circle()
                        .strokeBorder(isSelected ? Color.appAccent : Color.white.opacity(0.5), lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .fill(isSelected ? Color.appAccent : Color.clear)
                                .frame(width: 14, height: 14)
                        )
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.interSemiBold(size: 17))
                        .foregroundStyle(.white)

                    Text(price)
                        .font(.bebasNeue(size: 24))
                        .foregroundStyle(.white)

                    if let priceSubtitle = priceSubtitle {
                        Text(priceSubtitle)
                            .font(.inter(size: 12))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if let trialText = trialText {
                    Text(trialText)
                        .font(.inter(size: 12))
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
