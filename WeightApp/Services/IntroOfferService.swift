//
//  IntroOfferService.swift
//  WeightApp
//
//  The single answer to "what price and what trial copy should this user see right now".
//
//  WHY A SERVICE AND NOT A COMPUTED PROPERTY ON EACH PAYWALL. Two paywalls show pricing —
//  `IntroOfferPaywallView` (post-onboarding and the More tab) and `UpsellView` (every locked
//  feature) — and they must never disagree. A user who taps a locked widget and a user who opens
//  the More tab are the same user on the same clock; if the two screens computed the window
//  separately they would eventually drift, and the failure mode is showing one person two prices.
//
//  WHAT THE OFFER ACTUALLY IS. $59.99/year inside a 72-hour window, $89.99/year after it, and the
//  $59.99 is a rate the subscriber KEEPS — these are two distinct StoreKit products, not one
//  product with an introductory price, so whichever one they buy is what renews forever. The
//  struck-through $89.99 on the paywall is therefore "what a later arrival pays", not "what you
//  pay next year". Getting that backwards would be a refund request.
//
//  APPLE DOES NOT ENFORCE THE WINDOW. There is no StoreKit mechanism for a time-limited price:
//  introductory offers are evaluated purely on "has this customer had one in this subscription
//  group", and promotional offers are for existing or lapsed subscribers. The 72 hours exist only
//  because this service decides which product the paywall displays. That is why `.5999` must be
//  marked not-promoted in App Store Connect — a promoted IAP is a path around this file.
//

import Foundation
import StoreKit
import Sentry

/// Whether the introductory window is still open.
enum OfferState: Equatable {
    case active(deadline: Date)
    case expired

    var isActive: Bool {
        if case .active = self { return true }
        return false
    }

    var deadline: Date? {
        if case .active(let deadline) = self { return deadline }
        return nil
    }

    /// For the `offer_state` analytics property. Deliberately a short stable string rather than
    /// the enum name, so a rename in Swift cannot silently re-label historical rows.
    var analyticsValue: String { isActive ? "active" : "expired" }
}

/// Whether this customer can still take the 7-day free trial.
///
/// Per SUBSCRIPTION GROUP, not per product — Apple allows one introductory offer per customer per
/// group, so a trial taken on the legacy $39.99 product blocks it on both new yearly SKUs. That
/// is the desired behaviour and the reason this exists: until now "7 days free" was unconditional
/// hardcoded copy, so anyone who had already used their trial was promised it a second time.
enum TrialState: Equatable {
    case available
    case consumed

    var isAvailable: Bool { self == .available }
}

/// Everything a paywall needs to render its pricing block. Resolved once per presentation and
/// passed down, so no child view reaches for a global and no two children can disagree.
struct PricingContext: Equatable {
    let offer: OfferState
    let trial: TrialState

    /// The product the CTA will actually purchase. `.5999` while the window is open, `.8999`
    /// after it, or the legacy `.3999` if neither new SKU resolved — see `isLegacyFallback`.
    let yearly: Product?
    let monthly: Product?

    /// The struck-through comparison price: `.8999`'s localised `displayPrice`. Nil whenever
    /// there is nothing to compare against — window closed, or the standard SKU did not load.
    let strikePrice: String?

    /// True when the new SKUs could not be resolved and this is the pre-repricing product set.
    /// Paywalls must suppress ALL promotional chrome in this state: there is no offer, and a
    /// countdown over a $39.99 product would be a straightforwardly false claim.
    let isLegacyFallback: Bool

    // MARK: Display strings

    var yearlyPriceText: String { SubscriptionConfig.yearlyPrice(yearly) }
    var monthlyPriceText: String { SubscriptionConfig.monthlyPrice(monthly) }
    var yearlyPerMonthText: String { SubscriptionConfig.yearlyPerMonth(yearly) }

    /// Promotional chrome — countdown, strikethrough, the word "intro" — appears only here.
    /// Both conditions matter: an active window over fallback pricing is not an offer.
    var showsPromotion: Bool { offer.isActive && !isLegacyFallback }

    // MARK: Analytics

