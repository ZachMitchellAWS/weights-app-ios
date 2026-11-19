//
//  IntroOfferPaywallView.swift
//  WeightApp
//
//  A COPY of `FirstWeekPaywallView`, taken 2026-11-13 as the starting point for a paywall built
//  around a time-limited introductory PRICE rather than a free trial. Nothing presents it in the
//  normal flow — it is reachable only from the Developer menu while the design is iterated on.
//
//  WHY A COPY. `FirstWeekPaywallView` is the shipping post-onboarding paywall and the one every
//  current conversion number is measured against. It stays byte-identical so it remains the
//  honest comparison; this file changes freely and can be deleted in one commit.
//
//  WHAT CHANGED FROM THAT SCREEN, AND WHY
//
//  1. THE WEEK IS GONE. The old screen told a seven-day story — YOUR FIRST WEEK / FREE, then
//     DAY 1 -> DAY 5 -> DAY 7 down a timeline rail, with the demo session hanging off DAY 5.
//     That is four separate ideas competing for the same glance, and the demo card — the only
//     thing on the screen that shows the actual product — was the one buried inside them. The
//     timeline, the FREE pill and the whole first-week frame are removed, and the demo card is
//     promoted to the centerpiece it was always meant to be.
//
//  2. THE OFFER IS A PRICE, NOT A TRIAL. A 72-hour introductory price with the list price
//     struck through beside it, and a live countdown pinned above the plan cards where it
//     cannot scroll out of view. A countdown that scrolls away is decoration.
//
//  3. THE HEADLINE SAYS THE PRODUCT. "SHOW UP. / WE'LL PICK." — the whole proposition in four
//     words — with the former subhead ("The app plans every session around you") restated as a
//     stylized triplet so it reads as a claim rather than a caption.
//
//  PRICES COME FROM STOREKIT, resolved through `IntroOfferService.pricingContext()`, and the
//  72-hour window is computed from the account's creation date. This was briefly a UI study with
//  hardcoded display strings and a device-local first-seen anchor; both are gone. See
//  `IntroOfferService` for why the anchor had to be server-side and why there are two yearly
//  SKUs rather than one product with an introductory price.
//
//  WHAT IS SHARED, AND WHAT IS NOT
//
//  * All page types carry an `IO` prefix so traces and jump-to-definition stay unambiguous
//    against the `FW` originals.
//  * `PlanCard` is NOT reused for the yearly row — it cannot render a struck-through list
//    price. `OfferPlanCard` below is a local fork of it. The monthly row still uses the shared
//    `PlanCard`, so the two must be kept looking alike by hand.
//
import SwiftUI
import SwiftData
import StoreKit
import Sentry

struct IntroOfferPaywallView: View {
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
    @State private var viewedSections: Set<IOSection> = []
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
    @State private var sectionOpacity: [Double] = Array(repeating: 0, count: IOSection.allCases.count + 1)

    @State private var pricingOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    enum Plan { case monthly, yearly }

    /// Identifies this design in analytics. Every event fired from here carries it.
    ///
    /// Distinct from `first_week_v2` so these rows never pool with the shipping paywall's.
    ///
    /// SUFFIXED BY OFFER STATE, not by design. The screen has two pricing presentations —
    /// promotional and standard — and they are different offers to different people, so a
    /// single variant would average two conversion rates into one meaningless number. There was
    /// briefly a per-headline suffix here while two headlines were being compared; that
    /// comparison is settled and the suffix now carries the thing that actually varies.
    ///
    /// An INSTANCE property because it depends on resolved pricing, which arrives async.
    private var variant: String {
        // Derived from the SAME helper the view draws from, so the label can never describe a
        // presentation other than the one on screen. These were briefly two expressions with
        // different nil defaults, which is a reporting bug waiting to happen.
        "intro_offer_v1_" + (showsPromotion ? "promo" : "standard")
    }

    /// Page margin. 24 to match `pricingSection` and `subscribeButton`, so the demo card's
    /// edges line up with the plan cards below it.
    private static let hMargin: CGFloat = 24

    // Bottom fade over the scroll region. TWO KNOBS, and they do different things:
    //
    //   `fadeHeight`  — how tall the obscuring band is. This is the one that controls how far
    //                   down the page content stays legible. SHORTER means the scroll content
    //                   remains visible closer to the purchase block, which is what makes it
    //                   apparent that there is more below.
    //   `fadeSolidAt` — the fraction of that height at which the gradient reaches FULL
    //                   background. Everything past it is a flat band sitting directly above
    //                   the badge. Raise it for less flat band, lower it for more separation.
    //
    // 16pt, down from 30. At 30 the content dissolved a full half-inch above the purchase
    // block, and that dead band read as the natural end of the content rather than as a hint
    // that more was below it. At 16 the fade is short enough that a reader can still make out
    // the shape of whatever is being cut off, which is the actual cue.
    //
    // 0.92 of 16pt leaves ~1.3pt of solid — enough to land on background before the badge
    // without the flat band becoming the thing you see.
    private static let fadeHeight: CGFloat = 16
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
                        // ORDER MATTERS. Products first: `pricingContext()` reads them to pick
                        // the sellable SKU and to ask StoreKit about trial eligibility, so
                        // resolving pricing before the load returns would resolve it against an
                        // empty product list and fall back to legacy prices every time.
                        await purchaseService.loadProducts()
                        let resolved = await IntroOfferService.shared.pricingContext(
                            purchaseService: purchaseService
                        )
                        pricing = resolved
                        // Attribution and the shown event both wait for this point, because
                        // both have to carry the prices that are actually on screen.
                        purchaseService.setActivePaywall(
                            variant: variant, scrollDepth: maxScrollDepth, pricing: resolved
                        )

