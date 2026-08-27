//
//  ProgramMockData.swift
//  WeightApp
//
//  Every value shown on the Program tab's proof-of-concept. All of it is invented.
//
//  The concept being mocked: you show up, say you are ready to train, and the app picks
//  today's lifts and a set plan for each from your recent history. Nothing is scheduled
//  in advance — a plan is generated on demand, can be revised with extra context, and
//  can be discarded.
//
//  In a real build the generation step would send an elaborate prompt (recent sets from
//  the past ~2 weeks, current estimated 1RMs, the set-plan catalog, any context the user
//  typed) to the API and get back a chosen list of exercises with a plan each. Here it is
//  a timer and two hardcoded outcomes.
//
//  Deliberately static: no @Query, no ModelContext, no network. Looks identical on any
//  account and deletes in one move.
//

import Foundation

// MARK: - Types

/// How a planned set plan is going. Deliberately not pass/fail — a progress set that
/// came in under target is `.short`, which is a *description*, not a judgement. Nothing
/// in the UI marks it red, marks it incomplete, or scores it.
enum ItemOutcome {
    /// Not started.
    case pending
    /// Some sets logged, plan not finished.
    case underway
    /// Finished, and the progress set went up.
    case landed
    /// Finished, and the progress set came in below target. Still finished. Still work.
    case short

    var label: String? {
        switch self {
        case .pending: return nil
        case .underway: return "Underway"
        case .landed: return "Landed"
        case .short: return "Attempted"
        }
    }

    /// Only a landed progress set earns accent colour. `.short` is neutral, never
    /// negative — the point is that it reads as information, not failure.
    var isAccent: Bool {
        if case .landed = self { return true }
        return false
    }
}

/// One exercise the app chose for today, with exactly one set plan.
struct MockPlanItem: Identifiable {
    let id = UUID()
    /// Real `Exercise.id` and `SetPlan.id`, when the plan came from the backend.
    ///
    /// Nil for the mock plans below, which only ever named built-ins and are resolved by
    /// name. Present for generated plans, where resolving by id matters: the catalog we
    /// send includes user-created plans, and nothing stops a user naming one "Standard".
    /// Matching that by name would silently select the built-in instead.
    ///
    /// `var` with a default, not `let`: a `let` carrying an initial value is dropped from
    /// the synthesized memberwise initialiser altogether, which would leave no way to set
    /// these. Defaulted so every mock literal below still compiles untouched.
    var exerciseId: UUID?
    var setPlanId: UUID?
    let exerciseName: String
    let icon: String
    /// `var`, like `setPlanId` above: while a session is live these are merged from the
    /// store on every read (`ProgramMockView.liveItems`), so a plan swapped anywhere —
    /// the Lift tab included — shows up here without rebuilding the item.
    var planName: String
    /// Persisted effort keys, matching `SetPlan.effortSequence` ("easy"... "pr").
    var sequence: [String]
    /// How many sets of the sequence are logged. Drives which tiles read as filled, so
    /// partial progress through a plan is visible without any extra indicator.
    var completedSets: Int = 0
    /// Effort keys actually logged, mirrored from the session store so the tiles show
    /// what happened rather than what was asked for.
    var loggedEfforts: [String] = []
    var outcome: ItemOutcome = .pending
    /// Target before it is done, result after. Never phrased as a miss.
    var detail: String
    /// Why the app picked this lift today, shown when the reasoning is expanded.
    var rationale: String

    var totalSets: Int { sequence.count }
    var isFinished: Bool { completedSets >= totalSets }
}

/// A generated plan for one day.
struct MockDayPlan {
    /// One line of "why this, today" shown under the AI label. Declared first so the
    /// memberwise initialiser reads summary-then-items, matching how the plans below
    /// are written.
    let summary: String
    /// `var` so callers that adjust the plan can copy-and-amend rather than rebuild it from
    /// scratch. Rebuilding is how `noteOmitted` got silently dropped: a new `MockDayPlan(...)`
    /// takes defaults for every field the call site forgets, and the compiler cannot warn.
    var items: [MockPlanItem]
    /// The user wrote a note and it was withheld from the generator. Lives on the plan
    /// rather than widening `SessionDraftService`'s return type: it is a property of the
    /// generated plan, so it rides along everywhere the plan already goes — including into
    /// the store, which is what makes it survive a cold launch.
    var noteOmitted: Bool = false

    var totalSets: Int { items.reduce(0) { $0 + $1.totalSets } }
    var completedSets: Int { items.reduce(0) { $0 + $1.completedSets } }

    var fraction: Double {
        guard totalSets > 0 else { return 0 }
        return Double(completedSets) / Double(totalSets)
    }
}

// MARK: - The fiction

enum ProgramMockData {

    static let standard = ["easy", "easy", "moderate", "moderate", "hard", "pr"]
    static let maintenance = ["moderate", "moderate", "hard"]
    static let deload = ["easy", "easy", "easy"]

