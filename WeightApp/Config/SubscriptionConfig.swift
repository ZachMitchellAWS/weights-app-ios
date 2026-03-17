//
//  SubscriptionConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import SwiftUI

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
    static let premiumFeatures: [(icon: String, title: String, description: String, color: Color)] = [
        ("text.book.closed.fill", "Weekly Progress Narratives",
         "Get a personalized written summary of your training week — what improved, what to focus on, and how you're trending.",
         .setEasy),
        ("scale.3d", "Strength Balance Tracking",
         "Continuous monitoring of your push/pull and upper/lower ratios so you can spot and correct imbalances early.",
         .setModerate),
        ("chart.line.uptrend.xyaxis", "Advanced Analytics",
         "Track estimated 1RM trends, volume progression, and training frequency over time with detailed charts.",
         .setHard),
        ("list.clipboard.fill", "Set Plan Catalog & Custom Plans",
         "Full access to the complete set plan library plus the ability to create and save your own custom plans.",
         .setNearMax),
        ("square.and.arrow.up.fill", "Training Report Card",
         "Generate a shareable visual report card of your training — PRs, consistency, balance, and progress at a glance.",
         .setPR)
    ]
}
