//
//  ProgramMockComponents.swift
//  WeightApp
//
//  Building blocks for the Program tab proof-of-concept. Kept inside Views/Program/ so
//  the whole experiment deletes in one move.
//
//  Colour strategy: this view gets its colour from the effort tiers themselves, not from
//  a second decorative palette. Logged sets are drawn in solid effort colour; sets still
//  ahead are the same shape in outline. Notably it does NOT reuse `Color.dayChipColors`
//  for per-exercise identity — that array is the effort palette, so colouring a lift
//  green would imply a relationship to "easy" that does not exist.
//

import SwiftUI

// MARK: - Effort colours

/// Local copy of the effort→colour mapping.
///
/// This is knowingly a fifth copy — `CheckInView:5283`, `LegacyCheckInView:5166`,
/// `OnboardingView:988` and `SetPlanCatalogCardView:86` each have their own. Sharing one
/// would mean editing production files for a throwaway screen and giving up the clean
/// revert, which is worth more here than the deduplication.
///
/// Matches CheckInView's mapping specifically (`pr` → `appAccent`, not `setPR`) so the
/// tiles read identically to the Sets widget users already know from the Lift tab.
enum ProgramEffort {
    /// Ascending intensity. Matches the keys `POST /checkin/set-plans` validates against, with
    /// `pr` last: it is not an intensity band, but it is the payoff, so it sorts to the end.
    static let order = ["easy", "moderate", "hard", "redline", "pr"]

    static func color(_ key: String) -> Color {
        switch key {
        case "easy": return .setEasy
        case "moderate": return .setModerate
        case "hard": return .setHard
        case "redline": return .setNearMax
        case "pr": return .appAccent
        default: return .white.opacity(0.3)
        }
    }
}

// MARK: - Effort squares

/// The plan's shape, as fixed square tiles — one per set.
///
/// Fixed, not flexible: a set is a set, so every tile is the same size everywhere on the
/// screen and a six-set plan is visibly twice the work of a three-set plan. The tile size
/// is the constant; the container around it is what varies.
///
/// Filled tiles show the effort that ACTUALLY happened; unfilled tiles show what the
/// plan still asks for. So the strip reads as "here is what I did, here is what is left"
/// rather than pretending every logged set matched its slot — a plan is a rail, and a
/// deviation should be visible without being flagged as wrong.
///
/// Logging more sets than the plan called for grows the strip rather than truncating.
/// Extra work is work.
struct EffortSquares: View {
    let sequence: [String]
    /// Effort keys actually logged, in order. Takes precedence over `completed`.
    var loggedEfforts: [String] = []
    /// Count-only fallback, used where real efforts are unknown (samples, drafts crediting
    /// pre-existing sets). Fills with the planned colours.
    var completed: Int = 0
    var side: CGFloat = 18
    var spacing: CGFloat = 3
    var radius: CGFloat = 3
    /// Each tile casts a soft shadow in its own colour. Showcase only — it turns a row of flat
    /// chips into lit pixels without changing a single hue, so the hierarchy survives intact:
    /// the amber tile glows amber and stays the place the eye lands.
    var glow: Bool = false

    /// Planned colours standing in when only a count is known.
    private var efforts: [String] {
        loggedEfforts.isEmpty && completed > 0
            ? Array(sequence.prefix(completed))
            : loggedEfforts
    }

    var body: some View {
        let total = max(sequence.count, efforts.count)

        HStack(spacing: spacing) {
            ForEach(0..<total, id: \.self) { index in
                let isLogged = index < efforts.count
                let key = isLogged
                    ? efforts[index]
                    : sequence[min(index, sequence.count - 1)]
                let color = ProgramEffort.color(key)

                RoundedRectangle(cornerRadius: radius)
                    .fill(isLogged ? color : color.opacity(0.16))
                    .overlay {
                        if !isLogged {
                            RoundedRectangle(cornerRadius: radius)
                                .strokeBorder(color.opacity(0.65), lineWidth: 1)
                        }
                    }
                    .frame(width: side, height: side)
                    // Only on a filled tile: an unlogged one is 16% opacity, and haloing
                    // something that faint reads as a rendering artefact rather than light.
                    .shadow(color: (glow && isLogged) ? color.opacity(0.35) : .clear,
                            radius: 8)
            }
        }
    }
}

