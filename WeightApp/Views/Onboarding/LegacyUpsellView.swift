//
//  LegacyUpsellView.swift
//  WeightApp
//
//  The previous paywall, superseded by `UpsellView`. Kept, not deleted: it is the design every
//  conversion number to date was measured against, so it is the only honest comparison if the
//  new one underperforms. Reachable from More → Developer → Flows & Previews.
//
//  Nothing routes here automatically. Post-onboarding, the Session tab and every lock state all
//  present `UpsellView`.
//

import SwiftUI
import SwiftData
import StoreKit
import Sentry

struct LegacyUpsellView: View {
    let initialPage: Int
    let onComplete: (Bool) -> Void  // Bool indicates whether user subscribed

    init(initialPage: Int = 0, onComplete: @escaping (Bool) -> Void) {
        self.initialPage = initialPage
        self.onComplete = onComplete
        self._currentPage = State(initialValue: initialPage)
    }

    @Environment(\.modelContext) private var modelContext
    @StateObject private var purchaseService = PurchaseService.shared
    @State private var selectedPlan: SubscriptionPlan = .yearly
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var currentPage: Int
    @State private var safariURL: URL?

    // Entrance animation states
    @State private var titleOpacity: Double = 0
    @State private var badgeGlow: Double = 0
    @State private var carouselOpacity: Double = 0
    @State private var pricingOpacity: Double = 0
    @State private var ctaOpacity: Double = 0

    private enum SubscriptionPlan {
        case monthly
        case yearly
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(white: 0.12), .black],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header — icon + TRAIN SMARTER + badge
                headerSection
                    .padding(.top, 66)
                    .task {
                        await purchaseService.loadProducts()
                    }

                Spacer()
                    .frame(height: 12)

                // Benefits Carousel
                benefitsCarousel
                    .opacity(carouselOpacity)

                Spacer()
                    .frame(height: 14)

                // Pricing Section
                pricingSection
                    .padding(.horizontal, 24)
                    .opacity(pricingOpacity)

                Spacer()
                    .frame(height: 16)

