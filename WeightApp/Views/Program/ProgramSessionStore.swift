//
//  ProgramSessionStore.swift
//  WeightApp
//
//  The live session.
//
//  Deliberately NOT a SwiftData model, but no longer memory-only either: the whole store
//  is snapshotted to UserDefaults as JSON on every mutation and restored on launch.
//
//  That middle ground is the right weight for what this is. A session is ephemeral by
//  construction — it dissolves if idle four hours, and never outlives its own day by much
//  — so it has none of the things SwiftData exists to provide. There is nothing to query,
//  nothing to relate, nothing to sync to the backend, and a schema migration for an object
//  that deletes itself the same afternoon is cost without benefit. One small JSON blob,
//  rewritten a few times per session, buys the entire behaviour.
//
//  If a session ever needs to be readable across devices, or queried as history, that is
//  the point to promote it to a real model — and `Item` is already `Codable`, so the shape
//  is settled by then.
//
//  Same singleton shape as `TutorialPresenter` and `NotificationRouter`, which exist for
//  the same reason — a child view needs to drive state the whole app reads.
//
//  This is the one place where the mock touches reality: the generated plan carries
//  exercise and plan *names*, but the Lift tab needs real `Exercise` and `SetPlan` UUIDs
//  to select anything. Resolution happens once, in `start(from:)`.
//

import Foundation
import Observation
// `SyncLogger`'s categories are `os.Logger`, whose interpolation only resolves where
// `os` is imported.
import os

@Observable
final class ProgramSessionStore {
    static let shared = ProgramSessionStore()

    /// How long a session may go without a logged set before it is silently filed.
    /// Kept aggressive on purpose: a false positive costs one tap on the receipt's
    /// Continue, which restores everything without a network call.
    static let staleAfter: TimeInterval = 4 * 60 * 60

    struct Item: Identifiable, Codable {
        let id = UUID()
        let exerciseId: UUID
        let exerciseName: String
        let shortName: String
        let icon: String
        // `var` so the plan can be swapped during Planning without rebuilding the item and
        // losing its logged progress. Fixed once the session is underway — `changeSetPlan`
        // guards on the phase, not on these.
        var setPlanId: UUID
        var planName: String
        /// Effort keys, for the rail's tiles and the completion receipt.
        var sequence: [String]

        /// The generator's reasoning and target line for this lift.
        ///
        /// Held here rather than only in the view's copy of the plan, because the view's
        /// copy is `@State` and dies with the process. Without these the session survived
        /// a force quit but the card that draws it could not be rebuilt, and the Session
        /// tab came back blank.
        var rationale: String = ""
        var detail: String = ""

        /// Effort keys of the sets actually logged, in order. A filled tile is drawn in
        /// the effort that HAPPENED, not the one the plan asked for — the plan's shape
        /// stays readable in the tiles still ahead, and a session that deviates shows it
        /// honestly rather than pretending it complied.
        var loggedEfforts: [String] = []
        /// Sets logged against this exercise since the session began.
        var loggedSets: Int = 0
        /// Count credited at activation. New work is `loggedSets > baselineSets`.
        var baselineSets: Int = 0
        var completedAt: Date?

        var plannedSetCount: Int { sequence.count }
        var isComplete: Bool { completedAt != nil }

        /// `id` is deliberately absent.
        ///
        /// It exists only for `Identifiable`, so SwiftUI can diff a `ForEach` within one
        /// launch — `exerciseId` is the real key, and it is the one every lookup uses.
        /// Synthesised Codable would have silently skipped it anyway (a `let` with an
        /// initial value cannot be overwritten by a decoder), so this states the intent
        /// instead of leaving a compiler warning to explain it.
        enum CodingKeys: String, CodingKey {
            case exerciseId, exerciseName, shortName, icon, setPlanId, planName
            case sequence, rationale, detail
            case loggedEfforts, loggedSets, baselineSets, completedAt
        }
    }

    /// Presentation phase of a live session. Purely a UI-constraint gate: identity,
    /// crediting, lifecycle and end paths are identical in both. Planning offers
    /// negotiation (Revise, Refresh, Discard); Underway withdraws it.
    enum ActivePhase: String, Codable {
        case planning, underway
    }

    /// How the last session ended, for the Program tab to react to after teardown.
    enum Outcome: String, Codable {
        case completed
        case ended
    }

