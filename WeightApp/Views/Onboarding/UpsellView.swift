//
//  UpsellView.swift
//  WeightApp
//
//  The paywall. Presented after onboarding, from the Session tab, and from every locked feature.
//  `initialPage` lands the user on the feature they tapped — `SubscriptionConfig.upsellPage(for:)`
//  resolves those by title; it defaults to 0, which is Smart Sessions.
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

struct UpsellView: View {
    /// Which carousel page to open on. Index into `SubscriptionConfig.premiumFeatures`, so a
    /// lock state can land the user on the feature they just tapped; `SubscriptionConfig
    /// .upsellPage(for:)` resolves those by title. Defaults to 0 — Smart Sessions.
    let initialPage: Int
    /// Where this was presented from. Defaulted only so a forgotten call site is loud in the
    /// data ("unspecified") rather than silently pooled with a real source.
    let source: SubscriptionConfig.UpsellSource
    let onComplete: (Bool) -> Void

    init(initialPage: Int = 0,
         source: SubscriptionConfig.UpsellSource,
         onComplete: @escaping (Bool) -> Void) {
        self.initialPage = initialPage
        self.source = source
        self.onComplete = onComplete
        self._currentPage = State(initialValue: initialPage)
    }

    @Environment(\.modelContext) private var modelContext
    @StateObject private var purchaseService = PurchaseService.shared
    @State private var selectedPlan: Plan = .yearly
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var currentPage: Int
    @State private var safariURL: URL?

    // Entrance stagger. Carried over from `LegacyUpsellView`, minus the two stages that animated
    // a title and a badge this design no longer has.
    //
    // It matters most where this screen is seen first — straight out of onboarding, where the
    // whole thing appearing at once lands as an ambush. Building it top-down over about a second
    // reads as the screen arriving rather than being thrown at you.
    /// When the paywall appeared, for `seconds_on_screen` on dismissal.
    @State private var shownAt = Date()

    @State private var carouselOpacity: Double = 0
    @State private var pricingOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    enum Plan { case monthly, yearly }

    /// Pages, in order. Only Smart Sessions is designed; the rest are placeholders so the
    /// carousel is complete enough to judge the layout.
    private let pages = SubscriptionConfig.premiumFeatures

