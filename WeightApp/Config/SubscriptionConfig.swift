//
//  SubscriptionConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/4/26.
//

import Foundation
import SwiftUI
import StoreKit

enum SubscriptionConfig {
    // MARK: - Product IDs (configure in App Store Connect)
    static let monthlyProductId = "com.weightapp.premium.monthly.499"
    static let yearlyProductId = "com.weightapp.premium.yearly.3999"

    // MARK: - Display Prices
    //
    // FALLBACKS ONLY. Read prices through the resolvers below, never these constants directly:
    // they are US English literals, so on any other storefront they show the wrong currency AND
    // the wrong number, and an App Store Connect price change silently desyncs every screen
    // from what StoreKit will actually charge. They exist for the window before
    // `loadProducts()` returns, and for the case where it fails.
    static let monthlyDisplayPrice = "$4.99"
    static let yearlyDisplayPrice = "$39.99"
    static let yearlyPerMonthPrice = "$3.33"  // For "per month" display

    /// Localized yearly price, falling back to the constant until StoreKit has loaded.
    static func yearlyPrice(_ product: Product?) -> String {
        product?.displayPrice ?? yearlyDisplayPrice
    }

    /// Localized monthly price, same fallback.
    static func monthlyPrice(_ product: Product?) -> String {
        product?.displayPrice ?? monthlyDisplayPrice
    }

    /// The yearly plan expressed per month, formatted in the product's own currency.
    ///
    /// ROUNDED DOWN, deliberately: this number sits next to the real yearly price, so rounding
    /// up would advertise a monthly figure whose twelve-fold is more than we charge. $39.99/12
    /// is $3.3325 — down gives $3.33, up would give $3.34.
    ///
    /// `priceFormatStyle` comes from the product, so currency symbol, separator and placement
    /// all follow the storefront rather than the device locale.
    static func yearlyPerMonth(_ product: Product?) -> String {
        guard let product else { return yearlyPerMonthPrice }
        let perMonth = product.price / 12
        let rounded = NSDecimalNumber(decimal: perMonth)
            .rounding(accordingToBehavior: NSDecimalNumberHandler(
                roundingMode: .down, scale: 2,
                raiseOnExactness: false, raiseOnOverflow: false,
                raiseOnUnderflow: false, raiseOnDivideByZero: false))
        return (rounded as Decimal).formatted(product.priceFormatStyle)
    }

    // MARK: - Trial Configuration
    static let freeTrialDays = 7
    static let trialEligibleProduct = yearlyProductId  // Only yearly has trial

    // MARK: - URLs
    static var websiteBaseURL: String {
        APIConfig.environment == "production"
            ? "https://liftthebull.io"
            : "https://staging.liftthebull.io"
    }
    static var termsURL: URL { URL(string: "\(websiteBaseURL)/terms?embedded=1")! }
    static var privacyURL: URL { URL(string: "\(websiteBaseURL)/privacy?embedded=1")! }
    static var supportURL: URL { URL(string: "\(websiteBaseURL)/support?embedded=1")! }

    // MARK: - Marketing Copy
    static let upsellTitle = "Premium"
    static let upsellSubtitle = "Unlock the full power of your training"
    static let cancelAnytimeText = "Cancel anytime"
    static let bestValueBadge = "BEST VALUE"
    static let freeTrialBadge = "7-day free trial"

    // MARK: - Premium Feature Titles
    //
    // The carousel dispatches to its custom card views by title, and every lock state in
    // the app deep-links to a page by title (see `upsellPage(for:)`). Those were bare
    // string literals scattered across six files, which made the ORDER of the array below
    // load-bearing in places that never mentioned it. Named here so a retitle is one edit
    // and a typo is a compile error.
    //
    static let smartSessionsTitle = "Smart Sessions"
    static let balanceTitle = "Strength Balance Tracking"
    static let analyticsTitle = "Advanced Analytics"
    static let setPlanCatalogTitle = "Set Plan Catalog"
    static let progressCardTitle = "Progress Card"