    /// Context the user can hand the generator before it picks. Free text sits alongside
    /// these; the chips exist because the common cases are worth one tap.
    /// Kept deliberately mixed. An all-negative list ("sore", "low energy", "short on
    /// time") quietly frames the feature as damage control, when it should be just as
    /// happy to hear that today is a good day.
    /// Hard constraints on the SHAPE of the session, kept apart from the mood/state chips
    /// below. A user picking "2 lifts only" is not describing how they feel, they are
    /// setting a bound the generator must respect.
    ///
    /// The lift-count options carry "only" because they are exclusive claims, not
    /// preferences — "2 lifts only" says two and not three, which is exactly the
    /// distinction `liftCountChips` enforces below.
    static let sessionShapeChips = [
        "1 lift only",
        "2 lifts only",
        "Upper only",
        "Lower only",
        "Go heavy",
        "Light day",
        "No progress sets",
        "Short sets",
    ]

    /// Groups of shape chips where at most one may be selected.
    ///
    /// Each group is one axis, and its members are competing claims about that axis.
    /// Sending two of them would hand the generator a constraint it has to arbitrate,
    /// which is exactly the decision the user was trying to take away from it.
    ///
    /// "Go heavy" and "Light day" are the only true intensity opposites. "No progress sets"
    /// is deliberately NOT in that group: heavy work without spending an attempt is a
    /// coherent ask — near-max exposure, no PR — and it is precisely what Primer is for.
    /// Pairing it with "Light day" is merely redundant rather than contradictory, since
    /// capping effort at moderate already rules attempts out.
    ///
    /// "Short sets" belongs to no group — plan length is independent of both how many lifts
    /// and how hard, which is the whole reason for adding it.
    static let exclusiveChipGroups: [Set<String>] = [
        ["1 lift only", "2 lifts only"],
        ["Upper only", "Lower only"],
        ["Go heavy", "Light day"],
        // The mood chips have opposites too, and they are pure contradictions rather than
        // shades — "short on time" and "extra time today" cannot both be true. Grouping
        // them keeps a nonsense pair out of the payload without the user having to notice.
        // Deliberately NOT grouped: "Legs are sore" and "No squat rack" are facts about
        // today that combine with anything, including each other.
        ["Short on time", "Extra time today"],
        ["Well rested", "Didn't sleep well"],
        ["Feeling strong", "Run down"],
    ]

    /// Kept as its own name because callers ask "did they cap the lift count?" rather than
    /// "which group is this in".
    static let liftCountChips: Set<String> = ["1 lift only", "2 lifts only"]

    static let contextChips = [
        "Short on time",
        "Extra time today",
        "Feeling strong",
        "Run down",
        "Well rested",
        "Didn't sleep well",
        "Legs are sore",
        "No squat rack",
    ]

    /// Cycled, not stepped through — the request has no progress to report, so these
    /// rotate for as long as it takes rather than advancing toward an end. Each one has
    /// to stand on its own when it comes back around, which rules out anything that reads
    /// as a stage ("Almost there…").
    ///
    /// No day count: the window is set by the backend, and a number here would be a second
    /// copy of it that quietly goes stale. It was already wrong — this said "last 14 days"
    /// while the payload carries 30.
    static let generatingSteps = [
        "Reading your recent training…",
        "Checking your estimated 1RMs…",
        "Weighing what's due…",
        "Choosing today's lifts…",
        "Matching set plans…",
    ]

    // MARK: Plans

    /// The default pick: a full lower-and-push day.
    static var defaultPlan: MockDayPlan {
        MockDayPlan(
            summary: "Squats and Bench are both due a progress set, and you have not pulled since Monday.",
            items: [
                MockPlanItem(
                    exerciseName: "Squats", icon: "SquatIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 320 × 3",
                    rationale: "Last progress set landed 8 days ago at 315."
                ),
                MockPlanItem(
                    exerciseName: "Bench Press", icon: "BenchPressIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 250 × 3",
                    rationale: "Two clean sessions at 245. Ready to move up."
                ),
                MockPlanItem(
                    exerciseName: "Barbell Rows", icon: "BarbellRowIcon",
                    planName: "Maintenance", sequence: maintenance,
                    detail: "Volume · 145 × 8",
                    rationale: "Last rowed Monday. Keeping the frequency up."
                ),
            ]
        )
    }

    /// What a revision looks like when the user says their legs are sore: squats drop
    /// out entirely, an upper-body lift takes their place, and the remaining work stays
    /// intact. A revision has to visibly *respond* or the feature reads as a reshuffle.
    static var revisedPlan: MockDayPlan {
        MockDayPlan(
            summary: "Skipping lower body today. Swapped in Overhead Press and kept your pulling volume.",
            items: [
                MockPlanItem(
                    exerciseName: "Bench Press", icon: "BenchPressIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 250 × 3",
                    rationale: "Two clean sessions at 245. Ready to move up."
                ),
                MockPlanItem(
                    exerciseName: "Overhead Press", icon: "OverheadPressIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 150 × 3",
                    rationale: "Longest gap of your five lifts — 11 days."
                ),
                MockPlanItem(
                    exerciseName: "Barbell Rows", icon: "BarbellRowIcon",
                    planName: "Maintenance", sequence: maintenance,
                    detail: "Volume · 145 × 8",
                    rationale: "Last rowed Monday. Keeping the frequency up."
                ),
            ]
        )
    }

