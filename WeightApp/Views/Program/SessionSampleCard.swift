//
//  SessionSampleCard.swift
//  WeightApp
//
//  The illustrative session shown on both of the Session tab's pre-access states —
//  `SessionPremiumPlaceholder` (not subscribed) and `SessionTierPrerequisite` (starting
//  Strength Tier not yet unlocked).
//
//  One definition rather than two, for the same reason `StrengthSampleChrome` is shared
//  on the Strength tab: two surfaces arguing for the same feature should show the same
//  object, and a copy would drift the moment the real draft card changes.
//
//  A real draft card, shrunk. Non-interactive and badged, so it is never mistaken for
//  something generated from this user's training. It deliberately omits the real card's
//  "Built 9:41 AM" marker — that timestamp earns its place by telling you a real draft is
//  current, and inventing one here would be a small fiction in service of nothing.
//

import SwiftUI

struct SessionSampleCard: View {
    /// Frozen so the sample never implies it was generated for this user.
    private let sample = ProgramMockData.defaultPlan

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appAccent)
                Text("Today's Session")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)

            Text(sample.summary)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Divider().overlay(Color.white.opacity(0.08))

            VStack(spacing: 12) {
                ForEach(sample.items) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(item.icon)
                                .resizable().scaledToFit()
                                .frame(width: 30, height: 30)
                                .foregroundStyle(.white.opacity(0.6))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.85)
                                Text(item.planName)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.45))
                            }

                            Spacer(minLength: 6)

                            PlanTile(item: item)
                        }

                        // The reasoning is the product. Hiding it here would leave the
                        // sample looking like any other list of exercises.
                        Text(item.rationale)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            // Tracks the icon width + row spacing, so the reasoning
                            // hangs under the exercise name rather than under the icon.
                            .padding(.leading, 40)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            StrengthSampleBadge().padding(10)
        }
        .allowsHitTesting(false)
    }
}
