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
}