                        // `initialPage`/`initialFeature` are carousel concepts and this screen
                        // has no carousel. Reported as what is on screen at offset 0 rather than
                        // left blank, so the properties keep a consistent meaning across
                        // paywalls.
                        AmplitudeService.shared.track(.premiumUpsellShown(
                            source: source.rawValue,
                            initialPage: 0,
                            initialFeature: IOSection.session.rawValue,
                            paywallVariant: variant,
                            pricing: resolved
                        ))
                    }

                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(priceBlockOpacity)

                Spacer().frame(height: 10)

                subscribeButton
                    .padding(.horizontal, 24)
                    .opacity(priceCtaOpacity)

                // Restates the guarantee where the card itself is three sections up and out of
                // sight. A LABEL, NOT A BUTTON — there is nothing to navigate to, and making it
                // tappable would promise detail that does not exist.
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 13))
                        .accessibilityHidden(true)
                    Text(IOCopy.guaranteeLine)
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(IOPalette.amberText)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.top, 6)
                .accessibilityElement(children: .combine)
                .opacity(ctaOpacity)

                // The shipping paywall's line, with this screen's price in it. Trial length,
                // rate, cancel — nothing else. Earlier drafts appended a renewal price (wrong)
                // and then a "your rate for as long as you stay subscribed" clause (right, but
                // it turned one plain line into two lines of reassurance for a commitment
                // nobody has made yet). The struck-out price and the clock make the offer; this
                // line states the terms.
                // TRIAL STATE IS LOAD-BEARING HERE. Until now "7 days free" was unconditional
                // across three paywalls, so a customer who had already used their trial — on
                // the legacy product, months ago — was promised it again. Apple evaluates
                // eligibility per subscription group, so that promise was one the store would
                // have refused to honour at the sheet.
                Text(selectedPlan == .yearly
                     ? (trialAvailable
                        ? "7 days free, then \(yearlyPriceText)/year. Cancel anytime."
                        : "\(yearlyPriceText)/year. Cancel anytime.")
                     : "\(monthlyPriceText)/month. Cancel anytime.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
                    .opacity(priceCtaOpacity)

                // Carries the only way off this screen, so it has to READ as a control rather
                // than as a caption — the reason it is 16pt semibold at 92% white and the full
                // width of the CTA rather than the 15pt/50% row the shipping paywall started
                // with. Someone scanning for an exit has to find something button-shaped.
                //
                // BORDERLESS. `FirstWeekPaywallView` puts a 1pt white-30% stroke around this,
                // which is what makes the pair read as two options there. Here the amber CTA
                // already has to compete with a coloured countdown band directly above it, and
                // a third outlined rectangle underneath turned the bottom of the screen into
                // three stacked boxes. Type weight and width carry the "this is a control"
                // job on their own; the absence of a fill still carries the hierarchy.
                //
                // The 2pt vertical padding and `contentShape` are load-bearing: without a
                // border there is nothing to size the tap target, and 40pt alone is under
                // Apple's 44pt minimum.
                Button { dismiss() } label: {
                    // 16pt is kept — size is what makes it findable as a control, which is the
                    // whole reason it is not a 15pt caption. Weight and opacity are what got
                    // dialled back: semibold at 92% white made the second option as insistent
                    // as the first, which is not the hierarchy this screen wants.
                    Text("Not now")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isProcessing)
                // 32 = the CTA's effective inset (24 at its call site, 8 inside
                // `subscribeButton`), so the two edges line up.
                .padding(.horizontal, 32)
                .padding(.vertical, 10)
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

            // `premiumUpsellShown` IS NOT FIRED HERE. It is fired from the `.task` above, once
            // pricing has resolved.
            //
            // `onAppear` runs before the StoreKit load returns, so anything reported from here
            // describes the pre-resolution fallback rather than what the reader saw — every row
            // would read "standard" with no prices, including the promotional presentations.
            // This event is the denominator for price-level conversion, so it has to be right.

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
                IOHeader()
                    .opacity(sectionOpacity[0])

                IOSessionShowcase()
                    .padding(.top, 20)
                    .opacity(sectionOpacity[1])
                    .ioTrack(.session, seen: markSectionViewed)

                // Back to 24. The 28 was borrowed while this section had no container — plain
                // text needs whitespace to separate itself, a bordered box does not.
                IOGuaranteeCard()
                    .padding(.top, 24)
                    .opacity(sectionOpacity[2])
                    .ioTrack(.guarantee, seen: markSectionViewed)

                IOPremiumStackList()
                    .padding(.top, 28)
                    .opacity(sectionOpacity[3])
                    .ioTrack(.everythingInPremium, seen: markSectionViewed)

                IOPriceAnchor(yearlyPrice: yearlyPriceText, perMonth: perMonthText)
                    .padding(.top, 28)
                    .opacity(sectionOpacity[4])
                    .ioTrack(.priceAnchor, seen: markSectionViewed)
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
            purchaseService.setActivePaywall(variant: variant, scrollDepth: depth)
        }
        // The scroll view's own frame IS the area above the purchase block, so a 30pt fade
        // pinned to its bottom edge sits exactly where content disappears. Non-interactive: the
        // purchase block starts below it, and a fade that ate touches would be a dead strip.
        .overlay(alignment: .bottom) {
            // Three stops, not two. A plain clear->bg gradient only reaches FULL bg at its
            // very last pixel, so content stayed faintly visible right up against the badge
            // below.
            //
            // But the solid band is the thing you SEE, and it reads as dead space between the
            // content and the badge rather than as separation. At 12pt it looked like a gap;
            // at ~2.5pt the fade appears to terminate right at the badge while still landing
            // on solid background before it.
            //
            // A PANEL TREATMENT WAS TRIED HERE AND REVERTED: the fixed block below was given a
            // lighter fill, a top hairline and an upward shadow to make the scroll region read
            // as passing underneath it. It looked bad on device. If scroll affordance is
            // revisited, that is the approach that did not work.
            LinearGradient(
                stops: [
                    .init(color: IOPalette.bg.opacity(0), location: 0.0),
                    .init(color: IOPalette.bg, location: Self.fadeSolidAt),
                    .init(color: IOPalette.bg, location: 1.0),
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: Self.fadeHeight)
            .allowsHitTesting(false)
        }
    }

    /// One `Upsell Section Viewed` per section per presentation.
    private func markSectionViewed(_ section: IOSection) {
        guard viewedSections.insert(section).inserted else { return }
        AmplitudeService.shared.track(.upsellSectionViewed(
            source: source.rawValue,
            section: section.rawValue,
            paywallVariant: variant
        ))
    }

    /// The resolved offer state, prices and trial eligibility for this presentation.
    ///
    /// Resolved ONCE in `.task` and held, rather than recomputed per body pass. Trial
    /// eligibility is a StoreKit round trip, and re-resolving pricing underneath a reader who
    /// is mid-decision would let the price change while they look at it. The one state that
    /// does move during a presentation — the window closing — is handled by the countdown
    /// reaching zero, which is a visual change rather than a repricing.
    ///
    /// Nil until resolved. Everything that reads it falls back to the non-promotional
    /// presentation, so the first frame never flashes a countdown it then has to withdraw.
    @State private var pricing: PricingContext?

    /// StoreKit prices with `SubscriptionConfig`'s literals as the pre-load fallback.
    private var yearlyPriceText: String {
        pricing?.yearlyPriceText ?? SubscriptionConfig.yearlyDisplayPrice
    }
    private var perMonthText: String {
        pricing?.yearlyPerMonthText ?? SubscriptionConfig.yearlyPerMonthPrice
    }
    private var monthlyPriceText: String {
        pricing?.monthlyPriceText ?? SubscriptionConfig.monthlyDisplayPrice
    }

    /// Whether to draw the countdown, the strikethrough and the word "intro" at all.
    /// Opacity for anything that states a PRICE, gated on resolution.
    ///
    /// WHY NOT JUST THE STAGGER'S OPACITY. The fallback literals in `SubscriptionConfig` can
    /// only match one of the two presentations. Rendering them and then correcting produces a
    /// visible price change: $59.99 flashing to $89.99 for a reader outside the window reads as
    /// a bait and switch, and $59.99 flashing to $39.99 — which is what the unresolved-SKU
    /// fallback does — reads as a bug. A price that moves after the reader has seen it is worse
    /// than a price that arrives 200ms late.
    ///
    /// SAFE AGAINST A STOREKIT FAILURE. `loadProducts()` catches its own errors and returns
    /// normally, so `pricing` is always assigned — offline included, where it resolves to a
    /// context with nil products and the literals show. There is no path that leaves this at
    /// zero forever.
    ///
    /// Deliberately NOT applied to "Not now" or the legal footer: neither states a price, and
    /// gating the only way off the screen on a network round trip would be a worse bug than the
    /// one this fixes.
    private var priceBlockOpacity: Double { pricing == nil ? 0 : pricingOpacity }
    private var priceCtaOpacity: Double { pricing == nil ? 0 : ctaOpacity }

    private var showsPromotion: Bool { pricing?.showsPromotion ?? false }

    /// Whether the 7-day trial is still available to this customer.
    ///
    /// Defaults to TRUE before resolution, matching every paywall that shipped before trial
    /// state existed. The cost of being wrong in that direction is one frame of an over-generous
    /// promise; the other direction withholds a trial from someone entitled to it.
    private var trialAvailable: Bool { pricing?.trial.isAvailable ?? true }

    // MARK: - Countdown
    //
    // THERE IS NO TICKER HERE ANY MORE. This screen used to own a `Timer.publish`, a
    // `countdownRemaining` `@State` and a `refreshCountdown()` that recomputed it from a
    // deadline — about thirty lines, all so a child view could be handed a `TimeInterval`.
    // `OfferCountdownBadge` now takes the deadline and runs its own `TimelineView`, which the
    // carousel paywall also needed and could not have borrowed from a `private` type in here.
    // The deadline comes from `pricing?.offer.deadline`.

    // MARK: - Pricing (identical to the shipping paywall — not what this experiment varies)

    private var pricingSection: some View {
        // 12/10 rather than the shipping 16/14. Two plan cards is the one block on this screen
        // that can give up height without losing anything — the row is a radio button, a price
        // and a badge, and none of them needed 14pt of air. ~20pt reclaimed, spent on "Not now".
        VStack(spacing: 12) {
            // The countdown sits HERE, in the fixed block, not in the scroll region. It is the
            // only thing on the screen with a deadline, and a deadline the reader can scroll
            // away from is decoration.
            //
            // A TAB, notched onto the top-leading corner of the card it is about — the slot
            // and the shape the "7 DAYS FREE" badge occupied on the shipping paywall, so this
            // costs no vertical space over it.
            //
            // KNOWN WEAKNESS, DELIBERATELY ACCEPTED. The tab does not reliably catch the eye,
            // and the reason is structural rather than stylistic: amber is this screen's only
            // accent, and the CTA 60pt below is a 40pt solid amber slab. Two elements in the
            // same hue resolve by area, so a ~22pt tab loses. Two fixes were tried and both
            // were rejected as worse than the problem — a full-width fuse to the card (too
            // heavy) and a second hue (off-palette). What is left as an actual lever is motion
            // or a second placement higher up the scroll; neither is in yet.
            VStack(alignment: .leading, spacing: 0) {
                // ONE SLOT, THREE OCCUPANTS, driven by offer state and trial state together.
                // This is the slot the shipping paywall used for its "7 DAYS FREE" badge, which
                // is why the non-promotional states cost no layout work:
                //
                //   offer active              -> the countdown
                //   expired + trial available -> "7 DAYS FREE"
                //   expired + trial used      -> nothing
                //
                // Trial state cannot promote itself over the countdown: a reader inside the
                // window is being sold a price, and two competing badges on one card is how you
                // get neither read.
                if showsPromotion, let deadline = pricing?.offer.deadline {
                    OfferCountdownBadge(deadline: deadline)
                        .padding(.leading, 24)
                } else if trialAvailable {
                    OfferTrialBadge()
                        .padding(.leading, 24)
                }

                OfferPlanCard(
                    isSelected: selectedPlan == .yearly,
                    title: "Yearly",
                    price: yearlyPriceText,
                    // NIL OUTSIDE THE WINDOW, and nil whenever there is no genuinely higher
                    // price to show — `IntroOfferService` only supplies this when the standard
                    // SKU is both loaded and more expensive than what is being charged. A
                    // strikethrough over a price equal to or below the one we are selling at is
                    // a lie that would survive a casual glance.
                    strikePrice: pricing?.strikePrice,
                    // Just the per-month figure, exactly as the shipping paywall has it. Two
                    // attempts at qualifying it here — "first year", then "locked in" — were
                    // both wrong: the first misdescribed the offer, and the second explains a
                    // deal the reader has not agreed to yet in the row where they are still
                    // choosing a plan. The subtitle converts a yearly price to a monthly one.
                    // That is all it is for.
                    priceSubtitle: "(\(perMonthText)/mo)",
                    // NO DISCOUNT BADGE. "33% OFF" sat two inches from a struck-through price
                    // and a running clock, both of which say the same thing without asking the
                    // reader to trust an arithmetic claim they cannot check.
                    badge: nil,
                    onTap: { selectPlan(.yearly) }
                )
            }

            // Shared `PlanCard`, so this row and the one above are two different components
            // drawn to look alike. They will drift the moment either is restyled — if this
            // design survives, fork the monthly row too rather than reverse-engineering the
            // match a second time.
            PlanCard(
                isSelected: selectedPlan == .monthly,
                title: "Monthly",
                price: monthlyPriceText,
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
            plan: plan == .yearly ? "yearly" : "monthly",
            pricing: pricing
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
                        // The trial LENGTH, not just "Free Trial". The screen never said seven
                        // anywhere, and "free trial" without a number is the kind of vagueness
                        // a reader discounts. On the button it costs no vertical space.
                        Text(ctaLabel)
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

    /// Terms and Privacy, as the shipping paywall has them.
    ///
    /// NO RESTORE HERE. A Restore link was added when this screen was briefly a hard paywall
    /// with no "Not now" — at that point there was nowhere else on the reader's path to put
    /// one. "Not now" is back, so the path exists again: decline, More -> Restore Purchases,
    /// which is where the app has always kept it and which is what satisfies Apple's
    /// expectation of a restore mechanism. A second entry point on the paywall was a third
    /// link competing with two legal ones for the same 12pt line.
    /// Switches on BOTH plan and trial state — the button and the terms line beneath it must
    /// agree, and for a while they did not: this read "Start 7 Days Free" unconditionally while
    /// the line under it correctly said "$59.99/year. Cancel anytime." for a customer whose
    /// trial was spent. The button was making a promise the App Store would have refused at the
    /// purchase sheet.
    ///
    /// Four combinations, three labels. Monthly and trial-spent-yearly both read "Subscribe
    /// Now", because for that customer the two plans now differ only in price and duration and
    /// neither offers anything a trial word would describe.
    private var ctaLabel: String {
        guard selectedPlan == .yearly else { return "Subscribe Now" }
        return trialAvailable ? "Start 7 Days Free" : "Subscribe Now"
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
            feature: viewedSections.count >= IOSection.allCases.count
                ? IOSection.priceAnchor.rawValue
                : IOSection.session.rawValue,
            secondsOnScreen: Date().timeIntervalSince(shownAt),
            paywallVariant: variant,
            maxScrollDepthPct: maxScrollDepth,
            pricing: pricing
        ))
        // Dismissed without buying — release the attribution so a later renewal is not tagged
        // with this paywall.
        purchaseService.clearActivePaywall()
        onComplete(false)
    }

    // MARK: - Purchase

    private func handlePurchase() async {
        let planName = selectedPlan == .yearly ? "yearly" : "monthly"
        // FROM THE RESOLVED CONTEXT. There is deliberately no `purchaseService.yearlyProduct`
        // accessor any more: with two yearly SKUs live, "the yearly product" is a question only
        // `IntroOfferService` can answer, and a call site that guessed would charge the wrong
        // price while compiling perfectly.
        let product = selectedPlan == .yearly ? pricing?.yearly : pricing?.monthly
        guard let product else {
            errorMessage = "Product not available. Please try again."
            AmplitudeService.shared.track(.purchaseAbandoned(
                productId: "unknown", plan: planName, reason: "product_unavailable",
                paywallVariant: variant, pricing: pricing
            ))
            return
        }
        AmplitudeService.shared.track(.purchaseStarted(
            productId: product.id,
            plan: selectedPlan == .yearly ? "yearly" : "monthly",
            // REAL ELIGIBILITY, not "is this the yearly plan". Those were the same thing only
            // while the trial was unconditional; now a yearly purchase by someone who has
            // already used their trial is a plain purchase, and reporting it as a trial start
            // would inflate the one funnel step this screen exists to move.
            isFreeTrial: selectedPlan == .yearly && trialAvailable,
            paywallVariant: variant,
            pricing: pricing
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
                    productId: product.id, plan: planName, reason: "cancelled",
                    paywallVariant: variant, pricing: pricing
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
                    productId: product.id, plan: planName, reason: "failed",
                    paywallVariant: variant, pricing: pricing
                ))
            }
        }
    }
}

