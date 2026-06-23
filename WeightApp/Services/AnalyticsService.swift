//
//  AnalyticsService.swift
//  WeightApp
//
//  Thin wrapper around Firebase Analytics for Google Ads conversion tracking.
//  Centralizes event names + parameter shapes so call sites stay clean and
//  schema doesn't drift.
//
//  Environment isolation strategy: production fires the standard Firebase
//  event names; staging suffixes them with `_staging`. This keeps Google Ads
//  conversion actions (which target the unsuffixed names) from ever counting
//  staging signups/purchases — the App-campaign Firebase flow doesn't expose
//  parameter-level filters, so name-level separation is the workaround.
//  The `environment` default parameter set in WeightAppApp.init() still rides
//  on every event for cross-reference in Firebase reports.
//

import Foundation
import FirebaseAnalytics
import StoreKit

enum AnalyticsService {

    /// True when running against the production backend / production build.
    private static var isProduction: Bool {
        APIConfig.environment == "production"
    }

    /// Returns the event name as-is on production, suffixed `_staging` otherwise.
    /// Production events keep Firebase's recognized standard names (which feed
    /// built-in funnels, retention reports, and Google Ads conversion-action
    /// suggestions); staging events land in separate custom-event buckets and
    /// stay out of those production-facing surfaces.
    private static func envName(_ baseName: String) -> String {
        isProduction ? baseName : "\(baseName)_staging"
    }

    /// New account created. Maps to Google Ads "sign_up" conversion action.
    /// `method` is "email" or "apple" depending on the auth path.
    static func logSignUp(userId: String, method: String = "email") {
        Analytics.logEvent(envName(AnalyticsEventSignUp), parameters: [
            AnalyticsParameterMethod: method,
            "user_id": userId,
        ])
    }

    /// Returning user logged in.
    static func logLogin(userId: String, method: String = "email") {
        Analytics.logEvent(envName(AnalyticsEventLogin), parameters: [
            AnalyticsParameterMethod: method,
            "user_id": userId,
        ])
    }

    /// Subscription purchase confirmed by StoreKit. Maps to Google Ads
    /// "purchase" conversion action. `product` is optional so the renewal
    /// path can still log even if the product object isn't readily available
    /// (price/currency will fall back to 0 / USD, which Google Ads can
    /// override with a default value if configured).
    static func logPurchase(transaction: Transaction, product: Product?) {
        let value = product.map { NSDecimalNumber(decimal: $0.price).doubleValue } ?? 0.0
        let currency = product?.priceFormatStyle.currencyCode ?? "USD"

        Analytics.logEvent(envName(AnalyticsEventPurchase), parameters: [
            AnalyticsParameterValue: value,
            AnalyticsParameterCurrency: currency,
            AnalyticsParameterTransactionID: String(transaction.id),
            "product_id": transaction.productID,
            "is_renewal": transaction.originalID != transaction.id,
        ])
    }

    /// User finished the 7-page onboarding flow. Custom event (not a Firebase
    /// standard event) — useful as a higher-funnel signal in Google Ads.
    static func logOnboardingComplete() {
        Analytics.logEvent(envName("onboarding_complete"), parameters: nil)
    }

    /// User started watching the onboarding tutorial video (tapped "Watch Now"
    /// or the poster area, opening the fullscreen player). Uses Firebase's
    /// standard `tutorial_begin` event name so Google Ads recognizes it as an
    /// engagement event if promoted to a conversion later.
    static func logTutorialBegin(resourceId: String) {
        Analytics.logEvent(envName(AnalyticsEventTutorialBegin), parameters: [
            "resource_id": resourceId,
        ])
    }

    /// User closed the tutorial player. `durationSeconds` is wall-clock time
    /// the player was open; `watchedToEnd` is true if duration covers the
    /// full video length (with a 1s slack for the swipe-down dismiss gesture).
    static func logTutorialEnded(resourceId: String, durationSeconds: Double, watchedToEnd: Bool) {
        Analytics.logEvent(envName("tutorial_ended"), parameters: [
            "resource_id": resourceId,
            "duration_seconds": durationSeconds,
            "watched_to_end": watchedToEnd,
        ])
    }

    /// User dismissed the tutorial popup without ever opening the player
    /// (tapped "Maybe later" or the X close button).
    static func logTutorialSkipped(resourceId: String) {
        Analytics.logEvent(envName("tutorial_skipped"), parameters: [
            "resource_id": resourceId,
        ])
    }
}
