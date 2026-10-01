//
//  AnalyticsService.swift
//  WeightApp
//
//  Thin wrapper around Firebase Analytics for Google Ads conversion tracking.
//  Centralizes event names + parameter shapes so call sites stay clean and
//  schema doesn't drift.
//
//  ENVIRONMENT ISOLATION. Firebase is not configured at all outside production
//  (`WeightAppApp.init()` gates it on `isEnabled`), so on staging every function here is a
//  no-op and nothing reaches Firebase.
//
//  That gate replaced the `_staging` suffixing below as the primary defence, because
//  suffixing could never cover the event that actually mattered. `first_open` — the metric
//  Google Ads optimises against — is emitted by the SDK itself, not logged by us, so
//  `envName()` never sees it. With one Firebase project and an empty `APP_BUNDLE_ID_SUFFIX`
//  in both xcconfigs, every staging install was counted as a production install.
//
//  The suffixing is KEPT anyway, as belt-and-braces: if anyone ever configures Firebase on
//  staging again, the events we log ourselves still land in separate buckets rather than
//  silently polluting live conversion actions. It is no longer the thing doing the work.
//

import Foundation
import FirebaseAnalytics
import StoreKit

enum AnalyticsService {

    /// True when running against the production backend / production build.
    private static var isProduction: Bool {
        APIConfig.environment == "production"
    }

    /// Whether Firebase is live at all this launch.
    ///
    /// Read by `WeightAppApp.init()` to decide whether to call `FirebaseApp.configure()`, and
    /// by every log function here to bail before touching the SDK. Both matter: the first
    /// suppresses the automatic events (`first_open`, `session_start`, `app_remove`), the
    /// second stops our own calls logging "Firebase not configured" errors on every action.
    static var isEnabled: Bool { isProduction }

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
        guard isEnabled else { return }
        Analytics.logEvent(envName(AnalyticsEventSignUp), parameters: [
            AnalyticsParameterMethod: method,
            "user_id": userId,
        ])
    }

    /// Returning user logged in.
    static func logLogin(userId: String, method: String = "email") {
        guard isEnabled else { return }
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
        guard isEnabled else { return }
        let value = product.map { NSDecimalNumber(decimal: $0.price).doubleValue } ?? 0.0
        let currency = product?.priceFormatStyle.currencyCode ?? "USD"

        Analytics.logEvent(envName(AnalyticsEventPurchase), parameters: [
            AnalyticsParameterValue: value,
            AnalyticsParameterCurrency: currency,
            AnalyticsParameterTransactionID: String(transaction.id),
            "product_id": transaction.productID,
            "is_renewal": transaction.originalID != transaction.id,
            // Google Ads cannot filter on this, but Firebase and the BigQuery export can, and
            // without it there is no way to separate a trial start from a monthly purchase
            // after the fact. Both are intended conversions here; only their value differs.
            "is_free_trial": transaction.offer?.paymentMode == .freeTrial,
        ])
    }

    /// User finished the 7-page onboarding flow. Custom event (not a Firebase
    /// standard event) — useful as a higher-funnel signal in Google Ads.
    static func logOnboardingComplete() {
        guard isEnabled else { return }
        Analytics.logEvent(envName("onboarding_complete"), parameters: nil)
    }

    /// User started watching the onboarding tutorial video (tapped "Watch Now"
    /// or the poster area, opening the fullscreen player). Uses Firebase's
    /// standard `tutorial_begin` event name so Google Ads recognizes it as an
    /// engagement event if promoted to a conversion later.
    static func logTutorialBegin(resourceId: String) {
        guard isEnabled else { return }
        Analytics.logEvent(envName(AnalyticsEventTutorialBegin), parameters: [
            "resource_id": resourceId,
        ])
    }

    /// User closed the tutorial player. `durationSeconds` is wall-clock time
    /// the player was open; `watchedToEnd` is true if duration covers the
    /// full video length (with a 1s slack for the swipe-down dismiss gesture).
    static func logTutorialEnded(resourceId: String, durationSeconds: Double, watchedToEnd: Bool) {
        guard isEnabled else { return }
        Analytics.logEvent(envName("tutorial_ended"), parameters: [
            "resource_id": resourceId,
            "duration_seconds": durationSeconds,
            "watched_to_end": watchedToEnd,
        ])
    }

    /// User dismissed the tutorial popup without ever opening the player
    /// (tapped "Maybe later" or the X close button).
    static func logTutorialSkipped(resourceId: String) {
        guard isEnabled else { return }
        Analytics.logEvent(envName("tutorial_skipped"), parameters: [
            "resource_id": resourceId,
        ])
    }
}
