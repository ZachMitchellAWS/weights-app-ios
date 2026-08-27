//
//  SessionTierPrerequisite.swift
//  WeightApp
//
//  What a premium user sees on the Session tab before their starting Strength Tier is
//  unlocked.
//
//  This is a genuine prerequisite, not a paywall. The generator picks from the five
//  fundamentals and reasons about how hard to push each one, and both of those need a
//  baseline e1RM per lift. Without all five it has nothing to choose between, so the
//  request is not made at all rather than sent and answered badly.
//
//  Structure mirrors `SessionPremiumPlaceholder` exactly — hero → sample → footer —
//  because both answer the same question ("why can't I use this yet?") and should not
//  look like two unrelated screens. What differs is the ask: that one sells, this one
//  points at five lifts and a number.
//
//  The footer is `StrengthUnlockFooter`, the same component the Strength tab's sample
//  cards use. Three surfaces now track this one goal — the tier card, the milestones
//  card, and this — and they deliberately share the checklist so it reads as one mechanic
//  rather than three separate nudges. It is also the honest half of the screen: the
//  sample above is imaginary, the count below is true.
//

import SwiftUI

struct SessionTierPrerequisite: View {
    /// One flag per fundamental, in `TrendsCalculator.fundamentalExercises` order.
    let loggedFlags: [Bool]

    @State private var shimmer = false

    private var loggedCount: Int { loggedFlags.filter { $0 }.count }
    private var remaining: Int { loggedFlags.count - loggedCount }

    var body: some View {
        VStack(spacing: 20) {
            hero
            SessionSampleCard()

            // Carries the real count, the five icons, and the tap through to the Lift
            // tab. `widget` is what separates this surface from the two Strength-tab
            // cards in Amplitude, so the same event can answer "which screen actually
            // drives people to log their baseline?".
            StrengthUnlockFooter(
                loggedFlags: loggedFlags,
                widget: "session_tab",
                // No "your starting" lead-in here — Smart Sessions is the whole payoff, and
                // the shorter line lets the amber term carry the sentence.
                unlockPrefix: "",
                unlockHighlight: "Smart Sessions"
            )
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.appAccent.opacity(0.10))
                    .frame(width: 64, height: 64)
                    .scaleEffect(shimmer ? 1.06 : 0.96)

                Image(systemName: "sparkles")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
            }
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    shimmer = true
                }
            }

            Text("Smart Sessions start where you do.")
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)

            // States the dependency plainly instead of apologising for a lock. The count
            // itself lives in the footer below, so this says WHY rather than repeating
            // HOW MANY — the two halves of the screen should not say the same thing.
            //
            // Two authored lines rather than one wrapping string, matching the premium
            // placeholder: the break belongs after the comma so the reason and the
            // requirement each get their own line.
            VStack(spacing: 2) {
                Text("To pick your lifts and how hard to push them,")
                Text("we need a starting point for each one.")
            }
            .font(.footnote)
            .foregroundStyle(.white.opacity(0.55))
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 8)

            // Only once there is real progress to acknowledge. At zero this would be
            // "5 lifts to go", which is just the requirement restated in a gloomier tone;
            // partway through, it is the sentence that makes finishing feel close.
            if loggedCount > 0 {
                Text(remaining == 1 ? "One lift to go." : "\(remaining) lifts to go.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.appAccent)
                    .padding(.top, 2)
            }
        }
    }
}