    var body: some View {
        ZStack {
            // Flat, not the shipping paywall's top-down gradient. The gradient reads as a
            // vignette behind a header that no longer exists, and it puts the lightest part of
            // the screen where there is now only the carousel.
            Color(white: 0x0A/255.0)   // #0A0A0A
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Takes every point the header and the X used to occupy.
                carousel
                    .frame(maxHeight: .infinity)
                    .task {
                        // Not optional: without it `purchaseService.yearlyProduct` is nil and
                        // every tap on the CTA fails with "Product not available".
                        await purchaseService.loadProducts()
                    }
                    .opacity(carouselOpacity)

                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(pricingOpacity)

                Spacer().frame(height: 14)

                subscribeButton
                    .padding(.horizontal, 24)
                    .opacity(ctaOpacity)

                Text(selectedPlan == .yearly
                     ? "7-day free trial, then \(SubscriptionConfig.yearlyDisplayPrice)/year. Cancel anytime."
                     : "\(SubscriptionConfig.monthlyDisplayPrice)/month. Cancel anytime.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .opacity(ctaOpacity)

                // Replaces the X. The flanking rules do the work the padding used to: they
                // separate it from the CTA above and the legal text below without spending
                // vertical space, which the carousel needs more than this does. Both rules take
                // the same expansion, so they stay symmetrical at any width.
                HStack(spacing: 12) {
                    rule
                    Button("Not now") { dismiss() }
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .disabled(isProcessing)
                    rule
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 16)
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
            AmplitudeService.shared.track(.premiumUpsellShown(
                source: source.rawValue,
                initialPage: initialPage,
                initialFeature: featureTitle(at: initialPage)
            ))

            // 0.0s — the carousel. First here, where the legacy design ran a title and badge
            // ahead of it; this screen's headline lives inside the carousel, so it leads.
            withAnimation(.easeOut(duration: 0.4)) {
                carouselOpacity = 1.0
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

    // MARK: - Carousel

    private var carousel: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    Group {
                        if pages[index].title == SubscriptionConfig.smartSessionsTitle {
                            SmartSessionsPage()
                        } else {
                            FeaturePage(feature: pages[index])
                        }
                    }
                    .padding(.horizontal, 20)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            // Fires on landing, not on the initial page — that one is already reported by
            // `premiumUpsellShown`, and double-counting it would inflate page 0 on every
            // presentation and make the swipe-through rate meaningless.
            .onChange(of: currentPage) { _, page in
                AmplitudeService.shared.track(.upsellPageViewed(
                    source: source.rawValue,
                    feature: featureTitle(at: page),
                    index: page
                ))
            }

            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Circle()
                        .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.25))
                        .frame(width: 7, height: 7)
                }
            }
            .padding(.bottom, 6)
        }
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
                    price: SubscriptionConfig.yearlyDisplayPrice,
                    priceSubtitle: "(\(SubscriptionConfig.yearlyPerMonthPrice)/mo)",
                    badge: SubscriptionConfig.bestValueBadge,
                    verticalPadding: 10,
                    onTap: { selectPlan(.yearly) }
                )
            }

            PlanCard(
                isSelected: selectedPlan == .monthly,
                title: "Monthly",
                price: SubscriptionConfig.monthlyDisplayPrice,
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

    /// Feature title for the page currently on screen, for the page-level events.
    private func featureTitle(at index: Int) -> String {
        guard pages.indices.contains(index) else { return "unknown" }
        return pages[index].title.replacingOccurrences(of: "\n", with: " ")
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
            feature: featureTitle(at: currentPage),
            secondsOnScreen: Date().timeIntervalSince(shownAt)
        ))
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
private enum ShowcaseEffort {
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

/// The page this experiment exists to rethink.
///
/// The shipping card is a two-column split: four generic bullets on the left, a small screenshot
/// on the right. That tells you Smart Sessions has features. It does not show you a session,
/// which is the only thing that explains what this is.
///
/// So the page IS a session, read top to bottom as one sentence: here is what you told it, here
/// is what came back. No bullets — each of them restated something the thing below it already
/// demonstrates. Drawn live rather than from an exported image, so it stays sharp, reflows to
/// whatever the carousel gives it, and tracks `SessionShowcase` with no export step.
///
/// Only the Bench row carries a reasoning caption. Giving all three one turns the card back into
/// a list; giving it to the row that also owns the single gold square puts the strongest evidence
/// and the brightest element in the same place.
private struct SmartSessionsPage: View {
    private let plan = SessionShowcase.plan
    private let context = SessionShowcase.context

    private let cardFill = Color(white: 0x16/255.0)        // #161616
    private let chipFill = Color(white: 0x2A/255.0)        // #2A2A2A

    private var chips: [String] {
        (ProgramMockData.contextChips + ProgramMockData.sessionShapeChips)
            .filter { context.chips.contains($0) }
    }

    /// The row's icon slot. Fixed, so every lift name starts at the same x.
    private static let iconSlot: CGFloat = 34

    /// Drawn size per lift — an optical correction, not a data one.
    ///
    /// These glyphs are line art with different amounts of surrounding whitespace and different
    /// stroke densities, so at one nominal size they do not read as one weight: the bench figure
    /// is horizontal and busy and sits heavy, while the overhead figure is narrow and reads small.
    /// Deadlifts is the reference at the slot size.
    private func iconSize(_ item: MockPlanItem) -> CGFloat {
        switch item.exerciseName {
        case "Bench Press":    return 30
        case "Overhead Press": return 38
        default:               return Self.iconSlot
        }
    }

