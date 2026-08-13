//
//  StrengthSampleData.swift
//  WeightApp
//
//  The single source for the pre-unlock sample shown on the Strength tab, used by both
//  `StrengthTierWidget` and `StrengthMilestonesWidget`.
//
//  Only the five e1RM values are authored. Tiers, the overall tier, progress and the
//  whole milestone grid are DERIVED from them through the same production code that
//  runs on real data (`StrengthTierData`, `TrendsCalculator.strengthMilestones`), so
//  the two cards can't disagree with each other or with the app's own rules — and they
//  stay correct if the threshold table is ever retuned.
//

import Foundation

enum StrengthSampleData {

    /// The sample lifter. Matches the app's own fallbacks when a profile is unset
    /// (`BalanceView` passes 200 lb / male), so the numbers read as plausible for the
    /// default reader.
    static let bodyweightLbs: Double = 200
    static let sex: BiologicalSex = .male
    static var sexRawValue: String { sex.rawValue }

    /// e1RM in lbs per fundamental, hand-authored for a coherent 200 lb male:
    /// a solid lifter whose bench is the laggard.
    ///
    /// At 200 lb male the Advanced thresholds are DL 450 / SQ 350 / BP 300 / Row 200 /
    /// OHP 160, so four lifts clear Advanced and Bench sits mid-Intermediate. Because
    /// the overall tier is the LOWEST of the five, the card lands on Intermediate with
    /// a visible reason — which demonstrates the limiting-lift rule rather than just
    /// asserting it in the footer.
    static let e1rmByName: [String: Double] = [
        "Deadlifts": 495,
        "Squats": 405,
        "Bench Press": 265,
        "Barbell Rows": 235,
        "Overhead Press": 175,
    ]

    static func e1rm(for name: String) -> Double { e1rmByName[name] ?? 0 }

    /// Real threshold lookup — never hand-assert a pill's tier.
    static func tier(for name: String) -> StrengthTier {
        StrengthTierData.tierForExercise(
            name: name,
            e1rm: e1rm(for: name),
            bodyweight: bodyweightLbs,
            sex: sex
        )
    }

    /// Lowest of the five, matching `strengthTierAssessment`.
    static var overallTier: StrengthTier {
        TrendsCalculator.fundamentalExercises
            .map { tier(for: $0.name) }
            .min() ?? .novice
    }

    /// Fraction from the limiting lift's current tier floor to the next tier's floor —
    /// the same quantity the real card's overall progress bar shows.
    static var progressToNextTier: Double {
        guard let limiting = TrendsCalculator.fundamentalExercises
            .min(by: { tier(for: $0.name) < tier(for: $1.name) })
        else { return 0 }

        let current = tier(for: limiting.name)
        let value = e1rm(for: limiting.name)
        let floor = StrengthTierData.currentTierMinimum(
            name: limiting.name, tier: current, bodyweight: bodyweightLbs, sex: sex
        )
        guard let ceiling = StrengthTierData.nextTierMinimum(
            name: limiting.name, currentTier: current, bodyweight: bodyweightLbs, sex: sex
        ), ceiling > floor else { return 1 }

        return min(max((value - floor) / (ceiling - floor), 0), 1)
    }

    /// Progress within a single lift's own tier, for the mini row bars.
    static func tierProgress(for name: String) -> Double {
        let current = tier(for: name)
        let value = e1rm(for: name)
        let floor = StrengthTierData.currentTierMinimum(
            name: name, tier: current, bodyweight: bodyweightLbs, sex: sex
        )
        guard let ceiling = StrengthTierData.nextTierMinimum(
            name: name, currentTier: current, bodyweight: bodyweightLbs, sex: sex
        ), ceiling > floor else { return 1 }

        return min(max((value - floor) / (ceiling - floor), 0), 1)
    }

    /// A milestone grid consistent with the e1RMs above, computed by the real algorithm.
    ///
    /// Builds five in-memory `Exercise` objects carrying the sample e1RMs and feeds them
    /// to the production `strengthMilestones(fromExercises:)`. They are NEVER inserted
    /// into a `ModelContext` — they exist only as an input shape, so there's no
    /// persistence, no uniqueness conflict with the user's real rows, and no risk of
    /// the sample leaking into their data.
    ///
    /// The alternative, hand-building a `MilestoneResult`, would duplicate the
    /// achievement logic and drift the moment thresholds change.
    static var milestoneResult: TrendsCalculator.MilestoneResult? {
        let sampleExercises = TrendsCalculator.fundamentalExercises.map { fundamental -> Exercise in
            let exercise = Exercise(id: fundamental.id, name: fundamental.name, isCustom: false, icon: fundamental.icon)
            exercise.currentE1RMLocalCache = e1rm(for: fundamental.name)
            return exercise
        }
        return TrendsCalculator.strengthMilestones(
            fromExercises: sampleExercises,
            bodyweight: bodyweightLbs,
            biologicalSex: sexRawValue
        )
    }
}