// MARK: - Plan tile

/// Geometry for the planning card's set-plan strip.
///
/// These numbers are measured, not chosen. The row is `[22pt icon][name][>=6pt spacer][strip]`
/// inside an `HStack(spacing: 8)`, on a card that leaves 311pt of usable width on the narrowest
/// device running the deployment target (375pt, less 16pt of scroll inset and 16pt of card
/// padding on each side). "Overhead Press" — the longest of the five lifts the generator can
/// pick — is 113.1pt at `.subheadline.weight(.semibold)`, and the name is `fixedSize` with a
/// layout priority, so it does not give: anything the strip takes past its share pushes the
/// row over rather than shrinking the text.
///
/// That leaves `311 - 52 = 259pt` for name plus strip, hence:
///
///     6 tiles @ 20 -> 143pt strip, 116pt for a 113.1pt name   (fits)
///     7 tiles @ 20 -> 167pt strip,  92pt                      (does not)
///     8 tiles @ 14 -> 138pt strip, 121pt                      (fits)
///
/// Re-measure before changing any of them.
enum PlanTileMetrics {
    /// Matches `underwayRow`'s tiles, so a session does not appear to change size when it
    /// goes from Planning to Underway.
    static let standardSide: CGFloat = 20
    /// For plans too long to draw at `standardSide` without crowding out the lift name.
    static let compactSide: CGFloat = 14
    /// Longest plan that still fits at `standardSide`. Covers Standard (6) and everything
    /// shorter, which is nearly every plan in the catalogue.
    static let standardMaxSets = 6
    static let padding: CGFloat = 4

    static func spacing(for side: CGFloat) -> CGFloat { side >= standardSide ? 3 : 2.5 }

    /// One size for a whole card, driven by its longest plan.
    static func side(forLongestPlan sets: Int) -> CGFloat {
        sets > standardMaxSets ? compactSide : standardSide
    }
}

/// One exercise's set plan for today — the atomic unit.
///
/// The container hugs its tiles: fixed height, width set purely by how many sets the plan
/// has, so plan length is legible from the container's width alone. Bounded by a hairline
/// rather than a fill, which would add another grey to a screen that already has the page
/// and the cards.
struct PlanTile: View {
    let item: MockPlanItem
    /// Tile edge, chosen by the CARD rather than the row — see `ProgramMockView.planTileSide`.
    ///
    /// Sized per-row it would be actively misleading: a 3-set strip and an 8-set strip drawn
    /// at different tile sizes look comparable when the whole point of the strip is that they
    /// are not. One size for every row in a card keeps "twice as long means twice the work"
    /// true where a reader actually compares them.
    var side: CGFloat = PlanTileMetrics.standardSide
    var glow: Bool = false
    /// Draw every tile filled in its planned colour, regardless of what is logged.
    ///
    /// For the showcase session only. In the app an unlogged tile is 16% opacity behind a
    /// hairline, which correctly says "not done yet" — but the sample state exists to be
    /// photographed, and at that treatment the effort palette barely reads.
    var saturated: Bool = false

    var body: some View {
        EffortSquares(
            sequence: item.sequence,
            loggedEfforts: saturated ? [] : item.loggedEfforts,
            completed: saturated ? item.sequence.count : item.completedSets,
            side: side,
            spacing: PlanTileMetrics.spacing(for: side),
            glow: glow
        )
            .padding(PlanTileMetrics.padding)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }
}

// MARK: - Progress

struct ProgramProgressBar: View {
    let fraction: Double
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.10))
                Capsule()
                    .fill(Color.appAccent)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Pills

struct StatusPill: View {
    let text: String
    var isAccent: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(isAccent ? Color.appAccent : .white.opacity(0.55))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    isAccent ? Color.appAccent.opacity(0.15) : Color.white.opacity(0.08)
                )
            )
    }
}

/// The session's whole set list as one ribbon, grouped by intensity.
///
/// Grouped rather than in play order: interleaved, ten segments read as noise at 4pt tall, while
/// grouped it reads as a shape — mostly easy, a couple of working sets, one attempt. It also puts
/// full-saturation colour in the card's quietest zone, which is what the removed duration line
/// used to occupy.
struct EffortMixStrip: View {
    let sequences: [[String]]
    var height: CGFloat = 4

