//
//  SessionDraftService.swift
//  WeightApp
//
//  The seam where a real generator would live.
//
//  Everything the UI needs is behind this protocol, so swapping the mock for a real API
//  call later is a one-type change and none of the state machine moves. The mock exists
//  to make all seven UI states reachable on demand — including the ones you cannot
//  produce by behaving normally, like a refresh that fails.
//

import Foundation
// `SyncLogger`'s categories are `os.Logger`, whose interpolation and literal initialisers
// only resolve where `os` is imported — hence this alongside Foundation.
import os

/// Bounds on what the user may hand the generator.
///
/// The backend enforces the same two numbers — a client is not a validator — but it enforces
/// them by truncating silently. These exist so the user is told where they stand BEFORE
/// their words are quietly cut in half.
enum SessionContextLimits {
    static let noteLimit = 500
    /// Start showing the counter this close to the limit. Silent before then, so the field
    /// stays clean for the short notes that are the normal case.
    static let warnWithin = 50
    static let maxChips = 8
}

struct DraftContext {
    var chips: Set<String> = []
    var note: String = ""

    var isEmpty: Bool {
        chips.isEmpty && note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Characters remaining; negative once over.
    var noteRemaining: Int { SessionContextLimits.noteLimit - note.count }
    var isNoteOver: Bool { noteRemaining < 0 }
    var shouldShowNoteCount: Bool { noteRemaining <= SessionContextLimits.warnWithin }
    var chipsAtLimit: Bool { chips.count >= SessionContextLimits.maxChips }

    /// What actually travels. Going over is allowed — only the first 500 are sent, matching
    /// what the backend would keep anyway.
    var truncatedNote: String {
        String(note.trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(SessionContextLimits.noteLimit))
    }
}

enum DraftError: Error {
    /// Carries a short machine-readable cause ("http_503", "offline", …) purely for the
    /// analytics property. The user is never shown it — every one of these reads as "it
    /// did not work, try again" — but without it the failure event is a single
    /// undifferentiated count and tells you nothing about which failure you have.
    case generationFailed(reason: String)
    /// The account is not premium. Distinct from a failure because Retry cannot fix it.
    case notPremium
    /// The generated session resolved to nothing locally. Treated as a failure rather
    /// than shown as an empty session.
    case emptySession
    /// Everything worth recommending is already logged today, so the generator chose
    /// nothing. NOT a failure — it carries the generator's own explanation for display.
    case nothingToRecommend(summary: String)

    /// Value of the `reason` property on `sessionGenerationFailed`.
    var analyticsReason: String {
        switch self {
        case let .generationFailed(reason): return reason
        case .notPremium: return "not_premium"
        case .emptySession: return "empty_session"
        case .nothingToRecommend: return "nothing_to_recommend"
        }
    }
}

protocol SessionDraftService {
    /// - Parameter catalog: every set plan available to this user, built-ins and their own.
    ///   Passed in rather than read here because the catalog lives in SwiftData and the
    ///   view already holds the `ModelContext` — a service singleton would have to acquire
    ///   one just to fetch it.
    func generateDraft(context: DraftContext, catalog: [SetPlanCatalogEntry]) async throws -> MockDayPlan
}

@Observable
final class MockSessionDraftService: SessionDraftService {
    static let shared = MockSessionDraftService()

    // MARK: Injectable test flags
    //
    // Deliberately not `#if DEBUG` — driven from a staging-only strip on the Session
    // tab, because a generation failure is not something normal use will produce.

    /// Makes the next generation throw, so the failure state is reachable on demand.
    var shouldFail = false

    private var variationIndex = 0

    private init() {}

    func generateDraft(context: DraftContext, catalog: [SetPlanCatalogEntry]) async throws -> MockDayPlan {
        // 1.5–2.5s, varied so the wait never feels like a fixed animation.
        let delay = Double.random(in: 1.5...2.5)
        try? await Task.sleep(for: .seconds(delay))

        if shouldFail {
            shouldFail = false
            throw DraftError.generationFailed(reason: "mock")
        }

        return plan(for: context)
    }

    /// Context wins when the user said something specific; otherwise the neutral drafts
    /// rotate so tapping Refresh visibly changes the output rather than appearing broken.
    private func plan(for context: DraftContext) -> MockDayPlan {
        let text = context.note.lowercased()

        let mentionsLegs = context.chips.contains("Legs are sore")
            || context.chips.contains("No squat rack")
            || text.contains("leg") || text.contains("squat") || text.contains("knee")

        let feelingGood = context.chips.contains("Feeling strong")
            || context.chips.contains("Well rested")

        let shortOnTime = context.chips.contains("Short on time")
            || !context.chips.isDisjoint(with: ProgramMockData.liftCountChips)
            || text.contains("time") || text.contains("quick")

        // A caveat is more actionable than enthusiasm, so constraints outrank good moods.
        if mentionsLegs { return ProgramMockData.revisedPlan }
        if shortOnTime { return ProgramMockData.shortPlan }
        if feelingGood { return ProgramMockData.fullPlan }

        let neutrals = [
            ProgramMockData.defaultPlan,
            ProgramMockData.pullFocusPlan,
            ProgramMockData.shortPlan,
        ]
        let picked = neutrals[variationIndex % neutrals.count]
        variationIndex += 1
        return picked
    }
}

// MARK: - Live

/// The real generator: `POST /sessions/generate`.
///
/// The backend assembles the model's inputs from DynamoDB, so this sends only the catalog
/// and the user's context and maps the answer back onto `MockDayPlan`. That the UI type is
/// still called Mock is now a misnomer — it is the plan type, and renaming it touches every
/// file in this directory, so it is left for a deliberate pass.
final class LiveSessionDraftService: SessionDraftService {
    static let shared = LiveSessionDraftService()