    /// Where the paywall was opened from.
    ///
    /// Nine entry points, four of which open on page 0 — without this they are one undifferentiated
    /// bucket in Amplitude, and the post-onboarding presentation (seen by every new user, converting
    /// far lower) drowns the deliberate taps.
    enum UpsellSource: String {
        case postOnboarding = "post_onboarding"
        case moreTab = "more_tab"
        case sessionTab = "session_tab"
        case strengthInsight = "strength_insight"
        case lockedBalance = "locked_balance"
        case lockedAnalytics = "locked_analytics"
        case lockedProgressCard = "locked_progress_card"
        case lockedSetPlans = "locked_set_plans"
        case lockedE1RM = "locked_e1rm"
        case readyToLift = "ready_to_lift"
        case legacyDevPreview = "legacy_dev_preview"
        /// Opened from More -> Developer. Its own case so dev opens never land in the real
        /// funnel, the same reason `legacyDevPreview` exists.
        case firstWeekDevPreview = "first_week_dev_preview"
    }

    /// Carousel page for a feature, by title.
    ///
    /// Page index IS the array index — there is no longer an overview page in front of the
    /// features, so nothing needs a `+ 1`. Every call site used to add that offset itself,
    /// which is exactly the kind of arithmetic that goes stale silently when the carousel
    /// changes shape.
    ///
    /// Falls back to the first page rather than a hardcoded guess. An unknown title means
    /// someone renamed a feature without updating a caller; landing on the default page is
    /// wrong but harmless, where a stale index lands confidently on the wrong feature.
    static func upsellPage(for title: String) -> Int {
        premiumFeatures.firstIndex { $0.title == title } ?? 0
    }

    // MARK: - Premium Features (for carousel display)
    //
    // ORDER IS THE CAROUSEL ORDER, and index 0 is what the upsell opens on when nothing
    // more specific is requested.
    //
    // `description` and `color` are currently read by nothing — the cards use `icon`,
    // `title` and `bullets`. Left populated rather than removed because the tuple shape is
    // shared by all six entries and a partial one would not compile.
    static let premiumFeatures: [(icon: String, title: String, description: String, color: Color, bullets: [(icon: String, text: String, color: Color)])] = [
        // Bullet colours here are bespoke pastels rather than the `Color+Theme` set
        // intensity palette the other features reuse. They sit at 11pt against a dark card,
        // where the saturated originals vibrate; these are the muted equivalents.
        ("sparkles", smartSessionsTitle,
         "A session picked for today when you show up — the right lifts, the right set plans, shaped by how you are feeling.",
         .appAccent,
         [("sparkles", "Built when you show up", Color(red: 0xF0/255, green: 0xC0/255, blue: 0x5A/255)),        // #F0C05A
          ("bubble.left", "Takes how you feel today", Color(red: 0x5B/255, green: 0xC0/255, blue: 0xDE/255)),   // #5BC0DE
          ("checklist", "Picks lifts and set plans", Color(red: 0x7E/255, green: 0xC9/255, blue: 0x7E/255)),    // #7EC97E
          ("arrow.clockwise", "Re-roll or revise in a tap", Color(red: 0xB3/255, green: 0x9D/255, blue: 0xDB/255))]), // #B39DDB
        ("scale.3d", balanceTitle,
         "Continuous monitoring of your push/pull and upper/lower ratios so you can spot and correct imbalances early.",
         .setModerate,
         [("scale.3d", "Balance Assessments", .setEasy),
          ("arrow.left.arrow.right", "Push / Pull Ratios", .setModerate),
          ("arrow.up.arrow.down", "Upper / Lower Balance", .setHard),
          ("chart.line.uptrend.xyaxis", "Balance Over Time", .appAccent)]),
        ("chart.line.uptrend.xyaxis", analyticsTitle,
         "Track estimated 1RM trends, volume progression, and training frequency over time with detailed charts.",
         .setHard,
         [("trophy.fill", "Estimated 1RM Trends", .setPR),
          ("chart.bar.fill", "Volume Progression", .setEasy),
          ("calendar", "Frequency Analysis", .setModerate),
          ("flame.fill", "Set Intensity Tracking", .setHard)]),
        ("list.clipboard.fill", setPlanCatalogTitle,
         "Full access to the complete set plan library plus the ability to create and save your own custom plans.",
         .setNearMax,
         [("book.fill", "Full Plan Library", .setEasy),
          ("plus.rectangle.fill", "Create Custom Plans", .setPR),
          ("pencil", "Edit & Personalize", .setModerate),
          ("square.and.arrow.down", "Save & Reuse", .setHard)]),
        ("square.and.arrow.up.fill", progressCardTitle,
         "Generate a shareable visual progress card of your training — PRs, strength tiers, and progress at a glance.",
         .setPR,
         [])  // Progress Card uses its own specialized view
    ]
}
