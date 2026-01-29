//
//  PlateCalculator.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation

struct PlateStack {
    let plates: [Double]  // Ordered from heaviest to lightest
    let totalWeight: Double
}

enum PlateCalculator {
    /// Calculates the optimal plate combination for one side of the barbell
    /// - Parameters:
    ///   - targetWeight: The weight needed on one side (e.g., (total - barWeight) / 2)
    ///   - availablePlates: All available plate weights from the collection
    /// - Returns: PlateStack with plates ordered heaviest to lightest, or nil if impossible
    static func calculatePlateStack(targetWeight: Double, availablePlates: [Double]) -> PlateStack? {
        guard targetWeight >= 0 else { return nil }

        // If target is 0 or very small, return empty stack
        if targetWeight < 0.01 {
            return PlateStack(plates: [], totalWeight: 0)
        }

        // Sort plates by weight descending (heaviest first)
        let sortedPlates = availablePlates.sorted { $0 > $1 }

        // Try to find exact or close match using greedy algorithm
        // Assume unlimited quantity of each plate increment
        var remainingWeight = targetWeight
        var selectedPlates: [Double] = []

        for plateWeight in sortedPlates {
            // Calculate how many of this plate we can use (unlimited quantity)
            let neededQuantity = Int(remainingWeight / plateWeight)

            // Add this many plates to the stack
            for _ in 0..<neededQuantity {
                selectedPlates.append(plateWeight)
                remainingWeight -= plateWeight
            }

            // If we've reached the target (with small tolerance), we're done
            if abs(remainingWeight) < 0.01 {
                break
            }
        }

        // Calculate actual total weight
        let actualWeight = selectedPlates.reduce(0) { $0 + $1 }

        return PlateStack(plates: selectedPlates, totalWeight: actualWeight)
    }

    /// Calculates plate stack for a barbell exercise suggestion
    /// Assumes 45lb barbell
    static func calculateForSuggestion(totalWeight: Double, availablePlates: [Double], barWeight: Double = 45.0) -> PlateStack? {
        let weightPerSide = (totalWeight - barWeight) / 2.0
        return calculatePlateStack(targetWeight: weightPerSide, availablePlates: availablePlates)
    }
}
