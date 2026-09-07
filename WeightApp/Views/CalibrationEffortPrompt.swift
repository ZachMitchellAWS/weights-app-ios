//
//  CalibrationEffortPrompt.swift
//  WeightApp
//
//  "How did that feel?" — the question asked once per fundamental lift, immediately after the
//  first weighted set, whose answer becomes that lift's starting estimated 1RM.
//
//  This was a system `.alert` with five unlabelled buttons and a one-line footnote. That was
//  the wrong instrument twice over. An alert reads as an interruption to be cleared, when this
//  is the most consequential input the app ever asks for — the answer divides the Epley
//  estimate (`OneRMCalculator.calibrated1RM`), so picking "Easy" instead of "Hard" moves the
//  resulting e1RM by nearly 30%. And a bare stack of five words gives no basis for choosing
//  between them: "Moderate" and "Hard" mean whatever the user decides they mean.
//
//  So each option now carries the sentence that disambiguates it, and the app's own effort
//  colours (`Color.setEasy` … `.setPR`, the same five the set tiles and effort squares use)
//  rather than five identical rows. Someone who has seen a session card has already met this
//  palette.
//
//  Card chrome is `readyToLiftCard`'s / `SessionCelebrationCard`'s / `BaselineRevealOverlay`'s,
//  which is also what makes the sequence read as one flow: this card asks, and the reveal that
//  replaces it answers in the same frame.
//
//  CANCELLING IS A REAL PATH. `discardPendingCalibration` deletes the set outright — nothing
//  was synced yet — so the wording stays "Cancel" rather than anything implying the set is
//  kept.
//

import SwiftUI

struct CalibrationEffortPrompt: View {
    let exerciseName: String
    let weight: Double
    let reps: Int
    let unit: WeightUnit

    /// Four of the five map to an `EffortMode`; "Max Effort" has no mode and passes a raw
    /// fraction of 1.0, which is why the callback takes both and each option supplies one.
    let onSelect: (EffortMode?, Double?) -> Void
    let onCancel: () -> Void

    private struct Option {
        let title: String
        let detail: String
        let color: Color
        let mode: EffortMode?
        let fraction: Double?
    }

    /// Ordered easy → maximal, matching the effort ramp everywhere else in the app.
    ///
    /// The detail lines are written as things a lifter would say about a set they just did,
    /// not as percentages. The percentages exist (`EffortMode.calibrationMidpoint`) but
    /// showing them would invite the user to reverse-engineer a number instead of reporting
    /// an experience, and the experience is the only thing they actually know.
    private var options: [Option] {
        [
            Option(title: "Easy", detail: "Could have done many more",
                   color: .setEasy, mode: .easy, fraction: nil),
            Option(title: "Moderate", detail: "A few more in the tank",
                   color: .setModerate, mode: .moderate, fraction: nil),
            Option(title: "Hard", detail: "Maybe one or two more",
                   color: .setHard, mode: .hard, fraction: nil),
            Option(title: "Near Max", detail: "Almost nothing left",
                   color: .setNearMax, mode: .progress, fraction: nil),
            Option(title: "Max Effort", detail: "All I could possibly lift",
                   color: .setPR, mode: nil, fraction: 1.0),
        ]
    }

    var body: some View {
        ZStack {
            // No tap-to-dismiss. Every other card in this family closes on a scrim tap, but
            // there is a set already written waiting on this answer — an accidental tap would
            // silently delete it. Cancel is explicit here on purpose.
            Color.black.opacity(0.62)
                .ignoresSafeArea()

            card
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            Text("HOW DID THAT FEEL?")
                .font(.interSemiBold(size: 11))
                .tracking(3)
                .foregroundStyle(Color.appAccent)

            // The lift, then the set, and no sentence explaining either. What the answer is
            // FOR is a paragraph the user does not need at the moment of answering — the
            // reveal that follows says it, when there is something concrete to attach it to.
            // Naming the lift still matters here: by this point they have typed a weight, a
            // rep count and tapped Log, and "which lift was this?" is a fair question.
            VStack(spacing: 4) {
                Text(exerciseName.uppercased())
                    .font(.bebasNeue(size: 32))
                    .tracking(1.5)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text("\(unit.formatWeightTrimmed(weight)) \(unit.label) × \(reps)")
                    .font(.inter(size: 14))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
            }

            VStack(spacing: 8) {
                ForEach(options, id: \.title) { option in
                    optionRow(option)
                }
            }
            .padding(.top, 2)

            Button(action: onCancel) {
                Text("Cancel")
                    .font(.inter(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 22)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .frame(maxWidth: 330)
        .background(
            LinearGradient(colors: [Color(white: 0.14), Color(white: 0.09)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Color.appAccent.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(.horizontal, 24)
    }

    private func optionRow(_ option: Option) -> some View {
        Button {
            onSelect(option.mode, option.fraction)
        } label: {
            HStack(spacing: 11) {
                // A bar rather than a dot: it reads as the same vocabulary as the set rows on
                // the Lift tab, which lead with a coloured rule in exactly this palette.
                RoundedRectangle(cornerRadius: 2)
                    .fill(option.color)
                    .frame(width: 3, height: 24)

                Text(option.title)
                    .font(.interSemiBold(size: 15))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()

                Spacer(minLength: 8)

                Text(option.detail)
                    .font(.inter(size: 14))
                    // Lifted from 0.4 along with the size. The detail is what actually
                    // disambiguates the options, so it should not read as a footnote to the
                    // one-word label beside it.
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(option.color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(option.color.opacity(0.35), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
