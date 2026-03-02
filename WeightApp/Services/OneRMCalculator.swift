//
//  OneRMCalculator.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation

enum OneRMCalculator {
    // Epley with a special-case to match your screenshot:
    // reps == 1 => 1RM = weight
    // reps > 1  => 1RM = weight * (1 + reps/30)
    static func estimate1RM(weight: Double, reps: Int) -> Double {
        guard reps > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1.0 + Double(reps) / 30.0)
    }

    static func calibrated1RM(weight: Double, reps: Int, effortFraction: Double) -> Double {
        guard effortFraction > 0 else { return estimate1RM(weight: weight, reps: reps) }
        return estimate1RM(weight: weight, reps: reps) / effortFraction
    }

    /// Inverse Epley: max reps possible at a given weight for a given estimated 1RM.
    static func maxRepsAtWeight(weight: Double, estimated1RM: Double) -> Double {
        guard weight > 0, estimated1RM > 0 else { return 0 }
        let I = weight / estimated1RM
        guard I < 1.0 else { return 1.0 }
        return 30.0 * (1.0 / I - 1.0)
    }

    /// Estimated Reps In Reserve: how many reps the lifter had left.
    static func estimatedRIR(weight: Double, reps: Int, estimated1RM: Double) -> Double? {
        guard estimated1RM > 0, weight > 0 else { return nil }
        let maxReps = maxRepsAtWeight(weight: weight, estimated1RM: estimated1RM)
        return maxReps - Double(reps)
    }

    static func current1RM(from sets: [LiftSet]) -> Double {
        let eligible = sets.filter { $0.reps >= 1 && $0.weight >= 0 }
        let best = eligible.map { estimate1RM(weight: $0.weight, reps: $0.reps) }.max() ?? 0
        return best
    }

    struct Suggestion: Identifiable {
        let id = UUID()
        let reps: Int
        let weight: Double
        let projected1RM: Double
        let delta: Double
    }

    static func minimizedSuggestions(current1RM: Double, increment: Double) -> [Suggestion] {
        guard increment > 0 else { return [] }
        let base = max(0, current1RM)
        let repsRange = Array(1...12)

        return repsRange.map { reps in
            let mult: Double = (reps == 1) ? 1.0 : (1.0 + Double(reps)/30.0)

            // Strictly exceed current 1RM by a tiny epsilon, then round weight up to increment
            let requiredRaw = (base + 0.01) / mult
            var suggestedWeight = requiredRaw.roundedUp(toIncrement: increment)

            // Ensure the projected 1RM actually exceeds current 1RM
            var proj = estimate1RM(weight: suggestedWeight, reps: reps)
            while proj <= base {
                suggestedWeight += increment
                proj = estimate1RM(weight: suggestedWeight, reps: reps)
            }

            let delta = proj - base

            return Suggestion(reps: reps, weight: suggestedWeight, projected1RM: proj, delta: delta)
        }
    }

    struct EffortSuggestion: Identifiable {
        let id = UUID()
        let reps: Int
        let weight: Double
        let percent1RM: Double
    }

    static func effortSuggestions(
        current1RM: Double,
        targetPercent1RMs: [Double],
        loadType: ExerciseLoadType,
        repRange: ClosedRange<Int>
    ) -> [EffortSuggestion] {
        guard current1RM > 0 else { return [] }
        let increment: Double = loadType == .barbell ? 5.0 : 2.5
        var seen = Set<String>()
        var results: [EffortSuggestion] = []
        for pct in targetPercent1RMs {
            let targetE1RM = pct * current1RM
            for reps in repRange {
                let rawWeight = targetE1RM * 30.0 / (30.0 + Double(reps))
                let rounded = max(0, (rawWeight / increment).rounded() * increment)
                guard rounded >= increment else { continue }
                let key = "\(rounded)-\(reps)"
                guard seen.insert(key).inserted else { continue }
                let actualPct = estimate1RM(weight: rounded, reps: reps) / current1RM * 100.0
                results.append(EffortSuggestion(reps: reps, weight: rounded, percent1RM: actualPct))
            }
        }
        return results
    }
}
