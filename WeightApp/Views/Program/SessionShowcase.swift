//
//  SessionShowcase.swift
//  WeightApp
//
//  A hand-authored Smart Session used for App Store screenshots.
//
//  Nothing here is generated and nothing here is read from the account. Enabling
//  `ShowcaseSessionOverride` in the Developer section makes Start Session return this
//  plan — and the context that supposedly produced it — regardless of what the user has
//  actually logged. That independence is the whole point: a screenshot has to show the
//  feature at its most legible, and a real account's history will not oblige on demand.
//
//  Distinct from `ProgramMockData`, which exists to make hard-to-reach UI states testable
//  and deliberately rotates between outcomes. This is one fixed answer, chosen to be
//  representative, and it does not vary between taps — a screenshot session that changed
//  under you would be useless.
//
//  The fiction has to hold together under inspection. Someone reading the screenshot sees
//  the context and the plan side by side, so every clause of the plan must trace back to
//  something the user said: "Short on time" is why three of the five lifts are there at all,
//  "No squat rack" is why Squats specifically is one of the two that sat out, and the note's
//  cranky shoulder is why Overhead Press is on a deload rather than simply absent. Read in
//  that order the card is cause, reasoning, effect — a plausible session that ignored the
//  context would advertise the opposite of the feature.
//

import Foundation

enum SessionShowcase {

    /// The context the screenshot presents as the user's own.
    ///
    /// Seeded into the view's live `context` at generation time rather than rendered
    /// separately, so the recap under the plan and the Revise sheet both show it without
    /// either one needing to know this exists.
    ///
    /// A CONSTRAINT, deliberately. "Extra time today / feeling strong" produces the full
    /// five lifts, which is the least impressive thing this feature does — it looks like a
    /// list, not a decision. Something has to be given up before curation is visible, so
    /// the staged context takes time away and names a sore joint.
    ///
    /// The note is short enough to render on one line uncut, and that is a MEASURED claim, not
    /// an intention. The recap clamps the quote to one line, and the row gives it
    /// `cardWidth - 71` (card padding, panel padding, the gap and the chevron) — 257pt on the
    /// narrowest supported device. At `.caption` italic:
    ///
    ///     "About 45 minutes. Shoulder's still a little cranky."  282.3pt  -> truncated
    ///     "About 45 minutes. Shoulder's still cranky."           244.3pt  -> fits
    ///
    /// The first version shipped and was cut to "…still a lit…" on the real card, not just in
    /// the export. This is the card's best evidence — the one part a store visitor can see is
    /// not canned — and an ellipsis throws that away at exactly the size where it has to land
    /// in a glance. Re-measure before lengthening it.
    static let context = DraftContext(
        chips: ["Short on time", "No squat rack"],
        note: "I only have 45 minutes. Shoulder's still cranky."
    )