    /// A shorter summary than `SessionShowcase.plan.summary`, for this page only.
    ///
    /// The shared one names the two chips and explains why Squats and Rows sit out, which is
    /// right on the Session tab where the card has a whole screen. Here it runs to FOUR lines on
    /// every device against the brief version's two, and the page already scrolls on anything
    /// smaller than a 6.3" phone — so those two lines come straight out of the screenshot below,
    /// which is the thing actually doing the selling.
    ///
    /// The context that copy would have explained is directly above this anyway: the chips and
    /// the quote are on screen, so a reader can make the connection without being walked through
    /// it. Counts derived, so the numbers still cannot disagree with the squares.
    private var briefSummary: String {
        let sets = plan.items.reduce(0) { $0 + $1.sequence.count }
        return "\(plan.items.count) lifts, \(sets) sets. The heavy pulls come first, "
            + "then an easy one for that shoulder."
    }

    /// The one lift whose reasoning line is shown.
    private var captionedLift: UUID? {
        plan.items.first { $0.exerciseName == "Bench Press" }?.id
    }

    var body: some View {
        // Scrolls only when it has to. Trimming fixed the overflow on a 6.3" phone, but the
        // page still needs ~456pt and an iPhone SE leaves the carousel ~355 — no amount of
        // padding closes that. `minHeight` keeps the content centred whenever it does fit, so
        // on everything modern this behaves exactly like the plain stack it replaces.
        GeometryReader { geo in
            ScrollView(.vertical, showsIndicators: false) {
                content.frame(minHeight: geo.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Text("SMART SESSIONS")
                .font(.inter(size: 13))
                .tracking(3.5)
                .foregroundStyle(ShowcaseEffort.gold)

            Spacer().frame(height: 10)

            // Bebas Neue is already a condensed all-caps face, so the copy is set in caps and
            // the negative spacing pulls the two lines into one block rather than two lines.
            VStack(spacing: -6) {
                Text("SHOW UP.")
                    .foregroundStyle(.white)
                Text("WE'LL PICK.")
                    .foregroundStyle(ShowcaseEffort.gold)
            }
            .font(.bebasNeue(size: 36))

            Spacer().frame(height: 16)

            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(chipFill))
                }
            }

            Spacer().frame(height: 10)

            Text("“\(context.note)”")
                .font(.system(size: 14).italic())
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            // The turn. Small, but it is what makes the two halves read as one sentence rather
            // than two stacked lists.
            Image(systemName: "arrow.down")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(ShowcaseEffort.gold)
                .padding(.vertical, 7)

            sessionCard

            Spacer(minLength: 0)
        }
        .padding(.bottom, 30)   // clears the pagination dots, with room to breathe
    }

    private var sessionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(spacing: 4) {
                // Not Bebas. The condensed face gave this the same voice as the page headline
                // two elements above it, so the card read as a second title rather than as a
                // label on the thing below it. Smaller and dimmer puts it back in its place.
                Text("Today's Session")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text(briefSummary)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 14) {
                ForEach(plan.items) { item in
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 12) {
                            Image(item.icon)
                                .resizable().scaledToFit()
                                .frame(width: iconSize(item), height: iconSize(item))
                                // Constant slot around a varying glyph. The per-lift sizes below
                                // are optical corrections, and letting them change the slot would
                                // ripple into the lift names, which must stay left-aligned with
                                // each other.
                                .frame(width: Self.iconSlot, height: Self.iconSlot)
                                // Back to white line art. Amber read well on its own, but three
                                // gold glyphs plus a gold border left the single gold progress
                                // square with nothing to stand out against.
                                .foregroundStyle(.white.opacity(0.9))

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.exerciseName)
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                // Grey, not gold — a gold plan name on every row would compete
                                // with the progress square for the same job.
                                Text(item.planName)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.45))
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 8)

                            effortSquares(item.sequence)
                        }

                        // One row only, and it is the row that also owns the single gold square:
                        // the strongest evidence and the brightest element land together. On all
                        // three this became a list; on none of them the card never showed that
                        // the generator reasons about a specific lift's history.
                        if item.id == captionedLift {
                            Text(item.rationale)
                                .font(.system(size: 11))
                                .foregroundStyle(.white.opacity(0.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.75)
                                .padding(.leading, 46)   // 34pt icon + 12pt row spacing
                        }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(cardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
                )
        )
    }

    /// Drawn here rather than via `EffortSquares` because the app component reads
    /// `ProgramEffort.color`, and this card runs the tuned palette above. Always full
    /// saturation — the app's unlogged tile is 16% opacity, which is right in the app and
    /// invisible here.
    private func effortSquares(_ sequence: [String]) -> some View {
        HStack(spacing: 4) {
            ForEach(sequence.indices, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4)
                    .fill(ShowcaseEffort.color(sequence[i]))
                    .frame(width: 19, height: 19)
            }
        }
    }
}

