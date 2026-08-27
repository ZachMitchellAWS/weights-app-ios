//
//  SmartSessionsCardView.swift
//  WeightApp
//
//  Static display card for the Smart Sessions visualization.
//  Exported as an image for the Go Premium upsell, via `exportSmartSessionsCard()` in MoreView.
//
//  Sibling of `StrengthBalanceCardView`, `AdvancedAnalyticsCardView` and
//  `SetPlanCatalogCardView` in `Views/Trends/`. This one sits here because its content comes from
//  `SessionShowcase`, next door.
//
//  DESIGNED FOR THE THUMBNAIL, NOT FOR FIDELITY.
//
//  The first version of this file reproduced `planningCard` pixel for pixel and scaled it to fit.
//  That was the wrong shape twice over. The card's aspect ran edge to edge horizontally, leaving
//  no side gutter while stranding ~70pt of black top and bottom — the opposite of the margins the
//  other four cards share. And at the 130x280pt the asset actually ships at inside the carousel,
//  every element was too small to resolve.
//
//  The other four are not screenshots either. They are compositions that fill 360x780 with large
//  saturated blocks, because at roughly a third scale a viewer reads COLOUR and SHAPE and almost
//  no text. So this is the same session, restated at a size that survives being shrunk:
//
//    - three panels filling the frame, on the set's shared 12pt horizontal / 14pt vertical margins
//    - the effort strip is the hero at more than double the app's tile size, since it is the one
//      element carrying the full five-colour palette
//    - the paragraph summary is gone — a short amber headline says as much in a glance, where
//      three lines of grey footnote say nothing at all
//    - one amber CTA bar anchoring the bottom, the largest single block of brand colour on the card
//
//  Still honest: every lift, plan name, effort sequence, chip and quote is the real
//  `SessionShowcase` content, and the tiles are the real `EffortSquares` in the real colours.
//
//  No live state — no store, no `@Query`, no services — so the export renders identically on any
//  device and any account.
//

import SwiftUI

struct SmartSessionsCardView: View {

    // Shared by all five exports; at `renderer.scale = 3` this is the 1080x2340 every shipped
    // `Display*Card` asset is.
    private static let exportWidth: CGFloat = 360
    private static let exportHeight: CGFloat = 780

    /// The margins the other four cards use (`.padding(.horizontal, 12)` / `.vertical, 14`).
    /// Getting these wrong is what made the first attempt look unlike the rest of the set.
    private static let hMargin: CGFloat = 12
    private static let vMargin: CGFloat = 14

    /// Effort tile edge.
    ///
    /// The app draws these at 20pt on a 328pt card — 6% of the width. At 46pt on 360 they are
    /// 13%, so they still separate into distinct colours once the asset is shrunk to 130pt wide.
    /// This is the single biggest legibility lever on the card.
    private static let tileSide: CGFloat = 46

    private let plan = SessionShowcase.plan
    private let context = SessionShowcase.context

    var body: some View {
        VStack(spacing: 12) {
            contextPanel
            liftsPanel
            ctaBar
        }
        .padding(.horizontal, Self.hMargin)
        .padding(.vertical, Self.vMargin)
        .frame(width: Self.exportWidth, height: Self.exportHeight)
        .background(Color.black)
    }

    // MARK: - Panel 1 — what the user said
    //
    // The cause half of the story. The chips and the quote are the only proof on the card that
    // this session was shaped by something a person typed rather than generated blind, so they
    // are set larger than the app sets them even though they are the smallest type here.

    private var contextPanel: some View {
        VStack(spacing: 10) {
            Text("TODAY'S SESSION")
                .font(.inter(size: 12))
                .tracking(4)
                .foregroundStyle(.white.opacity(0.55))

            // Stands in for the app's three-line summary paragraph. At a third scale a paragraph
            // is grey texture; one short line in the accent colour is still a sentence.
            Text("Built around your day")
                .font(.bebasNeue(size: 38))
                .foregroundStyle(Color.appAccent)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(spacing: 8) {
                ForEach(chips, id: \.self) { chip in
                    Text(chip)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
                        .lineLimit(1)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Color.white.opacity(0.10)))
                }
            }

            Text("“\(context.note)”")
                .font(.system(size: 14).italic())
                .foregroundStyle(.white.opacity(0.5))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .padding(.horizontal, 12)
        .background(panel)
    }

    /// Catalog order, matching the live recap's filter — not the order they were tapped.
    private var chips: [String] {
        (ProgramMockData.contextChips + ProgramMockData.sessionShapeChips)
            .filter { context.chips.contains($0) }
    }

    // MARK: - Panel 2 — what it picked
    //
    // The effect half, and where the colour lives. Each lift's effort strip gets its own full-width
    // line rather than being squeezed beside the name, which is the whole reason the tiles can be
    // big enough to tell apart at thumbnail size.

    private var liftsPanel: some View {
        VStack(spacing: 20) {
            ForEach(plan.items) { item in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Image(item.icon)
                            .resizable().scaledToFit()
                            .frame(width: 32, height: 32)
                            // Brighter than the app's 0.6: these are thin line-art glyphs, and at
                            // export scale they wash out into the panel long before the text does.
                            .foregroundStyle(.white.opacity(0.9))

                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.exerciseName)
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Text(item.planName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(Color.appAccent.opacity(0.85))
                        }

                        Spacer(minLength: 0)
                    }

                    // The real component in the real colours. A second drawing of the effort
                    // palette would eventually disagree with the app it advertises.
                    //
                    // `completed:` set to the full count so every tile renders FILLED. In the app
                    // an unlogged tile is drawn at `opacity(0.16)` behind a hairline border, which
                    // correctly says "not done yet" — but on a card at a third scale it reads as
                    // five shades of dark grey, and the effort palette is the only real colour
                    // here. Solid tiles are also the truer statement for a marketing card: it is
                    // showing a PLAN, and these are the plan's colours.
                    EffortSquares(
                        sequence: item.sequence,
                        completed: item.sequence.count,
                        side: Self.tileSide,
                        spacing: 6,
                        radius: 7
                    )

                    Text(item.rationale)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.45))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 14)
        .background(panel)
    }

    // MARK: - Panel 3 — the action

    private var ctaBar: some View {
        Text("Start Lifting")
            .font(.interSemiBold(size: 21))
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 19)
            .background(Color.appAccent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var panel: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(white: 0.14))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
    }
}

#Preview {
    SmartSessionsCardView()
}