    /// A full five-lift day, picked when the user says they are feeling good. Exists
    /// partly to answer a real design question: five names plus the action button is the
    /// widest the Lift tab's session rail will ever have to be.
    static var fullPlan: MockDayPlan {
        MockDayPlan(
            summary: "You said you are feeling good, so this is a full day — all five lifts, with progress attempts on the three that are due.",
            items: [
                MockPlanItem(
                    exerciseName: "Squats", icon: "SquatIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 320 × 3",
                    rationale: "Last progress set landed 8 days ago at 315."
                ),
                MockPlanItem(
                    exerciseName: "Bench Press", icon: "BenchPressIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 250 × 3",
                    rationale: "Two clean sessions at 245. Ready to move up."
                ),
                MockPlanItem(
                    exerciseName: "Deadlifts", icon: "DeadliftIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 410 × 3",
                    rationale: "Recovered — 6 days since the last heavy pull."
                ),
                MockPlanItem(
                    exerciseName: "Barbell Rows", icon: "BarbellRowIcon",
                    planName: "Maintenance", sequence: maintenance,
                    detail: "Volume · 145 × 8",
                    rationale: "Last rowed Monday. Keeping the frequency up."
                ),
                MockPlanItem(
                    exerciseName: "Overhead Press", icon: "OverheadPressIcon",
                    planName: "Maintenance", sequence: maintenance,
                    detail: "Volume · 115 × 8",
                    rationale: "Keeping it ticking over between progress attempts."
                ),
            ]
        )
    }

    /// A pull-led alternative. Exists so Refresh rotates between genuinely different
    /// drafts — if the output looked the same each time, the control would read as broken.
    static var pullFocusPlan: MockDayPlan {
        MockDayPlan(
            summary: "Pulling is the gap this week, so this leads with deadlifts and keeps pressing light.",
            items: [
                MockPlanItem(
                    exerciseName: "Deadlifts", icon: "DeadliftIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 410 × 3",
                    rationale: "Six days since the last heavy pull — fully recovered."
                ),
                MockPlanItem(
                    exerciseName: "Barbell Rows", icon: "BarbellRowIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 190 × 5",
                    rationale: "Row volume trails pressing by two sessions."
                ),
                MockPlanItem(
                    exerciseName: "Overhead Press", icon: "OverheadPressIcon",
                    planName: "Maintenance", sequence: maintenance,
                    detail: "Volume · 115 × 8",
                    rationale: "Keeping it ticking over between progress attempts."
                ),
            ]
        )
    }

    /// The short day, for "short on time" or "low energy". Two lifts, one progress
    /// attempt — a real answer to the constraint rather than the same day compressed.
    static var shortPlan: MockDayPlan {
        MockDayPlan(
            summary: "Trimmed to the two that matter most today. In and out.",
            items: [
                MockPlanItem(
                    exerciseName: "Squats", icon: "SquatIcon",
                    planName: "Standard", sequence: standard,
                    detail: "Progress · 320 × 3",
                    rationale: "The one lift most overdue for an attempt."
                ),
                MockPlanItem(
                    exerciseName: "Bench Press", icon: "BenchPressIcon",
                    planName: "Maintenance", sequence: maintenance,
                    detail: "Volume · 205 × 8",
                    rationale: "Keeps pressing frequency up without the long warm-up."
                ),
            ]
        )
    }

    /// The same default plan part-way through, showing all three outcome states at once:
    /// a landed progress set, one that came in under target, and one not yet started.
    static var inProgressPlan: MockDayPlan {
        MockDayPlan(
            summary: "Squats and Bench are both due a progress set, and you have not pulled since Monday.",
            items: [
                MockPlanItem(
                    exerciseName: "Squats", icon: "SquatIcon",
                    planName: "Standard", sequence: standard,
                    completedSets: 6, outcome: .landed,
                    detail: "Landed · 320 × 3",
                    rationale: "Last progress set landed 8 days ago at 315."
                ),
                MockPlanItem(
                    exerciseName: "Bench Press", icon: "BenchPressIcon",
                    planName: "Standard", sequence: standard,
                    completedSets: 6, outcome: .short,
                    detail: "Logged · 250 × 2, target was 3",
                    rationale: "Two clean sessions at 245. Ready to move up."
                ),
                MockPlanItem(
                    exerciseName: "Barbell Rows", icon: "BarbellRowIcon",
                    planName: "Maintenance", sequence: maintenance,
                    completedSets: 1, outcome: .underway,
                    detail: "Volume · 145 × 8",
                    rationale: "Last rowed Monday. Keeping the frequency up."
                ),
            ]
        )
    }

    // MARK: Standing context

    /// "Thursday, Aug 13"
    static var todayLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
}
