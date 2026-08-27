//
//  StrengthSampleChrome.swift
//  WeightApp
//
//  Shared chrome for the pre-unlock sample cards on the Strength tab. Both
//  `StrengthTierWidget` and `StrengthMilestonesWidget` use these, so the two cards read
//  as one system rather than two similar-looking treatments.
//
//  None of this borrows from the premium-lock vocabulary (blur, scrim, lock, CTA).
//  Tiers and milestones are free; obscuring them would tell a free user to pay for
//  something they already have.
//

import SwiftUI

// Note: the sample content is deliberately NOT dimmed. Fading it was tried and read as
// dull grey rather than as hierarchy — it made the reward look less appealing, which is
// the opposite of what a sample card is for. The separation between illustrative and
// real is carried entirely by the SAMPLE badge and the footer's own chrome below.

/// Marks a card as illustrative.
///
/// A bordered rounded rectangle rather than a capsule: capsules in this app mean tier
/// pills and effort chips, which are data. A squared, outlined badge reads as chrome —
/// a label about the card, not a value inside it.
struct StrengthSampleBadge: View {
    var body: some View {
        Text("SAMPLE")
            .font(.system(size: 10, weight: .bold))
            .tracking(1.4)
            .foregroundStyle(Color.appAccent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.appAccent.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.appAccent.opacity(0.55), lineWidth: 1)
            )
    }
}

/// Separates the illustrative half of a sample card from the real footer beneath it.
///
/// Inset rather than full-bleed so it reads as a soft break inside one card, rather than
/// slicing the card into two stacked panels.
struct StrengthSampleDivider: View {
    var body: some View {
        Rectangle()
            .fill(.white.opacity(0.09))
            .frame(height: 1)
            .padding(.horizontal, 32)
    }
}

/// The user's REAL progress toward unlocking, shown under a sample card.
///
/// This is what keeps a sample card from being pure decoration — the illustration is
/// imaginary, but this footer is true, and it attaches a concrete number to the nudge
/// instead of generic encouragement.
///
/// Deliberately borrows `TierJourneyOverlay`'s checklist vocabulary — same icons, same
/// short names, same checkmark-or-hollow-circle beneath each — so the two surfaces that
/// track this one goal look like the same mechanic rather than two separate systems.
/// It is a quieter, static rendition: no entrance animation, no glow, no CTA.
struct StrengthUnlockFooter: View {
    /// One flag per fundamental, in `TrendsCalculator.fundamentalExercises` order.
    let loggedFlags: [Bool]
    /// Which sample card this footer belongs to, for analytics. Both cards appear on the
    /// Strength tab together, so this is what distinguishes which one earned the tap.
    let widget: String

    /// What the five lifts unlock, from the perspective of the tab you are on.
    ///
    /// The same checklist gates different things: on the Strength tab it is the starting
    /// Strength Tier, on the Session tab it is Smart Sessions. Naming the wrong one is not
    /// a cosmetic error — it tells the user to go do something for a feature they were not
    /// looking at.
    ///
    /// Split in two so the highlight can be the accent-coloured payoff term while any
    /// lead-in ("your starting ") stays plain.
    var unlockPrefix: String = "your starting "
    var unlockHighlight: String = "Strength Tier"

    private var loggedCount: Int { loggedFlags.filter { $0 }.count }

    /// Paired with the fundamentals so the row can show each lift's real icon and name.
    /// `zip` rather than index math — a short or stale flag array truncates the row
    /// instead of trapping.
    private var lifts: [(fundamental: TrendsCalculator.FundamentalExercise, isLogged: Bool)] {
        zip(TrendsCalculator.fundamentalExercises, loggedFlags).map { ($0, $1) }
    }

    /// Tapping goes straight to the Lift tab — the footer names an action, so it should
    /// perform it. Routed through `NotificationRouter`, which `ContentView` already
    /// consumes for exactly this destination, rather than threading a `selectedTab`
    /// binding down through the tab root and BalanceView to reach these widgets.
    var body: some View {
        Button {
            AmplitudeService.shared.track(
                .strengthSampleUnlockTapped(widget: widget, liftsLogged: loggedCount)
            )
            NotificationRouter.shared.pendingDestination = .liftTab
        } label: {
            content
        }
        .buttonStyle(.plain)
        // Fired here rather than on each card: the footer renders only on a sample card
        // and only once per card, so both widgets stay instrumented identically.
        .onAppear {
            AmplitudeService.shared.track(
                .strengthSampleShown(widget: widget, liftsLogged: loggedCount)
            )
        }
    }

    private var content: some View {
        VStack(spacing: 10) {
            Text("\(loggedCount) of \(TrendsCalculator.fundamentalExercises.count) Lifts Logged")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.85))

            HStack(spacing: 12) {
                ForEach(lifts, id: \.fundamental.id) { item in
                    VStack(spacing: 4) {
                        Image(item.fundamental.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 34, height: 34)
                            // Unlogged sits brighter than TierJourneyOverlay's 0.2. The
                            // overlay draws on a near-black modal; here the backing is a
                            // lit card, so the same value loses the lift entirely. These
                            // are the to-do items — they have to stay readable.
                            .foregroundStyle(item.isLogged ? Color.appAccent : .white.opacity(0.42))

                        Text(Self.shortName(for: item.fundamental.name))
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(item.isLogged ? 0.7 : 0.5))

                        if item.isLogged {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(Color.appAccent)
                        } else {
                            Circle()
                                .stroke(.white.opacity(0.4), lineWidth: 1)
                                .frame(width: 8, height: 8)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Two authored lines rather than one wrapping string: the break belongs
            // after "unlock" so the payoff term lands whole on its own line, which
            // free wrapping would not guarantee across dynamic type sizes.
            VStack(spacing: 1) {
                Text("Log one set of each lift to unlock")

                Text(unlockPrefix)
                + Text(unlockHighlight).foregroundColor(.appAccent)
            }
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.5))
            .multilineTextAlignment(.center)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        // Only a shade under the card's 0.14 — enough to read as an inset panel, not so
        // dark it becomes a void. Earlier passes at 0.07 and pure black separated more
        // strongly but sank the section; with the amber border at 0.55 doing the framing,
        // the fill does not have to.
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.11))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.appAccent.opacity(0.55), lineWidth: 1)
        )
    }

    /// Matches `TierJourneyOverlay.shortName` — full names overflow a five-across row.
    private static func shortName(for name: String) -> String {
        switch name {
        case "Overhead Press": return "OH Press"
        case "Bench Press": return "Bench"
        case "Barbell Rows": return "Rows"
        default: return name
        }
    }
}