                // Subscribe Button
                subscribeButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 10)
                    .opacity(ctaOpacity)

                // Plan-specific subtitle
                Text(selectedPlan == .yearly
                     ? "7-day free trial, then \(SubscriptionConfig.yearlyDisplayPrice)/year. Cancel anytime."
                     : "\(SubscriptionConfig.monthlyDisplayPrice)/month. Cancel anytime.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 8)
                    .opacity(ctaOpacity)

                // Footer Links
                footerLinks
                    .padding(.bottom, 16)
                    .opacity(ctaOpacity)
            }

            // X dismiss button (top-right overlay)
            dismissButton
                .opacity(ctaOpacity)
        }
        .sheet(item: $safariURL) { url in
            SafariView(url: url)
                .ignoresSafeArea()
        }
        .onAppear {
            AmplitudeService.shared.track(.premiumUpsellShown(
                source: SubscriptionConfig.UpsellSource.legacyDevPreview.rawValue,
                initialPage: initialPage,
                initialFeature: "legacy"
            ))
            // 0.0s — Badge fades in
            withAnimation(.easeOut(duration: 0.4)) {
                titleOpacity = 1.0
            }

            // 0.2s — Badge glow pulses
            withAnimation(.easeInOut(duration: 1.2).delay(0.2).repeatForever(autoreverses: true)) {
                badgeGlow = 1.0
            }

            // 0.3s — Carousel container fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
                carouselOpacity = 1.0
            }

            // 0.7s — Pricing section fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.7)) {
                pricingOpacity = 1.0
            }

            // 0.9s — Subscribe button + X fades in
            withAnimation(.easeOut(duration: 0.4).delay(0.9)) {
                ctaOpacity = 1.0
            }
        }
    }

    // MARK: - Dismiss Button

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 8) {
            // Unlock Your Strength
            HStack(spacing: 6) {
                Text("Unlock")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(.white)
                Text("Your Strength")
                    .font(.bebasNeue(size: 32))
                    .foregroundStyle(Color.appAccent)
            }

            // GO PREMIUM badge
            Text("GO PREMIUM")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2.5)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(.white.opacity(0.5), lineWidth: 1)
                )
                .shadow(color: Color.appAccent.opacity(badgeGlow * 0.3), radius: 10, x: 0, y: 0)
        }
        .opacity(titleOpacity)
    }

    // MARK: - Dismiss Button

    private var dismissButton: some View {
        Button {
            onComplete(false)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.white.opacity(0.4))
                .padding(14)
        }
        .buttonStyle(.plain)
        .disabled(isProcessing)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .padding(.trailing, 8)
        .padding(.top, 24)
    }

    // MARK: - Benefits Carousel

    private let totalPages = SubscriptionConfig.premiumFeatures.count

    private var benefitsCarousel: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $currentPage) {
                // FEATURE FLAG: the overview page is disabled, not deleted.
                //
                // It was page 0 — the bull silhouette behind a scrolling column of feature
                // names. It looks good, but it opened a paywall on decoration rather than
                // on a reason to pay, and it pushed every real feature a swipe away. The
                // first card is now the strongest feature instead.
                //
                // To revive: uncomment the block below AND the `overviewPage` property,
                // restore `totalPages` to `... .count + 1`, change the `.tag(index)` calls
                // below back to `.tag(index + 1)`, and make `upsellPage(for:)` in
                // `SubscriptionConfig` return `index + 1` again. That last one is the
                // easily-missed step: every lock state in the app routes through it, so
                // leaving it alone would send all of them one page short.
                //
                // overviewPage
                //     .padding(.horizontal, 20)
                //     .tag(0)

                // One page per feature, in array order. Page index IS the array index.
                ForEach(0..<SubscriptionConfig.premiumFeatures.count, id: \.self) { index in
                    let feature = SubscriptionConfig.premiumFeatures[index]
                    if feature.title == SubscriptionConfig.smartSessionsTitle {
                        SmartSessionsFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index)
                    } else if feature.title == SubscriptionConfig.progressCardTitle {
                        ProgressCardFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index)
                    } else if feature.title == SubscriptionConfig.balanceTitle {
                        StrengthBalanceFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index)
                    } else if feature.title == SubscriptionConfig.analyticsTitle {
                        AdvancedAnalyticsFeatureCard()
                            .padding(.horizontal, 20)
                            .tag(index)
                    } else {
                        PremiumFeatureCard(
                            icon: feature.icon,
                            title: feature.title,
                            bullets: feature.bullets
                        )
                        .padding(.horizontal, 20)
                        .tag(index)
                    }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 350)

            // Page indicators + swipe hint overlaid at the bottom
            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.appAccent : Color.white.opacity(0.25))
                            .frame(width: 7, height: 7)
                    }
                }

                HStack(spacing: 4) {
                    Text("Swipe to explore")
                        .font(.inter(size: 10))
                        .foregroundStyle(.white.opacity(0.4))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.4))
                }
                .opacity(currentPage == totalPages - 1 ? 0 : 1)
            }
            .padding(.bottom, 14)
        }
    }

    // MARK: - Overview Page (DISABLED)
    //
    // Disabled with its `.tag(0)` entry in `benefitsCarousel`; see the revival steps
    // there. Kept because the artwork and the scrolling column are worth more than the
    // effort of rebuilding them, and `ScrollingFeatureColumn` below is retained for the
    // same reason — it has no other caller while this is off.

    // private var overviewPage: some View {
    //     ZStack(alignment: .bottomTrailing) {
    //         // Dark background
    //         Color(white: 0.10)
    //
    //         // Bull figure — amber, bottom-right, cropped at hips
    //         Image("PoseFromBehind")
    //             .resizable()
    //             .aspectRatio(contentMode: .fit)
    //             .foregroundStyle(Color.appAccent)
    //             .frame(height: 260)
    //             .offset(x: 20, y: 30)
    //
    //         // Scrolling feature column — spans full height
    //         HStack(spacing: 0) {
    //             ScrollingFeatureColumn(direction: .down)
    //                 .frame(width: 160)
    //                 .padding(.leading, 18)
    //
    //             Spacer()
    //         }
    //     }
    //     .frame(maxWidth: .infinity)
    //     .frame(height: 338)
    //     .clipShape(RoundedRectangle(cornerRadius: 16))
    //     .overlay(
    //         RoundedRectangle(cornerRadius: 16)
    //             .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
    //     )
    // }
    //

    // MARK: - Pricing Section

    private var pricingSection: some View {
        VStack(spacing: 16) {
            // Yearly plan with "7 DAYS FREE" notch
            VStack(alignment: .leading, spacing: 0) {
                // Notch tab — left-aligned
                Text("7 DAYS FREE")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color.appAccent)
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
                    .padding(.leading, 24)

                // Yearly plan card
                PlanCard(
                    isSelected: selectedPlan == .yearly,
                    title: "Yearly",
                    price: SubscriptionConfig.yearlyDisplayPrice,
                    priceSubtitle: "(\(SubscriptionConfig.yearlyPerMonthPrice)/mo)",
                    badge: SubscriptionConfig.bestValueBadge,
                    onTap: { selectedPlan = .yearly }
                )
            }

            // Monthly plan
            PlanCard(
                isSelected: selectedPlan == .monthly,
                title: "Monthly",
                price: SubscriptionConfig.monthlyDisplayPrice,
                priceSubtitle: nil,
                badge: nil,
                onTap: { selectedPlan = .monthly }
            )
        }
    }

    // MARK: - Subscribe Button

    private var subscribeButton: some View {
        VStack(spacing: 8) {
            Button {
                Task {
                    await handlePurchase()
                }
            } label: {
                HStack {
                    if isProcessing {
                        ProgressView()
                            .tint(.black)
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
            .padding(.horizontal, 32)

            if let errorMessage {
                Text(errorMessage)
                    .font(.inter(size: 12))
                    .foregroundStyle(.red.opacity(0.8))
            }
        }
    }

    private func handlePurchase() async {
        let product: Product?
        switch selectedPlan {
        case .monthly:
            product = purchaseService.monthlyProduct
        case .yearly:
            product = purchaseService.yearlyProduct
        }

        guard let product else {
            errorMessage = "Product not available. Please try again."
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
            let transaction = try await purchaseService.purchase(product, userId: userId)

            guard let transaction else {
                // User cancelled — not an error
                isProcessing = false
                return
            }

            // Send transaction to backend
            let originalId = String(transaction.originalID)
            let environment: String? = transaction.environment == .sandbox ? "Sandbox" : nil
            let response = try await EntitlementsService.shared.processTransactions(
                originalTransactionIds: [originalId],
                environment: environment
            )

            // Update local premium status
            EntitlementsService.shared.updateLocalEntitlements(
                from: response,
                context: modelContext
            )

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
            }
        }
    }

    // MARK: - Footer Links

    private var footerLinks: some View {
        HStack(spacing: 0) {
            Button("Terms and Conditions") {
                safariURL = SubscriptionConfig.termsURL
            }
            .font(.inter(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .trailing)

            Text("|")
                .font(.inter(size: 12))
                .foregroundStyle(.white.opacity(0.5))
                .padding(.horizontal, 10)

            Button("Privacy Policy") {
                safariURL = SubscriptionConfig.privacyURL
            }
            .font(.inter(size: 12))
            .foregroundStyle(.white.opacity(0.5))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Bullet Metrics

/// Shared sizing for the bullet rows on every carousel card.
///
/// One type rather than five copies of the same literals: the cards are swiped between, so a
/// size differing by a point between them reads as the text jumping. `minimumScaleFactor` is
/// deliberately NOT used to fit these — it resolves per `Text`, so each bullet would settle at
/// its own size and the column would come out ragged.
///
/// `textSize` is measured, not chosen. The longest bullet in `premiumFeatures` is "Takes how
/// you feel today", which CoreText renders in Inter-Regular at 11.77x the point size. The
/// narrowest device running iOS 18.6 is 375pt, which leaves the text 151pt after the card's
/// 20pt outer padding, the 130pt screenshot, its 12pt trailing padding, the column's 8pt
/// insets and the icon column:
///
///     151pt / 11.77 = 12.8pt   <- where the longest bullet starts to wrap
///
/// 12.5 takes nearly all of that and leaves a little for rounding. Raising it, or adding a
/// bullet longer than that one, wraps on a 375pt screen — re-measure before doing either.
/// `lineLimit(1)` is the backstop for Dynamic Type, which these still scale with: truncating
/// one bullet is survivable, reflowing a fixed-height card is not.
enum UpsellBulletMetrics {
    static let textSize: CGFloat = 12.5
    static let iconSize: CGFloat = 13
    /// Wide enough for the broadest glyph in use (`arrow.left.arrow.right`) at `iconSize`, so
    /// a wide icon cannot push into the text and cause the wrap this exists to avoid.
    static let iconWidth: CGFloat = 18
    static let gap: CGFloat = 8
    static let rowSpacing: CGFloat = 10
}

// MARK: - Premium Feature Card

private struct PremiumFeatureCard: View {
    let icon: String
    let title: String
    let bullets: [(icon: String, text: String, color: Color)]

    private let accentColor: Color = .appAccent

    var body: some View {
        HStack(spacing: 0) {
            // Left side — header unit + bullets
            VStack(spacing: 0) {
                // Header block — fixed minHeight so bullets align across cards
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    Image(systemName: icon)
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                    Spacer().frame(height: 8)

                    Text("PREMIUM")
                        .font(.inter(size: 9))
                        .tracking(3)
                        .foregroundStyle(accentColor.opacity(0.7))

                    // The eyebrow sat directly on the title's cap-height with nothing between
                    // them — Bebas Neue has very little internal leading, so at `spacing: 0` the
                    // two read as one crowded block rather than a label and a heading.
                    Spacer().frame(height: 3)

                    Text(title)
                        .font(.bebasNeue(size: 26))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 5)

                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 24, height: 2)
                }
                .frame(minHeight: 148)

                Spacer().frame(height: 14)

                VStack(alignment: .leading, spacing: UpsellBulletMetrics.rowSpacing) {
                    ForEach(bullets.indices, id: \.self) { i in
                        featureItem(
                            icon: bullets[i].icon,
                            text: bullets[i].text,
                            color: bullets[i].color
                        )
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — set plan catalog card image
            Image("DisplaySetPlanCard")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 130, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.25), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func featureItem(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: UpsellBulletMetrics.gap) {
            Image(systemName: icon)
                .font(.system(size: UpsellBulletMetrics.iconSize))
                .foregroundStyle(color)
                .frame(width: UpsellBulletMetrics.iconWidth)
            Text(text)
                .font(.inter(size: UpsellBulletMetrics.textSize))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}

// MARK: - Smart Sessions Feature Card

/// The carousel's first page, and what the upsell opens on by default.
///
/// Structurally identical to the other feature cards — same header unit, same
/// `minHeight: 148` so the bullets align with every other card when swiping, same right
/// column geometry. The one difference is that the right column is a placeholder rather
/// than an `Image`, pending the Smart Sessions screenshot.
private struct SmartSessionsFeatureCard: View {
    private let accentColor: Color = .appAccent
    private let feature = SubscriptionConfig.premiumFeatures
        .first { $0.title == SubscriptionConfig.smartSessionsTitle }!

    var body: some View {
        HStack(spacing: 0) {
            // Left side — header unit + bullets
            VStack(spacing: 0) {
                // Header block — fixed minHeight so bullets align across cards
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    // `sparkles`, which is `AppTab.session.systemImage` — the same glyph
                    // that labels the tab this unlocks, so the paywall and the destination
                    // are recognisably the same feature.
                    Image(systemName: feature.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                    Spacer().frame(height: 8)

                    Text("PREMIUM")
                        .font(.inter(size: 9))
                        .tracking(3)
                        .foregroundStyle(accentColor.opacity(0.7))

                    // The eyebrow sat directly on the title's cap-height with nothing between
                    // them — Bebas Neue has very little internal leading, so at `spacing: 0` the
                    // two read as one crowded block rather than a label and a heading.
                    Spacer().frame(height: 3)

                    Text(feature.title)
                        .font(.bebasNeue(size: 26))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 5)

                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 24, height: 2)
                }
                .frame(minHeight: 148)

                Spacer().frame(height: 22)

                VStack(alignment: .leading, spacing: UpsellBulletMetrics.rowSpacing) {
                    ForEach(feature.bullets.indices, id: \.self) { i in
                        HStack(spacing: UpsellBulletMetrics.gap) {
                            Image(systemName: feature.bullets[i].icon)
                                .font(.system(size: UpsellBulletMetrics.iconSize))
                                .foregroundStyle(feature.bullets[i].color)
                                .frame(width: UpsellBulletMetrics.iconWidth)
                            Text(feature.bullets[i].text)
                                .font(.inter(size: UpsellBulletMetrics.textSize))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — the Smart Sessions card image.
            //
            // Produced by "Export Smart Sessions Card" in the Developer menu, which renders
            // `SmartSessionsCardView` at 360x780 @3x. Regenerate from there rather than
            // screenshotting a device, so it stays reproducible.
            Image("DisplaySmartSessionsCard")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 130, height: 280)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.25), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Strength Balance Feature Card

private struct StrengthBalanceFeatureCard: View {
    private let accentColor: Color = .appAccent
    // Looked up, not indexed. These were positional (`[0]`, `[1]`, `[2]`) and any
    // insertion into `premiumFeatures` silently repointed them at the neighbouring
    // feature — wrong icon, wrong title, wrong bullets, and no compiler complaint.
    private let feature = SubscriptionConfig.premiumFeatures
        .first { $0.title == SubscriptionConfig.balanceTitle }!

    var body: some View {
        HStack(spacing: 0) {
            // Left side — header unit + bullets
            VStack(spacing: 0) {
                // Header block — fixed minHeight so bullets align across cards
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    Image(systemName: feature.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                    Spacer().frame(height: 8)

                    Text("PREMIUM")
                        .font(.inter(size: 9))
                        .tracking(3)
                        .foregroundStyle(accentColor.opacity(0.7))

                    // The eyebrow sat directly on the title's cap-height with nothing between
                    // them — Bebas Neue has very little internal leading, so at `spacing: 0` the
                    // two read as one crowded block rather than a label and a heading.
                    Spacer().frame(height: 3)

                    Text(feature.title)
                        .font(.bebasNeue(size: 26))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 5)

                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 24, height: 2)
                }
                .frame(minHeight: 148)

                Spacer().frame(height: 22)

                VStack(alignment: .leading, spacing: UpsellBulletMetrics.rowSpacing) {
                    ForEach(feature.bullets.indices, id: \.self) { i in
                        HStack(spacing: UpsellBulletMetrics.gap) {
                            Image(systemName: feature.bullets[i].icon)
                                .font(.system(size: UpsellBulletMetrics.iconSize))
                                .foregroundStyle(feature.bullets[i].color)
                                .frame(width: UpsellBulletMetrics.iconWidth)
                            Text(feature.bullets[i].text)
                                .font(.inter(size: UpsellBulletMetrics.textSize))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — balance card image
            Image("DisplayBalanceCard")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 130, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.25), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    // MARK: - Mini Phone Preview

    private var miniBalancePreview: some View {
        VStack(spacing: 3) {
            // Widget 1: Strength Balance Assessment
            miniBalanceAssessment
            // Widget 2: Movement Ratios
            miniMovementRatios
            // Widget 3: Balance Over Time
            miniBalanceOverTime
            // Widget 4: Tier Progression
            miniTierProgression
        }
        .padding(4)
        .frame(width: 130, height: 280)
        .background(Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
        )
    }

    // Mini Widget 1: Balance Assessment
    private var miniBalanceAssessment: some View {
        let exercises: [(name: String, score: Double)] = [
            ("DL", 1.08), ("SQ", 0.95), ("BP", 1.02), ("OHP", 0.88), ("ROW", 1.05)
        ]

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text("Balance")
                    .font(.system(size: 3.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("Balanced")
                    .font(.system(size: 3, weight: .semibold))
                    .foregroundStyle(Color(red: 0x21/255, green: 0xB7/255, blue: 0xC9/255))
            }

            GeometryReader { geo in
                let barWidth = geo.size.width
                let center = barWidth * 0.5 // 1.0 maps to center (range 0.7-1.3)
                ZStack(alignment: .leading) {
                    // Ideal line at center
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(width: 0.5)
                        .offset(x: center)

                    VStack(spacing: 1.5) {
                        ForEach(exercises.indices, id: \.self) { i in
                            let ex = exercises[i]
                            let normalized = (ex.score - 0.7) / 0.6 // 0.7→0, 1.3→1
                            let width = max(barWidth * normalized, 2)
                            HStack(spacing: 1) {
                                Text(ex.name)
                                    .font(.system(size: 2.5))
                                    .foregroundStyle(.white.opacity(0.5))
                                    .frame(width: 12, alignment: .trailing)
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(miniBalanceColor(for: ex.score))
                                    .frame(width: width, height: 4)
                            }
                        }
                    }
                }
            }
        }
        .padding(4)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(height: 65)
    }

    private func miniBalanceColor(for score: Double) -> Color {
        if score >= 1.08 { return Color(red: 0.13, green: 0.77, blue: 0.37) } // strong green
        if score >= 0.97 { return Color(red: 0.21, green: 0.72, blue: 0.79) } // ideal cyan
        if score >= 0.92 { return Color(red: 0.96, green: 0.62, blue: 0.04) } // mild amber
        return Color(red: 0.94, green: 0.27, blue: 0.27) // weak red
    }

    // Mini Widget 2: Movement Ratios
    private var miniMovementRatios: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Movement Ratios")
                .font(.system(size: 3.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            // Push/Pull bar
            VStack(spacing: 1) {
                HStack(spacing: 0) {
                    Text("52%")
                        .font(.system(size: 2.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 10, alignment: .leading)
                    GeometryReader { geo in
                        HStack(spacing: 0.5) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.setEasy)
                                .frame(width: geo.size.width * 0.52)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.setModerate)
                        }
                    }
                    .frame(height: 5)
                    Text("48%")
                        .font(.system(size: 2.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 10, alignment: .trailing)
                }

                // Upper/Lower bar
                HStack(spacing: 0) {
                    Text("55%")
                        .font(.system(size: 2.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 10, alignment: .leading)
                    GeometryReader { geo in
                        HStack(spacing: 0.5) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.setHard)
                                .frame(width: geo.size.width * 0.55)
                            RoundedRectangle(cornerRadius: 1)
                                .fill(Color.appAccent)
                        }
                    }
                    .frame(height: 5)
                    Text("45%")
                        .font(.system(size: 2.5))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(width: 10, alignment: .trailing)
                }
            }
        }
        .padding(4)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(height: 50)
    }

    // Mini Widget 3: Balance Over Time
    private var miniBalanceOverTime: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Balance Over Time")
                .font(.system(size: 3.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            // Mini line chart
            GeometryReader { geo in
                let points: [CGFloat] = [0.5, 0.45, 0.35, 0.25, 0.2, 0.15] // Trending toward balanced (lower = better)
                let w = geo.size.width
                let h = geo.size.height

                // Green zone (top = balanced)
                Rectangle()
                    .fill(Color.setEasy.opacity(0.08))
                    .frame(height: h * 0.3)

                // Line
                Path { path in
                    for (i, p) in points.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(points.count - 1)
                        let y = h * p
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.setEasy, lineWidth: 1)

                // Points
                ForEach(points.indices, id: \.self) { i in
                    let x = w * CGFloat(i) / CGFloat(points.count - 1)
                    let y = h * points[i]
                    Circle()
                        .fill(Color.setEasy)
                        .frame(width: 2, height: 2)
                        .position(x: x, y: y)
                }
            }
        }
        .padding(4)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(height: 55)
    }

    // Mini Widget 4: Tier Progression
    private var miniTierProgression: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Tier Progression")
                .font(.system(size: 3.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))

            GeometryReader { geo in
                let points: [CGFloat] = [0.75, 0.68, 0.6, 0.52, 0.45, 0.38, 0.3, 0.22] // e1RM trending up (lower y = higher value)
                let w = geo.size.width
                let h = geo.size.height

                // Tier bands
                Rectangle()
                    .fill(Color.setModerate.opacity(0.08))
                    .frame(height: h * 0.5)
                    .offset(y: h * 0.0)
                Rectangle()
                    .fill(Color.setEasy.opacity(0.06))
                    .frame(height: h * 0.5)
                    .offset(y: h * 0.5)

                // Line
                Path { path in
                    for (i, p) in points.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(points.count - 1)
                        let y = h * p
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.appAccent, lineWidth: 1)

                // PR points
                ForEach([3, 6], id: \.self) { i in
                    let x = w * CGFloat(i) / CGFloat(points.count - 1)
                    let y = h * points[i]
                    Circle()
                        .fill(Color.appAccent)
                        .frame(width: 2.5, height: 2.5)
                        .position(x: x, y: y)
                }
            }
        }
        .padding(4)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .frame(height: 55)
    }
}

// MARK: - Advanced Analytics Feature Card

private struct AdvancedAnalyticsFeatureCard: View {
    private let accentColor: Color = .appAccent
    // Looked up, not indexed. These were positional (`[0]`, `[1]`, `[2]`) and any
    // insertion into `premiumFeatures` silently repointed them at the neighbouring
    // feature — wrong icon, wrong title, wrong bullets, and no compiler complaint.
    private let feature = SubscriptionConfig.premiumFeatures
        .first { $0.title == SubscriptionConfig.analyticsTitle }!

    var body: some View {
        HStack(spacing: 0) {
            // Left side — header unit + bullets
            VStack(spacing: 0) {
                // Header block — fixed minHeight so bullets align across cards
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    Image(systemName: feature.icon)
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                    Spacer().frame(height: 8)

                    Text("PREMIUM")
                        .font(.inter(size: 9))
                        .tracking(3)
                        .foregroundStyle(accentColor.opacity(0.7))

                    // The eyebrow sat directly on the title's cap-height with nothing between
                    // them — Bebas Neue has very little internal leading, so at `spacing: 0` the
                    // two read as one crowded block rather than a label and a heading.
                    Spacer().frame(height: 3)

                    Text(feature.title)
                        .font(.bebasNeue(size: 26))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Spacer().frame(height: 5)

                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 24, height: 2)
                }
                .frame(minHeight: 148)

                Spacer().frame(height: 14)

                VStack(alignment: .leading, spacing: UpsellBulletMetrics.rowSpacing) {
                    ForEach(feature.bullets.indices, id: \.self) { i in
                        HStack(spacing: UpsellBulletMetrics.gap) {
                            Image(systemName: feature.bullets[i].icon)
                                .font(.system(size: UpsellBulletMetrics.iconSize))
                                .foregroundStyle(feature.bullets[i].color)
                                .frame(width: UpsellBulletMetrics.iconWidth)
                            Text(feature.bullets[i].text)
                                .font(.inter(size: UpsellBulletMetrics.textSize))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — analytics card image
            Image("DisplayAnalyticsCard")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 130, height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.25), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }
}

// MARK: - Progress Card Feature Card

private struct ProgressCardFeatureCard: View {
    private let accentColor: Color = .appAccent

    var body: some View {
        HStack(spacing: 0) {
            // Left side — marketing text
            VStack(spacing: 0) {
                // Header block — fixed minHeight so bullets align across cards
                VStack(spacing: 0) {
                    Spacer().frame(height: 16)

                    Image(systemName: "square.and.arrow.up.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(accentColor)
                        .shadow(color: accentColor.opacity(0.4), radius: 8, x: 0, y: 2)

                    Spacer().frame(height: 8)

                    Text("PREMIUM")
                        .font(.inter(size: 9))
                        .tracking(3)
                        .foregroundStyle(accentColor.opacity(0.7))

                    // The eyebrow sat directly on the title's cap-height with nothing between
                    // them — Bebas Neue has very little internal leading, so at `spacing: 0` the
                    // two read as one crowded block rather than a label and a heading.
                    Spacer().frame(height: 3)

                    Text("Progress Card")
                        .font(.bebasNeue(size: 26))
                        .foregroundStyle(.white)

                    Spacer().frame(height: 5)

                    Rectangle()
                        .fill(accentColor)
                        .frame(width: 24, height: 2)
                }
                .frame(minHeight: 148)

                Spacer().frame(height: 14)

                VStack(alignment: .leading, spacing: 8) {
                    featureItem(icon: "trophy.fill", text: "Personal Records", color: .setPR)
                    featureItem(icon: "chart.bar.fill", text: "Strength Tiers", color: .setEasy)
                    featureItem(icon: "flame.fill", text: "Intensity Breakdown", color: .setNearMax)
                    featureItem(icon: "figure.strengthtraining.traditional", text: "Volume & Frequency", color: .setModerate)
                    featureItem(icon: "square.and.arrow.up.fill", text: "Shareable Image", color: .setHard)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)

            // Right side — progress card image
            Image("DisplayProgressCard")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 280)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: accentColor.opacity(0.25), radius: 16, x: -2, y: 0)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 306)
        .padding(.vertical, 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(white: 0.10))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(accentColor.opacity(0.2), lineWidth: 1)
                )
        )
    }

    private func featureItem(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: UpsellBulletMetrics.gap) {
            Image(systemName: icon)
                .font(.system(size: UpsellBulletMetrics.iconSize))
                .foregroundStyle(color)
                .frame(width: UpsellBulletMetrics.iconWidth)
            Text(text)
                .font(.inter(size: UpsellBulletMetrics.textSize))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }
}

// MARK: - Scrolling Feature Column

private struct ScrollingFeatureColumn: View {
    enum Direction { case up, down }
    let direction: Direction

    private let accentColor: Color = .appAccent
    private let features = SubscriptionConfig.premiumFeatures

    @State private var offset: CGFloat = 0

    private var itemHeight: CGFloat { 127 }
    private var totalHeight: CGFloat { itemHeight * CGFloat(features.count) }

    var body: some View {
        GeometryReader { geo in
            VStack(spacing: 12) {
                ForEach(0..<features.count * 3, id: \.self) { i in
                    let feature = features[i % features.count]
                    miniFeatureUnit(icon: feature.icon, title: feature.title)
                }
            }
            .offset(y: direction == .up
                ? -totalHeight + offset
                : -(totalHeight * 2) + totalHeight - offset)
            .onAppear {
                withAnimation(
                    .linear(duration: Double(features.count) * 8)
                    .repeatForever(autoreverses: false)
                ) {
                    offset = totalHeight
                }
            }
        }
        .clipped()
    }

    private func miniFeatureUnit(icon: String, title: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundStyle(accentColor)

            Text("PREMIUM")
                .font(.system(size: 9, weight: .medium))
                .tracking(2)
                .foregroundStyle(accentColor.opacity(0.7))

            Text(title)
                .font(.bebasNeue(size: 21))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Rectangle()
                .fill(accentColor)
                .frame(width: 26, height: 2)
        }
        .frame(width: 145, height: 115)
    }
}