    private var counts: [(key: String, count: Int)] {
        let all = sequences.flatMap { $0 }
        return ProgramEffort.order.compactMap { key in
            let n = all.filter { $0 == key }.count
            return n > 0 ? (key, n) : nil
        }
    }

    var body: some View {
        let total = max(1, counts.reduce(0) { $0 + $1.count })
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(counts, id: \.key) { seg in
                    Capsule()
                        .fill(ProgramEffort.color(seg.key))
                        .frame(width: max(2, (geo.size.width - CGFloat(counts.count - 1) * 2)
                                             * CGFloat(seg.count) / CGFloat(total)))
                }
            }
        }
        .frame(height: height)
    }
}

// MARK: - Card chrome

extension View {
    /// The thin edge the Session tab's cards carry, matching the strength-tier widget on
    /// the Lift tab (`CheckInView:1238-1242`) — same 1pt stroke on the same 12pt radius.
    ///
    /// An extension rather than the literal repeated at each card: every state of the
    /// session state machine needs it, and a border that appeared on some states and not
    /// others would flicker as the card swapped between them.
    ///
    /// The neutral white is deliberate. The Lift tab's version tints with the user's tier
    /// (and goes amber mid-session), but there is no tier to reflect here, and amber is
    /// already carrying meaning inside these cards — completed lifts, the accent on
    /// actions. A coloured edge would compete with the content it frames.
    func sessionCardBorder() -> some View {
        overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.15), lineWidth: 1)
        )
    }
}

// MARK: - Layout measurement

/// Carries the collapsed idle card's height up so the generating state can match it.
/// Without this the card visibly jumps the moment you tap Start Session.
struct CardHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

// MARK: - Context chips

/// Selectable context handed to the generator. Multi-select, because "short on time" and
/// "legs are sore" are not mutually exclusive.
struct ContextChip: View {
    let text: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Unselected chips were sitting at 0.75 text on a 0.06 fill with a 0.14
            // border — legible in isolation, but they read as disabled next to the solid
            // accent of a selected one. Lifted across all three so an untapped chip looks
            // like an available option rather than a greyed-out one; the selected state is
            // still unmistakable, since it is the only filled thing in the row.
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSelected ? .black : .white.opacity(0.92))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule().fill(isSelected ? Color.appAccent : Color.white.opacity(0.10))
                )
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? Color.clear : Color.white.opacity(0.26),
                        lineWidth: 1
                    )
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glinting sparkle

/// A sparkle that catches the light once every few seconds, then rests.
///
/// A continuous pulse would read as a loading indicator; a single slow glint reads as
/// something latent. Built with `phaseAnimator` rather than `repeatForever` because
/// `repeatForever` only does symmetric cycles — the long still pause between glints is
/// the whole effect, and here it is just a phase whose animation is long and changes
/// nothing.
struct GlintingSparkle: View {
    var size: CGFloat = 14

    private enum GlintPhase: CaseIterable {
        case rest, glint, settle
    }

    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size, weight: .semibold))
            .phaseAnimator(GlintPhase.allCases) { content, phase in
                content
                    .opacity(phase == .glint ? 1 : 0.82)
                    .scaleEffect(phase == .glint ? 1.15 : 1)
            } animation: { phase in
                switch phase {
                case .glint: return .easeOut(duration: 0.3)
                case .settle: return .easeIn(duration: 0.55)
                // Same values as `.settle`, so this is a still hold, not a movement.
                case .rest: return .linear(duration: 3.2)
                }
            }
    }
}

// MARK: - Generating

/// The wait. Steps through `ProgramMockData.generatingSteps` so the delay explains what a
/// real request would be doing rather than showing an unexplained spinner, and the dots
/// give it a visible end.
struct GeneratingView: View {
    let steps: [String]

    @State private var index = 0
    @State private var pulse = false
    @State private var sweep = false
    /// Which lift the sweep is currently "considering". Purely decorative, but it is the
    /// detail that makes the wait feel like work being done on YOUR lifts rather than a
    /// generic spinner.
    @State private var scanIndex = 0

