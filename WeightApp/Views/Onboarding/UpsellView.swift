//
//  UpsellView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import SwiftUI

struct UpsellView: View {
    let onComplete: (Bool) -> Void  // Bool indicates whether user subscribed

    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isProcessing = false

    private enum SubscriptionPlan {
        case monthly
        case yearly
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(white: 0.18), Color(white: 0.10)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header Section
                headerSection
                    .padding(.top, 60)

                Spacer()
                    .frame(height: 32)

                // Benefits Carousel
                benefitsCarousel
                    .padding(.horizontal, 24)

                Spacer()
                    .frame(height: 32)

                // Pricing Section
                pricingSection
                    .padding(.horizontal, 24)

                Spacer()

                // Subscribe Button
                subscribeButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)

                // Cancel anytime text
                Text(SubscriptionConfig.cancelAnytimeText)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
                    .padding(.bottom, 16)

                // Footer Links
                footerLinks
                    .padding(.bottom, 16)

                // Skip option
                skipButton
                    .padding(.bottom, 50)
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            // Decorative icon
            Image(systemName: "crown.fill")
                .font(.system(size: 48))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appAccent, Color.appAccent.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .shadow(color: Color.appAccent.opacity(0.5), radius: 10, x: 0, y: 5)

            Text(SubscriptionConfig.upsellTitle)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            Text(SubscriptionConfig.upsellSubtitle)
                .font(.body)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
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
                        description: feature.description
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
        Button {
            // TODO: Implement actual purchase via PurchaseService
            isProcessing = true
            // Simulate processing
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                isProcessing = false
                onComplete(true)
            }
        } label: {
            HStack {
                if isProcessing {
                    ProgressView()
                        .tint(.black)
                } else {
                    Text("Subscribe Now")
                        .font(.body.weight(.semibold))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(Color.appAccent)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: 16) {
            Link("Terms of Service", destination: SubscriptionConfig.termsOfServiceURL)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))

            Text("|")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.3))

            Link("Privacy Policy", destination: SubscriptionConfig.privacyPolicyURL)
                .font(.caption)
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
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.6))
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
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

    @State private var isVisible = false

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundStyle(Color.appAccent)

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            Text(description)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .frame(width: 140, height: 150)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .scaleEffect(isVisible ? 1.0 : 0.95)
        .opacity(isVisible ? 1.0 : 0.7)
        .onAppear {
            withAnimation(.easeOut(duration: 0.4)) {
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
                            .font(.caption2.weight(.bold))
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
                        .strokeBorder(isSelected ? Color.appAccent : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 24, height: 24)
                        .overlay(
                            Circle()
                                .fill(isSelected ? Color.appAccent : Color.clear)
                                .frame(width: 14, height: 14)
                        )
                }

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.white)

                    Text(price)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)

                    if let priceSubtitle = priceSubtitle {
                        Text(priceSubtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                if let trialText = trialText {
                    Text(trialText)
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(white: 0.14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