// MARK: - Feature page (the other four)

/// The remaining features, built to the same skeleton as `SmartSessionsPage` so swiping between
/// them does not feel like swiping between two apps:
///
///     gold tracked eyebrow  ->  big condensed headline  ->  what you get  ->  the thing itself
///
/// The differences from that page are only what the content forces: the eyebrow is the tier
/// rather than the feature (the headline is already the feature name), and the payoff at the
/// bottom is an exported screenshot instead of a live card.
///
/// The screenshot runs the full width and is cut off by the bottom of the carousel. Shown whole
/// it is a 1:2.17 sliver that has to shrink below ~150pt wide to fit anything above it, which is
/// how the shipping card ends up with a thumbnail nobody can read. Anchored at the top of its
/// crop and allowed to run off the bottom, it is nearly three times wider, and the top of the
/// card — the part that names what you are looking at — is legible.
private struct FeaturePage: View {
    let feature: (icon: String, title: String, description: String, color: Color,
                  bullets: [(icon: String, text: String, color: Color)])

    /// Two columns, so each text cell is ~140pt on the narrowest device. The longest bullet
    /// ("Upper / Lower Balance") runs 10.61x the point size, putting the wrap point at 13.2pt.
    private static let bulletSize: CGFloat = 12.5

    /// Progress Card carries `[]` in the config — the shipping paywall gives it a bespoke card
    /// with its bullets hardcoded in the view, so the shared data was never filled in. Supplied
    /// here rather than there, to leave the shipping paywall's table alone.
    private var bullets: [(icon: String, text: String, color: Color)] {
        guard feature.bullets.isEmpty else { return feature.bullets }
        return [("trophy.fill", "Personal Records", .setPR),
                ("chart.bar.fill", "Strength Tiers", .setEasy),
                ("flame.fill", "Intensity Breakdown", .setNearMax),
                ("square.and.arrow.up.fill", "Shareable Image", .setHard)]
    }

    /// Display title for this experiment only — `SubscriptionConfig`'s titles are shared with the
    /// shipping paywall and every lock state's deep link.
    ///
    /// "Progress Cards" is plural because there is one per week; the config name is singular.
    /// Set Plan Catalog keeps its real name now that "includes" is gone — without that lead-in,
    /// "All Set Plans" was solving a sentence that no longer exists.
    private var displayTitle: String {
        feature.title == SubscriptionConfig.progressCardTitle ? "Progress Cards" : feature.title
    }

