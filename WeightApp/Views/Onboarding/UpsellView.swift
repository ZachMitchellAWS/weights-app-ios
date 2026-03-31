//
//  UpsellView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import SwiftUI
import SwiftData
import StoreKit
import Sentry

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
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var currentPage: Int
    @State private var safariURL: URL?

    // Entrance animation states
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
                // Header — icon + TRAIN SMARTER + badge
                headerSection
                    .padding(.top, 66)
                    .task {
                        await purchaseService.loadProducts()
                    }

                Spacer()
                    .frame(height: 12)

                // Benefits Carousel
                benefitsCarousel
                    .opacity(carouselOpacity)

                Spacer()
                    .frame(height: 14)

                // Pricing Section
                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(pricingOpacity)

                Spacer()
                    .frame(height: 16)

                // Subscribe Button
                subscribeButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .opacity(ctaOpacity)

                // Plan-specific subtitle
                Text(selectedPlan == .yearly
                     ? "7 days free, then \(SubscriptionConfig.yearlyDisplayPrice)/year. Cancel anytime."
                     : "\(SubscriptionConfig.monthlyDisplayPrice)/month. Cancel anytime.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
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
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .onAppear {
            // 0.0s — Badge fades in
            withAnimation(.easeOut(duration: 0.4)) {
                titleOpacity = 1.0
            }

            // 0.2s — Badge glow pulses
            withAnimation(.easeInOut(duration: 1.2).delay(0.2).repeatForever(autoreverses: true)) {
                badgeGlow = 1.0
            }

            // 0.3s — Carousel container fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                carouselOpacity = 1.0
            }

            // 0.7s — Pricing section fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
                pricingOpacity = 1.0
            }

            // 0.9s — Subscribe button + X fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
                ctaOpacity = 1.0
            }
        }
    }

    // MARK: - Dismiss Button

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            // Unlock Your Strength
            HStack(spacing: 6) {
                Text("Unlock")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                Text("Your Strength")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(Color.appAccent)
            }

            // GO PREMIUM badge
            Text("GO PREMIUM")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.appAccent.opacity(badgeGlow * 0.3), radius: 10, x: 0, y: 0)
        }
        .opacity(titleOpacity)
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

    // MARK: - Benefits Carousel

    private let totalPages = SubscriptionConfig.premiumFeatures.count + 1

    private var benefitsCarousel: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                // Page 0: Overview
                overviewPage
                    .padding(.horizontal, 20)
                    .tag(0)

                // Pages 1–N: Individual feature cards
                ForEach(0..<SubscriptionConfig.premiumFeatures.count, id: \.self) { index in
                    let feature = SubscriptionConfig.premiumFeatures[index]
                    if feature.title == "Progress Card" {
                        ProgressCardFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index + 1)
                    } else if feature.title == "Weekly Insights" {
                        WeeklyInsightsFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index + 1)
                    } else {
                        PremiumFeatureCard(
                            icon: feature.icon,
                            title: feature.title,
                            bullets: feature.bullets
                        )
                        .padding(.horizontal, 20)
                        .tag(index + 1)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 350)

            // Page indicators + swipe hint overlaid at the bottom
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 4) {
                    Text("Swipe to explore")
                        .font(.inter(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .opacity(currentPage == totalPages - 1 ? 0 : 1)
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Overview Page (page 0 of carousel)

    private var overviewPage: some View {
        ZStack(alignment: .bottomTrailing) {
            // Dark background
            Color(white: 0.10)

            // Bull figure — amber, bottom-right, cropped at hips
            Image("PoseFromBehind")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(Color.appAccent)
                .frame(height: 260)
                .offset(x: 20, y: 30)

            // Scrolling feature column — spans full height
            HStack(spacing: 0) {
                ScrollingFeatureColumn(direction: .down)
                    .frame(width: 160)
                    .padding(.leading, 18)

                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 338)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
        )
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

        let purchaseCrumb = Breadcrumb(level: .info, category: "purchase")
        purchaseCrumb.message = "Purchase initiated: \(product.id)"
        SentrySDK.addBreadcrumb(purchaseCrumb)

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
            EntitlementsService.shared.updateLocalEntitlements(
                from: response,
                context: modelContext
            )

            isProcessing = false
            let successCrumb = Breadcrumb(level: .info, category: "purchase")
            successCrumb.message = "Subscription purchased: \(product.id)"
            SentrySDK.addBreadcrumb(successCrumb)
            onComplete(true)
        } catch {
            isProcessing = false
            if !(error is CancellationError) {
                errorMessage = error.localizedDescription
                SentrySDK.capture(error: error)
            }
        }
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: 0) {
            Button("Terms and Conditions") {
                safariURL = SubscriptionConfig.termsURL
            }
            .font(.inter(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text("|")
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 10)

            Button("Privacy Policy") {
                safariURL = SubscriptionConfig.privacyURL
            }
            .font(.inter(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - Premium Feature Card

private struct PremiumFeatureCard: View {
    let icon: String
    let title: String
    let bullets: [(icon: String, text: String, color: Color)]

    private let accentColor: Color = .appAccent

    var body: some View {
        HStack(spacing: 0) {
            // Left side — header unit + bullets
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                Spacer().frame(height: 8)

                Text("PREMIUM")
                    .font(.inter(size: 9))
                    .tracking(3)
                    .foregroundStyle(accentColor.opacity(0.7))

                Text(title)
                    .font(.bebasNeue(size: 26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 5)

                Rectangle()
                    .fill(accentColor)
                    .frame(width: 24, height: 2)

                Spacer().frame(height: 14)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(bullets.indices, id: \.self) { i in
                        featureItem(
                            icon: bullets[i].icon,
                            text: bullets[i].text,
                            color: bullets[i].color
                        )
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — placeholder for screenshot
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(white: 0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(accentColor.opacity(0.15), lineWidth: 1)
                )
                .frame(width: 130, height: 280)
                .shadow(color: accentColor.opacity(0.2), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
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

// MARK: - Weekly Insights Feature Card

private struct WeeklyInsightsFeatureCard: View {
    private let accentColor: Color = .appAccent
    private let feature = SubscriptionConfig.premiumFeatures[0]

    var body: some View {
        HStack(spacing: 0) {
            // Left side — header unit + bullets
            VStack(spacing: 0) {
                Spacer().frame(height: 16)

                Image(systemName: feature.icon)
                    .font(.system(size: 24))
                    .foregroundStyle(accentColor)
                    .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                Spacer().frame(height: 8)

                Text("PREMIUM")
                    .font(.inter(size: 9))
                    .tracking(3)
                    .foregroundStyle(accentColor.opacity(0.7))

                Text(feature.title)
                    .font(.bebasNeue(size: 26))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Spacer().frame(height: 5)

                Rectangle()
                    .fill(accentColor)
                    .frame(width: 24, height: 2)

                Spacer().frame(height: 14)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(feature.bullets.indices, id: \.self) { i in
                        HStack(spacing: 8) {
                            Image(systemName: feature.bullets[i].icon)
                                .font(.system(size: 11))
                                .foregroundStyle(feature.bullets[i].color)
                                .frame(width: 16)
                            Text(feature.bullets[i].text)
                                .font(.inter(size: 11))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — mini phone preview of insights tab
            miniInsightsPreview
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
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

    // Miniature representation of the insights tab
    private var miniInsightsPreview: some View {
        VStack(spacing: 0) {
            // Mini header
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 4))
                        .foregroundStyle(Color.appAccent)
                    Text("WEEKLY INSIGHTS")
                        .font(.system(size: 4, weight: .bold))
                        .foregroundStyle(.white)
                }
                Text("Mar 24 – Mar 30, 2026")
                    .font(.system(size: 3))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.top, 8)
            .padding(.bottom, 4)

            // Mini section cards
            VStack(spacing: 3) {
                ForEach(InsightSectionStyle.allCases) { style in
                    miniSectionCard(style: style)
                }
            }
            .padding(.horizontal, 4)

            Spacer()
        }
        .frame(width: 110, height: 280)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        )
    }

    private func miniSectionCard(style: InsightSectionStyle) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: style.icon)
                    .font(.system(size: 4))
                    .foregroundStyle(style.color)
                    .frame(width: 8, height: 8)
                    .background(style.color.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 2))

                Text(style.title)
                    .font(.system(size: 3.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))

                Spacer()
            }

            // Fake text lines
            VStack(alignment: .leading, spacing: 1.5) {
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1.5)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 1.5)
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color.white.opacity(0.08))
                    .frame(width: 60, height: 1.5)
            }
        }
        .padding(4)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(style.color)
                .frame(width: 1.5)
        }
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Progress Card Feature Card

private struct ProgressCardFeatureCard: View {
    private let accentColor: Color = .appAccent

    var body: some View {
        HStack(spacing: 0) {
            // Left side — marketing text
            VStack(spacing: 0) {
                // Header block — icon, premium, progress card, divider
                Spacer().frame(height: 16)

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

            // Right side — progress card image
            Image("IdealizedProgressCard")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .shadow(color: accentColor.opacity(0.25), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
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

// MARK: - Scrolling Feature Column

private struct ScrollingFeatureColumn: View {
    enum Direction { case up, down }
    let direction: Direction

    private let accentColor: Color = .appAccent
    private let features = SubscriptionConfig.premiumFeatures

    @State private var offset: CGFloat = 0

    private var itemHeight: CGFloat { 127 }
    private var totalHeight: CGFloat { itemHeight * CGFloat(features.count) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                ForEach(0..<features.count * 3, id: \.self) { i in
                    let feature = features[i % features.count]
                    miniFeatureUnit(icon: feature.icon, title: feature.title)
                }
            }
            .offset(y: direction == .up
                ? -totalHeight + offset
                : -(totalHeight * 2) + totalHeight - offset)
            .onAppear {
                withAnimation(
                    .linear(duration: Double(features.count) * 8)
                    .repeatForever(autoreverses: false)
                ) {
                    offset = totalHeight
                }
            }
        }
        .clipped()
    }

    private func miniFeatureUnit(icon: String, title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(accentColor)

            Text("PREMIUM")
                .font(.system(size: 9, weight: .medium))
                .tracking(2)
                .foregroundStyle(accentColor.opacity(0.7))

            Text(title)
                .font(.bebasNeue(size: 21))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(accentColor)
                .frame(width: 26, height: 2)
        }
        .frame(width: 145, height: 115)
    }
}
