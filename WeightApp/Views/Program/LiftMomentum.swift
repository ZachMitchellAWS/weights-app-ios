//
//  LiftMomentum.swift
//  WeightApp
//
//  "How much momentum does this lift have right now" as a single 0...1 number, and the amber
//  it maps to.
//
//  MOMENTUM, NOT RECENCY. The score weights how HARD (effort per set), how MUCH (sets sum)
//  and how RECENTLY (linear decay) — all three. Recency named only the last, which made the
//  label a quiet lie: six easy sets and one progress set land in the same place, and neither
//  is "more recent" than the other. Momentum is the one ordinary word that carries all three,
//  because it builds with work and decays on its own when the work stops.
//
//  THE UI CALLS IT "TRAINING STATUS". That is deliberate and not drift. This type names the
//  METRIC, which is a decayed effort-weighted sum — momentum is what that is. The screens
//  name the SECTION, and "status" is the friendlier word for what the user is reading. Do not
//  rename this to match: the earlier `LiftRecency` rename happened because that name was
//  factually wrong about the arithmetic, which this one is not.
//
//  Used on the generating screen, in the section that recaps the last fourteen days while the
//  session is being drafted.
//
//  NOT on the context panel's lift selector, which was the first thing tried. Those cells
//  already say something with amber — whether the lift is eligible — and a second amber
//  meaning "recently trained" put two signals on one channel, so an eligible-but-cold lift
//  and an excluded one looked the same. One thing per control.
//
//  THE SCALE IS ANCHORED, NOT TUNED BY EYE. Four situations are defined to reach the top:
//
//    - one PROGRESS set today                    1.00
//    - a Quick Attempt today (easy/mod/hard/pr)   2.10  → clamps
//    - a Standard plan today                      2.65  → clamps
//    - six sets of anything today                 1.20  → clamps
//
//  and one is defined to reach the bottom: nothing logged in the last fourteen days, which
//  is 0 exactly because the decay term is zero at fourteen days. Everything else falls out of
//  those anchors rather than being chosen. If a weight below is changed, re-check them.
//
//  WHY EFFORT IS WEIGHTED AT ALL. Six easy sets and one progress set are both "a session's
//  worth" of evidence that the lift is being trained, and they should land in the same place;
//  a single easy set should not. Counting sets alone would make a warm-up look like work, and
//  counting only heavy sets would make a deload look like neglect.
//

import SwiftUI
import SwiftData

enum LiftMomentum {

    /// The window. Fourteen days because that is the span over which "have you been training
    /// this" is a question with a useful answer — a week punishes anyone on a four-day split,
    /// and a month makes a lift dropped two weeks ago still look live.
    static let windowDays = 14

    // MARK: - Scoring

    /// What a set turned out to be.
    ///
    /// Mirrors `CheckInView.actualEffort` exactly — same buckets, same labels, same colours,
    /// and a PR detected the same way (the set's Epley estimate exceeding the e1RM standing
    /// BEFORE it, rather than by reading the set plan, because what matters is what the set
    /// actually did). Shared so the heat gauge and the history feed can never disagree about
    /// what a given set was.
    enum Effort {
        case easy, moderate, hard, nearMax, progress
        /// Only reachable for a lift's first-ever set, where there is no e1RM to grade
        /// against. Named rather than folded into `.moderate` so the feed can label it
        /// honestly instead of asserting an intensity it cannot know.
        case baseline

        var label: String {
            switch self {
            case .easy: return "Easy"
            case .moderate: return "Moderate"
            case .hard: return "Hard"
            case .nearMax: return "Near Max"
            case .progress: return "Progress"
            case .baseline: return "Baseline"
            }
        }

        var color: Color {
            switch self {
            case .easy: return .setEasy
            case .moderate: return .setModerate
            case .hard: return .setHard
            case .nearMax: return .setNearMax
            case .progress: return .appAccent
            case .baseline: return .white.opacity(0.45)
            }
        }

        /// Contribution to the heat score, before recency decay. See the header's anchors.
        var weight: Double {
            switch self {
            case .progress: return 1.00
            case .nearMax:  return 0.80
            case .hard:     return 0.55
            case .moderate, .baseline: return 0.35
            case .easy:     return 0.20
            }
        }
    }

    /// Classify one set against the e1RM standing immediately before it.
    ///
    /// `prior <= 0` is the baseline case and is GUARDED, not incidental: `estimate / 0` is
    /// +infinity in Swift, which falls straight through to the near-max band and would score
    /// a brand-new user's first deadlift at 0.80.
    static func effort(weight setWeight: Double, reps: Int, priorE1RM prior: Double) -> Effort {
        guard prior > 0 else { return .baseline }
        let estimate = OneRMCalculator.estimate1RM(weight: setWeight, reps: reps)
        if estimate - prior > 0.0001 { return .progress }
        switch TrendsCalculator.IntensityBucket.from(percent1RM: estimate / prior) {
        case .pr, .nearMax: return .nearMax
        case .hard:         return .hard
        case .moderate:     return .moderate
        case .easy:         return .easy
        }
    }

