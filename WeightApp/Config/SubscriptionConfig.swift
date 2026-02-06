//
//  SubscriptionConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation

enum SubscriptionConfig {
    // MARK: - Product IDs (configure in App Store Connect)
    static let monthlyProductId = "com.weightapp.premium.monthly"
    static let yearlyProductId = "com.weightapp.premium.yearly"

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
    static let upsellTitle = "Unlock Premium"
    static let upsellSubtitle = "Take your training to the next level"
    static let cancelAnytimeText = "Cancel anytime"
    static let bestValueBadge = "BEST VALUE"
    static let freeTrialBadge = "7-day free trial"

    // MARK: - Premium Features (for carousel display)
    static let premiumFeatures: [(icon: String, title: String, description: String)] = [
        ("chart.line.uptrend.xyaxis", "Advanced Analytics", "Track 1RM progression and volume over time"),
        ("clock.arrow.circlepath", "Unlimited History", "Access your complete workout history"),
        ("square.and.arrow.up", "Export Data", "Export workouts to CSV or PDF"),
        ("bolt.fill", "Priority Sync", "Faster cloud synchronization"),
        ("paintpalette.fill", "Custom Themes", "Personalize your app appearance")
    ]
}
