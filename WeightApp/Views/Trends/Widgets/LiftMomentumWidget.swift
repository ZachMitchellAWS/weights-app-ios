//
//  LiftMomentumWidget.swift
//  WeightApp
//
//  "Which of my five lifts have I actually been training?" — as one glance.
//
//  Placed directly under the report-card button, above every other widget, because it is the
//  only one that answers a question about TODAY. Everything below it describes what has
//  already happened; this one is a prompt to act, and it is the input the Session tab's
//  generator reasons from, so surfacing it makes the app's own logic legible.
//
//  Laid out as the Lift tab's tier strip, deliberately: same card, same 84pt height, same
//  radius, same icon-over-name stack, same bar at the foot. That strip is where the user
//  already looks to compare their five lifts side by side, and reusing its shape means this
//  reads as the same comparison asking a different question — recency instead of tier.
//
//  NOT the same thing as `TrainingRecencyWidget` ("Exercise Activity"), which lists EVERY
//  exercise ever logged as a vertical row of day-counts and grows without bound. That one is
//  a reference table and sits last for that reason. This one is fixed at five, horizontal,
//  and colour-first. They coexist on purpose; if that ever reads as duplication, this is the
//  one to keep.
//
//  Not premium-gated. The five fundamentals ARE the product's spine, and a free user who
//  cannot see which of them has gone cold cannot act on the thing the app most wants them to
//  act on.
//

import SwiftUI

struct LiftMomentumWidget: View {
    let allSets: [LiftSet]
    let allEstimated1RM: [Estimated1RM]

    private var heat: [UUID: Double] {
        LiftMomentum.heatByExercise(sets: allSets, estimated1RMs: allEstimated1RM)
    }

    /// Only used to tell "never trained" from "no data yet" for the empty state. The cells
    /// themselves show no day counts — see the note in `content`.
    private var daysSince: [UUID: Int] {
        LiftMomentum.daysSinceLastTrained(sets: allSets)
    }

    var body: some View {
        // "Momentum", not "Recency". The number weights how HARD and how MUCH as well as
        // how recently — six easy sets and one progress set score the same, and both decay
        // if you stop. Recency named only the third of those three.
        // Subtitle states the QUESTION; the legend below labels the scale. Splitting those
        // two jobs is what lets each be short. "How hard, how much, how recently" tried to
        // do both and did neither — it described the arithmetic to someone who wanted to
        // know what they were looking at.
        //
        // Wording tracks the legend's ends ("Due" / "Worked"), so the card reads as one
        // thought rather than as two vocabularies for one scale.
        WidgetCard(
            title: "Training Status",
            subtitle: "Which lifts are worked, and which are due"
        ) {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        let heat = heat
        let days = daysSince

        if days.isEmpty {
            EmptyWidgetState(icon: "flame", message: "Log sets to see where your momentum is")
        } else {
            VStack(spacing: 8) {
                // No ScrollView. The Lift tab's strip scrolls because it carries accessories
                // too; there are exactly five here forever, and a scroll view that never
                // scrolls only adds a gesture that does nothing.
                //
                // Spacing 6 and the card geometry below are copied from that strip so the two
                // read as the same control. The cells come out ~6pt narrower here — the widget
                // card's own padding eats that — which is as close as it gets without
                // special-casing WidgetCard.
                HStack(spacing: 6) {
                    ForEach(TrendsCalculator.fundamentalExercises, id: \.id) { lift in
                        cell(lift: lift, heat: heat[lift.id] ?? 0)
                    }
                }
                // Claws back 10 of `WidgetCard`'s 16pt side padding, which buys each of the
                // five cells ~4pt and lands them within a couple of points of the Lift tab
                // strip they are copying. Negative padding rather than a new `WidgetCard`
                // parameter: this is the only widget that wants it, and widening the shared
                // chrome's API for one caller is the worse trade.
                .padding(.horizontal, -10)

                // NO DAY-COUNT ROW. It said "3d" under a colour that is not about days —
                // the tint weights intensity and volume too — so the number quietly
                // contradicted the thing it sat beneath. There is no honest one-word label
                // for the score itself, so the legend carries the scale instead.

                legend
                    .padding(.top, 8)
            }
        }
    }

    /// Icon and name, sitting straight on the widget's own background.
    ///
    /// NO CARD. It started as a copy of the Lift tab strip, which boxes each lift because
    /// there one card is SELECTED — the container is what carries that state. Nothing here is
    /// selectable, so the box was drawing a border around a thing that never changes, in
    /// `Color(white: 0.12)` against the widget's own `0.14`: a rectangle you could see and
    /// which told you nothing.
    ///
    /// Without it the five icons read as one row, which is the comparison being made, and the
    /// tint has the background to itself instead of competing with an edge.
    ///
    /// A bar and a day count used to live in here too. Both went for the same reason — the
    /// bar restated the icon's own tint, and one signal drawn twice is noise, not emphasis.
    private func cell(lift: TrendsCalculator.FundamentalExercise, heat: Double) -> some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)

            Image(lift.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 40, height: 40)
                .foregroundStyle(LiftMomentum.tint(heat))

            Text(ProgramSessionStore.shortName(for: lift.name))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        // 84 was the Lift tab card's height and existed to give that card presence. With no
        // card it is just dead air, so the row is sized to its content plus a little.
        .frame(minHeight: 62)
    }

    /// Swatches sampled from `LiftMomentum.tint`, so the key cannot drift from the icons above
    /// it. Same construction as `TrainingRecencyWidget`'s legend, which is where the user has
    /// met this control before.
    private var legend: some View {
        HStack(spacing: 5) {
            Text("Due")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))

            ForEach([0.0, 0.2, 0.4, 0.6, 0.8, 1.0], id: \.self) { step in
                RoundedRectangle(cornerRadius: 2)
                    .fill(LiftMomentum.tint(step))
                    .frame(width: 11, height: 11)
            }

            Text("Worked")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.4))
        }
    }
}