    /// Linear to zero across the window. Deliberately not exponential: the point is a legible
    /// ramp the user could reconstruct if they thought about it, and an exponential curve
    /// makes anything past four or five days look identical to nothing at all.
    private static func decay(daysAgo: Int) -> Double {
        max(0, 1 - Double(daysAgo) / Double(windowDays))
    }

    /// Heat per fundamental lift, 0...1, keyed by exercise id.
    ///
    /// Computed for all five in one pass because every caller wants the whole row, and doing
    /// it per lift would re-scan and re-sort the same set list five times.
    static func heatByExercise(
        sets: [LiftSet],
        estimated1RMs: [Estimated1RM],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UUID: Double] {
        let fundamentalIds = Set(TrendsCalculator.fundamentalExercises.map(\.id))
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(windowDays - 1), to: today)
        else { return [:] }

        // e1RM history per exercise, oldest first, so "the value standing before this set" is
        // a walk rather than a re-sort per set.
        var historyByExercise: [UUID: [(date: Date, value: Double)]] = [:]
        for row in estimated1RMs where !row.deleted {
            guard let exerciseId = row.exercise?.id, fundamentalIds.contains(exerciseId) else { continue }
            historyByExercise[exerciseId, default: []].append((row.createdAt, row.value))
        }
        for key in historyByExercise.keys {
            historyByExercise[key]?.sort { $0.date < $1.date }
        }

        var heat: [UUID: Double] = [:]

