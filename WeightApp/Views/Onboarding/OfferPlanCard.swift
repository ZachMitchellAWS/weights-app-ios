//
//  OfferPlanCard.swift
//  WeightApp
//
//  The yearly plan row for both pricing paywalls, and the only one that can draw a struck-out
//  comparison price.
//
//  WHY IT IS NOT `PlanCard`. `PlanCard` (in `UpsellView.swift`) is shared by all four paywalls
//  and renders exactly one price per row. Teaching it a second, cancelled price would change
//  every paywall at once, including the two that have no offer to compare against — so this is
//  a fork, kept deliberately close to the original's metrics because the MONTHLY row beside it
//  is still the real `PlanCard`. 22pt Bebas price, 14pt Inter title, 14pt corner radius, 2pt
//  accent border when selected. Any change here that is not mirrored there shows up as two
//  mismatched rows, which is the most likely way these screens break.
//
//  WHY IT IS SHARED RATHER THAN FORKED AGAIN. It began as `IOPlanCard`, private to
//  `IntroOfferPaywallView`. When the carousel paywall also became offer-aware, the choice was a
//  second copy or one shared type; a second copy of a component whose whole job is a precise
//  visual match to a third component is how three rows end up looking like three rows.
//
//  The accent is `Color.appAccent` rather than a per-screen palette token, because both callers
//  resolve their amber to that anyway.
//

import SwiftUI

// MARK: Plan card with a struck list price

/// A FORK of `PlanCard`, which cannot show a list price beside the one being charged.
///
/// Kept deliberately close to the original's metrics — 22pt Bebas price, 14pt Inter title,
/// 14pt corner radius, 2pt accent border when selected — because the monthly row below it is
/// still the real `PlanCard`. Any change here that is not mirrored there shows up as two
/// mismatched rows, which is the most likely way this screen breaks.
struct OfferPlanCard: View {
    let isSelected: Bool
    let title: String
    let price: String
    /// The list price, struck through. This is the whole reason the fork exists.
    ///
    /// OPTIONAL, and nil is a real state rather than an oversight: outside the introductory
    /// window there is no higher price to compare against, and `IntroOfferService` also
    /// withholds it when the standard SKU failed to load or is not actually more expensive
    /// than what is being charged. When nil the row draws one price and no mark, which is
    /// `PlanCard`'s layout — so the two rows still match.
    let strikePrice: String?
    let priceSubtitle: String?
    let badge: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .strokeBorder(isSelected ? Color.appAccent : Color.white.opacity(0.5), lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .fill(isSelected ? Color.appAccent : Color.clear)
                            .frame(width: 12, height: 12)
                    )

                // List price FIRST, then the intro price. Reading order carries the discount:
                // the number being replaced has to be seen before the one replacing it, or the
                // strikethrough is just decoration on a number the eye has already skipped.
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    // AMBER IN THE STRIKE, NOT IN THE NUMBER. Both were amber briefly, and
                    // that put the accent on the price you do not pay — an inversion of what
                    // the accent means everywhere else on the screen, and it left the row with
                    // two amber numbers for the eye to sort out.
                    //
                    // The mark is the right place for it. A coloured line ACROSS a neutral
                    // number is unambiguous about which number is being cancelled; a coloured
                    // number with a line through it asks the reader to decide whether the
                    // colour is emphasis or negation.
                    //
                    // Prominence comes from the other two changes instead: 19pt rather than
                    // 17, and white at 55% rather than 45%. Still quieter than the $79.99 next
                    // to it, which wins on size (22 vs 19) and on being the only one uncrossed.
                    //
                    // The strike is a drawn `Path`, not `.strikethrough()`, which renders a
                    // hairline at the font's own weight, cannot be thickened independently of
                    // its colour, and is dead straight. See `CurvedStrike`.
                    if let strikePrice {
                        Text(strikePrice)
                            .font(.bebasNeue(size: 19))
                            .foregroundStyle(.white.opacity(0.55))
                            .overlay {
                                CurvedStrike()
                                    .stroke(Color.appAccent,
                                            style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            }
                    }

                    Text(price)
                        .font(.bebasNeue(size: 22))
                        .foregroundStyle(.white)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)

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
                .lineLimit(1)
                .minimumScaleFactor(0.85)

                Spacer(minLength: 4)

                if let badge {
                    Text(badge)
                        .font(.interSemiBold(size: 9))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.appAccent))
                        .fixedSize()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color(white: 0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(isSelected ? Color.appAccent : Color.white.opacity(0.15),
                                    lineWidth: isSelected ? 2 : 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(strikePrice.map { "\(title), \(price), normally \($0)" }
                            ?? "\(title), \(price)")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}


// MARK: - Curved strike

/// The line through the list price.
///
/// WHY A SHAPE AND NOT `.strikethrough()`. The built-in modifier draws a straight hairline whose
/// weight is derived from the font and whose colour cannot be set independently of it. This one
/// needs to be 2pt, amber, and bowed — none of which that modifier can express.
///
/// A `Shape` is the cheap way to get there: SwiftUI hands `path(in:)` the overlaid view's own
/// bounds, so the mark sizes itself to whatever the price string happens to be without a
/// `GeometryReader` or a hardcoded width.
///
/// The geometry is a single quadratic curve rather than an arc, because an arc of this length is
/// visually indistinguishable from a straight line unless the radius is small enough to look
/// like a smile. The two ends sit slightly BELOW and ABOVE centre respectively — that tilt is
/// what the earlier `-8°` rotation was doing — and the control point pulls the middle up, so the
/// result reads as one pen stroke that started low, bowed over the digits and lifted off. It
/// overshoots the text by 2pt at each end for the same reason: a mark that stops exactly at the
/// glyph edges looks printed, not drawn.
struct CurvedStrike: Shape {
    /// Peak deflection of the curve's middle, as a fraction of the overlaid view's height.
    /// Past about 0.3 it stops reading as a strike and starts reading as an underline for the
    /// line above.
    var bow: CGFloat = 0.20
    /// How far each end sits off centre, as a fraction of height. This is the apparent tilt.
    var tilt: CGFloat = 0.09
    /// Horizontal overshoot past the text, in points.
    var overshoot: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let start = CGPoint(x: rect.minX - overshoot, y: rect.midY + rect.height * tilt)
        let end = CGPoint(x: rect.maxX + overshoot, y: rect.midY - rect.height * tilt)
        let control = CGPoint(x: rect.midX, y: rect.midY - rect.height * bow)
        path.move(to: start)
        path.addQuadCurve(to: end, control: control)
        return path
    }
}


