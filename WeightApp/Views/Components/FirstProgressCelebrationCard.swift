//
//  FirstProgressCelebrationCard.swift
//  WeightApp
//
//  The first time a user's estimated 1RM goes up on a fundamental lift after unlocking their
//  starting strength tier. Once ever.
//
//  Before this, that moment drew the same 180x180 dialog every other set draws: logo,
//  "Increased 1RM by", a number, gone in two seconds. Outside a session it is also the screen
//  immediately preceding the App Store review prompt, so the best moment the app has was
//  represented by its most generic component and used as the run-up to asking for five stars.
//
//  DELIBERATELY TIER-AGNOSTIC. An earlier cut coloured the card by the lift's strength tier and
//  named the tier under the lift, with a CTA through to the Strength tab. That made it a tier
//  card, which it is not: this is a special state of the ordinary e1RM-increase dialog, and it
//  is about the increment, not about where the user sits on the ladder. Everything is the app
//  accent, the tier is never shown, and the button only closes.
//
//  Standalone rather than a private `var` on CheckInView so the Developer menu can present it
//  directly with sample data, which is the only practical way to look at a once-ever screen.
//

import SwiftUI

struct FirstProgressCelebrationCard: View {
    let exerciseName: String
    /// Asset name from `TrendsCalculator.FundamentalExercise.icon`.
    let exerciseIcon: String
    /// Pre-formatted by the caller, which owns the user's unit preference. e.g. "+2.5 lb".
    let deltaText: String
    /// The scrim and the button do the same thing. There is nowhere else for this card to go.
    let onDismiss: () -> Void

    private let accent = Color.appAccent

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            VStack(spacing: 12) {
                Text("STRONGER ALREADY")
                    .font(.bebasNeue(size: 26))
                    .foregroundStyle(accent)

                ZStack {
                    Circle()
                        .fill(accent.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(accent.opacity(0.7), lineWidth: 3)
                        .frame(width: 72, height: 72)
                    Image(exerciseIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                        .foregroundStyle(accent)
                }

                VStack(spacing: 3) {
                    Text(exerciseName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text("\(deltaText) estimated max")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                // Accented term inside prose, built by Text concatenation the same way
                // `BaselineRevealOverlay.explanation` does it. "e1RM" is a named concept in
                // this app, and the colour is what makes it register as one rather than as
                // an abbreviation the user is expected to already know.
                VStack(spacing: 6) {
                    (Text("It's working. Keep pushing your ")
                        + Text("e1RM").foregroundColor(accent)
                        + Text(" incrementally higher over time."))
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    // Its own line on purpose: it is the sign-off, not part of the
                    // instruction above it.
                    Text("You're on your way.")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)

                Button(action: onDismiss) {
                    Text("Got it")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(accent, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                .padding(.bottom, 4)
            }
            .padding(16)
            .frame(width: 260)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(accent.opacity(0.5), lineWidth: 1.5)
            )
        }
    }
}

#Preview("Bench Press") {
    FirstProgressCelebrationCard(
        exerciseName: "Bench Press", exerciseIcon: "BenchPressIcon",
        deltaText: "+2.5 lb", onDismiss: {}
    )
}

#Preview("Long name, small delta") {
    FirstProgressCelebrationCard(
        exerciseName: "Overhead Press", exerciseIcon: "OverheadPressIcon",
        deltaText: "+0.75 lb", onDismiss: {}
    )
}