    private init() {}

    func generateDraft(context: DraftContext, catalog: [SetPlanCatalogEntry]) async throws -> MockDayPlan {
        guard !catalog.isEmpty else {
            // The backend rejects an empty catalog with a 400. Caught here so a seeding
            // failure does not read to the user as a generation failure.
            SyncLogger.api.error("Session generation skipped: empty set plan catalog")
            throw DraftError.generationFailed(reason: "empty_catalog")
        }

        let response: GeneratedSessionResponse
        do {
            response = try await APIService.shared.generateSession(
                catalog: catalog,
                // A Set has no order, so sorting keeps the request stable across taps.
                chips: Array(context.chips.sorted().prefix(SessionContextLimits.maxChips)),
                note: context.truncatedNote
            )
        } catch let error as APIError {
            throw Self.draftError(for: error)
        }

        let session = response.session

        // Checked BEFORE resolving anything. The generator deliberately chose no lifts
        // because the user has already trained them today — a correct answer, and the one
        // case where an empty session must not read as a failure.
        if response.nothingToRecommend == true || session.items.isEmpty {
            throw DraftError.nothingToRecommend(summary: session.summary)
        }

        let items = session.items.compactMap { Self.planItem(from: $0, catalog: catalog) }

        // Distinct from the above: the backend DID send lifts and none of them resolved
        // locally. The backend guarantees every id it returns is one we sent, so this
        // means something is wrong on this side — a lift missing from
        // `fundamentalExercises`, say — and is worth surfacing as a failure.
        guard !items.isEmpty else {
            SyncLogger.api.error("Session generation returned \(session.items.count) items, none resolvable locally")
            throw DraftError.emptySession
        }

        // `note_used == false` means the note was withheld — flagged, or unscreenable. The
        // client is deliberately not told which.
        let noteOmitted = !context.truncatedNote.isEmpty && response.noteUsed == false
        return MockDayPlan(summary: session.summary, items: items, noteOmitted: noteOmitted)
    }

    // MARK: Mapping

    private static func planItem(
        from item: GeneratedSessionItem,
        catalog: [SetPlanCatalogEntry]
    ) -> MockPlanItem? {
        let exerciseId = UUID(uuidString: item.exerciseId)
        let setPlanId = UUID(uuidString: item.setPlanId)

        // The icon is not on the wire — it is client-side presentation, so it is resolved
        // from the same table the rest of the app draws lift icons from.
        let fundamental = TrendsCalculator.fundamentalExercises.first { candidate in
            if let exerciseId, candidate.id == exerciseId { return true }
            return candidate.name == item.exerciseName
        }
        guard let fundamental else { return nil }

        // The sequence comes from the catalog WE sent, never from the response. The
        // backend echoes ids and names only; the effort keys are ours and stay ours.
        //
        // Matched on the parsed UUID rather than the raw string so that a difference in
        // hex casing cannot cause a miss — `UUID(uuidString:)` is case-insensitive where
        // `==` on the strings is not.
        var entry: SetPlanCatalogEntry?
        if let setPlanId {
            entry = catalog.first { UUID(uuidString: $0.id) == setPlanId }
        }
        if entry == nil {
            entry = catalog.first { $0.id == item.setPlanId }
        }
        let sequence = entry?.sequence ?? []
        guard !sequence.isEmpty else { return nil }

        return MockPlanItem(
            exerciseId: fundamental.id,
            setPlanId: setPlanId,
            exerciseName: fundamental.name,
            icon: fundamental.icon,
            planName: entry?.name ?? item.setPlanName,
            sequence: sequence,
            detail: detail(for: sequence),
            rationale: item.rationale
        )
    }

    /// The one-line target under each lift.
    ///
    /// Deliberately structural — "Progress · 6 sets", not "Progress · 320 × 3".
    /// A weight belongs to the Lift tab, which computes it from the current e1RM, the
    /// user's plates and the load type. Guessing one here would eventually disagree with
    /// the number the user sees when they arrive, and a target that contradicts itself is
    /// worse than one that is merely less specific.
    /// Internal, not private: `ProgramSessionStore` recomputes this when the user swaps a
    /// plan by hand. One definition — this is user-visible copy, and two copies of it would
    /// drift the first time the wording changed.
    static func detail(for sequence: [String]) -> String {
        let sets = sequence.count
        let noun = sets == 1 ? "set" : "sets"
        if sequence.contains("pr") {
            return "Progress · \(sets) \(noun)"
        }
        if sequence.allSatisfy({ $0 == "easy" }) {
            return "Recovery · \(sets) \(noun)"
        }
        return "Volume · \(sets) \(noun)"
    }

    /// Every case except 402 reads the same to the user — it did not work, try again — so
    /// the distinction survives only as an analytics reason.
    private static func draftError(for error: APIError) -> DraftError {
        switch error {
        case .httpError(402, _):
            return .notPremium
        case let .httpError(code, _):
            return .generationFailed(reason: "http_\(code)")
        case .unauthorized:
            return .generationFailed(reason: "unauthorized")
        case .decodingError:
            return .generationFailed(reason: "decode")
        case let .networkError(underlying):
            // Timeout and offline are the two worth separating: the first says the model
            // is running long, the second says nothing about the backend at all.
            switch (underlying as? URLError)?.code {
            case .timedOut: return .generationFailed(reason: "timeout")
            case .notConnectedToInternet, .networkConnectionLost:
                return .generationFailed(reason: "offline")
            default: return .generationFailed(reason: "network")
            }
        default:
            return .generationFailed(reason: "unknown")
        }
    }
}
