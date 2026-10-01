//
//  FirstWeekPaywallView.swift
//  WeightApp
//
//  A COPY of `UpsellView`, taken 2026-09-21 as the starting point for a paywall aimed at users
//  in their first week. Nothing presents it yet — it is wired to no call site until the design
//  diverges enough to be worth showing.
//
//  WHY A COPY RATHER THAN A PARAMETER. `UpsellView` is the paywall every conversion number to
//  date was measured against, reached from onboarding, the Session tab and every locked
//  feature. Editing it in place to serve a second audience risks the one screen that is known
//  to work; a copy lets this one change freely and be deleted cheaply if it does not earn its
//  place. That is the same reasoning that kept `LegacyUpsellView` around.
//
//  WHAT IS SHARED, AND WHAT IS NOT
//
//  * `PlanCard` is NOT duplicated. It is the one non-private type in the original and is
//    already shared with `LegacyUpsellView`; copying it would be a duplicate declaration.
//    Changing it therefore changes all three paywalls — fork it before restyling.
//  * The page types are renamed with an `FW` prefix. They are `private`, so they would not
//    collide, but two identically-named views across two files makes traces and jump-to-
//    definition ambiguous exactly when something is wrong.
//  * `SubscriptionConfig.premiumFeatures`, the pricing and the purchase flow are shared as-is.
//    A first-week-specific offer would need its own product ids, which do not exist yet.
//
//  The original header follows, since every design decision it records still applies here.
//
//
//  The paywall. Presented after onboarding, from the Session tab, and from every locked feature.
//
//  Promoted from an R&D experiment. The design it replaced is kept as `LegacyUpsellView` — that
//  is the layout every conversion number to date was measured against, so it is the only honest
//  comparison if this one underperforms.
//
//  WHAT IT CHANGED FROM THAT DESIGN, AND WHY
//
//  1. No fixed header. The old paywall stacked "Unlock Your Strength" and a GO PREMIUM
//     badge above a carousel whose pages carry their OWN eyebrow and title — two headers for
//     one screen, with the real content squeezed into what was left. The page titles win,
//     because they are the ones that change as you swipe.
//
//  2. No X. Dismissal moves to a quiet "Not now" under the CTA, where it reads as the second
//     option rather than an escape hatch in the corner — and it costs no vertical space at
//     the top, which is the whole point.
//
//  3. The carousel absorbs everything 1 and 2 freed, taking `maxHeight: .infinity` while the
//     pricing block below stays its natural size. Where the carousel ends is wherever the
//     fixed furniture below it begins.
//
//  4. No screenshot. The shipping cards show a `Display*Card` JPEG exported from a developer
//     menu — but those exports were always SwiftUI views themselves, so the round trip through
//     an image bought nothing and cost sharpness, a fixed aspect, and a manual re-export
//     whenever the copy changed. The Smart Sessions page here draws live at whatever size the
//     carousel gives it.
//

import SwiftUI
import SwiftData
import StoreKit
import Sentry

struct FirstWeekPaywallView: View {
    /// Which carousel page to open on. Index into `SubscriptionConfig.premiumFeatures`, so a
    /// lock state can land the user on the feature they just tapped; `SubscriptionConfig
    /// .upsellPage(for:)` resolves those by title. Defaults to 0 — Smart Sessions.
    /// Where this was presented from. Defaulted only so a forgotten call site is loud in the
    /// data ("unspecified") rather than silently pooled with a real source.
    let source: SubscriptionConfig.UpsellSource
    let onComplete: (Bool) -> Void

    /// No `initialPage`. `UpsellView` takes one so a locked feature can open its carousel on
    /// the matching page; this screen has no pages to land on.
    init(source: SubscriptionConfig.UpsellSource,
         onComplete: @escaping (Bool) -> Void) {
        self.source = source
        self.onComplete = onComplete
    }

    @Environment(\.modelContext) private var modelContext
    @StateObject private var purchaseService = PurchaseService.shared
    @State private var selectedPlan: Plan = .yearly
    @State private var isProcessing = false
    @State private var errorMessage: String?
    /// Sections that have already reported `Upsell Section Viewed`. Per presentation, so
    /// scrolling back up does not re-fire one.
    @State private var viewedSections: Set<FWSection> = []
    /// Furthest point reached, 0-100. Reported on dismiss and on a completed purchase.
    @State private var maxScrollDepth: Int = 0
    @State private var safariURL: URL?

    // Entrance stagger. Carried over from `LegacyUpsellView`, minus the two stages that animated
    // a title and a badge this design no longer has.
    //
    // It matters most where this screen is seen first — straight out of onboarding, where the
    // whole thing appearing at once lands as an ambush. Building it top-down over about a second
    // reads as the screen arriving rather than being thrown at you.
    /// When the paywall appeared, for `seconds_on_screen` on dismissal.
    @State private var shownAt = Date()