    private(set) var items: [Item] = []
    /// The generator's one-or-two-sentence "why today looks like this". Same reason as
    /// `Item.rationale`: the card cannot be redrawn after a cold launch without it.
    private(set) var summary: String = ""
    /// The user's note was withheld from the generator. Persisted with everything else, so
    /// the notice survives a cold launch alongside the session it belongs to.
    private(set) var noteOmitted: Bool = false
    /// The user changed the generated session by hand — removed a lift, added one, or
    /// swapped a plan. Surfaced so the card does not silently present an edited session as
    /// though the generator produced it.
    private(set) var wasEdited: Bool = false

    /// Lifts whose completion has already been celebrated.
    ///
    /// Completion is not latching — delete a set and a lift un-completes, re-log it and it
    /// completes again — so without this the popup would replay every time. Persisted with
    /// the session, so a force quit does not replay one on relaunch either.
    private(set) var celebratedLiftIds: Set<UUID> = []

    /// Consume-and-clear, the same shape as `pendingSelection`: the Lift tab may not be on
    /// screen at the moment the set is logged, and the popup has to wait for the overlays
    /// `logSet()` already raised.
    var pendingLiftCelebration: UUID?
    var pendingSessionCelebration = false
    private(set) var activePhase: ActivePhase = .planning
    /// When the session went Underway — the Start Lifting tap or the first credited set,
    /// whichever fired. Shown as "Started 10:02 AM".
    private(set) var startedLiftingAt: Date?
    private(set) var startedAt: Date?
    /// The local calendar day the session is filed under.
    ///
    /// Sets belong to a session by MEMBERSHIP, not by date: a session owns whatever was
    /// logged while it was active, so a 12:04am set still counts toward a session that
    /// began at 11:30pm. The calendar is only where the receipt gets filed. The residue
    /// — Today's Sets browsing shows that set on the 15th while its receipt sits on the
    /// 14th — is a deliberate absorb, and far milder than a session that dies or forgets
    /// itself at midnight.
    private(set) var startedOnDay: Date?

    /// Day the last receipt belongs to, so "already trained today" survives teardown.
    private(set) var receiptDay: Date?
    private(set) var lastOutcome: Outcome?
    /// Snapshot of the items as they stood at `finish()`, for the receipt.
    private(set) var receipt: [Item] = []

    /// An exercise the Lift tab should select. Set when a session starts, because the
    /// tab may not exist yet at that moment — the user could be on the Program tab with
    /// CheckInView never having been created. Same consume-and-clear shape as
    /// `NotificationRouter.pendingDestination`, which exists for the same reason.
    var pendingSelection: UUID?

    /// Set by the Lift tab's Start Session button. The Session tab consumes it on appear
    /// and begins drafting immediately, so that button lands the user on the loading
    /// state rather than on another button to press.
    var pendingAutoStart = false
    /// Last time a set was logged against *a session exercise*. Off-plan work does not
    /// keep a session warm, which is what makes the stale check meaningful.
    private(set) var lastActivityAt: Date?

    private init() {
        restore()
    }

    // MARK: - Persistence

    private static let storageKey = "program_session_store_v1"

    /// Everything worth surviving a launch.
    ///
    /// `pendingSelection` and `pendingAutoStart` are deliberately absent. They are
    /// navigation intents — "the Lift tab should jump to this exercise", "the Session tab
    /// should start drafting" — that were true at the moment they were set. Restoring one
    /// would hijack the first screen the user sees on a cold launch with an instruction
    /// they gave hours ago.
    private struct Snapshot: Codable {
        var items: [Item]
        var summary: String = ""
        var noteOmitted: Bool = false
        var wasEdited: Bool = false
        var celebratedLiftIds: [UUID] = []
        var activePhase: ActivePhase
        var startedLiftingAt: Date?
        var startedAt: Date?
        var startedOnDay: Date?
        var receiptDay: Date?
        var lastOutcome: Outcome?
        var receipt: [Item]
        var lastActivityAt: Date?
    }

    /// Called at the end of every mutation. Cheap enough to be unconditional: the blob is
    /// a few hundred bytes and a session mutates on the order of tens of times, so there
    /// is nothing here worth the bugs that a "save later" path would introduce.
    private func persist() {
        let snapshot = Snapshot(
            items: items,
            summary: summary,
            noteOmitted: noteOmitted,
            wasEdited: wasEdited,
            celebratedLiftIds: Array(celebratedLiftIds),
            activePhase: activePhase,
            startedLiftingAt: startedLiftingAt,
            startedAt: startedAt,
            startedOnDay: startedOnDay,
            receiptDay: receiptDay,
            lastOutcome: lastOutcome,
            receipt: receipt,
            lastActivityAt: lastActivityAt
        )
        do {
            let data = try JSONEncoder().encode(snapshot)
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        } catch {
            // A session that fails to save still works for this launch. Losing it on the
            // next one is the same behaviour this store had before it persisted at all,
            // so there is nothing to escalate to the user.
            SyncLogger.api.error("Failed to persist session: \(error)")
        }
    }