// MARK: - Smart Sessions page

/// Effort colours, diverging from the app's own `ProgramEffort.color` so the squares read as
/// one object when scanned rather than as a row with a hole in it — the app's `hard` violet
/// (#5B3BE8, luminance 0.112) is nearly four times darker than its green (0.411), which is fine
/// in a list you read one row at a time and wrong on a card meant to be taken in at a glance.
/// Lifting violet to #A78BFA (0.336) puts every non-gold square in a 0.320-0.411 band, and gold
/// at 0.570 stays 1.39x above the brightest square beside it so it wins the eye.
///
/// Used in two places at two sizes: the 16pt per-set tiles on the demo session card, and the
/// 7pt abstract grid `IOGlyph` draws as the set-plans icon in the premium list. Neither expects
/// the reader to decode an individual colour — there is no legend on this screen and there is
/// no room for one. What they carry is that the work VARIES across a session, which survives
/// not knowing which shade means what. `gold` is separately this screen's accent, aliased as
/// `IOPalette.amberText`.
private enum IOShowcaseEffort {
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
enum IOSection: String, CaseIterable {
    case session = "session_demo"
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
    func ioTrack(_ section: IOSection, seen: @escaping (IOSection) -> Void) -> some View {
        onScrollVisibilityChange(threshold: 0.5) { visible in
            if visible { seen(section) }
        }
    }
}

/// Palette. Values the spec sampled from the mock; where a real token exists it wins — the
/// gold is `IOShowcaseEffort.gold`, the amber fill is `Color.appAccent`.
private enum IOPalette {
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
    static let amberText = IOShowcaseEffort.gold          // #F0C05A
    static let amberFill = Color.appAccent                // #FFC850
    static let guaranteeBorder = Color(red: 0x57/255, green: 0x49/255, blue: 0x2A/255)
}

/// Every string on this screen, in one place. Copy changes between releases without layout
/// changes, and hunting them across six view structs is how a stale line survives a rewrite.
private enum IOCopy {
    // Four words, the whole proposition. Two alternatives were tried and dropped:
    // "STOP PLANNING. / START LIFTING." (asserts planning is a burden the reader carries — a
    // claim about them rather than about the app) and "SHOW UP. / YOUR SESSION'S READY."
    // (present tense, stronger, but untrue at the moment this screen is shown: session
    // generation needs established baselines, so a reader straight out of onboarding has no
    // session waiting). "WE'LL PICK." is a promise about what the app does, which stays true
    // whenever they start.
    static let headline1 = "SHOW UP."
    static let headline2 = "WE\u{2019}LL PICK."