    /// Half-respecting Reduce Motion would be worse than ignoring it: the scroll sections
    /// would appear instantly while the pricing block below still faded in.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// One opacity per scroll section, driven from the root's `onAppear` — the same place and
    /// the same mechanism as `pricingOpacity` below.
    ///
    /// An earlier attempt put the animation in a `ViewModifier` with its own `@State` and its
    /// own `onAppear`. It did not animate: the modifier's first render and its `onAppear` land
    /// in the same pass, so there is no prior value for SwiftUI to interpolate from and the
    /// opacity simply snaps. Driving it from a root that has already rendered is what makes
    /// the transition real.
    @State private var sectionOpacity: [Double] = Array(repeating: 0, count: FWSection.allCases.count + 1)

    @State private var pricingOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    enum Plan { case monthly, yearly }

    /// Identifies this design in analytics. Every event fired from here carries it.
    ///
    /// Bumped to v2 when the timeline was restructured. Rows already written as
    /// `first_week_v1` are left alone — the cohort read compares the two, so rewriting
    /// history would erase the comparison.
    static let variant = "first_week_v2"

    /// Page margin. 24 to match `pricingSection` and `subscribeButton`, so the demo card's
    /// edges line up with the plan cards below it.
    private static let hMargin: CGFloat = 24

    /// Bottom fade over the scroll region. `fadeSolidAt` is the fraction at which the gradient
    /// reaches FULL background — everything past it is a flat band sitting directly above the
    /// "7 DAYS FREE" badge. Raise it to bring content visually closer to the badge, lower it
    /// for more separation. 0.92 of 30pt leaves ~2.5pt of solid.
    private static let fadeHeight: CGFloat = 30
    private static let fadeSolidAt: CGFloat = 0.92

    var body: some View {
        ZStack {
            // Flat, not the shipping paywall's top-down gradient. The gradient reads as a
            // vignette behind a header that no longer exists, and it puts the lightest part of
            // the screen where there is now only the carousel.
            Color(white: 0x0A/255.0)   // #0A0A0A
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Takes the slot the carousel had: `maxHeight: .infinity` against a purchase
                // block that stays its natural size. KEEPING that arrangement is what keeps the
                // block pixel-identical to the shipping paywall — it is not a `safeAreaInset`,
                // and converting it to one would move it.
                scrollRegion
                    .frame(maxHeight: .infinity)
                    .task {
                        // Not optional: without it `purchaseService.yearlyProduct` is nil and
                        // every tap on the CTA fails with "Product not available".
                        await purchaseService.loadProducts()
                    }

                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(pricingOpacity)

                Spacer().frame(height: 10)

                subscribeButton
                    .padding(.horizontal, 24)
                    .opacity(ctaOpacity)

                // Restates the guarantee at the moment of commitment, where the card itself is
                // three sections up and out of sight. A label, NOT a button — there is nothing
                // to navigate to, and making it tappable would promise detail that does not
                // exist.
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text(FWCopy.guaranteeLine)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(FWPalette.amberText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .opacity(ctaOpacity)

                // v2 drops "Reminder on day 5." — nothing on this screen promises a reminder
                // any more, so the day-5 notification can ship on its own schedule.
                Text(selectedPlan == .yearly
                     ? "7 days free, then \(yearlyPriceText)/year. Cancel anytime."
                     : "\(SubscriptionConfig.monthlyPrice(purchaseService.monthlyProduct))/month. Cancel anytime.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .opacity(ctaOpacity)

                // Replaces the X. The flanking rules do the work the padding used to: they
                // separate it from the CTA above and the legal text below without spending
                // vertical space, which the carousel needs more than this does. Both rules take
                // the same expansion, so they stay symmetrical at any width.
                // The visible row shrinks to 36 to buy back what the guarantee line costs, but
                // the TAP TARGET stays 44 — `contentShape` extends it invisibly past the text,
                // so the row reads tighter without becoming harder to hit.
                HStack(spacing: 12) {
                    rule
                    Button("Not now") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .disabled(isProcessing)
                    rule
                }
                .padding(.horizontal, 44)
                .frame(height: 36)
                .opacity(ctaOpacity)

                footerLinks
                    .padding(.bottom, 4)
                    .opacity(ctaOpacity)
            }
            .padding(.top, 8)
        }
        .sheet(item: $safariURL) { SafariView(url: $0).ignoresSafeArea() }
        .onAppear {
            shownAt = Date()
            purchaseService.setActivePaywall(variant: Self.variant, scrollDepth: 0)
            // `initialPage`/`initialFeature` are carousel concepts and this variant has no
            // carousel. Reported as what is actually on screen at offset 0 rather than left
            // blank, so the property keeps a consistent meaning across paywalls.
            AmplitudeService.shared.track(.premiumUpsellShown(
                source: source.rawValue,
                initialPage: 0,
                initialFeature: FWSection.firstWeek.rawValue,
                paywallVariant: Self.variant
            ))

            guard !reduceMotion else {
                sectionOpacity = Array(repeating: 1.0, count: sectionOpacity.count)
                pricingOpacity = 1.0
                ctaOpacity = 1.0
                return
            }

            // 0.00-0.28s — the scroll sections, 0.07s apart, so the pricing block at 0.35s
            // continues the same cascade rather than starting a second one.
            for index in sectionOpacity.indices {
                withAnimation(.easeOut(duration: 0.4).delay(Double(index) * 0.07)) {
                    sectionOpacity[index] = 1.0
                }
            }

            // 0.35s — pricing
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) {
                pricingOpacity = 1.0
            }

            // 0.55s — CTA, trial terms, "Not now" and the legal footer, as one group. Splitting
            // them further would draw the eye to the dismissal, which is not what should arrive
            // last on a paywall.
            withAnimation(.easeOut(duration: 0.4).delay(0.55)) {
                ctaOpacity = 1.0
            }
        }
    }