    private func restore() {
        guard let data = UserDefaults.standard.data(forKey: Self.storageKey) else { return }

        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            // Unreadable means a shape change across an app update. Drop it rather than
            // limp along with a half-restored session.
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
            return
        }

        items = snapshot.items
        summary = snapshot.summary
        noteOmitted = snapshot.noteOmitted
        wasEdited = snapshot.wasEdited
        celebratedLiftIds = Set(snapshot.celebratedLiftIds)
        activePhase = snapshot.activePhase
        startedLiftingAt = snapshot.startedLiftingAt
        startedAt = snapshot.startedAt
        startedOnDay = snapshot.startedOnDay
        receiptDay = snapshot.receiptDay
        lastOutcome = snapshot.lastOutcome
        receipt = snapshot.receipt
        lastActivityAt = snapshot.lastActivityAt

        pruneAfterRestore()
    }

    /// Apply the session's own lifecycle rules to whatever came back off disk.
    ///
    /// Necessary because time passes while the app is closed, and it can pass in
    /// quantities a running app never sees — the existing `finalizeIfIdle4h` and
    /// `dissolveIfSetlessAndRolledOver` run on tab appearance, which is too late: a
    /// week-old session would be live and observable before any view got a chance to
    /// clean it up.
    private func pruneAfterRestore() {
        // Setless and no longer today: it never happened. Same rule as the rollover
        // dissolve, and it must run first — a session with no sets should leave no
        // receipt, no matter how long ago it was abandoned.
        if isActive, !hasLoggedSets, let day = startedOnDay,
           !Calendar.current.isDate(day, inSameDayAs: Date()) {
            clear()
        } else if isActive, isIdle4h {
            // Work happened, then the app closed for hours. That is a finished session,
            // and `finish()` files it as one.
            finish()
        }

        // A receipt is only ever offered for the current day, so one from an earlier day
        // is dead weight — and left in place it would fire the Session tab's
        // outcome-driven transition into a receipt card for a day that is over.
        if let day = receiptDay, !Calendar.current.isDate(day, inSameDayAs: Date()) {
            receipt = []
            receiptDay = nil
            lastOutcome = nil
        }

        persist()
    }

    // MARK: - Lifecycle

    /// Resolve the generated plan's names into real UUIDs and go live.
    ///
    /// `compactMap` rather than a force: if a name ever fails to resolve the item is
    /// dropped and the session runs shorter, instead of trapping in front of the user.
    func start(from plan: MockDayPlan) {
        items = plan.items.compactMap { Self.resolve($0) }
        summary = plan.summary
        noteOmitted = plan.noteOmitted
        // Regenerating replaces the plan wholesale, so it is the generator's again.
        wasEdited = false
        startedAt = Date()
        startedOnDay = Calendar.current.startOfDay(for: Date())
        activePhase = .planning
        startedLiftingAt = nil

        // The first lift that still needs work, NOT simply the first lift — same rule
        // the rail's Next and the Session tab's Back to Lifting use. Falls back to the
        // first item only when everything is somehow already done.
        pendingSelection = (nextIncomplete ?? items.first)?.exerciseId
        persist()
    }

    /// One generated item → one live item, or nil if its exercise cannot be resolved.
    ///
    /// Split out of `start(from:)` and written as plain statements rather than chained
    /// optionals: as one expression inside the `compactMap` closure this exceeded the
    /// type checker's budget outright.
    private static func resolve(_ planItem: MockPlanItem) -> Item? {
        guard let fundamental = resolveExercise(planItem) else { return nil }
        let plan = resolveSetPlan(planItem)

        // Carry the draft's crediting across. The draft already folded in today's
        // logged sets, so starting the store blank would throw that away and make
        // the rail re-ask for work the user can see is done — until the Lift tab's
        // sync happened to run and silently corrected it.
        let alreadyLogged = planItem.completedSets
        let isDone = alreadyLogged >= planItem.sequence.count

        return Item(
            exerciseId: fundamental.id,
            exerciseName: fundamental.name,
            shortName: shortName(for: fundamental.name),
            icon: fundamental.icon,
            setPlanId: plan.id,
            planName: plan.name,
            sequence: planItem.sequence,
            rationale: planItem.rationale,
            detail: planItem.detail,
            loggedEfforts: Array(planItem.sequence.prefix(alreadyLogged)),
            loggedSets: alreadyLogged,
            baselineSets: alreadyLogged,
            completedAt: isDone ? Date() : nil
        )
    }

    /// Id first, name second. A generated plan carries the real ids the backend echoed
    /// back, which are unambiguous; the mock plans carry none and match on name, which is
    /// all they ever had.
    private static func resolveExercise(_ planItem: MockPlanItem) -> (id: UUID, name: String, icon: String)? {
        let all = TrendsCalculator.fundamentalExercises
        if let id = planItem.exerciseId, let match = all.first(where: { $0.id == id }) {
            return (match.id, match.name, match.icon)
        }
        if let match = all.first(where: { $0.name == planItem.exerciseName }) {
            return (match.id, match.name, match.icon)
        }
        return nil
    }

    /// A generated plan may name a plan the user wrote, which is not in `builtInPlans` at
    /// all. Falls back to the item's own id and name rather than dropping the lift — a
    /// custom plan is a legitimate answer, and silently shortening the session is worse.
    private static func resolveSetPlan(_ planItem: MockPlanItem) -> (id: UUID, name: String) {
        if let id = planItem.setPlanId {
            if let builtIn = SetPlan.builtInPlans.first(where: { $0.id == id }) {
                return (builtIn.id, builtIn.name)
            }
            return (id, planItem.planName)
        }
        if let builtIn = SetPlan.builtInPlans.first(where: { $0.name == planItem.planName }) {
            return (builtIn.id, builtIn.name)
        }
        return (SetPlan.standardId, planItem.planName)
    }

    /// Swap the plan without touching the session's identity.
    ///
    /// Revise and Refresh produce a new plan for the *same* session, so `startedAt`,
    /// `startedOnDay` and `lastActivityAt` all survive — re-drafting must not re-file the
    /// session under a new date or restart its idle clock.
    func replacePlan(from plan: MockDayPlan) {
        let preservedStart = startedAt
        let preservedDay = startedOnDay
        let preservedActivity = lastActivityAt
        let preservedPhase = activePhase
        let preservedLiftingAt = startedLiftingAt

        start(from: plan)

        startedAt = preservedStart ?? startedAt
        startedOnDay = preservedDay ?? startedOnDay
        lastActivityAt = preservedActivity
        activePhase = preservedPhase
        startedLiftingAt = preservedLiftingAt
        persist()
    }

    /// Bring a finished session back. Restores from the receipt — never regenerates, so
    /// this costs no API call.
    func resume() {
        guard !receipt.isEmpty, let day = receiptDay else { return }

        items = receipt
        startedAt = Date()
        startedOnDay = day
        activePhase = .underway
        startedLiftingAt = Date()
        // MUST be stamped. A finalized session is by definition more than four hours past
        // its last set, so restoring the original timestamp would let `finalizeIfIdle4h`
        // close it again on the very next appearance and Continue would look inert.
        lastActivityAt = Date()
        pendingSelection = (nextIncomplete ?? items.first)?.exerciseId

        receipt = []
        receiptDay = nil
        lastOutcome = nil
        persist()
    }

    /// All planned lifts done. Snapshots the items so the Program tab can draw a receipt
    /// after the live session is gone.
    func finish() {
        receipt = items
        receiptDay = startedOnDay
        lastOutcome = .completed
        clear()
        persist()
    }

    /// Left early. Identical teardown to `finish()` minus the receipt — deliberately no
    /// separate "incomplete" state, because ending early is not a failure mode.
    func end() {
        receipt = []
        lastOutcome = .ended
        clear()
        persist()
    }

    /// Consumed by the Program tab once it has shown the outcome.
    func clearOutcome() {
        lastOutcome = nil
        receipt = []
        receiptDay = nil
        persist()
    }

    /// A finished session already filed for today. Read-only by definition — the receipt
    /// records what the session *was*. Logging more sets afterwards is always allowed;
    /// they are simply ordinary sets rather than session sets.
    var hasReceiptForToday: Bool {
        guard let day = receiptDay else { return false }
        return Calendar.current.isDate(day, inSameDayAs: Date())
    }

    /// True while the app should stop recommending a different lift — the session, or
    /// today's receipt, is already the answer to "what should I do".
    var ownsTodaysRecommendation: Bool { isActive || hasReceiptForToday }

    /// Wipe everything and forget the persisted snapshot. Call on logout / account switch.
    ///
    /// Harder than `clear()`, which deliberately preserves the receipt, `activePhase` and the
    /// auto-start flag so the Session tab can transition smoothly between one session and the
    /// next. None of that belongs to the next ACCOUNT, so this drops all of it and removes the
    /// UserDefaults key rather than persisting an empty snapshot.
    ///
    /// Its absence was a real bug: the store snapshots to UserDefaults on every mutation and
    /// restores on launch, and nothing cleared it at logout — so signing into a different, free
    /// account inherited the previous one's live session. The Session tab looked correct because
    /// it gates on premium; the Lift tab showed the session banner because it only gated on
    /// `isActive`.
    func clearOnLogout() {
        items = []
        summary = ""
        noteOmitted = false
        editSnapshot = nil
        wasEdited = false
        celebratedLiftIds = []
        pendingLiftCelebration = nil
        pendingSessionCelebration = false
        activePhase = .planning
        startedLiftingAt = nil
        startedAt = nil
        startedOnDay = nil
        lastActivityAt = nil
        pendingSelection = nil
        pendingAutoStart = false
        receipt = []
        receiptDay = nil
        lastOutcome = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    private func clear() {
        items = []
        summary = ""
        noteOmitted = false
        // Drop any in-flight undo buffer with the session it belonged to. Left behind, it
        // would make `beginEditing()` a no-op on the NEXT session (it refuses to overwrite
        // an existing snapshot), and Cancel would then revert to a session that is gone.
        editSnapshot = nil
        wasEdited = false
        celebratedLiftIds = []
        pendingLiftCelebration = nil
        pendingSessionCelebration = false
        // `activePhase` is deliberately NOT reset here. Every entry point sets it
        // explicitly — `start(from:)` to `.planning`, `resume()` to `.underway` — so
        // resetting bought nothing, and it actively hurt: a cleared store briefly claiming
        // `.planning` is what let the planning card flash between ending a session and the
        // receipt. Leaving the last value means a stray frame shows what was already there.
        startedLiftingAt = nil
        startedAt = nil
        startedOnDay = nil
        lastActivityAt = nil
        pendingSelection = nil
        persist()
    }

    /// Close out a session nobody is using any more.
    ///
    /// Real sessions run 30–120 minutes; four silent hours means it is over and the user
    /// simply never said so. Finalised into a receipt rather than discarded — the work
    /// happened, so it deserves a record — and silently, because a prompt about a workout
    /// you left hours ago is noise.
    ///
    /// This, not a midnight cutoff, is what bounds a session's life. It also makes
    /// midnight-crossing sessions nearly extinct without ever cutting someone off
    /// mid-set at 11:59pm.
    func finalizeIfIdle4h() {
        guard isActive, isIdle4h else { return }
        finish()
    }

    /// A session that never saw a set leaves no trace. Dissolved silently at rollover —
    /// no receipt, no outcome, nothing to dismiss the next morning.
    ///
    /// Strictly setless: a session WITH sets survives the boundary and is closed later by
    /// the idle finalizer, so the 11:30pm starter logging at 12:04am is never cut off.
    func dissolveIfSetlessAndRolledOver() {
        guard isActive, !hasLoggedSets, let day = startedOnDay,
              !Calendar.current.isDate(day, inSameDayAs: Date()) else { return }
        clear()
    }

    /// Clear an item's logged work when the caller KNOWS the sets are gone.
    ///
    /// `recordSetCount` deliberately ignores a zero that contradicts existing credit, so
    /// this is the explicit path for the one case where zero is real: every set for that
    /// lift was deleted. Separated because "I counted zero" and "I know there are none"
    /// are different claims, and only the second should be able to erase progress.
    func clearLoggedSets(forExerciseId exerciseId: UUID) {
        guard let index = items.firstIndex(where: { $0.exerciseId == exerciseId }),
              items[index].loggedSets > 0 else { return }

        items[index].loggedSets = 0
        items[index].loggedEfforts = []
        items[index].completedAt = nil
        persist()
    }

    /// Rebuild the plan card from persisted state.
    ///
    /// The Session tab holds the generated plan in `@State`, which does not survive the
    /// process. On a cold launch into a live session the store has everything — items,
    /// their reasoning, the summary — so the view asks for this instead of showing an
    /// empty card or, worse, regenerating and spending a model call to recover something
    /// it already had.
    var restoredPlan: MockDayPlan? {
        guard isActive, !items.isEmpty else { return nil }
        return MockDayPlan(
            summary: summary,
            items: items.map { item in
                MockPlanItem(
                    exerciseId: item.exerciseId,
                    setPlanId: item.setPlanId,
                    exerciseName: item.exerciseName,
                    icon: item.icon,
                    planName: item.planName,
                    sequence: item.sequence,
                    completedSets: item.loggedSets,
                    loggedEfforts: item.loggedEfforts,
                    outcome: item.isComplete ? .landed : (item.loggedSets > 0 ? .underway : .pending),
                    detail: item.detail,
                    rationale: item.rationale
                )
            },
            noteOmitted: noteOmitted
        )
    }

    // MARK: - Editing (Planning only)

    /// The item list as it stood when editing began, held so Cancel has something to
    /// restore. Transient by design — it is not part of `Snapshot`, so a force quit
    /// mid-edit keeps whatever was applied rather than resurrecting a half-finished undo.
    private var editSnapshot: (items: [Item], wasEdited: Bool)?

    /// Open an editing session. Idempotent, so re-entering does not overwrite the
    /// original with an already-edited state.
    func beginEditing() {
        guard activePhase == .planning, editSnapshot == nil else { return }
        editSnapshot = (items, wasEdited)
    }

    /// Throw the changes away and put the session back as it was.
    func cancelEditing() {
        guard let snapshot = editSnapshot else { return }
        items = snapshot.items
        wasEdited = snapshot.wasEdited
        editSnapshot = nil
        persist()
    }

    /// Keep the changes. Only drops the undo buffer — the edits were applied as they were
    /// made, which is what let the card show them live while deciding.
    func commitEditing() {
        editSnapshot = nil
        persist()
    }

    // The session is negotiable until it is underway. These mirror that rule: every one
    // guards on `.planning`, so nothing here can rewrite a session already in progress.
    // That is the same boundary Revise and Refresh sit behind — the difference is that
    // these change one thing instead of regenerating the lot, and cost no model call.

    /// Drop a lift from the session.
    ///
    /// Refuses to remove the last one: an empty session is not a state the Session tab can
    /// render, and "I want none of this" is what Discard is for.
    @discardableResult
    func removeLift(exerciseId: UUID) -> Bool {
        guard activePhase == .planning, items.count > 1,
              let index = items.firstIndex(where: { $0.exerciseId == exerciseId }) else { return false }

        items.remove(at: index)
        wasEdited = true
        // The Lift tab may be holding a request to select the lift that just disappeared.
        if pendingSelection == exerciseId {
            pendingSelection = (nextIncomplete ?? items.first)?.exerciseId
        }
        persist()
        return true
    }

    /// Add a fundamental the generator left out.
    ///
    /// `creditedSets` is what the user has already logged for it today, so a lift added
    /// after the fact does not appear untouched when it is not.
    @discardableResult
    func addLift(
        exerciseId: UUID,
        exerciseName: String,
        icon: String,
        setPlanId: UUID,
        planName: String,
        sequence: [String],
        creditedSets: Int
    ) -> Bool {
        guard activePhase == .planning,
              !items.contains(where: { $0.exerciseId == exerciseId }) else { return false }

        let credited = min(creditedSets, sequence.count)
        items.append(Item(
            exerciseId: exerciseId,
            exerciseName: exerciseName,
            shortName: Self.shortName(for: exerciseName),
            icon: icon,
            setPlanId: setPlanId,
            planName: planName,
            sequence: sequence,
            rationale: "Added by you",
            detail: LiveSessionDraftService.detail(for: sequence),
            loggedEfforts: Array(sequence.prefix(credited)),
            loggedSets: credited,
            // Credited at activation, so pre-existing work does not read as new work and
            // flip the session Underway on its own.
            baselineSets: credited,
            completedAt: credited >= sequence.count ? Date() : nil
        ))
        wasEdited = true
        persist()
        return true
    }

    /// Swap the set plan for a lift already in the session.
    ///
    /// ALLOWED IN BOTH PHASES, unlike `addLift`/`removeLift` above. Those change what the
    /// session IS, which is a negotiation and belongs to Planning. This changes how one
    /// lift is run, which is a decision you make standing at the rack — and the Lift tab's
    /// plan chip is a live entry point for exactly that, mid-session.
    ///
    /// The `.planning` guard that used to be here made that chip silently do nothing: the
    /// catalog opened, a tap registered, and the call returned false because the session
    /// was Underway.
    @discardableResult
    func changeSetPlan(
        forExerciseId exerciseId: UUID,
        setPlanId: UUID,
        planName: String,
        sequence: [String]
    ) -> Bool {
        guard let index = items.firstIndex(where: { $0.exerciseId == exerciseId }) else { return false }

        // Nothing to do if the user picked the plan it already has — re-picking the same
        // option should not mark the session edited or discard a valid justification.
        guard items[index].setPlanId != setPlanId else { return false }

        items[index].setPlanId = setPlanId
        items[index].planName = planName
        items[index].sequence = sequence
        // The rationale justified this lift ON THIS PLAN — "two clean sessions at 245,
        // ready to move up" is an argument for a plan with a progress set in it. Once the
        // plan is swapped that reasoning may no longer hold, and leaving it would present
        // the generator's argument as though it endorsed a choice it never made.
        //
        // Replaced rather than blanked: an empty rationale reads as a missing value, where
        // this states plainly who made the call.
        items[index].rationale = "Plan changed by you"
        // Recomputed, not carried over. `detail` describes the PLAN ("Progress · 6 sets"),
        // so leaving the old string would have the row describing a plan the lift no longer
        // has — the wrong set count, or a progress target on a plan with no attempt in it.
        items[index].detail = LiveSessionDraftService.detail(for: sequence)
        // Logged work is kept — the sets happened regardless of which plan is on the rail —
        // but completion is re-judged, since the new plan may ask for more or fewer sets.
        updateCompletion(at: index)
        wasEdited = true
        persist()
        return true
    }

    /// Fundamentals not currently in the session, in canonical order.
    var availableLifts: [TrendsCalculator.FundamentalExercise] {
        let present = Set(items.map(\.exerciseId))
        return TrendsCalculator.fundamentalExercises.filter { !present.contains($0.id) }
    }

    // MARK: - Progress

    /// Record how many sets exist for an exercise on the session's day.
    ///
    /// The count passed in is AUTHORITATIVE — it is recomputed from the live query by the
    /// caller, so deleting a set reopens a lift and empties its tiles, exactly as adding
    /// one fills them. The rail reflects what has actually been performed, not the
    /// high-water mark of what once was.
    func recordSetCount(_ count: Int, forExerciseId exerciseId: UUID) {
        guard let index = items.firstIndex(where: { $0.exerciseId == exerciseId }) else { return }

        let previous = items[index].loggedSets

        // AUTHORITATIVE, not monotonic — deleting a set has to empty tiles, so this cannot
        // be `max(loggedSets, count)` as it once was.
        //
        // BUT it must not run ahead of the store it is reconciling against. `recordEffort`
        // credits a set the instant it is logged, while this recounts from a `@Query` that
        // has not necessarily observed the insert yet — the two race, and this one wins
        // because it is authoritative. When it won with a stale zero it silently wiped the
        // credit, and `hasLoggedSets` then reported no work: ending a session skipped the
        // receipt entirely.
        //
        // So: a DROP to zero is only believed when the store already thought it was zero.
        // Deletes still empty tiles (any non-zero count applies immediately, and deleting
        // down to one set reports 1, not 0), but a stale zero arriving a beat after a log
        // cannot erase it. `resyncCleared` covers the genuine "all sets deleted" case.
        if count == 0 && previous > 0 {
            return
        }

        items[index].loggedSets = count

        // Trim first, then backfill, so the array always matches the count in both
        // directions.
        //
        // Trimming takes from the END regardless of which set was actually deleted: efforts
        // are positional and carry no set identity, so a count alone cannot say which one
        // went. Removing the most recent is the honest approximation — the earlier tiles
        // are the ones most likely to still reflect real work — and the next logged set
        // re-appends its true effort anyway.
        if items[index].loggedEfforts.count > count {
            items[index].loggedEfforts.removeLast(items[index].loggedEfforts.count - count)
        }

        // Backfill unknown efforts with the planned key. This covers sets that existed
        // before the session started, where reconstructing the real effort would mean
        // replaying each set against its prior e1RM. Live sets get their true effort via
        // `recordEffort` below.
        while items[index].loggedEfforts.count < items[index].loggedSets {
            let next = items[index].loggedEfforts.count
            let planned = next < items[index].sequence.count ? items[index].sequence[next] : "moderate"
            items[index].loggedEfforts.append(planned)
        }

        // Only real work counts as activity. Stamping unconditionally meant every
        // reconciliation — which runs on tab appearance and on any set change anywhere —
        // reset the idle clock, so a session could never go stale while the app was open.
        // A deletion is emphatically not activity.
        if count > previous { lastActivityAt = Date() }

        updateCompletion(at: index)
        if hasNewWork { markUnderway() }
        persist()
    }

    /// Record a set logged right now, with the effort it actually landed at.
    func recordEffort(_ effortKey: String, forExerciseId exerciseId: UUID) {
        guard let index = items.firstIndex(where: { $0.exerciseId == exerciseId }) else { return }

        let wasComplete = items[index].isComplete

        items[index].loggedEfforts.append(effortKey)
        items[index].loggedSets = items[index].loggedEfforts.count
        lastActivityAt = Date()
        updateCompletion(at: index)

        // ARMED HERE AND NOWHERE ELSE.
        //
        // `recordSetCount` also calls `updateCompletion`, but it fires on deletes and on
        // every tab appearance — arming from there would celebrate a lift again just for
        // switching tabs. This function means one specific thing: a set the user just
        // logged. That is the only event worth congratulating.
        if !wasComplete, items[index].isComplete, !celebratedLiftIds.contains(exerciseId) {
            celebratedLiftIds.insert(exerciseId)

            // The session popup SUPERSEDES the per-lift one. Finishing the last lift
            // satisfies both conditions, and showing two popups in a row for one set is
            // the sort of thing that turns a reward into an obstacle.
            if allComplete {
                pendingSessionCelebration = true
            } else {
                pendingLiftCelebration = exerciseId
            }
        }

        persist()
    }

    /// Planning → Underway. One-way: nothing returns a live session to Planning, because
    /// re-opening negotiation mid-workout is exactly what this gate exists to prevent.
    /// Idempotent, so a Start Lifting tap after a set already flipped it is a no-op.
    func markUnderway() {
        guard isActive, activePhase == .planning else { return }
        activePhase = .underway
        startedLiftingAt = Date()
        persist()
    }

    /// Any work beyond what was credited at activation.
    private var hasNewWork: Bool {
        items.contains { $0.loggedSets > $0.baselineSets }
    }

    /// Completion follows the set count in BOTH directions.
    ///
    /// It used to latch — once complete, always complete, even if the sets were deleted.
    /// That was a deliberate simplification while this was a prototype, and it is the other
    /// half of why the rail could not un-fill: a lift kept its checkmark and stayed out of
    /// `nextIncomplete` after its work was removed.
    ///
    /// The original `completedAt` is preserved when a lift is still complete, so re-syncing
    /// does not keep moving the timestamp.
    private func updateCompletion(at index: Int) {
        if items[index].loggedSets >= items[index].plannedSetCount {
            if items[index].completedAt == nil { items[index].completedAt = Date() }
        } else {
            items[index].completedAt = nil
        }
    }

    // MARK: - Derived

    var isActive: Bool { startedAt != nil }

    func item(for exerciseId: UUID) -> Item? {
        items.first { $0.exerciseId == exerciseId }
    }

    var completedCount: Int { items.filter(\.isComplete).count }
    var allComplete: Bool { !items.isEmpty && completedCount == items.count }

    /// The lift the rail wants you on: the first one not yet finished. Used when the
    /// button is *advancing* you after finishing something.
    var nextIncomplete: Item? { items.first { !$0.isComplete } }

    /// The next lift in program order, wrapping. Used when the button is merely *cycling*
    /// — you are mid-lift and want to look ahead, so order matters more than status.
    func itemAfter(exerciseId: UUID) -> Item? {
        guard items.count > 1,
              let index = items.firstIndex(where: { $0.exerciseId == exerciseId })
        else { return nil }
        return items[(index + 1) % items.count]
    }

    /// Whether any work exists to put on a receipt.
    ///
    /// Read from the ITEMS, not from `lastActivityAt`. Those are two different questions —
    /// "was there work" and "when did it last happen" — and conflating them broke ending a
    /// session: `recordSetCount` used to stamp `lastActivityAt` on every reconciliation, so
    /// the flag was set merely by opening the tab. Once that stamp became conditional on
    /// the count actually rising, a session could end with no receipt despite logged sets.
    ///
    /// Reading the items is also self-correcting: delete every set and the receipt
    /// correctly stops being offered.
    var hasLoggedSets: Bool { items.contains { $0.loggedSets > 0 } }

    /// Silent for four hours since the LAST SET — not since generation. Deliberately no
    /// `startedAt` fallback: expiry-from-generation is the thing being removed, and a
    /// session that never started is never idle, it is weightless.
    var isIdle4h: Bool {
        guard isActive, let last = lastActivityAt else { return false }
        return Date().timeIntervalSince(last) > Self.staleAfter
    }

    // MARK: - Display

    /// Matches `TierJourneyOverlay.shortName` and CheckInView's `shortDisplayName` so the
    /// rail names read the same as everywhere else in the app.
    static func shortName(for name: String) -> String {
        switch name {
        case "Overhead Press": return "OH Press"
        case "Bench Press": return "Bench"
        case "Barbell Rows": return "Rows"
        default: return name
        }
    }
}