        for set in sets {
            guard !set.deleted,
                  let exerciseId = set.exercise?.id,
                  fundamentalIds.contains(exerciseId),
                  set.createdAt >= windowStart
            else { continue }

            let daysAgo = calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: set.createdAt), to: today
            ).day ?? 0
            let recency = decay(daysAgo: daysAgo)
            guard recency > 0 else { continue }

            let history = historyByExercise[exerciseId] ?? []
            let prior = history.last(where: { $0.date < set.createdAt })?.value ?? 0
            let effort = effort(weight: set.weight, reps: set.reps, priorE1RM: prior)

            heat[exerciseId, default: 0] += effort.weight * recency
        }

        return heat.mapValues { min(1, $0) }
    }

    /// Whole days since each fundamental last had a set. Absent from the map when the lift
    /// has never been trained at all, which the caller must distinguish from "0 days ago".
    ///
    /// Unbounded, unlike `heatByExercise`'s window: the heat gauge stops caring past
    /// fourteen days, but "47 days" is exactly the number someone wants to see when a lift
    /// has gone cold.
    static func daysSinceLastTrained(
        sets: [LiftSet],
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [UUID: Int] {
        let fundamentalIds = Set(TrendsCalculator.fundamentalExercises.map(\.id))
        let today = calendar.startOfDay(for: now)

        var newest: [UUID: Date] = [:]
        for set in sets where !set.deleted {
            guard let exerciseId = set.exercise?.id, fundamentalIds.contains(exerciseId) else { continue }
            if let existing = newest[exerciseId], existing >= set.createdAt { continue }
            newest[exerciseId] = set.createdAt
        }

        return newest.mapValues { date in
            max(0, calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: date), to: today
            ).day ?? 0)
        }
    }

    // MARK: - History feed

    /// One fundamental set, flattened for display. Everything the feed draws is resolved
    /// here so the view is a renderer with no lookups of its own.
    struct RecentSet: Identifiable {
        let id: UUID
        let icon: String
        let liftName: String
        let detail: String      // "245 lbs × 5"
        let effort: Effort
        let dayKey: String      // ISO day, for grouping
        let dayLabel: String    // "TODAY", "YESTERDAY", "TUE"
    }

    /// Named days rather than counts. "3D AGO" makes the reader do arithmetic to place a
    /// session in their week; "TUE" is where they already keep it.
    private static func dayLabel(daysAgo: Int, date: Date) -> String {
        switch daysAgo {
        case 0: return "TODAY"
        case 1: return "YESTERDAY"
        default:
            let f = DateFormatter()
            f.dateFormat = "EEE"
            return f.string(from: date).uppercased()
        }
    }

    /// A day of training, newest first, for the generating screen's timeline.
    struct RecentDay: Identifiable {
        let id: String          // ISO day key
        let label: String       // "TODAY", "YESTERDAY", "TUE"
        let sets: [RecentSet]
    }

    /// The feed's window. A week, not the fourteen days the heat gauge uses: the heat gauge
    /// is answering "is this lift cold", where two weeks is the honest span, and this is
    /// answering "what have I been doing lately", where a fortnight of rows is a wall of text
    /// nobody reads during a twenty-second wait.
    static let feedDays = 7

    /// Last week's fundamental sets, grouped by day, newest day first and newest set first
    /// within each day.
    ///
    /// Grouped rather than flat because the chronology has to be readable at a glance — a
    /// continuous list of sets with a relative-date column on each row makes the reader
    /// reconstruct the days themselves.
    static func recentDays(
        sets: [LiftSet],
        estimated1RMs: [Estimated1RM],
        unit: WeightUnit,
        maxSets: Int = 9,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RecentDay] {
        let flat = recentSets(
            sets: sets, estimated1RMs: estimated1RMs, unit: unit,
            limit: maxSets, windowDays: feedDays, now: now, calendar: calendar
        )
        // `flat` is already newest-first, so first-seen order is newest-day-first and the
        // sets inside each day keep their order. No re-sorting needed.
        var order: [String] = []
        var byDay: [String: [RecentSet]] = [:]
        for item in flat {
            if byDay[item.dayKey] == nil { order.append(item.dayKey) }
            byDay[item.dayKey, default: []].append(item)
        }
        return order.map { key in
            RecentDay(id: key, label: byDay[key]?.first?.dayLabel ?? key, sets: byDay[key] ?? [])
        }
    }

    static func recentSets(
        sets: [LiftSet],
        estimated1RMs: [Estimated1RM],
        unit: WeightUnit,
        limit: Int = 40,
        windowDays feedWindow: Int = feedDays,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [RecentSet] {
        let fundamentalIds = Set(TrendsCalculator.fundamentalExercises.map(\.id))
        let iconByExercise = Dictionary(
            uniqueKeysWithValues: TrendsCalculator.fundamentalExercises.map { ($0.id, $0.icon) }
        )

        var historyByExercise: [UUID: [(date: Date, value: Double)]] = [:]
        for row in estimated1RMs where !row.deleted {
            guard let exerciseId = row.exercise?.id, fundamentalIds.contains(exerciseId) else { continue }
            historyByExercise[exerciseId, default: []].append((row.createdAt, row.value))
        }
        for key in historyByExercise.keys {
            historyByExercise[key]?.sort { $0.date < $1.date }
        }

        let today = calendar.startOfDay(for: now)
        let cutoff = calendar.date(byAdding: .day, value: -(feedWindow - 1), to: today) ?? today

        return sets
            .filter {
                !$0.deleted
                    && fundamentalIds.contains($0.exercise?.id ?? UUID())
                    && $0.createdAt >= cutoff
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .compactMap { set -> RecentSet? in
                guard let exerciseId = set.exercise?.id, let icon = iconByExercise[exerciseId]
                else { return nil }

                let prior = (historyByExercise[exerciseId] ?? [])
                    .last(where: { $0.date < set.createdAt })?.value ?? 0
                let daysAgo = calendar.dateComponents(
                    [.day], from: calendar.startOfDay(for: set.createdAt), to: today
                ).day ?? 0

                return RecentSet(
                    id: set.id,
                    icon: icon,
                    liftName: (set.exercise?.name ?? "").uppercased(),
                    detail: "\(unit.formatWeightTrimmed(set.weight)) \(unit.label) × \(set.reps)",
                    effort: effort(weight: set.weight, reps: set.reps, priorE1RM: prior),
                    dayKey: ISO8601DateFormatter.dayKey.string(from: calendar.startOfDay(for: set.createdAt)),
                    dayLabel: Self.dayLabel(daysAgo: daysAgo, date: set.createdAt)
                )
            }
    }

    // MARK: - Colour

    /// Cold grey through to full accent amber.
    ///
    /// `pow(t, 0.7)` rather than linear: a lift trained once four days ago has a genuinely
    /// low score, and on a straight ramp it renders as the same grey as one trained never.
    /// Easing lifts the bottom of the range into visible amber while leaving the top alone,
    /// so "some" and "none" are distinguishable at a glance — which is the only comparison
    /// this control has to support.
    static func tint(_ heat: Double) -> Color {
        let t = pow(min(max(heat, 0), 1), 0.7)
        // Endpoints: white 0.22 (the app's standard inactive glyph) → Color.appAccent.
        return Color(
            red:   0.22 + (1.000 - 0.22) * t,
            green: 0.22 + (0.784 - 0.22) * t,
            blue:  0.22 + (0.314 - 0.22) * t
        )
    }
}

/// The five fundamentals tinted by how recently and how hard they were trained.
///
/// Read-only. The selector in the context panel draws its own cells because those also carry
/// selection state and a tap target; this is the plain version, for the generating screen.
struct LiftMomentumRow: View {
    let heat: [UUID: Double]
    var iconSize: CGFloat = 34

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TrendsCalculator.fundamentalExercises, id: \.id) { lift in
                VStack(spacing: 5) {
                    Image(lift.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: iconSize, height: iconSize)
                        .foregroundStyle(LiftMomentum.tint(heat[lift.id] ?? 0))

                    Text(ProgramSessionStore.shortName(for: lift.name))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.35))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

private extension ISO8601DateFormatter {
    /// Day-only keys for grouping. A shared instance because `DateFormatter` construction is
    /// expensive and this runs once per set.
    static let dayKey: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate]
        return f
    }()
}