    /// Raw numbers, not a "promo"/"standard" label. A label goes ambiguous the next time prices
    /// move; 59.99 is self-describing forever and survives a repricing without a client release.
    var yearlyPriceValue: Double? { yearly.map { NSDecimalNumber(decimal: $0.price).doubleValue } }
    var monthlyPriceValue: Double? { monthly.map { NSDecimalNumber(decimal: $0.price).doubleValue } }
    var currencyCode: String {
        yearly?.priceFormatStyle.currencyCode ?? monthly?.priceFormatStyle.currencyCode ?? "USD"
    }
}

/// NOT `ObservableObject`, unlike `PurchaseService` and `EntitlementsService` beside it.
///
/// It publishes nothing and nothing observes it: both paywalls `await pricingContext(...)` once
/// and hold the result in their own `@State`, which is deliberate — re-resolving pricing
/// underneath a reader who is mid-decision would let the price change while they look at it.
/// Declaring the conformance anyway was a reflex copied from the services around it, and it does
/// not even compile without `import Combine`, since that is where `objectWillChange`'s default
/// implementation comes from. Adding Combine to satisfy a protocol nothing uses would have been
/// the wrong fix.
///
/// `@MainActor` is still needed: it reads `PurchaseService`, which is main-actor isolated.
@MainActor
final class IntroOfferService {
    static let shared = IntroOfferService()

    /// 72 hours. Long enough to survive a night's sleep and a skipped day, short enough that the
    /// hours column moves while the paywall is open.
    static let window: TimeInterval = 72 * 60 * 60

    /// A `UserDefaults` date the pre-repricing UI study wrote on first sighting of the paywall,
    /// and anchored its countdown to.
    ///
    /// NOTHING READS IT. It is named here only so the Developer menu's reset button can clear it
    /// off devices that ran that build. The real anchor is the account's creation date, which is
    /// deliberately not resettable — a device-local clock turns an introductory offer into a
    /// discount anyone can re-trigger by reinstalling, which is the bug that key represents.
    static let legacyFirstSeenKey = "introOfferPaywallFirstSeenAt"

    private init() {}

    // MARK: - Offer state

    /// Resolved from the account's creation date, which is the one clock the user cannot reset.
    ///
    /// WHY NOT A LOCAL FIRST-SEEN DATE, which is what the prototype used: a `UserDefaults` anchor
    /// is wiped by deleting the app, so "introductory offer" would become a 33% discount anyone
    /// could re-trigger by reinstalling. `createdDatetime` comes from the server, is written once
    /// at registration, and is identical on every device the account touches.
    ///
    /// COST OF THIS CHOICE, accepted knowingly: the clock starts at signup, so time spent in
    /// onboarding is spent out of the window. And every account that predates this release is
    /// already past its window — the promo is for new signups only.
    func offerState() -> OfferState {
        switch IntroOfferStateOverride.value {
        case .active:  return .active(deadline: Date().addingTimeInterval(Self.window))
        case .expired: return .expired
        case .default: break
        }

        // FAIL OPEN. A missing or unparseable anchor almost always means a brand-new account
        // whose first user-properties sync has not landed yet — `AuthResponse` does not carry
        // the date, so there is a real gap between registering and knowing when you registered.
        // Showing $89.99 on a new user's very first paywall is the worst outcome available here;
        // the worst case of failing open is that someone marginally outside the window gets
        // $59.99, which costs $30 once.
        guard let raw = KeychainService.shared.getCreatedDatetime(),
              let created = Date.fromServerString(raw) else {
            return .active(deadline: Date().addingTimeInterval(Self.window))
        }

        let deadline = created.addingTimeInterval(Self.window)
        return deadline > Date() ? .active(deadline: deadline) : .expired
    }

    // MARK: - Pricing

