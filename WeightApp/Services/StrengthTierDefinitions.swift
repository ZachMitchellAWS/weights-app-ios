//
//  StrengthTierDefinitions.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/12/26.
//

import SwiftUI

// MARK: - Enums

enum StrengthTier: Int, CaseIterable, Comparable {
    case none = -1
    case novice = 0
    case beginner = 1
    case intermediate = 2
    case advanced = 3
    case elite = 4
    case legend = 5

    var title: String {
        switch self {
        case .none: return "None"
        case .novice: return "Novice"
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced: return "Advanced"
        case .elite: return "Elite"
        case .legend: return "Legend"
        }
    }

    var icon: String {
        "LiftTheBullIcon"
    }

    var color: Color {
        switch self {
        case .none: return .white.opacity(0.3)
        case .novice: return .white
        case .beginner: return Color(red: 0.29, green: 0.56, blue: 0.85)   // blue
        case .intermediate: return Color(red: 0.13, green: 0.72, blue: 0.79) // teal
        case .advanced: return Color(red: 0.13, green: 0.77, blue: 0.37)   // green
        case .elite: return .appAccent                                      // amber
        case .legend: return Color(red: 0.80, green: 0.52, blue: 0.96)     // violet
        }
    }

    var next: StrengthTier? {
        StrengthTier(rawValue: rawValue + 1)
    }

    static func < (lhs: StrengthTier, rhs: StrengthTier) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

enum BiologicalSex: String {
    case male
    case female
}

// MARK: - Threshold

struct TierThreshold {
    /// For Novice tier: absolute lb range (min, max). For higher tiers: BW multiplier range.
    let isAbsolute: Bool
    let min: Double
    let max: Double? // nil = unbounded top tier

    /// Check if a given value meets this tier's minimum.
    /// - Parameters:
    ///   - e1rm: The estimated 1RM in lbs
    ///   - bodyweight: User's bodyweight in lbs (only used for multiplier-based thresholds)
    /// - Returns: true if e1rm meets or exceeds this tier's minimum
    func meetsMinimum(e1rm: Double, bodyweight: Double) -> Bool {
        if isAbsolute {
            return e1rm >= min
        } else {
            return e1rm >= min * bodyweight
        }
    }

