//
//  BaselineRevealOverlay.swift
//  WeightApp
//
//  The moment a fundamental lift gets its first estimated 1RM.
//
//  Replaces `TierJourneyOverlay`'s "Nice Work / 2 of 5 Exercises Logged" for exactly one
//  situation: the user just logged, and this lift now has a number where it had none. That
//  popup was a counter. This one says what the number IS, in English, and what moves it —
//  the only chance the app gets to explain its own mechanic at the moment the user has just
//  performed it.
//
//  It deliberately does NOT name the exercise's tier or chart progress toward the next one.
//  That is the Strength tab's job, and putting it here made a first-ever set arrive with a
//  ranking attached before the user knew what was being ranked.
//
//  SCOPE. `TierJourneyOverlay` still owns everything else and is untouched:
//    - `.intro`                       app launch / post-onboarding
//    - `.progress(justLoggedId: nil)` resumed mid-journey on a later launch
//    - `.completion` for LATER overall tier-ups, which show the tier name
//  This view handles the just-logged case for lifts 1-4, and the fifth lift's starting-tier
//  unlock. See `CheckInView.applyCalibration` / `logSet` for the routing.
//
//  THE TIER NAME IS NEVER RENDERED HERE. `TierJourneyOverlay` needs a `hideTierName` flag
//  because it serves both the starting unlock (mystery: colour but no name, so the user goes
//  to the Strength tab to find out) and later unlocks (named). This view only ever serves the
//  starting one, so the flag would have a single value and is simply absent.
//
//  Visual language is `readyToLiftCard`'s (CheckInView) and `SessionCelebrationCard`'s: same
//  scrim, card width, corner radius, gradient, accent border, shadow and type ramp. Those two
//  already duplicate the spec literally rather than share a modifier; this is the third, and
//  factoring all three into one `.popupCard()` would be a fair cleanup for whoever adds a
//  fourth.
//

import SwiftUI

enum BaselineRevealMode {
    /// Lifts 1-4. `nextUp` is the lift to send them to; nil only if the tier array is stale,
    /// which is handled rather than left to render a card with no button.
    case progress(nextUp: TrendsCalculator.FundamentalExercise?)
    /// Lift 5. The starting Strength Tier just unlocked.
    case unlocked(tier: StrengthTier)
}

struct BaselineRevealOverlay: View {
    let mode: BaselineRevealMode
    let exercise: TrendsCalculator.FundamentalExercise
    let e1rm: Double
    let exerciseTiers: [(exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier)]
    let unit: WeightUnit

    let onDismiss: () -> Void
    let onNavigateToExercise: (UUID) -> Void
    let onNavigateToStrength: () -> Void
    /// Deletes the set that produced this reveal. Absent from `.unlocked` — see `undoButton`.
    let onReset: () -> Void

    @State private var glowPhase: CGFloat = 1.0
    @State private var revealed = false


    private var isUnlocked: Bool {
        if case .unlocked = mode { return true }
        return false
    }

