//
//  SubscriptionConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation

enum SubscriptionConfig {
    // MARK: - Product IDs (configure in App Store Connect)
    static let monthlyProductId = "com.weightapp.premium.monthly.499"
    static let yearlyProductId = "com.weightapp.premium.yearly.3999"

    // MARK: - Display Prices (fallback when StoreKit unavailable)
    static let monthlyDisplayPrice = "$4.99"
    static let yearlyDisplayPrice = "$39.99"
    static let yearlyPerMonthPrice = "$3.33"  // For "per month" display

    // MARK: - Trial Configuration
    static let freeTrialDays = 7
    static let trialEligibleProduct = yearlyProductId  // Only yearly has trial

    // MARK: - URLs
    static let termsOfServiceURL = URL(string: "https://example.com/terms")!
    static let privacyPolicyURL = URL(string: "https://example.com/privacy")!

    // MARK: - Marketing Copy
    static let upsellTitle = "Go Premium"
    static let upsellSubtitle = "Unlock the full power of your training"
    static let cancelAnytimeText = "Cancel anytime"
    static let bestValueBadge = "BEST VALUE"
    static let freeTrialBadge = "7-day free trial"

    // MARK: - Premium Features (for carousel display)
    static let premiumFeatures: [(icon: String, title: String, description: String)] = [
        ("chart.line.uptrend.xyaxis", "Advanced Analytics", "Track 1RM trends, volume, and frequency over time"),
        ("clock.arrow.circlepath", "Unlimited History", "Access your complete workout history anytime"),
        ("lightbulb.fill", "Smart Suggestions", "Get weight and rep targets to beat your personal records"),
        ("icloud.fill", "Cloud Backup", "Keep your data safe and synced across devices"),
        ("books.vertical.fill", "Exercise Library", "Full access to all exercises and custom additions")
    ]
}
