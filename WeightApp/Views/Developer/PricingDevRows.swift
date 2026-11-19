//
//  PricingDevRows.swift
//  WeightApp
//
//  The Developer menu's paywall and pricing controls, lifted OUT of `MoreView`.
//
//  WHY THESE LIVE IN THEIR OWN FILE, AND IT IS NOT TIDINESS. `MoreView.moreFormContent` is a
//  single ~1,680-line view body. SwiftUI compiles a body like that into one enormous nested
//  generic type, and evaluating that type recurses proportionally deep — deep enough, in a debug
//  build, to exhaust the main thread's 1MB stack. Adding roughly sixty lines of pricing controls
//  inline was enough to tip it over, and it crashed with `EXC_BAD_ACCESS (code=2)` pointing at
//  the first `Image` in the Form, which is simply where the stack happened to run out rather
//  than anything to do with that image.
//
//  Extracting into a child `View` fixes it structurally: the child's body is a separate type,
//  evaluated in its own stack frame, so the parent's type stops growing. These two views pull
//  MORE out than was added, which leaves `MoreView` shallower than before rather than returning
//  it to the edge it was already sitting on.
//
//  If something else in that Form ever crashes the same way, this is the pattern — extract, do
//  not reorganise in place.
//

import SwiftUI

/// The four paywall designs, openable for inspection.
///
/// Bindings rather than its own state: the covers that present these live on `MoreView`'s
/// `NavigationStack`, because a cover attached in here would be torn down with the row.
struct PaywallPreviewDevRows: View {
    @Binding var showCarouselPreview: Bool
    @Binding var showFirstWeekPaywall: Bool
    @Binding var showIntroOfferPaywall: Bool

    var body: some View {
        // The carousel. Its own state, no longer sharing `showUpsellPreview` with the More tab
        // header — that header now opens `IntroOfferPaywallView`, so sharing left no way at all
        // to preview the carousel, which sits behind all nine feature touchpoints and is newly
        // offer-aware. Opens on page 0; a specific page needs a real touchpoint.
        row("Show Premium Upsell (Carousel)", "crown") { showCarouselPreview = true }

        // Kept reachable although nothing presents it any more: it is the design every
        // conversion number before the repricing was measured against.
        row("Show First Week Paywall", "calendar.badge.clock") { showFirstWeekPaywall = true }

        // One row. There were briefly two, one per headline candidate; that comparison settled
        // on "SHOW UP. / WE'LL PICK." Which pricing state this opens in is governed by the
        // overrides below, not by which button you press — which is what makes those overrides
        // apply to the real entry points too.
        row("Show Intro Offer Paywall", "tag.fill") { showIntroOfferPaywall = true }
    }

    private func row(_ title: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: glyph).foregroundStyle(Color.appAccent)
            }
        }
    }
}

/// Forces the offer window and trial eligibility, and surfaces what StoreKit actually returned.
struct PricingOverrideDevRows: View {
    @Binding var showPricingDebug: Bool

    // MIRRORED IN `@State`, NOT READ STRAIGHT OFF THE OVERRIDE.
    //
    // A `Picker` bound to `Binding(get: { Override.value }, set: { Override.set($0) })` writes
    // correctly and then has nothing to redraw from: `UserDefaults` publishes nothing SwiftUI
    // observes, so the row can keep showing the previous selection until something unrelated
    // invalidates the view. These hold the value locally and write through on change, which is
    // the only way the control reflects what it just did.
    @State private var offerState = IntroOfferStateOverride.value
    @State private var trialState = TrialStateOverride.value

    var body: some View {
        // Three-valued, not Bool, because "don't override" is distinct from "force off". They
        // apply to every paywall and every premium touchpoint — `IntroOfferService` consults
        // them before anything else — which is the only way to check that the REAL entry points
        // behave in a state the real clock is not currently in.
        Picker("Offer State", selection: $offerState) {
            ForEach(IntroOfferStateOverride.Value.allCases) { Text($0.label).tag($0) }
        }
        .foregroundStyle(.primary)
        .onChange(of: offerState) { _, new in IntroOfferStateOverride.set(new) }

        Picker("Trial State", selection: $trialState) {
            ForEach(TrialStateOverride.Value.allCases) { Text($0.label).tag($0) }
        }
        .foregroundStyle(.primary)
        .onChange(of: trialState) { _, new in TrialStateOverride.set(new) }

        // The one place that distinguishes "the window closed" from "the new SKUs never
        // loaded". The paywall looks the same either way by design, because the fallback's job
        // is to keep working silently.
        row("Pricing / StoreKit State", "tag.circle") { showPricingDebug = true }

        // The tier-unlock paywall is once-ever and its flag is written at fire time, so without
        // this it could only be tested on a fresh account.
        row("Reset Tier-Unlock Paywall", "arrow.counterclockwise") {
            TierUnlockUpsellPresenter.shared.resetForTesting()
        }

        // Clears the pre-repricing UI study's device-local anchor. The real clock runs from the
        // account's creation date and is deliberately NOT resettable — use Offer State above to
        // inspect the expired presentation.
        row("Reset Legacy Offer Clock", "arrow.counterclockwise") {
            UserDefaults.standard.removeObject(forKey: IntroOfferService.legacyFirstSeenKey)
        }
    }

    private func row(_ title: String, _ glyph: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: glyph).foregroundStyle(Color.appAccent)
            }
        }
    }
}