    /// Check if a value falls within this tier's range (at or above min, below max).
    func contains(e1rm: Double, bodyweight: Double) -> Bool {
        let meetsMin = meetsMinimum(e1rm: e1rm, bodyweight: bodyweight)
        guard meetsMin else { return false }
        guard let max = max else { return true } // unbounded top
        if isAbsolute {
            return e1rm < max
        } else {
            return e1rm < max * bodyweight
        }
    }
}

// MARK: - Tier Thresholds Data

struct StrengthTierData {
    /// Lookup: [exerciseName: [BiologicalSex: [StrengthTier: TierThreshold]]]
    static let thresholds: [String: [BiologicalSex: [StrengthTier: TierThreshold]]] = [
        "Squats": [
            .male: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,    max: 0.75),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.75, max: 1.25),
                .intermediate: TierThreshold(isAbsolute: false, min: 1.25, max: 1.75),
                .advanced:     TierThreshold(isAbsolute: false, min: 1.75, max: 2.5),
                .elite:        TierThreshold(isAbsolute: false, min: 2.5,  max: 3.0),
                .legend:       TierThreshold(isAbsolute: false, min: 3.0,  max: nil),
            ],
            .female: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,   max: 0.5),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.5, max: 1.0),
                .intermediate: TierThreshold(isAbsolute: false, min: 1.0, max: 1.5),
                .advanced:     TierThreshold(isAbsolute: false, min: 1.5, max: 1.75),
                .elite:        TierThreshold(isAbsolute: false, min: 1.75, max: 2.25),
                .legend:       TierThreshold(isAbsolute: false, min: 2.25, max: nil),
            ],
        ],
        "Bench Press": [
            .male: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,   max: 0.5),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.5, max: 1.0),
                .intermediate: TierThreshold(isAbsolute: false, min: 1.0, max: 1.5),
                .advanced:     TierThreshold(isAbsolute: false, min: 1.5, max: 2.0),
                .elite:        TierThreshold(isAbsolute: false, min: 2.0, max: 2.25),
                .legend:       TierThreshold(isAbsolute: false, min: 2.25, max: nil),
            ],
            .female: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,    max: 0.25),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.25, max: 0.5),
                .intermediate: TierThreshold(isAbsolute: false, min: 0.5, max: 0.75),
                .advanced:     TierThreshold(isAbsolute: false, min: 0.75, max: 1.0),
                .elite:        TierThreshold(isAbsolute: false, min: 1.0, max: 1.25),
                .legend:       TierThreshold(isAbsolute: false, min: 1.25, max: nil),
            ],
        ],
        "Deadlifts": [
            .male: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,   max: 1.0),
                .beginner:     TierThreshold(isAbsolute: false, min: 1.0, max: 1.5),
                .intermediate: TierThreshold(isAbsolute: false, min: 1.5, max: 2.25),
                .advanced:     TierThreshold(isAbsolute: false, min: 2.25, max: 3.0),
                .elite:        TierThreshold(isAbsolute: false, min: 3.0, max: 3.5),
                .legend:       TierThreshold(isAbsolute: false, min: 3.5, max: nil),
            ],
            .female: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,   max: 0.5),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.5, max: 1.0),
                .intermediate: TierThreshold(isAbsolute: false, min: 1.0, max: 1.75),
                .advanced:     TierThreshold(isAbsolute: false, min: 1.75, max: 2.25),
                .elite:        TierThreshold(isAbsolute: false, min: 2.25, max: 3.0),
                .legend:       TierThreshold(isAbsolute: false, min: 3.0, max: nil),
            ],
        ],
        "Barbell Rows": [
            .male: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,    max: 0.50),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.50, max: 0.75),
                .intermediate: TierThreshold(isAbsolute: false, min: 0.75, max: 1.0),
                .advanced:     TierThreshold(isAbsolute: false, min: 1.0,  max: 1.5),
                .elite:        TierThreshold(isAbsolute: false, min: 1.5,  max: 1.75),
                .legend:       TierThreshold(isAbsolute: false, min: 1.75, max: nil),
            ],
            .female: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,    max: 0.25),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.25, max: 0.40),
                .intermediate: TierThreshold(isAbsolute: false, min: 0.40, max: 0.65),
                .advanced:     TierThreshold(isAbsolute: false, min: 0.65, max: 0.90),
                .elite:        TierThreshold(isAbsolute: false, min: 0.90, max: 1.20),
                .legend:       TierThreshold(isAbsolute: false, min: 1.20, max: nil),
            ],
        ],
        "Overhead Press": [
            .male: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,    max: 0.40),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.40, max: 0.55),
                .intermediate: TierThreshold(isAbsolute: false, min: 0.55, max: 0.80),
                .advanced:     TierThreshold(isAbsolute: false, min: 0.80, max: 1.05),
                .elite:        TierThreshold(isAbsolute: false, min: 1.05, max: 1.35),
                .legend:       TierThreshold(isAbsolute: false, min: 1.35, max: nil),
            ],
            .female: [
                .novice:       TierThreshold(isAbsolute: false, min: 0,    max: 0.20),
                .beginner:     TierThreshold(isAbsolute: false, min: 0.20, max: 0.35),
                .intermediate: TierThreshold(isAbsolute: false, min: 0.35, max: 0.55),
                .advanced:     TierThreshold(isAbsolute: false, min: 0.55, max: 0.75),
                .elite:        TierThreshold(isAbsolute: false, min: 0.75, max: 1.00),
                .legend:       TierThreshold(isAbsolute: false, min: 1.00, max: nil),
            ],
        ],
    ]

    /// Determine the tier for a specific exercise given an e1RM value.
    static func tierForExercise(
        name: String,
        e1rm: Double,
        bodyweight: Double,
        sex: BiologicalSex
    ) -> StrengthTier {
        guard let exerciseThresholds = thresholds[name]?[sex] else {
            return .novice
        }

        // Walk from highest tier down to find the first one where e1rm meets minimum
        for tier in StrengthTier.allCases.reversed() {
            guard let threshold = exerciseThresholds[tier] else { continue }
            if threshold.meetsMinimum(e1rm: e1rm, bodyweight: bodyweight) {
                return tier
            }
        }

        // Below novice minimum still counts as Novice (floor)
        return .novice
    }

    /// Get the next tier's minimum threshold value in lbs for progress display.
    static func nextTierMinimum(
        name: String,
        currentTier: StrengthTier,
        bodyweight: Double,
        sex: BiologicalSex
    ) -> Double? {
        guard currentTier != .legend else { return nil }
        guard let nextTier = StrengthTier(rawValue: currentTier.rawValue + 1) else { return nil }
        guard let threshold = thresholds[name]?[sex]?[nextTier] else { return nil }

        if threshold.isAbsolute {
            return threshold.min
        } else {
            return threshold.min * bodyweight
        }
    }

    /// Get the current tier's minimum threshold value in lbs.
    static func currentTierMinimum(
        name: String,
        tier: StrengthTier,
        bodyweight: Double,
        sex: BiologicalSex
    ) -> Double {
        guard let threshold = thresholds[name]?[sex]?[tier] else { return 0 }
        if threshold.isAbsolute {
            return threshold.min
        } else {
            return threshold.min * bodyweight
        }
    }
}