    // The former subhead was "The app plans every session around you" — true, and read as a
    // caption. Broken into three nouns it reads as a claim, and it names the three decisions
    // the user is handing over, which is more concrete than "plans".
    static let triplet = ["THE LIFTS", "THE WEIGHTS", "THE EFFORT"]

    // SPLIT SO THE FEATURE NAME CAN BE ACCENTED. "Smart Session" is the product's own name for
    // the thing — `SubscriptionConfig.smartSessionsTitle`, the first row of the premium list
    // and the carousel's first page — and this is the only place on the screen it appears.
    //
    // TITLE CASE, NOT SENTENCE CASE, inside running prose: it is a proper noun here, and
    // lowercasing it would read as a description of a session that happens to be clever rather
    // than as the name of a feature they are being sold. The amber does the same job from the
    // other direction.
    static let tripletTailLead = "picked for you, every "
    static let tripletTailFeature = "Smart Session."

    // MARK: Session showcase

    // Replaces "YOUR FIRST WEEK" / "FREE".
    // NO EYEBROW ABOVE THIS. One was tried and removed: the section already sits under a
    // headline and a triplet, and a fourth line of type before the card pushed the one thing
    // worth seeing further down. The feature gets named in the triplet instead.
    static let sessionTitle = "YOUR NEXT SESSION"
    /// Names what the typed note below it IS. Without this the input strip reads as the first
    /// row of the session rather than as the thing the session is a response to.
    static let sessionLead = "Tell it how you\u{2019}re showing up today."
    static let typed = "Shoulder\u{2019}s still cranky."