    private var assetName: String? {
        switch feature.title {
        case SubscriptionConfig.balanceTitle:        return "DisplayBalanceCard"
        case SubscriptionConfig.analyticsTitle:      return "DisplayAnalyticsCard"
        case SubscriptionConfig.setPlanCatalogTitle: return "DisplaySetPlanCard"
        case SubscriptionConfig.progressCardTitle:   return "DisplayProgressCard"
        default:                                     return nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // The feature's own glyph. Slide one has none and needs none — it is the only page
            // whose subject is named in its eyebrow. Here the eyebrow is the tier, so the icon
            // is what tells these four pages apart at a glance.
            Image(systemName: feature.icon)
                .font(.system(size: 24))
                .foregroundStyle(ShowcaseEffort.gold)

            Spacer().frame(height: 10)

            // Same eyebrow treatment as SMART SESSIONS on slide one.
            Text("PREMIUM")
                .font(.inter(size: 13))
                .tracking(3.5)
                .foregroundStyle(ShowcaseEffort.gold)

            Spacer().frame(height: 10)

            // Same face and size as "SHOW UP. / WE'LL PICK." — the feature name is this page's
            // headline, so it should carry the headline's weight.
            Text(displayTitle)
                .font(.bebasNeue(size: 36))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineSpacing(-6)
                .fixedSize(horizontal: false, vertical: true)

            Spacer().frame(height: 18)

            // Two columns. Half the height of a stacked list, and that height is exactly what
            // lets the screenshot below sit higher and show more of itself.
            let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                ForEach(bullets.indices, id: \.self) { i in
                    HStack(spacing: 7) {
                        Image(systemName: bullets[i].icon)
                            .font(.system(size: 13))
                            .foregroundStyle(bullets[i].color)
                            .frame(width: 16)
                        Text(bullets[i].text)
                            .font(.inter(size: Self.bulletSize))
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 6)

            Spacer().frame(height: 20)

            if let assetName {
                // `.fill`, NOT `.scaledToFit()`.
                //
                // Fit honours BOTH dimensions, so a 1:2.17 asset dropped into a short wide frame
                // is constrained by height and collapses to about a quarter of the frame's width
                // — the whole card rendered small inside an oversized border, which is exactly
                // what it was doing. Fill covers the frame and lets the excess run off the
                // bottom, which is the crop this layout is built around.
                //
                // `Color.black` carries the flexible frame and the image rides on top of it, so
                // the crop is driven by the container rather than by the image's own size.
                Color.black
                    .overlay(alignment: .top) {
                        Image(assetName)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Top corners only. The bottom edge is off-screen by design, so rounding or
                    // stroking it would draw a boundary where the content is meant to continue.
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14))
                    .overlay(
                        UnevenRoundedRectangle(topLeadingRadius: 14, topTrailingRadius: 14)
                            .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
                    )
                    // Inset from the page edges so it reads as an object on the screen rather
                    // than as the screen itself — and narrower means a smaller scale factor, so
                    // the same height shows more of the card.
                    .padding(.horizontal, 36)
            } else {
                Spacer(minLength: 0)
            }
        }
    }
}

// MARK: - Plan Card

/// Shared with `LegacyUpsellView`, which is why this is not `private`.
struct PlanCard: View {
    let isSelected: Bool
    let title: String
    let price: String
    let priceSubtitle: String?
    let badge: String?
    /// Defaulted so `LegacyUpsellView` keeps its original proportions; `UpsellView` passes a
    /// smaller value to buy vertical space for the carousel above it.
    var verticalPadding: CGFloat = 14
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // Selection indicator
                Circle()
                    .strokeBorder(isSelected ? Color.appAccent : Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.appAccent : Color.clear)
                            .frame(width: 12, height: 12)
                    )

                // Price (prominent)
                Text(price)
                    .font(.bebasNeue(size: 22))
                    .foregroundStyle(.white)

                // Title + per-month subtitle
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.interSemiBold(size: 14))
                        .foregroundStyle(.white)

                    if let priceSubtitle {
                        Text(priceSubtitle)
                            .font(.inter(size: 11))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Spacer()

                // Badge (right side)
                if let badge {
                    Text(badge)
                        .font(.interSemiBold(size: 9))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(Color.appAccent)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