    /// Amber normally; the tier's colour on the unlock, following `milestoneOverlay`'s
    /// precedent of tinting the whole card to the tier being revealed.
    private var borderColor: Color {
        if case .unlocked(let tier) = mode { return tier.color.opacity(0.35) }
        return Color.appAccent.opacity(0.25)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
                .ignoresSafeArea()
                .onTapGesture { onDismiss() }

            card
        }
    }

    // MARK: - Card

    private var card: some View {
        VStack(spacing: 14) {
            Text(isUnlocked ? "STARTING TIER SET" : "STARTING POINT SET")
                .font(.interSemiBold(size: 11))
                .tracking(3)
                .foregroundStyle(Color.appAccent)

            liftIdentity
            measurement
            explanation

            Rectangle()
                .fill(Color.white.opacity(0.18))
                .frame(height: 1)

            footer
        }
        .padding(.horizontal, 26)
        .padding(.top, 30)
        .padding(.bottom, 22)
        .frame(maxWidth: 330)
        .background(
            LinearGradient(colors: [Color(white: 0.14), Color(white: 0.09)],
                           startPoint: .top, endPoint: .bottom),
            in: RoundedRectangle(cornerRadius: 22)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(borderColor, lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 30, height: 30)
                    .background(Color.white.opacity(0.08), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(12)
        }
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(.horizontal, 24)
    }

    // MARK: - Identity

    private var liftIdentity: some View {
        VStack(spacing: 6) {
            Image(exercise.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .foregroundStyle(Color.appAccent)

            Text(exercise.name.uppercased())
                .font(.bebasNeue(size: 32))
                .tracking(1.5)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    // MARK: - The number

    /// The number, with the unit stacked over the label beside it.
    ///
    /// `.center` alignment, NOT `.firstTextBaseline`. Baseline alignment matches the block's
    /// first line to the 48pt digit's baseline, which drops the whole stack to the number's
    /// feet and reads as an afterthought hanging off the corner. Centring sits it squarely
    /// beside the figure, which is what it is annotating.
    ///
    /// `formatWeightRounded` converts from the stored lbs, so a kg user sees kg.
    private var measurement: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(unit.formatWeightRounded(e1rm))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 0) {
                Text(unit.label)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                // Tinted `StrengthTier.elite.color`, not `.appAccent` — same amber, but that
                // is the idiom every other e1RM glyph in the app uses.
                Text("e1RM")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(StrengthTier.elite.color)
            }
        }
    }

    /// What moves the number, and what the number is called.
    ///
    /// Names the metric in full with the abbreviation in parentheses, rather than saying
    /// "this number". The card's hero is labelled `e1RM` and nothing else in the flow expands
    /// it — a user who skipped past onboarding meets the initialism cold, and one wordier
    /// sentence here is cheaper than an abbreviation they never decode.
    ///
    /// Two accented runs. Both are terms of art they will meet again all over the app, and
    /// the colour is what makes them register as named concepts rather than prose. The
    /// parenthetical stays inside the accented run — splitting the colour partway through a
    /// term and its own abbreviation reads as a mistake.
    ///
    /// Split into two blocks rather than one paragraph.
    ///
    /// As a single centred run it read as noise: ragged lines, an em dash breaking mid-thought,
    /// and two accent runs of different lengths scattered through with no structure to hang on.
    ///
    /// So the two sentences do visibly different jobs. The first NAMES the number — larger and
    /// brighter, because it is the one that has to land, and because the hero above it is
    /// labelled with an initialism the user has not necessarily met. The second states the
    /// objective and sits quieter beneath it.
    ///
    /// Both accented runs are terms of art the user will meet again all over the app; the
    /// colour is what makes them register as named concepts rather than prose. The `(e1RM)`
    /// stays inside its accent — splitting the colour partway through a term and its own
    /// abbreviation reads as a mistake.
    private var explanation: some View {
        VStack(spacing: 8) {
            (Text("This is your starting ")
                + Text("estimated 1-rep max (e1RM)").foregroundColor(Color.appAccent)
                + Text(" for \(exercise.name)."))
                .font(.inter(size: 13))
                .foregroundStyle(.white.opacity(0.62))

            // Non-breaking space, so "Progress sets" cannot be split across the wrap. A
            // two-word term of art broken in half stops reading as one thing, and this line
            // wraps at almost exactly that point.
            (Text("Move this number up by performing ")
                + Text("Progress\u{00A0}sets").foregroundColor(Color.appAccent)
                + Text("."))
                .font(.inter(size: 11.5))
                .foregroundStyle(.white.opacity(0.42))
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        switch mode {
        case .progress(let nextUp):
            VStack(spacing: 10) {
                // NO "N of 5 Lifts Logged". The row below already says it — five icons, the
                // logged ones amber with a tick, the rest hollow — and a card this dense
                // cannot afford to state the same fact twice, once in words and once in
                // pictures. The count was the redundant one.
                exerciseRow

                if let next = nextUp {
                    primaryCTA(label: "NEXT UP: \(Self.shortName(for: next.name).uppercased())",
                               color: .appAccent) {
                        onDismiss()
                        onNavigateToExercise(next.id)
                    }
                    // Extra air above the CTA specifically. The lift row above it is dense,
                    // and at the stack's 10pt the button read as the row's sixth column
                    // rather than as the thing to do next.
                    .padding(.top, 8)
                } else {
                    // `TierJourneyOverlay` renders NO button in this case, which leaves a
                    // popup whose only exit is the scrim. Reachable whenever the tier array
                    // is stale relative to the mode.
                    primaryCTA(label: "KEEP GOING", color: .appAccent) { onDismiss() }
                        .padding(.top, 8)
                }

                undoButton
            }

        case .unlocked(let tier):
            VStack(spacing: 10) {
                unlockBadge(tier: tier)

                Text("Strength Tier Unlocked")
                    .font(.bebasNeue(size: 24))
                    .foregroundStyle(tier.color)

                primaryCTA(label: "SEE MY STRENGTH TIER", color: tier.color) {
                    onDismiss()
                    onNavigateToStrength()
                }
            }
        }
    }

    /// Lifted from `TierJourneyOverlay.completionContent` so the unlock beat is unchanged from
    /// what shipped — same 60pt badge, same four layers, same 1.8s glow repeated four times.
    private func unlockBadge(tier: StrengthTier) -> some View {
        ZStack {
            Circle()
                .fill(tier.color.opacity(0.3))
                .frame(width: 60, height: 60)
                .scaleEffect(glowPhase)
                .opacity(1.0 - (glowPhase - 1.0) / 0.6)

            Circle()
                .fill(tier.color.opacity(0.2))
                .frame(width: 60, height: 60)

            Circle()
                .stroke(tier.color.opacity(0.7), lineWidth: 2.5)
                .frame(width: 60, height: 60)

            Image(tier.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 34, height: 34)
                .foregroundStyle(tier.color)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatCount(4, autoreverses: false)) {
                glowPhase = 1.6
            }
        }
    }

    /// The five-lift row, in `TierJourneyOverlay`'s vocabulary: 28pt icons, amber when logged,
    /// checkmark or hollow ring beneath. Icons are a touch smaller here than the 32 there,
    /// because this card carries considerably more above them.
    private var exerciseRow: some View {
        HStack(spacing: 10) {
            ForEach(exerciseTiers, id: \.exercise.id) { item in
                let isLogged = item.e1rm != nil
                let isJustLogged = item.exercise.id == exercise.id

                VStack(spacing: 4) {
                    Image(item.exercise.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 28, height: 28)
                        // Unlogged lifts are the to-do list this card is nudging toward, so
                        // they sit brighter than a typical disabled state.
                        .foregroundStyle(isLogged ? Color.appAccent : .white.opacity(0.42))

                    Text(Self.shortName(for: item.exercise.name))
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(isLogged ? 0.7 : 0.5))

                    if isLogged {
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
                .background {
                    if isJustLogged && revealed {
                        Circle()
                            .fill(Color.appAccent.opacity(0.15))
                            .frame(width: 40, height: 40)
                            .blur(radius: 8)
                    }
                }
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.4).delay(0.35)) { revealed = true }
        }
    }

    private func primaryCTA(label: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                // Bold, not semibold. On a filled amber capsule the black glyphs have to
                // hold their own against the fill, and at semibold this read lighter than
                // the button it sits in.
                .font(.system(size: 16, weight: .bold))
                .tracking(1)
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(color, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Deliberately plain text, not a button shape. It is an escape hatch for someone who
    /// typed a number to see what would happen, not an action the card is recommending.
    ///
    /// Absent on `.unlocked`: by then `markStartingTierUnlocked` has written
    /// `hasMetStrengthTierConditions` locally AND to the backend, fired its Amplitude event,
    /// POSTed a tier-unlock narrative that is generating audio, and cancelled the session
    /// reminder. None of that has an un-set path, and a local reset alone would be restored
    /// by the next `SyncService` pull.
    @ViewBuilder
    private var undoButton: some View {
        if !isUnlocked {
            Button(action: onReset) {
                Text("Undo this set")
                    .font(.inter(size: 13))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Helpers

    /// Same mapping as `TierJourneyOverlay` and `StrengthUnlockFooter`. Static so the previews
    /// in `MoreView` can label rows without constructing the view.
    static func shortName(for name: String) -> String {
        switch name {
        case "Overhead Press": return "OH Press"
        case "Bench Press": return "Bench"
        case "Barbell Rows": return "Rows"
        default: return name
        }
    }
}