    // MARK: Offer

    // "INTRO OFFER ENDS IN". Three labels have been through here and the width was never
    // actually the constraint — the tab sizes to its content and has ~80pt of slack at this
    // length on the narrowest supported screen.
    //
    //   "INTRO PRICE ENDS IN"  — original. Verbose, and the digits were 9.5pt behind it, so
    //                            the preamble genuinely was crowding them out.
    //   "ENDS IN"              — fixed the crowding and removed the only place on the screen
    //                            that named the offer. A clock counting down to nothing.
    //   "INTRO OFFER"          — named it, dropped the deadline framing.
    //   "INTRO OFFER ENDS IN"  — both. Affordable now ONLY because the digits went to 15pt in
    //                            between: at 15 against a 9pt label the clock wins on weight
    //                            rather than on having the row to itself, so the label can be
    //                            as long as it needs to be.
    // The countdown's own strings live on `OfferCountdownBadge`, which both pricing paywalls
    // share. Keeping a second copy here is how the two screens would eventually disagree about
    // what the clock says.

    // MARK: Guarantee — unchanged from the shipping paywall

    // "Show-Up" is hyphenated with both caps, and is repeated verbatim under the CTA. The two
    // spellings must match the card below, which is now the only place either appears.
    static let guaranteeTitle = "THE SHOW-UP GUARANTEE"
    static let guaranteeBody1 = "Log 3 sessions a week for 8 weeks."
    // "No lift moves up" rather than "no new best". Same condition — e1RM is a running max, so
    // a lift moving up IS a new best — but it says what the user would actually observe.
    //
    // SPLIT IN TWO so the remedy can be accented inside the sentence. The condition is what
    // the reader has to accept; the remedy is what they get, and it was previously rendering
    // in the same grey as everything else in the block.
    static let guaranteeBody2Lead = "No lift moves up? We add "
    static let guaranteeBody2Remedy = "3 months free."
    /// Restates the guarantee at the moment of commitment, where the card itself is three
    /// sections up and out of sight.
    ///
    /// Cut once, against the bar "say the guarantee in five words or drop the line" — the terms
    /// are two conditions and a remedy, and no five-word compression keeps all three. That was
    /// the wrong test. This line is not a compression of the guarantee, it is a POINTER to one:
    /// a reader at the CTA does not need the terms restated, they need to remember that terms
    /// exist. "Show-Up" is hyphenated with both caps and must match `guaranteeTitle`.
    static let guaranteeLine = "Backed by the Show-Up Guarantee"

    static let premiumTitle = "EVERYTHING IN PREMIUM"

