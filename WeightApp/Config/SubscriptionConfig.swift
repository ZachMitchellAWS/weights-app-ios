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
    //
    // THE PRICE IS IN THE IDENTIFIER. An established convention here, not an accident — the
    // previous repricing went from `...premium.yearly` to `...premium.yearly.3999` rather than
    // changing a price in place, which is what let existing subscribers keep paying the old rate
    // forever with no Apple consent flow. Same approach again.
    //
    // TWO YEARLY SKUS, ONE SUBSCRIPTION GROUP. `.5999` is sold while the 72-hour window is open
    // and `.8999` after it. They are separate products rather than one product with an
    // introductory price because the $59.99 is meant to be a rate the subscriber KEEPS; an
    // introductory offer would revert to the standard price at the first renewal. Consequence
    // worth knowing: every grant in DynamoDB keeps its product id forever, so cohort analysis
    // now spans three yearly strings.
    static let yearlyPromoProductId = "com.weightapp.premium.yearly.5999"
    static let yearlyStandardProductId = "com.weightapp.premium.yearly.8999"
    static let monthlyProductId = "com.weightapp.premium.monthly.1299"

    // LEGACY, STILL LIVE. Not displayed anywhere and not purchasable from any paywall, but they
    // must stay loaded for two reasons:
    //
    //   1. Renewals. `PurchaseService.logPurchaseIfNew` resolves a transaction's price by
    //      matching its product id against the loaded products. Drop these and every renewal
    //      from the existing paid base reports `price: nil` to Amplitude — invisible until a
    //      renewal fires, which is exactly how it would ship broken.
    //   2. The fallback in `IntroOfferService.pricingContext`, for any day the new SKUs are not
    //      yet approved in App Store Connect.
    static let legacyMonthlyProductId = "com.weightapp.premium.monthly.499"
    static let legacyYearlyProductId = "com.weightapp.premium.yearly.3999"

    /// Everything `Product.products(for:)` should request, new and legacy.
    static let allProductIds = [
        yearlyPromoProductId,
        yearlyStandardProductId,
        monthlyProductId,
        legacyMonthlyProductId,
        legacyYearlyProductId,
    ]

    // MARK: - Display Prices
    //
    // FALLBACKS ONLY. Read prices through the resolvers below, never these constants directly:
    // they are US English literals, so on any other storefront they show the wrong currency AND
    // the wrong number, and an App Store Connect price change silently desyncs every screen
    // from what StoreKit will actually charge. They exist for the window before
    // `loadProducts()` returns, and for the case where it fails.
    static let monthlyDisplayPrice = "$12.99"
    static let yearlyDisplayPrice = "$59.99"
    static let yearlyStandardDisplayPrice = "$89.99"
    /// $59.99 / 12 is $4.9991, and `yearlyPerMonth` rounds DOWN — so $4.99, not $5.00.
    static let yearlyPerMonthPrice = "$4.99"

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
    /// up would advertise a monthly figure whose twelve-fold is more than we charge. $59.99/12
    /// is $4.9991 — down gives $4.99, up would give $5.00 and imply $60.00/year.
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
    //
    // Both of these were dead constants until `IntroOfferService` — nothing read either, and
    // "7 days free" was hardcoded in three paywalls independently.
    static let freeTrialDays = 7

    /// Monthly carries no introductory offer in App Store Connect, so eligibility is read off a
    /// yearly product and trial copy appears on the yearly row only.
    ///
    /// Note that Apple evaluates eligibility per SUBSCRIPTION GROUP, not per product: a trial
    /// taken on the legacy `.3999` blocks it on both new yearly SKUs, and a full-price monthly
    /// purchase does NOT consume it. See `IntroOfferService.trialState`.
    static let trialEligibleProductIds = [yearlyPromoProductId, yearlyStandardProductId]

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
        /// Opened from More -> Developer. Separate from `firstWeekDevPreview` so the intro-offer
        /// study and the shipping first-week paywall never share rows.
        case introOfferDevPreview = "intro_offer_dev_preview"
        /// Auto-raised ten seconds after the starting strength tier unlocks, from wherever the
        /// user happens to be. Its own case because it is the only unprompted presentation in
        /// the app — every other source is a tap — so its conversion rate is not comparable to
        /// any of them and must never be averaged in.
        case tierUnlock = "tier_unlock"
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