    /// Three lifts, ten sets.
    ///
    /// Three, not five: the two ABSENT lifts are the feature. A five-lift card reads as a
    /// generic prescription — everything you own, in order — where three reads as a choice,
    /// and the summary can name what was dropped and why. It also leaves vertical room, so
    /// the card fills the frame with Start Lifting still in it instead of cramming.
    ///
    /// Plan names are the plain-English ones on purpose. Openers, Primer and Compact
    /// Standard are insider vocabulary that a store visitor has to decode; "Quick Attempt"
    /// and "Deload" parse instantly, and "Deload · Overhead Press" is what makes the summary's
    /// "while the shoulder settles" visibly true rather than merely claimed. That pairing has
    /// to stay in frame together or the clause stops being evidence.
    ///
    /// Bench is the star row: four tiles ending in the amber progress square, carrying the
    /// one rationale that shows the generator reasoning about a specific lift's history. One
    /// row of that is worth more than five rows of names.
    static var plan: MockDayPlan {
        let built: [MockPlanItem] = [
                item(
                    "Deadlifts",
                    // Openers, not Standard. Standard ends in a progress set, which drew a
                    // SECOND amber square on a card whose summary says "Bench gets the
                    // attempt" — singular. Openers closes on near-max instead, so the one
                    // amber square left on the card sits on the one lift the copy claims
                    // attempts, and the brand colour marks the payoff rather than competing
                    // with itself. Its three sets also suit the stated 45 minutes.
                    plan: SetPlan.openersId,
                    rationale: "Heaviest work first, while you're fresh."
                ),
                item(
                    "Bench Press",
                    plan: SetPlan.quickAttemptId,
                    rationale: "Two clean sessions at 245 — ready to move up."
                ),
                item(
                    "Overhead Press",
                    plan: SetPlan.deloadId,
                    rationale: "Kept easy until the shoulder's happy."
                ),
        ].compactMap { $0 }

        // Written to answer the context above it, clause by clause: "Short on time" and "No
        // squat rack" are the two chips, and they are what put Squats and Rows on the bench —
        // naming the cause is what makes the absence read as a decision rather than an omission.
        // The shoulder closes it because the note raised it.
        //
        // Second person throughout, matching the app's voice elsewhere ("Your next recommended
        // focus"), so it reads as a coach talking rather than a summary being printed.
        //
        // Counts stay derived from the items so they cannot disagree with the squares below.
        // No minutes: nothing in the API returns a duration and the generator is never asked to
        // reason about one, so a sample claiming "45 minutes is about 10 sets" was advertising
        // arithmetic the product does not do. The set count is different — it is genuinely the
        // sum of the chosen plans, and naming it tells a first-time reader the squares ARE sets.
        let totalSets = built.reduce(0) { $0 + $1.sequence.count }
        let summary = "You're short on time and there's no rack, so Squats and Rows wait for "
            + "next time. That leaves \(built.count) lifts and \(totalSets) sets — the heavy "
            + "pulls while you're fresh, then something easy on that shoulder."
        return MockDayPlan(summary: summary, items: built)
    }

    /// Resolved from the same two tables the real generator resolves from, never written
    /// out by hand.
    ///
    /// `TrendsCalculator.fundamentalExercises` supplies the real `Exercise.id` and icon,
    /// and `SetPlan.builtInPlans` the real plan id and effort sequence. That is what makes
    /// the showcase session a genuinely working one — the Lift tab rail, the set-plan
    /// catalog and plan swapping all key off those ids — so the screenshots can be taken
    /// by driving the app normally rather than by posing a dead screen.
    ///
    /// Optional rather than force-unwrapped: both lookups are against static tables that
    /// certainly contain these names today, but a rename should drop one lift from a
    /// screenshot, not crash the tab.
    private static func item(_ name: String, plan planId: UUID, rationale: String) -> MockPlanItem? {
        guard let fundamental = TrendsCalculator.fundamentalExercises.first(where: { $0.name == name }),
              let def = SetPlan.builtInPlans.first(where: { $0.id == planId })
        else { return nil }

        return MockPlanItem(
            exerciseId: fundamental.id,
            setPlanId: def.id,
            exerciseName: fundamental.name,
            icon: fundamental.icon,
            planName: def.name,
            sequence: def.sequence,
            // The same function the live path uses, so the showcase cannot describe a
            // plan differently from how a generated one would.
            detail: LiveSessionDraftService.detail(for: def.sequence),
            rationale: rationale
        )
    }
}

// MARK: - Service

/// Returns `SessionShowcase.plan`, ignoring both the context and the catalog it is handed.
///
/// Ignoring the catalog is what keeps the screenshots reproducible on any account: the real
/// path resolves sequences out of the user's own set plans, so a demo device with an edited
/// or partially-synced catalog would quietly produce a different-looking session.
final class ShowcaseSessionDraftService: SessionDraftService {
    static let shared = ShowcaseSessionDraftService()

    private init() {}

    func generateDraft(context: DraftContext, catalog: [SetPlanCatalogEntry]) async throws -> MockDayPlan {
        // Long enough to photograph the loading state, which cycles its captions and is
        // itself worth a screenshot. Fixed rather than randomised — everything else here
        // is reproducible and the wait should be too.
        try? await Task.sleep(for: .seconds(2.2))
        return SessionShowcase.plan
    }
}