    /// The full context for one paywall presentation.
    ///
    /// Async because trial eligibility is a StoreKit round trip. Callers resolve this in `.task`
    /// and hold it for the life of the presentation rather than recomputing per body pass — the
    /// window boundary moving mid-presentation is handled by the countdown reaching zero, not by
    /// re-resolving pricing underneath the user.
    func pricingContext(purchaseService: PurchaseService) async -> PricingContext {
        let state = offerState()
        let trial = await trialState(purchaseService: purchaseService)

        let promo = purchaseService.yearlyPromoProduct
        let standard = purchaseService.yearlyStandardProduct
        let monthly = purchaseService.monthlyProduct

        // NEITHER NEW YEARLY SKU RESOLVED. `Product.products(for:)` does not error on a product
        // that is in "Missing Metadata" or still awaiting review — it simply omits it from the
        // array. So this is the state on any day the App Store Connect work is incomplete, and
        // the app has to stay sellable rather than show a dead CTA.
        if promo == nil && standard == nil {
            reportUnresolvedSKUs(purchaseService: purchaseService)
            return PricingContext(
                offer: .expired,
                trial: trial,
                yearly: purchaseService.legacyYearlyProduct,
                monthly: purchaseService.legacyMonthlyProduct ?? monthly,
                strikePrice: nil,
                isLegacyFallback: true
            )
        }

        // Falling back to whichever one DID load, rather than to legacy pricing: if only one of
        // the two new SKUs is live, selling at that price is closer to intent than reverting the
        // whole repricing. A nil `strikePrice` suppresses the strikethrough on its own.
        let sellable = state.isActive ? (promo ?? standard) : (standard ?? promo)

        return PricingContext(
            offer: state,
            trial: trial,
            yearly: sellable,
            monthly: monthly,
            // Only while the window is open, and only if there is a genuinely higher price to
            // show. Striking out a price equal to or below what we are charging is a lie that
            // would survive a casual glance.
            strikePrice: state.isActive ? higherPriceText(than: sellable, candidate: standard) : nil,
            isLegacyFallback: false
        )
    }

    // MARK: - Trial eligibility

    /// Read off the YEARLY product specifically.
    ///
    /// Monthly carries no introductory offer in App Store Connect, so asking it is meaningless —
    /// `isEligibleForIntroOffer` would still answer, because eligibility is a property of the
    /// subscription group rather than the product, but the answer would describe an offer that
    /// does not exist on the thing being asked about. Trial copy belongs on the yearly row only,
    /// which is already how every paywall behaves.
    private func trialState(purchaseService: PurchaseService) async -> TrialState {
        switch TrialStateOverride.value {
        case .available: return .available
        case .consumed:  return .consumed
        case .default:   break
        }

        let yearly = purchaseService.yearlyPromoProduct
            ?? purchaseService.yearlyStandardProduct
            ?? purchaseService.legacyYearlyProduct

        guard let subscription = yearly?.subscription else {
            // No product, so no eligibility answer. Claim the trial is available: the fallback
            // state already suppresses the offer, and promising a trial we then honour is a far
            // smaller error than withholding one the user is entitled to.
            return .available
        }
        return await subscription.isEligibleForIntroOffer ? .available : .consumed
    }

    // MARK: - Helpers

    /// `candidate`'s display price, but only when it is actually more expensive than what we are
    /// charging. Returns nil otherwise so the caller draws no strikethrough.
    private func higherPriceText(than sellable: Product?, candidate: Product?) -> String? {
        guard let sellable, let candidate, candidate.price > sellable.price else { return nil }
        return candidate.displayPrice
    }

    /// Reported ONCE per launch. The whole point of the legacy fallback is that the app keeps
    /// working, which also means nothing in the UI reveals that the repricing never went live —
    /// so without this the app could sell at $39.99 indefinitely while looking perfectly healthy.
    private var hasReportedUnresolvedSKUs = false
    private func reportUnresolvedSKUs(purchaseService: PurchaseService) {
        guard !hasReportedUnresolvedSKUs else { return }
        hasReportedUnresolvedSKUs = true

        let loaded = purchaseService.products.map(\.id).sorted().joined(separator: ", ")
        let crumb = Breadcrumb(level: .error, category: "pricing")
        crumb.message = "Intro-offer SKUs unresolved; fell back to legacy pricing. Loaded: [\(loaded)]"
        SentrySDK.addBreadcrumb(crumb)
        SentrySDK.capture(message: "Intro-offer SKUs unresolved — paywall fell back to legacy pricing") { scope in
            scope.setLevel(.error)
            scope.setContext(value: [
                "loadedProductIds": loaded,
                "expectedPromo": SubscriptionConfig.yearlyPromoProductId,
                "expectedStandard": SubscriptionConfig.yearlyStandardProductId,
            ], key: "pricing")
        }
    }
}