    static let anchor1 = "A FULL YEAR FOR LESS THAN"
    static let anchor2 = "ONE SESSION WITH A COACH."
    static func anchorSub(_ year: String, _ month: String) -> String {
        "\(year) a year. That\u{2019}s \(month) a month."
    }
}

/// The introductory offer, in one place.
///
/// EVERY NUMBER HERE IS ILLUSTRATIVE. There is no StoreKit product for an introductory tier, so
/// nothing in this enum is reachable from `PurchaseService` and the CTA still charges the
/// ordinary yearly/monthly price. Treat these as the spec for a product that does not exist
/// yet, not as a description of one that does.

// MARK: Section A — header

private struct IOHeader: View {
    var body: some View {
        // NO EYEBROW. The shipping paywall opens with "LIFT THE BULL PREMIUM"; an earlier cut
        // of this one opened with "INTRODUCTORY OFFER". Both spend the first line the reader
        // sees on something other than the product — one on a brand they just onboarded into,
        // the other on a deal the countdown above the plan cards already names. The headline
        // gets the top of the screen.
        VStack(spacing: 0) {
            // Same face and negative leading as the shipping paywall's headline — Bebas carries
            // far more line height than it needs.
            VStack(spacing: -6) {
                Text(IOCopy.headline1).foregroundStyle(.white)
                Text(IOCopy.headline2).foregroundStyle(IOPalette.amberText)
            }
            .font(.bebasNeue(size: 44))
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            IOTriplet()
                .padding(.top, 12)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityLabel("Show up, we'll pick. The lifts, the weights and the effort, "
                            + "picked for you every session.")
    }
}

/// The old subhead, restated as three nouns on a rule.
///
/// WHY NOT JUST A SENTENCE. "The app plans every session around you" is one grey line under a
/// headline, and it reads as the caption explaining the headline rather than as a second claim.
/// Split into the three decisions being handed over, with the dots carrying the rhythm, it
/// occupies the same two lines of height but asserts something specific: not "plans", but these
/// three things, which are exactly what a lifter would otherwise have to decide themselves.
private struct IOTriplet: View {
    var body: some View {
        VStack(spacing: 5) {
            HStack(spacing: 7) {
                ForEach(Array(IOCopy.triplet.enumerated()), id: \.offset) { index, word in
                    if index > 0 {
                        Circle()
                            .fill(IOPalette.amberText.opacity(0.65))
                            .frame(width: 2.5, height: 2.5)
                    }
                    Text(word)
                        .font(.inter(size: 11))
                        .tracking(1.6)
                        .foregroundStyle(.white)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            // TWO THINGS GOING ON IN ONE LINE.
            //
            // `.inter`, not `.system`: these two lines are one unit — three tracked words and
            // the phrase that completes them — and the tail used to render in SF while the
            // words above rendered in Inter. (Both currently fall back to SF anyway, because
            // `Font.inter` asks for "Inter-Regular" while the bundled face's PostScript name is
            // "Inter18pt-Regular". That is an app-wide bug affecting ~244 call sites, not this
            // one; written this way so it self-heals when the name is fixed.)
            //
            // And the feature name is accented by Text concatenation — the same construction
            // the guarantee card uses for "3 months free." and `FirstProgressCelebrationCard`
            // uses for "e1RM". All three are the same case: a named thing inside running prose,
            // where the colour is what makes it register as a NAME rather than as emphasis.
            (Text(IOCopy.tripletTailLead)
                .foregroundColor(IOPalette.textSecondary)
             + Text(IOCopy.tripletTailFeature)
                .foregroundColor(IOPalette.amberText))
                .font(.inter(size: 13))
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: Section B — the session showcase

/// What replaced the DAY 1 / DAY 5 / DAY 7 timeline.
///
/// The timeline spent three rail-connected steps and a FREE pill establishing a seven-day
/// narrative, and hung the demo card off the middle one — so the only element on the screen
/// that shows the actual product arrived as a supporting detail of a story about a trial. With
/// the trial gone there is no story to support, and the card becomes the section.
///
/// The two lines around it are what keep it from being a screenshot: the one above is the
/// input, the one below is the output, and the card in between is the transformation. Removing
/// either leaves the reader to infer that the session was chosen rather than typed, which is
/// the single claim this screen exists to make.
private struct IOSessionShowcase: View {
    var body: some View {
        VStack(spacing: 0) {
            // NO "AUTO-PICKED" PILL, AND NO CAPTION UNDER THE CARD. Both said the thing the
            // triplet in the header already says, two sections apart — a badge on the card and
            // a grey line beneath it restating "it picks for you" to a reader who has just read
            // exactly that. The lead line above the card stays because it is the only thing
            // naming what the typed note IS; nothing else on the screen says the session is a
            // response to something the user wrote.
            Text(IOCopy.sessionTitle)
                .font(.bebasNeue(size: 21))
                .tracking(0.6)
                .foregroundStyle(.white)
                .frame(height: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            IOShowcaseCaption(text: IOCopy.sessionLead)
                .padding(.top, 10)

            IOSessionDemoCard()
                .padding(.top, 8)
        }
    }
}

/// The line above the card, with an arrow pointing into it. There used to be a matching one
/// below pointing away; it restated the header and was cut.
private struct IOShowcaseCaption: View {
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "arrow.down")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(IOPalette.amberText)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(IOPalette.textSecondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}


// MARK: Session demo card

/// One row of the demo session. Hardcoded illustration — see the note at the top of this
/// section on why this is not generated.
private struct IOSessionDemoCardRow {
    let lift: String
    let sub: String
    /// One tile per set, coloured by effort — see `IOShowcaseEffort`. Briefly replaced by a
    /// plain "4 sets" on the grounds that a new reader has no key for the colours; reinstated
    /// because the count was never what the tiles were for. A row of four flat labels is a
    /// list, and the thing being sold is that the app varies the work set by set. The colours
    /// carry that at a glance whether or not the reader can name any individual one.
    let efforts: [String]
    var reason: String?
}

private struct IOSessionDemoCard: View {
    /// THREE LIFTS. Two was too few — the card read as a diagram of a session rather than a
    /// session, and "we'll pick" is a weaker claim about two lifts than about a workout. Four
    /// was too many for the height the card has.
    ///
    /// NO OVERHEAD PRESS. Prescribing overhead work to someone who has just typed that their
    /// shoulder is cranky reads, to anyone who actually lifts, as the app not having listened.
    ///
    /// Squats sits LAST, not second. Deadlifts opens because it carries the reason line, which
    /// is the card's only evidence that the app read anything; Bench Press follows because it
    /// is the row the typed shoulder note visibly acts on. Squats closes — it is the row that
    /// has to be there for the session to look complete, and nothing about it is making an
    /// argument.
    private let rows: [IOSessionDemoCardRow] = [
        IOSessionDemoCardRow(lift: "Deadlifts", sub: "Go for a new best",
            efforts: ["easy", "moderate", "hard", "pr"],
            reason: "Two clean sessions at 245 \u{2014} ready to move up."),
        IOSessionDemoCardRow(lift: "Bench Press", sub: "Steady sets, easy on the shoulder",
            efforts: ["easy", "moderate", "moderate"]),
        IOSessionDemoCardRow(lift: "Squats", sub: "Build on last week",
            efforts: ["moderate", "moderate", "hard"]),
    ]

    var body: some View {
        VStack(spacing: 0) {
            inputStrip
            VStack(spacing: 9) {
                ForEach(rows.indices, id: \.self) { IODemoLiftRow(row: rows[$0]) }
            }
            .padding(.top, 10)
            .padding(.horizontal, 11)
            .padding(.bottom, 10)
        }
        .background(IOPalette.demoCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(IOPalette.demoCardBorder, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Example session. You told it: shoulder's still cranky. "
            + "Deadlifts: go for a new best, four sets. "
            + "Two clean sessions at 245, ready to move up. "
            + "Bench press: steady sets, easy on the shoulder, three sets. "
            + "Squats: build on last week, three sets."
        )
    }

    /// What the user told it. The caret is static — a blinking one on a paywall reads as a
    /// live field you can type into.
    ///
    /// ONE INPUT, NOT THREE. This used to lead with "Short on time" and "No rack" chips. Neither
    /// changed anything visible in the session below them, so they read as decoration on a card
    /// whose entire job is to show cause and effect. The shoulder note is the one input with a
    /// traceable result — it is why Bench Press says "easy on the shoulder" — so it is the only
    /// one left.
    private var inputStrip: some View {
        HStack(spacing: 5) {
            Text(IOCopy.typed)
                .font(.system(size: 11.5))
                .foregroundStyle(IOPalette.textTyped)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .padding(.leading, 2)
            RoundedRectangle(cornerRadius: 1)
                .fill(IOPalette.amberText)
                .frame(width: 1.5, height: 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(IOPalette.strip)
        .overlay(alignment: .bottom) {
            Rectangle().fill(IOPalette.demoCardBorder).frame(height: 1)
        }
    }

}

private struct IODemoLiftRow: View {
    let row: IOSessionDemoCardRow

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
                            .foregroundStyle(IOPalette.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    Spacer(minLength: 4)
                    // One tile per set. NOT accompanied by a "4 sets" label — that pairing was
                    // tried and it reads as a key the tiles do not need, while costing the row
                    // the width four tiles want. Four tiles already say four sets.
                    HStack(spacing: 3.5) {
                        ForEach(row.efforts.indices, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 4)
                                .fill(IOShowcaseEffort.color(row.efforts[i]))
                                .frame(width: 16, height: 16)
                        }
                    }
                }
                .frame(height: 30)

                if let reason = row.reason {
                    Text(reason)
                        .font(.system(size: 10.5))
                        .foregroundStyle(IOPalette.textMuted)
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

/// A CARD AGAIN, BUT NOT A LOUD ONE. Worth reading the two swings this went through, because
/// they separate two things that were being changed together and only one of them was the
/// problem.
///
/// The original was a #161616 fill with a 1pt AMBER-BROWN border (#57492A), a 22pt shield and a
/// 20pt Bebas title — the heaviest element between the headline and the price, reading as a
/// second pitch competing with the session card. Stripping the box fixed that and overshot: a
/// guarantee with no container stops being a distinct promise and becomes another paragraph.
///
/// The container was never what made it loud. The amber border, the 22pt glyph and the 20pt
/// Bebas were. So the box comes back with a neutral #161616 fill and a #222222 hairline — no
/// accent anywhere in the chrome — while the quiet type survives: 14pt shield, and an 11pt
/// tracked Inter title matching "EVERYTHING IN PREMIUM" below, which is its real peer.
private struct IOGuaranteeCard: View {
    var body: some View {
        VStack(spacing: 0) {
            // SEAL AND TITLE ON ONE ROW, centred as a group — a letterhead rather than a stack.
            // The seal had its own row briefly and it was wrong twice over: it cost ~50pt of
            // height on a card that is already the tallest thing in the scroll region, and a
            // disc floating above a title reads as an illustration of the title rather than as
            // a mark issued alongside it. Side by side is how a seal actually sits on a
            // document.
            //
            // Measured against Bebas's own advance widths: the pair is ~202pt of the 281pt
            // available inside the card's padding on a 375pt screen, so nothing scales.
            HStack(spacing: 10) {
                seal
                // 20pt Bebas, back to the size the very first version used. That size was
                // removed once for being too loud — correctly, at the time, when this block sat
                // in the first screenful and competed with the headline. It no longer does: the
                // session showcase pushed it below the fold on every device, so a reader only
                // reaches it deliberately and the loudness has nothing left to shout over.
                Text(IOCopy.guaranteeTitle)
                    .font(.bebasNeue(size: 20))
                    .tracking(1.2)
                    .foregroundStyle(IOPalette.amberText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            // A short centred rule under the row. Cheap, and it is most of what separates "a
            // card with a shield on it" from something that reads as issued.
            Rectangle()
                .fill(IOPalette.amberText.opacity(0.45))
                .frame(width: 46, height: 1)
                .padding(.top, 9)
                .padding(.bottom, 9)

            // CONDITION THEN REMEDY, as two centred lines. Centring is the thing doing the
            // "official" work here — certificates, seals and warranties are centred, and the
            // left-aligned version read as a tip. It also sets this block apart from the
            // premium list below it, which is a left-aligned table, and lines it up with the
            // price anchor underneath, which is already centred.
            VStack(spacing: 3) {
                Text(IOCopy.guaranteeBody1)
                    .foregroundStyle(IOPalette.textSecondary)

                // Accented term inside prose, built by Text concatenation the same way
                // `FirstProgressCelebrationCard` does it. The remedy is the only part of this
                // block the reader is being offered rather than asked for.
                (Text(IOCopy.guaranteeBody2Lead)
                    .foregroundColor(IOPalette.textSecondary)
                 + Text(IOCopy.guaranteeBody2Remedy)
                    .foregroundColor(IOPalette.amberText))
            }
            .font(.system(size: 12.5))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 18)
        // A warm gradient rather than a flat fill, so the block has a light source. Lifted from
        // 5% to 7% amber along with everything else here.
        .background(
            LinearGradient(
                colors: [IOPalette.amberText.opacity(0.07), Color(white: 0x12/255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // DOUBLE BORDER — the one device that most reliably reads as a document rather than a
        // card. An outer edge at 32% amber, and a hairline at 14% inset 5pt inside it. Neither
        // is loud on its own; it is the pair that signals "certificate", because almost nothing
        // else in an app is drawn this way.
        //
        // The inner rule's radius is 9, not 14: an inset border has to tighten its corners by
        // the inset or the two curves diverge and the frame reads as a rendering mistake.
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(IOPalette.amberText.opacity(0.32), lineWidth: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9)
                .strokeBorder(IOPalette.amberText.opacity(0.14), lineWidth: 1)
                .padding(5)
        )
        .accessibilityElement(children: .combine)
    }

    /// The seal. A filled shield inside two concentric rings.
    ///
    /// WHY TWO RINGS. One ring is a badge; two is a stamp. The outer ring is dashed, which is
    /// the perforated-edge cue every physical seal and postage stamp carries — it is doing the
    /// same job as the double border around the card, at a different scale, and for the same
    /// reason: it is a shape that exists almost nowhere else in an app, so it reads as issued
    /// rather than as decoration.
    private var seal: some View {
        ZStack {
            // 36, down from 42. Standing alone it had the whole row's width to balance
            // against; beside 20pt caps a 42pt disc dominated the title it is supposed to
            // accompany. 36 outer against a ~14pt cap height reads as a mark on a line of type.
            Circle()
                .fill(IOPalette.amberText.opacity(0.12))
                .frame(width: 36, height: 36)

            Circle()
                .strokeBorder(
                    IOPalette.amberText.opacity(0.30),
                    style: StrokeStyle(lineWidth: 1, dash: [2.5, 2.5])
                )
                .frame(width: 36, height: 36)

            Circle()
                .strokeBorder(IOPalette.amberText.opacity(0.45), lineWidth: 1)
                .frame(width: 28, height: 28)

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 15))
                .foregroundStyle(IOPalette.amberText)
        }
        .accessibilityHidden(true)
    }
}

// MARK: Section D — everything in premium

private struct IOPremiumStackList: View {
    private struct Row: Identifiable {
        let id = UUID()
        let name: String
        let desc: String
        let glyph: IOGlyph
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
        // BOUNDED. This was five rows between six full-bleed hairlines with a centred title
        // floating above them — which is a table, not a block, and it ran edge to edge with
        // nothing marking where the section started or ended. Against a session card above it
        // and a guarantee card below, it was the one section with no boundary at all.
        //
        // The container does the bounding, so the rules no longer have to: the leading and
        // trailing hairlines are gone and the remaining four are INTERIOR separators inset
        // from the card edge. Five rows now need four rules instead of six.
        VStack(spacing: 0) {
            // AMBER, not white. This was the only section heading below the fold with no
            // accent in it at all, which is most of why the block read as a cold table sitting
            // between two warm ones. The guarantee above and the price anchor below both carry
            // amber in their titles; this one now joins them.
            Text(IOCopy.premiumTitle)
                .font(.bebasNeue(size: 21))
                .tracking(0.6)
                .foregroundStyle(IOPalette.amberText)
                .frame(height: 24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                    if index > 0 {
                        // Warmed from neutral #222222. At 8% amber it is the same weight of
                        // line, but it stops the interior of a warm card being ruled with cold
                        // grey, which is visible once the fill around it has any colour in it.
                        Rectangle()
                            .fill(IOPalette.amberText.opacity(0.08))
                            .frame(height: 1)
                    }
                    IOPremiumStackRow(name: row.name, desc: row.desc, glyph: row.glyph)
                }
            }
            .padding(.top, 10)
        }
        .padding(.vertical, 13)
        .padding(.horizontal, 14)
        // WARMED, reversing an earlier call. This was deliberately neutral — flat #111111
        // with a grey #2A2A2A border — on the reasoning that five rows is the longest block on
        // the screen and a wash on something that tall would read as demanding attention.
        //
        // That was the wrong trade. Sitting between the guarantee's amber seal above and the
        // amber price anchor below, the one cold block in the sequence did not read as
        // restrained, it read as unfinished, and the eye skipped it at exactly the point it is
        // meant to be itemising what you get.
        //
        // The wash is deliberately lighter than the guarantee's (6% against 7%) and there is no
        // double border or seal, so the two remain distinguishable: one is a certificate, this
        // is a list.
        .background(
            LinearGradient(
                colors: [IOPalette.amberText.opacity(0.06), Color(white: 0x12/255.0)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14)
            .strokeBorder(IOPalette.amberText.opacity(0.22), lineWidth: 1))
    }
}

private struct IOPremiumStackRow: View {
    let name: String
    let desc: String
    let glyph: IOGlyph

    var body: some View {
        HStack(spacing: 12) {
            // A TILE BEHIND EVERY GLYPH, and this is the change doing most of the work.
            //
            // The five glyphs are deliberately heterogeneous — one amber SF Symbol, one green
            // one, an amber share icon, and two hand-drawn multicoloured figures, because no
            // single symbol set says "these lifts are out of balance" and "a set scheme". The
            // cost of that is a left edge with no repeating element, so there was nothing for
            // the eye to lock onto and the rows read as five unrelated lines.
            //
            // The tile is the repetition. Kept at 8% amber specifically so it unifies the
            // column without competing with the glyphs sitting on it — a saturated tile would
            // fight the green and the multicoloured squares rather than containing them.
            ZStack {
                RoundedRectangle(cornerRadius: 9)
                    .fill(IOPalette.amberText.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 9)
                            .strokeBorder(IOPalette.amberText.opacity(0.16), lineWidth: 1)
                    )
                glyph.view
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 0) {
                // v2 drops the BONUS tags. Four of five rows carried one, which made the tag
                // mean "not Smart Sessions" rather than "extra" — it stopped distinguishing
                // anything. The row keeps its height; only the tag is gone.
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                Text(desc)
                    .font(.system(size: 12))
                    .foregroundStyle(IOPalette.textMuted)
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
private enum IOGlyph {
    case barbell, bars, trend, grid, share

    @ViewBuilder var view: some View {
        switch self {
        case .barbell:
            Image(systemName: "dumbbell.fill")
                .font(.system(size: 17))
                .foregroundStyle(IOPalette.amberText)
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
                .foregroundStyle(IOPalette.amberFill)
        }
    }

    private func bar(_ width: CGFloat, _ color: Color) -> some View {
        Capsule().fill(color).frame(width: width, height: 4)
    }

    private func square(_ effort: String) -> some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(IOShowcaseEffort.color(effort))
            .frame(width: 7, height: 7)
    }
}

// MARK: Section E — price anchor

private struct IOPriceAnchor: View {
    let yearlyPrice: String
    let perMonth: String

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: -4) {
                Text(IOCopy.anchor1).foregroundStyle(.white)
                Text(IOCopy.anchor2).foregroundStyle(IOPalette.amberText)
            }
            .font(.bebasNeue(size: 24))
            .tracking(0.5)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            Text(IOCopy.anchorSub(yearlyPrice, perMonth))
                .font(.system(size: 12.5))
                .foregroundStyle(IOPalette.textMuted)
                .padding(.top, 6)
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