    private var lifts: [TrendsCalculator.FundamentalExercise] {
        TrendsCalculator.fundamentalExercises
    }

    var body: some View {
        VStack(spacing: 18) {
            emblem

            // Fixed height so a longer line does not shove the card taller mid-crossfade.
            ZStack {
                Text(steps.isEmpty ? "" : steps[index % steps.count])
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
                    .id(index)
            }
            .frame(height: 20)
            .animation(.easeInOut(duration: Self.fade), value: index)

            liftScanner
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 26)
        .task { await cycle() }
        .task { await scan() }
    }

    // MARK: - Emblem

    /// A ring that sweeps continuously around the pulsing sparkle.
    ///
    /// The sweep is what carries "still working" now that the step dots are gone — a pulse
    /// alone reads as idle breathing, where rotation reads as progress without ever
    /// claiming a percentage it does not know.
    private var emblem: some View {
        ZStack {
            Circle()
                .strokeBorder(Color.appAccent.opacity(0.14), lineWidth: 2)
                .frame(width: 58, height: 58)

            Circle()
                .trim(from: 0, to: 0.28)
                .stroke(
                    Color.appAccent.opacity(0.9),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
                .frame(width: 58, height: 58)
                .rotationEffect(.degrees(sweep ? 360 : 0))

            Image(systemName: "sparkles")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Color.appAccent)
                .scaleEffect(pulse ? 1.10 : 0.94)
                .opacity(pulse ? 1 : 0.65)
        }
        .onAppear {
            // Two independent rhythms on purpose. Matched durations made the whole emblem
            // beat as one object; deliberately unrelated periods keep it alive for the
            // fifteen-plus seconds a real generation can take.
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
            withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) {
                sweep = true
            }
        }
    }

    // MARK: - Lift scanner

    /// The five fundamentals, lit one at a time.
    ///
    /// Reuses the checklist vocabulary from `StrengthUnlockFooter` and `TierJourneyOverlay`
    /// — same icons, same order — so the wait is visibly about the same five lifts the rest
    /// of the app is about. It is honest as far as it goes: the request really is weighing
    /// each of these, even though the highlight order is not tied to the model's work.
    private var liftScanner: some View {
        HStack(spacing: 12) {
            ForEach(Array(lifts.enumerated()), id: \.offset) { position, lift in
                let isActive = position == scanIndex
                Image(lift.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 34, height: 34)
                    .foregroundStyle(isActive ? Color.appAccent : .white.opacity(0.20))
                    .scaleEffect(isActive ? 1.16 : 1.0)
                    // Longer than the old 0.32 so the handover is a fade between two
                    // lifts rather than a blink — at this size a fast switch reads as
                    // flicker.
                    .animation(.easeInOut(duration: 0.45), value: scanIndex)
            }
        }
    }

    // MARK: - Timing

    /// Rotate the lines for as long as the request takes.
    ///
    /// Deliberately unbounded. This used to walk the steps once and stop on the last one,
    /// which was fine against a mock that always finished in about two seconds — against
    /// the real endpoint it lands on the final line after 2s and then sits frozen for the
    /// remaining ten-plus, reading as a hang. There is no progress to report, so the only
    /// honest signal is continued motion.
    ///
    /// `.task` cancels this when the view goes away, which is what ends the loop.
    private func cycle() async {
        guard steps.count > 1 else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.dwell))
            guard !Task.isCancelled else { return }
            index += 1
        }
    }

    /// Advances the lift highlight. Faster than the text, so the two never pulse in
    /// lockstep — synchronised motion reads as one animation looping, which is exactly the
    /// impression a long wait should avoid.
    private func scan() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.scanStep))
            guard !Task.isCancelled else { return }
            scanIndex = (scanIndex + 1) % max(1, lifts.count)
        }
    }

    /// Long enough to read a line without it feeling like a slideshow, short enough that
    /// two lines change before a typical request returns.
    private static let dwell: TimeInterval = 2.0
    private static let fade: TimeInterval = 0.35
    /// Deliberately unhurried: at 0.55 the row read as a strobe rather than as attention
    /// moving from one lift to the next. Also not a divisor of `dwell`, so the text and
    /// the scanner drift against each other instead of locking into a repeating pair.
    private static let scanStep: TimeInterval = 1.1
}