    // MARK: - Scroll region  (first_week_v1)

    /// Everything above the purchase block: one vertical scroll view, nothing tappable.
    ///
    /// Replaces the five-page horizontal carousel. The carousel showed five equal features and
    /// asked the reader to swipe through and decide; this tells one story in order — what the
    /// first week looks like, what happens if it does not work, what else is included, what it
    /// costs. The scroll indicator is deliberately left on: it is the cue that there is more.
    private var scrollRegion: some View {
        ScrollView(.vertical) {
            // A plain VStack, NOT a LazyVStack — every child is created up front, so each
            // one's `onAppear` fires immediately and the stagger is driven purely by the
            // delays. Switching this to lazy would make sections below the fold animate only
            // when scrolled to, which is a different effect entirely.
            VStack(spacing: 0) {
                FWHeader()
                    .opacity(sectionOpacity[0])

                FWTimeline(yearlyPrice: yearlyPriceText)
                    .padding(.top, 12)
                    .opacity(sectionOpacity[1])
                    .fwTrack(.firstWeek, seen: markSectionViewed)

                FWGuaranteeCard()
                    .padding(.top, 24)
                    .opacity(sectionOpacity[2])
                    .fwTrack(.guarantee, seen: markSectionViewed)

                FWPremiumStackList()
                    .padding(.top, 28)
                    .opacity(sectionOpacity[3])
                    .fwTrack(.everythingInPremium, seen: markSectionViewed)

                FWPriceAnchor(yearlyPrice: yearlyPriceText, perMonth: perMonthText)
                    .padding(.top, 28)
                    .opacity(sectionOpacity[4])
                    .fwTrack(.priceAnchor, seen: markSectionViewed)
            }
            .padding(.horizontal, Self.hMargin)
            .padding(.bottom, 28)
        }
        // Furthest point reached, as (offset + viewport) / content height. Reported on dismiss
        // and on a completed purchase, so a scroll that stopped at the guarantee is
        // distinguishable from one that read to the price.
        .onScrollGeometryChange(for: Double.self) { geo in
            let content = geo.contentSize.height
            guard content > 0 else { return 0 }
            return (geo.contentOffset.y + geo.containerSize.height) / content * 100
        } action: { _, pct in
            let depth = max(maxScrollDepth, min(100, max(0, Int(pct.rounded()))))
            guard depth != maxScrollDepth else { return }
            maxScrollDepth = depth
            // Mirrored onto PurchaseService because `purchaseCompleted` is fired from there,
            // after this view may already be gone.
            purchaseService.setActivePaywall(variant: Self.variant, scrollDepth: depth)
        }
        // The scroll view's own frame IS the area above the purchase block, so a 30pt fade
        // pinned to its bottom edge sits exactly where content disappears. Non-interactive: the
        // purchase block starts below it, and a fade that ate touches would be a dead strip.
        .overlay(alignment: .bottom) {
            // Three stops, not two. A plain clear->bg gradient only reaches FULL bg at its
            // very last pixel, so content stayed faintly visible right up against the
            // "7 DAYS FREE" badge below.
            //
            // But the solid band is the thing you SEE, and it reads as dead space between the
            // content and the badge rather than as separation. At 12pt it looked like a gap;
            // at ~2.5pt the fade appears to terminate right at the badge while still landing
            // on solid background before it. The scroll view's bottom edge already abuts the
            // badge — `pricingSection` follows it directly in a `VStack(spacing: 0)` — so this
            // gradient is the only thing controlling how close the content appears to come.
            LinearGradient(
                stops: [
                    .init(color: FWPalette.bg.opacity(0), location: 0.0),
                    .init(color: FWPalette.bg, location: Self.fadeSolidAt),
                    .init(color: FWPalette.bg, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)
            .allowsHitTesting(false)
        }
    }

    /// One `Upsell Section Viewed` per section per presentation.
    private func markSectionViewed(_ section: FWSection) {
        guard viewedSections.insert(section).inserted else { return }
        AmplitudeService.shared.track(.upsellSectionViewed(
            source: source.rawValue,
            section: section.rawValue,
            paywallVariant: Self.variant
        ))
    }

    /// Yearly price, from StoreKit when it has loaded.
    private var yearlyPriceText: String {
        SubscriptionConfig.yearlyPrice(purchaseService.yearlyProduct)
    }

    /// Per-month equivalent of the yearly plan. Must match what the plan card shows — it is the
    /// same helper, so it cannot drift.
    private var perMonthText: String {
        SubscriptionConfig.yearlyPerMonth(purchaseService.yearlyProduct)
    }


    // MARK: - Pricing (identical to the shipping paywall — not what this experiment varies)

    private var pricingSection: some View {
        // 12/10 rather than the shipping 16/14. Two plan cards is the one block on this screen
        // that can give up height without losing anything — the row is a radio button, a price
        // and a badge, and none of them needed 14pt of air. ~20pt reclaimed, spent on "Not now".
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text("7 DAYS FREE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.appAccent)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    .padding(.leading, 24)

                PlanCard(
                    isSelected: selectedPlan == .yearly,
                    title: "Yearly",
                    price: yearlyPriceText,
                    priceSubtitle: "(\(perMonthText)/mo)",
                    badge: SubscriptionConfig.bestValueBadge,
                    verticalPadding: 10,
                    onTap: { selectPlan(.yearly) }
                )
            }

            PlanCard(
                isSelected: selectedPlan == .monthly,
                title: "Monthly",
                price: SubscriptionConfig.monthlyPrice(purchaseService.monthlyProduct),
                priceSubtitle: nil,
                badge: nil,
                verticalPadding: 10,
                onTap: { selectPlan(.monthly) }
            )
        }
    }

    /// Only reports an actual change, so repeat taps on the already-selected card do not look
    /// like the user is deliberating.
    private func selectPlan(_ plan: Plan) {
        guard plan != selectedPlan else { return }
        selectedPlan = plan
        AmplitudeService.shared.track(.upsellPlanSelected(
            source: source.rawValue,
            plan: plan == .yearly ? "yearly" : "monthly"
        ))
    }

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                Task { await handlePurchase() }
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView().tint(.black)
                    } else {
                        Text(selectedPlan == .yearly ? "Start Free Trial" : "Subscribe Now")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(Color.appAccent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .disabled(isProcessing)
            .padding(.horizontal, 8)

            if let errorMessage {
                Text(errorMessage)
                    .font(.inter(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 1)
    }

    private var footerLinks: some View {
        HStack(spacing: 0) {
            Button("Terms and Conditions") { safariURL = SubscriptionConfig.termsURL }
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("|")
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 10)
            Button("Privacy Policy") { safariURL = SubscriptionConfig.privacyURL }
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func dismiss() {
        AmplitudeService.shared.track(.upsellDismissed(
            source: source.rawValue,
            feature: viewedSections.count >= FWSection.allCases.count
                ? FWSection.priceAnchor.rawValue
                : FWSection.firstWeek.rawValue,
            secondsOnScreen: Date().timeIntervalSince(shownAt),
            paywallVariant: Self.variant,
            maxScrollDepthPct: maxScrollDepth
        ))
        // Dismissed without buying — release the attribution so a later renewal is not tagged
        // with this paywall.
        purchaseService.clearActivePaywall()
        onComplete(false)
    }

    // MARK: - Purchase

    private func handlePurchase() async {
        let planName = selectedPlan == .yearly ? "yearly" : "monthly"
        let product = selectedPlan == .yearly ? purchaseService.yearlyProduct : purchaseService.monthlyProduct
        guard let product else {
            errorMessage = "Product not available. Please try again."
            AmplitudeService.shared.track(.purchaseAbandoned(
                productId: "unknown", plan: planName, reason: "product_unavailable"
            ))
            return
        }
        AmplitudeService.shared.track(.purchaseStarted(
            productId: product.id,
            plan: selectedPlan == .yearly ? "yearly" : "monthly",
            isFreeTrial: selectedPlan == .yearly
        ))

        isProcessing = true
        errorMessage = nil

        let purchaseCrumb = Breadcrumb(level: .info, category: "purchase")
        purchaseCrumb.message = "Purchase initiated: \(product.id)"
        SentrySDK.addBreadcrumb(purchaseCrumb)

        do {
            let userId = KeychainService.shared.getUserId()
            guard let transaction = try await purchaseService.purchase(product, userId: userId) else {
                // nil transaction = the user backed out of the StoreKit sheet. Not an error, but
                // it is the single largest drop between Started and Completed and was previously
                // indistinguishable from closing the app.
                isProcessing = false
                AmplitudeService.shared.track(.purchaseAbandoned(
                    productId: product.id, plan: planName, reason: "cancelled"
                ))
                return
            }
            let environment: String? = transaction.environment == .sandbox ? "Sandbox" : nil
            let response = try await EntitlementsService.shared.processTransactions(
                originalTransactionIds: [String(transaction.originalID)],
                environment: environment
            )
            EntitlementsService.shared.updateLocalEntitlements(from: response, context: modelContext)
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
                AmplitudeService.shared.track(.purchaseAbandoned(
                    productId: product.id, plan: planName, reason: "failed"
                ))
            }
        }
    }
}

// MARK: - Smart Sessions page

/// Palette for the effort squares ON THIS CARD ONLY.
///
/// A deliberate divergence from `ProgramEffort.color`, which the app uses and which this page
/// deliberately does not. Two reasons, both about a marketing surface rather than a product one:
///
///  1. Equal perceived brightness. The app's `hard` violet (#5B3BE8) has a relative luminance of
///     0.112 against green's 0.411 — nearly four times darker. In the app that is fine, because
///     the squares sit in a row you read one at a time. On a card meant to be scanned it reads as
///     a hole in the strip. Lifting it to #A78BFA (0.336) puts every non-gold square in a
///     0.320-0.411 band, so the row reads as one object.
///  2. Gold has to win. At #F0C05A (0.570) the progress square sits 1.39x above the brightest
///     square next to it, which is what makes it the thing the eye lands on inside the card —
///     and it is the only gold element in there.
///
/// The cost is real and worth stating: a viewer who subscribes and opens the Lift tab will see a
/// darker violet than the one advertised. Kept to one table so the divergence is visible in a
/// single place rather than smeared across the view.
private enum FWShowcaseEffort {
    static let gold = Color(red: 0xF0/255, green: 0xC0/255, blue: 0x5A/255)   // #F0C05A

    static func color(_ key: String) -> Color {
        switch key {
        case "easy":     return Color(red: 0x22/255, green: 0xC5/255, blue: 0x5E/255)   // #22C55E
        case "moderate": return Color(red: 0x21/255, green: 0xB7/255, blue: 0xC9/255)   // #21B7C9
        case "hard":     return Color(red: 0xA7/255, green: 0x8B/255, blue: 0xFA/255)   // #A78BFA, lifted
        case "redline":  return Color(red: 0xFF/255, green: 0x6B/255, blue: 0x35/255)   // #FF6B35
        case "pr":       return gold
        default:         return .white.opacity(0.3)
        }
    }
}


// MARK: - first_week_v1 sections
//
// Everything below is the scroll region. All of it is static illustration: nothing is tappable,
// nothing queries SwiftData, and the demo session is hardcoded rather than generated. A paywall
// that called the session generator would be slow, would fail offline, and would show a
// different session to every reader.

/// Sections, in scroll order. Raw values are the `section` property on `Upsell Section Viewed`.
enum FWSection: String, CaseIterable {
    case firstWeek = "first_week"
    case guarantee = "guarantee"
    case everythingInPremium = "everything_in_premium"
    case priceAnchor = "price_anchor"
}

private extension View {
    /// Reports a section the first time at least half of it is inside the scroll viewport.
    ///
    /// `onScrollVisibilityChange` measures against the scroll view's own bounds, which here is
    /// exactly the area above the purchase block — so "visible" means what the reader can
    /// actually see, not what is merely laid out.
    func fwTrack(_ section: FWSection, seen: @escaping (FWSection) -> Void) -> some View {
        onScrollVisibilityChange(threshold: 0.5) { visible in
            if visible { seen(section) }
        }
    }
}

/// Palette. Values the spec sampled from the mock; where a real token exists it wins — the
/// gold is `FWShowcaseEffort.gold`, the amber fill is `Color.appAccent`.
private enum FWPalette {
    static let bg = Color(white: 0x0A/255.0)              // #0A0A0A
    // `card` is the GUARANTEE card only. The session demo card gets its own, lighter surface
    // so it reads as a card sitting ON the page rather than a hole cut into it — it is the one
    // element here meant to look like a screenshot of the product.
    static let card = Color(white: 0x16/255.0)            // #161616, guarantee card
    static let cardBorder = Color(white: 0x2A/255.0)      // #2A2A2A, guarantee card
    static let demoCard = Color(white: 0x1C/255.0)        // #1C1C1C, session demo card
    static let demoCardBorder = Color(white: 0x3A/255.0)  // #3A3A3A, demo card + strip hairline
    static let strip = Color(white: 0x12/255.0)           // #121212
    static let chip = Color(white: 0x2A/255.0)            // #2A2A2A
    static let hairline = Color(white: 0x22/255.0)        // #222222
    static let rail = Color(white: 0x33/255.0)            // #333333
    static let textSecondary = Color(white: 0xD2/255.0)   // #D2D2D2
    static let textTyped = Color(white: 0xE4/255.0)       // #E4E4E4
    static let textMuted = Color(white: 0x8B/255.0)       // #8B8B8B
    static let onAmber = Color(white: 0x14/255.0)         // #141414
    static let amberText = FWShowcaseEffort.gold          // #F0C05A
    static let amberFill = Color.appAccent                // #FFC850
    static let guaranteeBorder = Color(red: 0x57/255, green: 0x49/255, blue: 0x2A/255)
}

/// Every string on this screen, in one place. Copy changes between releases without layout
/// changes, and hunting them across six view structs is how a stale line survives a rewrite.
private enum FWCopy {
    static let eyebrow = "LIFT THE BULL PREMIUM"
    static let headline1 = "STRONGER EVERY WEEK."
    static let headline2 = "JUST SHOW UP."
    static let subhead = "The app plans every session around you."

    static let firstWeekTitle = "YOUR FIRST WEEK"
    static let freePill = "FREE"

    // THREE steps in v2, not four. The old THIS WEEK step is gone and the demo card moved from
    // TODAY to DAY 5, which is what lets the whole card sit above the fold.
    //
    // NOTHING HERE PROMISES A REMINDER ANY MORE. v1's DAY 5 step said "We remind you before the
    // trial ends", which the backend cannot do — the only registered notification type is the
    // tier nudge. Removing that string is what unblocks shipping this screen ahead of the
    // day-5 reminder.
    /// Step 1's label reflects what the user said during onboarding, because the step claims
    /// they will unlock their tier THEN — "TODAY" is a promise only if they said today.
    ///
    /// Anyone who named a later day gets "DAY 1" rather than "TOMORROW" or "THIS WEEKEND".
    /// Two reasons: it stays true whenever they actually start, and it keeps the timeline on
    /// one clock — a literal "TOMORROW" sitting above "DAY 5" reads as two different
    /// calendars, since steps 2 and 3 count from the trial rather than from their session.
    ///
    /// Defaults to TODAY for "Not sure yet" and for anyone with no recorded answer (every
    /// account created before the step shipped). Today is the encouraging read and the one
    /// that costs nothing if wrong: the step is aspirational, not a schedule.
    static func step1Label(_ intent: NextSessionIntent?) -> String {
        switch intent {
        case .tomorrow, .thisWeekend: return "DAY 1"
        case .today, .notSure, nil:   return "TODAY"
        }
    }
    static let step1Title = "Your starting strength tier in five sets."
    static let step2Label = "DAY 5"
    static let step2Title = "Already moving up, one set at a time."
    static let step3Label = "DAY 7"
    static let step3Title = "Keep the system. Keep climbing."
    static func step3Body(_ price: String) -> String {
        "Trial ends. \(price)/year, or cancel and pay nothing."
    }

    static let chipShortOnTime = "Short on time"
    static let chipNoRack = "No rack"
    static let typed = "Shoulder\u{2019}s still cranky."

    // "Show-Up" is hyphenated with both caps, and is repeated verbatim under the CTA. The two
    // spellings must match — see `guaranteeLine`.
    static let guaranteeTitle = "THE SHOW-UP GUARANTEE"
    static let guaranteeBody1 = "Log 3 sessions a week for 8 weeks."
    // "No lift moves up" rather than "no new best". Same condition — e1RM is a running max, so
    // a lift moving up IS a new best — but it says what the user would actually observe.
    static let guaranteeBody2 = "No lift moves up? We add 3 months free."
    static let guaranteeLine = "Backed by the Show-Up Guarantee"

    static let premiumTitle = "EVERYTHING IN PREMIUM"

    static let anchor1 = "A FULL YEAR FOR LESS THAN"
    static let anchor2 = "ONE SESSION WITH A COACH."
    static func anchorSub(_ year: String, _ month: String) -> String {
        "\(year) a year. That\u{2019}s \(month) a month."
    }
}

// MARK: Section A — header

private struct FWHeader: View {
    var body: some View {
        VStack(spacing: 0) {
            Text(FWCopy.eyebrow)
                .font(.inter(size: 13))
                .tracking(3.5)
                .foregroundStyle(FWPalette.amberText)

            // Same face, size and negative leading as the shipping paywall's
            // "SHOW UP. / WE'LL PICK." — Bebas carries far more line height than it needs.
            VStack(spacing: -6) {
                Text(FWCopy.headline1).foregroundStyle(.white)
                Text(FWCopy.headline2).foregroundStyle(FWPalette.amberText)
            }
            .font(.bebasNeue(size: 36))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .padding(.top, 11)

            Text(FWCopy.subhead)
                .font(.system(size: 13.5))
                .foregroundStyle(FWPalette.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.top, 8)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Stronger every week. Just show up.")
    }
}

// MARK: Section B — your first week

private struct FWTimeline: View {
    let yearlyPrice: String

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(FWCopy.firstWeekTitle)
                    .font(.bebasNeue(size: 21))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                Text(FWCopy.freePill)
                    .font(.system(size: 9.5, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(FWPalette.onAmber)
                    .padding(.horizontal, 6)
                    .frame(height: 15)
                    .background(FWPalette.amberFill, in: RoundedRectangle(cornerRadius: 4))
            }
            .frame(height: 24)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            .accessibilityLabel("Your first week, free.")

            VStack(spacing: 0) {
                FWStep(label: FWCopy.step1Label(NextSessionIntent.declared),
                       title: FWCopy.step1Title, isFirst: true)
                // The card hangs off DAY 5 in v2. 6pt from the TITLE, not from the label —
                // every step now carries a title, so the card's anchor moved down a line.
                FWStep(label: FWCopy.step2Label, title: FWCopy.step2Title) {
                    FWSessionDemoCard().padding(.top, 6)
                }
                FWStep(label: FWCopy.step3Label, title: FWCopy.step3Title,
                       body: FWCopy.step3Body(yearlyPrice), isLast: true)
            }
            .padding(.top, 8)
        }
    }
}

private struct FWStep<Extra: View>: View {
    let label: String
    let title: String
    var body_: String?
    /// Drives the filled marker. Passed explicitly rather than inferred from the label —
    /// step 1's label is now dynamic ("TODAY" or "DAY 1"), so comparing it to a constant
    /// would silently unfill the marker for anyone who did not answer "today".
    var isFirst: Bool = false
    var isLast: Bool = false
    @ViewBuilder var extra: () -> Extra

    init(label: String, title: String, body: String? = nil,
         isFirst: Bool = false, isLast: Bool = false,
         @ViewBuilder extra: @escaping () -> Extra = { EmptyView() }) {
        self.label = label
        self.title = title
        self.body_ = body
        self.isFirst = isFirst
        self.isLast = isLast
        self.extra = extra
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            // Rail. The connector takes `maxHeight: .infinity` so it runs to the bottom of the
            // step INCLUDING its bottom padding, which is what makes it reach the next marker
            // instead of stopping short in the gap.
            VStack(spacing: 0) {
                Group {
                    if isFirst {
                        Circle().fill(FWPalette.amberFill)
                    } else {
                        Circle().strokeBorder(FWPalette.amberText, lineWidth: 2)
                    }
                }
                .frame(width: 11, height: 11)
                .padding(.top, 1.5)

                if !isLast {
                    Rectangle()
                        .fill(FWPalette.rail)
                        .frame(width: 1.5)
                        .frame(maxHeight: .infinity)
                        .padding(.top, 4)
                }
            }
            .frame(width: 24)

            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 11, weight: .bold))
                    .tracking(0.9)
                    .foregroundStyle(FWPalette.amberText)
                    .frame(height: 14, alignment: .leading)
                Text(title)
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(height: 19, alignment: .leading)
                if let body_ {
                    Text(body_)
                        .font(.system(size: 12.5))
                        .foregroundStyle(FWPalette.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
                extra()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, isLast ? 0 : 12)
        }
        .accessibilityElement(children: .combine)
    }

}

// MARK: Session demo card

/// One row of the demo session. Hardcoded illustration — see the note at the top of this
/// section on why this is not generated.
private struct FWSessionDemoCardRow {
    let lift: String
    let sub: String
    let efforts: [String]
    var reason: String?
}

private struct FWSessionDemoCard: View {
    private let rows: [FWSessionDemoCardRow] = [
        FWSessionDemoCardRow(lift: "Deadlifts", sub: "Go for a new best",
            efforts: ["easy", "moderate", "hard", "pr"],
            reason: "Two clean sessions at 245 \u{2014} ready to move up."),
        FWSessionDemoCardRow(lift: "Bench Press", sub: "Steady sets, easy on the shoulder",
            efforts: ["easy", "moderate", "moderate"]),
        FWSessionDemoCardRow(lift: "Overhead Press", sub: "Easy day",
            efforts: ["easy", "easy", "easy"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            inputStrip
            VStack(spacing: 9) {
                ForEach(rows.indices, id: \.self) { FWDemoLiftRow(row: rows[$0]) }
            }
            .padding(.top, 10)
            .padding(.horizontal, 11)
            .padding(.bottom, 10)
        }
        .background(FWPalette.demoCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(FWPalette.demoCardBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Example session. Deadlifts: go for a new best, four sets. "
            + "Two clean sessions at 245, ready to move up. "
            + "Bench press: steady sets, easy on the shoulder, three sets. "
            + "Overhead press: easy day, three sets."
        )
    }

    /// What the user told it, shown as the chips and free text they would have entered. The
    /// caret is static — a blinking one on a paywall reads as a live field you can type into.
    private var inputStrip: some View {
        HStack(spacing: 5) {
            chip(FWCopy.chipShortOnTime)
            chip(FWCopy.chipNoRack)
            Text(FWCopy.typed)
                .font(.system(size: 11.5))
                .foregroundStyle(FWPalette.textTyped)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.leading, 2)
            RoundedRectangle(cornerRadius: 1)
                .fill(FWPalette.amberText)
                .frame(width: 1.5, height: 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FWPalette.strip)
        .overlay(alignment: .bottom) {
            Rectangle().fill(FWPalette.demoCardBorder).frame(height: 1)
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .frame(height: 19)
            .background(FWPalette.chip, in: Capsule())
    }
}

private struct FWDemoLiftRow: View {
    let row: FWSessionDemoCardRow

    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(Self.asset(for: row.lift))
                .resizable()
                .scaledToFit()
                .frame(width: Self.glyph(for: row.lift), height: Self.glyph(for: row.lift))
                .frame(width: 30, height: 30)
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .center, spacing: 8) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(row.lift)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                        Text(row.sub)
                            .font(.system(size: 10.5))
                            .foregroundStyle(FWPalette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    HStack(spacing: 3.5) {
                        ForEach(row.efforts.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(FWShowcaseEffort.color(row.efforts[i]))
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                .frame(height: 30)

                if let reason = row.reason {
                    Text(reason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(FWPalette.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
        }
    }

    /// Asset name from the app's own five-lift table rather than a literal, so a renamed icon
    /// cannot leave this card showing the fallback bull.
    private static func asset(for lift: String) -> String {
        TrendsCalculator.fundamentalExercises.first { $0.name == lift }?.icon ?? "LiftTheBullIcon"
    }

    /// Per-lift optical correction, carried over from the shipping paywall: the bull glyphs are
    /// not drawn to a common bounding box, so a flat size makes Overhead Press look small and
    /// Bench Press look oversized next to it.
    private static func glyph(for lift: String) -> CGFloat {
        switch lift {
        case "Bench Press": return 26
        case "Overhead Press": return 30
        default: return 28
        }
    }
}

// MARK: Section C — guarantee

private struct FWGuaranteeCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "checkmark.shield")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(FWPalette.amberText)
                Text(FWCopy.guaranteeTitle)
                    .font(.bebasNeue(size: 20))
                    .tracking(0.6)
                    .foregroundStyle(.white)
            }
            .frame(height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(FWCopy.guaranteeBody1)
                Text(FWCopy.guaranteeBody2)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(FWPalette.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 13)
        .padding(.horizontal, 16)
        .background(FWPalette.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(FWPalette.guaranteeBorder, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: Section D — everything in premium

private struct FWPremiumStackList: View {
    private struct Row: Identifiable {
        let id = UUID()
        let name: String
        let desc: String
        let glyph: FWGlyph
    }

    private let rows: [Row] = [
        Row(name: "Smart Sessions",
            desc: "Every session picked for you, with the reason why.", glyph: .barbell),
        Row(name: "Strength Balance",
            desc: "Find the one lift that\u{2019}s holding the others back.", glyph: .bars),
        Row(name: "Advanced Analytics",
            desc: "Watch your maxes climb, week by week.", glyph: .trend),
        Row(name: "Set Plan Catalog",
            desc: "Stuck? Proven set schemes to break a plateau.", glyph: .grid),
        Row(name: "Progress Cards",
            desc: "Your PRs and tier in one image, ready to share.", glyph: .share),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Text(FWCopy.premiumTitle)
                .font(.bebasNeue(size: 21))
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(height: 24)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(rows) { row in
                    Rectangle().fill(FWPalette.hairline).frame(height: 1)
                    FWPremiumStackRow(name: row.name, desc: row.desc, glyph: row.glyph)
                }
                Rectangle().fill(FWPalette.hairline).frame(height: 1)
            }
            .padding(.top, 12)
        }
    }
}

private struct FWPremiumStackRow: View {
    let name: String
    let desc: String
    let glyph: FWGlyph

    var body: some View {
        HStack(spacing: 12) {
            glyph.view
                .frame(width: 30, height: 34)

            VStack(alignment: .leading, spacing: 0) {
                // v2 drops the BONUS tags. Four of five rows carried one, which made the tag
                // mean "not Smart Sessions" rather than "extra" — it stopped distinguishing
                // anything. The row keeps its height; only the tag is gone.
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(FWPalette.textMuted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.9)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// Row glyphs. Three are SF Symbols; two are drawn, because no symbol says "these four lifts are
/// out of balance" or "a set scheme" without a caption doing the work.
private enum FWGlyph {
    case barbell, bars, trend, grid, share

    @ViewBuilder var view: some View {
        switch self {
        case .barbell:
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 17))
                .foregroundStyle(FWPalette.amberText)
        case .bars:
            // Descending widths read as a ranking, and the colours run green-to-red, so the
            // bottom bar is visibly the lagging lift.
            VStack(alignment: .leading, spacing: 2) {
                bar(26, Color(red: 0x5D/255, green: 0xC0/255, blue: 0x68/255))
                bar(19, Color(red: 0x60/255, green: 0xB6/255, blue: 0xC5/255))
                bar(13, Color(red: 0xE9/255, green: 0xA2/255, blue: 0x3A/255))
                bar(6,  Color(red: 0xDE/255, green: 0x53/255, blue: 0x4D/255))
            }
            .frame(width: 28, alignment: .leading)
        case .trend:
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color(red: 0x5D/255, green: 0xC0/255, blue: 0x68/255))
        case .grid:
            VStack(spacing: 2) {
                HStack(spacing: 2) {
                    square("moderate"); square("hard"); square("pr")
                }
                HStack(spacing: 2) {
                    square("hard"); square("moderate"); square("easy")
                }
            }
        case .share:
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 17))
                .foregroundStyle(FWPalette.amberFill)
        }
    }

    private func bar(_ width: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: 4)
    }

    private func square(_ effort: String) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(FWShowcaseEffort.color(effort))
            .frame(width: 7, height: 7)
    }
}

// MARK: Section E — price anchor

private struct FWPriceAnchor: View {
    let yearlyPrice: String
    let perMonth: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: -4) {
                Text(FWCopy.anchor1).foregroundStyle(.white)
                Text(FWCopy.anchor2).foregroundStyle(FWPalette.amberText)
            }
            .font(.bebasNeue(size: 24))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(FWCopy.anchorSub(yearlyPrice, perMonth))
                .font(.system(size: 12.5))
                .foregroundStyle(FWPalette.textMuted)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