// MARK: - Trial badge

/// "7 DAYS FREE", in the slot a countdown vacates once the introductory window closes.
///
/// Drawn to the shipping paywall's original badge metrics — 9pt heavy, 12/4 padding, 6pt top
/// corners — because that is exactly what this is: the badge both carousel paywalls have always
/// had, now conditional.
///
/// ONLY RENDER THIS WHEN THE TRIAL IS GENUINELY AVAILABLE. The literal it replaces was
/// unconditional on three paywalls, so a customer who had already spent their trial — possibly
/// on the legacy product, months ago — was promised it again, and Apple would have refused to
/// honour that at the purchase sheet. Eligibility is per subscription group; ask
/// `IntroOfferService`, never assume.
struct OfferTrialBadge: View {
    var body: some View {
        Text("7 DAYS FREE")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.appAccent)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
            .accessibilityLabel("Seven days free")
    }
}


// MARK: - Countdown badge

/// The introductory window's clock, as a tab notched onto the top-leading corner of the yearly
/// plan card.
///
/// OWNS ITS OWN TICK, via `TimelineView(.periodic)`. The earlier version took a `remaining:
/// TimeInterval` and left the hosting screen to run a `Timer.publish` and push updates in — which
/// worked on the one screen that had such a timer and was unavailable to the carousel paywall,
/// which has none. Moving the clock inside means both screens pass a deadline and nothing else.
///
/// RECOMPUTED FROM THE DEADLINE, never decremented. A countdown that subtracts a second per tick
/// stops while the app is backgrounded and comes back wrong by however long it was away.
/// `TimelineView` re-evaluates against the real clock, so backgrounding for an hour costs
/// nothing — and there is no `@State` to get out of sync with the date it was derived from.
///
/// THE DEADLINE ITSELF comes from the account's creation date via `IntroOfferService`, not from
/// the first time a paywall was seen. A device-local anchor resets on reinstall, which turns an
/// introductory offer into a discount anyone can re-trigger by deleting the app.
struct OfferCountdownBadge: View {
    let deadline: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            content(remaining: max(0, deadline.timeIntervalSince(context.date)))
        }
    }

    private func content(remaining: TimeInterval) -> some View {
        let expired = remaining <= 0
        return HStack(spacing: 6) {
            Image(systemName: expired ? "clock.badge.xmark" : "clock.fill")
                .font(.system(size: 9, weight: .bold))
                .accessibilityHidden(true)

            // "INTRO OFFER ENDS IN", not the shorter "ENDS IN" an earlier cut used. Trimming it
            // did fix a crowding problem, and removed the only place on the screen that named
            // what the offer was — leaving a clock counting down to nothing in particular. The
            // long label is affordable because the digits grew at the same time.
            Text(expired ? "OFFER EXPIRED" : "INTRO OFFER ENDS IN")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)

            if !expired {
                // Monospaced digits are not cosmetic: without them the whole tab reflows every
                // second as digit widths change, and a jittering deadline reads as a rendering
                // bug rather than as urgency.
                //
                // 15pt against the 9pt label. At the original 9.5pt the digits sat level with
                // the words, so the one element that MOVES was the one nothing drew the eye to.
                Text(Self.formatted(remaining))
                    .font(.system(size: 15, weight: .heavy).monospacedDigit())
                    .tracking(0.3)
            }
        }
        .foregroundStyle(.black)
        .padding(.horizontal, 12)
        .padding(.vertical, 3)
        // AMBER, AND A TAB. Two alternatives were tried and both went too far the other way: a
        // solid #FF6B35 full-width band fused to the plan card (which drew the eye, and became
        // the loudest thing on a screen sold by its headline and its session card), then the
        // same orange as a 12% tint (quieter, but a second hue on a screen with one accent).
        //
        // What is left is the shipping paywall's own badge treatment. It does not out-shout the
        // CTA, and that is a known limitation rather than a solved problem: amber is the only
        // accent here and the CTA below is a 40pt solid amber slab, so two elements in the same
        // hue resolve by area and a ~22pt tab loses. The levers left are motion or a second
        // placement higher up; neither is in.
        .background(expired ? Color.white.opacity(0.35) : Color.appAccent)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(expired
            ? "Introductory price expired."
            : "Introductory price ends in \(Int(remaining) / 3600) hours.")
    }

    /// HH:MM:SS, zero-padded and clamped at zero. Hours are NOT wrapped into days: "71:59:58" is
    /// a bigger-feeling number than "2d 23h", and it is the hours that are doing the work.
    static func formatted(_ remaining: TimeInterval) -> String {
        let total = max(0, Int(remaining))
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }
}
