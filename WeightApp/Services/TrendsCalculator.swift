//
//  TrendsCalculator.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import Foundation

struct TrendsCalculator {
    // MARK: - Weekly Volume

    struct WeeklyVolume: Identifiable {
        let id = UUID()
        let weekStart: Date
        let volume: Double
    }

    static func weeklyVolume(from sets: [LiftSets], weeks: Int = 8) -> [WeeklyVolume] {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else {
            return []
        }

        let recentSets = sets.filter { $0.createdAt >= cutoffDate }
        let grouped = Dictionary(grouping: recentSets) { set -> Date in
            calendar.startOfWeek(for: set.createdAt)
        }

        var result: [WeeklyVolume] = []
        for (weekStart, weekSets) in grouped {
            let volume = weekSets.reduce(0.0) { total, set in
                total + set.weight * Double(set.reps)
            }
            result.append(WeeklyVolume(weekStart: weekStart, volume: volume))
        }
        return result.sorted { $0.weekStart < $1.weekStart }
    }

    static func exerciseWeeklyVolume(from sets: [LiftSets], exerciseName: String, weeks: Int = 8) -> [WeeklyVolume] {
        let exerciseSets = sets.filter { $0.exercise?.name == exerciseName }
        return weeklyVolume(from: exerciseSets, weeks: weeks)
    }

    // MARK: - Intensity Distribution

    enum IntensityBucket: String, CaseIterable {
        case easy = "Easy"
        case moderate = "Moderate"
        case hard = "Hard"
        case redline = "Redline"
        case pr = "PR"

        var color: String {
            switch self {
            case .easy: return "setEasy"
            case .moderate: return "setModerate"
            case .hard: return "setHard"
            case .redline: return "setNearMax"
            case .pr: return "setPR"
            }
        }

        /// Classify by percent of estimated 1RM into an intensity bucket.
        /// Does not handle PR detection — caller should check for PRs first.
        static func from(percent1RM p: Double) -> IntensityBucket {
            switch p {
            case 1.0...:      return .pr
            case 0.92..<1.0:  return .redline
            case 0.82..<0.92: return .hard
            case 0.70..<0.82: return .moderate
            default:          return .easy
            }
        }
    }

    struct IntensityDistribution {
        var easy: Int = 0
        var moderate: Int = 0
        var hard: Int = 0
        var redline: Int = 0
        var pr: Int = 0

        var total: Int { easy + moderate + hard + redline + pr }

        func percentage(for bucket: IntensityBucket) -> Double {
            guard total > 0 else { return 0 }
            let count: Int
            switch bucket {
            case .easy: count = easy
            case .moderate: count = moderate
            case .hard: count = hard
            case .redline: count = redline
            case .pr: count = pr
            }
            return Double(count) / Double(total) * 100
        }
    }

    static func intensityDistribution(from sets: [LiftSets], days: Int = 30) -> IntensityDistribution {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return IntensityDistribution()
        }

        let recentSets = sets.filter { $0.createdAt >= cutoffDate }
        var distribution = IntensityDistribution()

        // Group sets by exercise to compute per-exercise maxes
        let byExercise = Dictionary(grouping: sets) { $0.exercise?.id }

        for set in recentSets {
            // Skip baseline sets — they don't count in distribution
            if set.isBaselineSet { continue }

            let exerciseSets = byExercise[set.exercise?.id] ?? []
            let previousSets = exerciseSets.filter { $0.createdAt < set.createdAt }
            let currentMax = previousSets.map { OneRMCalculator.estimate1RM(weight: $0.weight, reps: $0.reps) }.max() ?? 0
            let setEstimated1RM = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)

            if currentMax > 0 {
                let percent1RM = setEstimated1RM / currentMax
                let bucket = IntensityBucket.from(percent1RM: percent1RM)
                switch bucket {
                case .pr: distribution.pr += 1
                case .redline: distribution.redline += 1
                case .hard: distribution.hard += 1
                case .moderate: distribution.moderate += 1
                case .easy: distribution.easy += 1
                }
            } else {
                // First set for this exercise, count as PR
                distribution.pr += 1
            }
        }

        return distribution
    }

    // MARK: - PR Timeline

    struct PREvent: Identifiable {
        let id = UUID()
        let date: Date
        let exerciseName: String
        let oldValue: Double
        let newValue: Double

        var percentageGain: Double {
            guard oldValue > 0 else { return 0 }
            return ((newValue - oldValue) / oldValue) * 100
        }
    }

    static func prTimeline(from sets: [LiftSets]) -> [PREvent] {
        var events: [PREvent] = []
        let byExercise = Dictionary(grouping: sets) { $0.exercise?.id }

        for (_, exerciseSets) in byExercise {
            let sortedSets = exerciseSets.sorted { $0.createdAt < $1.createdAt }
            var currentMax: Double = 0

            for set in sortedSets {
                let estimated1RM = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
                if estimated1RM > currentMax {
                    if currentMax > 0 {
                        events.append(PREvent(
                            date: set.createdAt,
                            exerciseName: set.exercise?.name ?? "Unknown",
                            oldValue: currentMax,
                            newValue: estimated1RM
                        ))
                    }
                    currentMax = estimated1RM
                }
            }
        }

        return events.sorted { $0.date > $1.date }
    }

    // MARK: - Best Lifts

    struct BestLift: Identifiable {
        let id = UUID()
        let exerciseName: String
        let estimated1RM: Double
        let lastPRDate: Date?
    }

    static func bestLifts(from sets: [LiftSets], limit: Int = 5) -> [BestLift] {
        let byExercise = Dictionary(grouping: sets) { $0.exercise?.name ?? "Unknown" }

        return byExercise.compactMap { exerciseName, exerciseSets -> BestLift? in
            let sortedSets = exerciseSets.sorted { $0.createdAt < $1.createdAt }
            var currentMax: Double = 0
            var lastPRDate: Date? = nil

            for set in sortedSets {
                let estimated1RM = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
                if estimated1RM > currentMax {
                    currentMax = estimated1RM
                    lastPRDate = set.createdAt
                }
            }

            guard currentMax > 0 else { return nil }
            return BestLift(exerciseName: exerciseName, estimated1RM: currentMax, lastPRDate: lastPRDate)
        }
        .sorted { $0.estimated1RM > $1.estimated1RM }
        .prefix(limit)
        .map { $0 }
    }

    // MARK: - Training Frequency

    struct DayActivity: Identifiable {
        let id = UUID()
        let date: Date
        let setCount: Int
    }

    static func trainingFrequency(from sets: [LiftSets], weeks: Int = 12) -> [DayActivity] {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else {
            return []
        }

        let recentSets = sets.filter { $0.createdAt >= cutoffDate }
        let grouped = Dictionary(grouping: recentSets) { set -> Date in
            calendar.startOfDay(for: set.createdAt)
        }

        return grouped.map { day, daySets in
            DayActivity(date: day, setCount: daySets.count)
        }
        .sorted { $0.date < $1.date }
    }

    // MARK: - Monthly Summary

    struct MonthlySummary {
        let currentMonthSets: Int
        let previousMonthSets: Int
        let currentMonthVolume: Double
        let previousMonthVolume: Double
        let prCount: Int
        let mostTrainedExercise: String?
        let mostTrainedCount: Int

        var setsChange: Double {
            guard previousMonthSets > 0 else { return 0 }
            return Double(currentMonthSets - previousMonthSets) / Double(previousMonthSets) * 100
        }

        var volumeChange: Double {
            guard previousMonthVolume > 0 else { return 0 }
            return (currentMonthVolume - previousMonthVolume) / previousMonthVolume * 100
        }
    }

    static func monthlySummary(from sets: [LiftSets]) -> MonthlySummary {
        let calendar = Calendar.current
        let now = Date()
        let currentMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let previousMonthStart = calendar.date(byAdding: .month, value: -1, to: currentMonthStart)!

        let currentMonthSets = sets.filter { $0.createdAt >= currentMonthStart }
        let previousMonthSets = sets.filter { $0.createdAt >= previousMonthStart && $0.createdAt < currentMonthStart }

        let currentVolume = currentMonthSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let previousVolume = previousMonthSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }

        // Count PRs this month
        let prEvents = prTimeline(from: sets).filter { $0.date >= currentMonthStart }

        // Most trained exercise this month
        let exerciseCounts = Dictionary(grouping: currentMonthSets) { $0.exercise?.name ?? "Unknown" }
            .mapValues { $0.count }
        let mostTrained = exerciseCounts.max { $0.value < $1.value }

        return MonthlySummary(
            currentMonthSets: currentMonthSets.count,
            previousMonthSets: previousMonthSets.count,
            currentMonthVolume: currentVolume,
            previousMonthVolume: previousVolume,
            prCount: prEvents.count,
            mostTrainedExercise: mostTrained?.key,
            mostTrainedCount: mostTrained?.value ?? 0
        )
    }

    // MARK: - 1RM Progression

    struct OneRMDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let isPR: Bool
    }

    static func oneRMProgression(from estimated1RMs: [Estimated1RMs], exerciseName: String) -> [OneRMDataPoint] {
        let exerciseRecords = estimated1RMs.filter { $0.exercise?.name == exerciseName }
            .sorted { $0.createdAt < $1.createdAt }

        var dataPoints: [OneRMDataPoint] = []
        var previousValue: Double = 0

        for record in exerciseRecords {
            let isPR = record.value > previousValue
            dataPoints.append(OneRMDataPoint(date: record.createdAt, value: record.value, isPR: isPR))
            previousValue = record.value
        }

        return dataPoints
    }

    static func exerciseNames(from estimated1RMs: [Estimated1RMs]) -> [String] {
        let names = Set(estimated1RMs.compactMap { $0.exercise?.name })
        return names.sorted()
    }

    static func exerciseNames(from sets: [LiftSets]) -> [String] {
        let names = Set(sets.compactMap { $0.exercise?.name })
        return names.sorted()
    }

    // MARK: - Exercise Recency

    struct ExerciseRecency: Identifiable {
        let id = UUID()
        let exerciseName: String
        let daysSinceLastSet: Int? // nil = no sets in last 30 days
    }

    static func exerciseRecency(from sets: [LiftSets], days: Int = 30) -> [ExerciseRecency] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let activeSets = sets.filter { !$0.deleted && $0.exercise != nil }

        // Get all unique exercise names and their most recent set date
        let byExercise = Dictionary(grouping: activeSets) { $0.exercise!.name }
        let mostRecentByExercise = byExercise.mapValues { exerciseSets in
            exerciseSets.map(\.createdAt).max()!
        }

        return mostRecentByExercise.map { name, lastDate in
            let lastDay = calendar.startOfDay(for: lastDate)
            let daysDiff = calendar.dateComponents([.day], from: lastDay, to: today).day ?? (days + 1)
            return ExerciseRecency(
                exerciseName: name,
                daysSinceLastSet: daysDiff <= days ? daysDiff : nil
            )
        }
        .sorted { a, b in
            switch (a.daysSinceLastSet, b.daysSinceLastSet) {
            case let (aVal?, bVal?): return aVal < bVal
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.exerciseName < b.exerciseName
            }
        }
    }
}

// MARK: - Calendar Extension

extension Calendar {
    func startOfWeek(for date: Date) -> Date {
        // Always use Monday as start of week to match the M-S day labels
        var cal = self
        cal.firstWeekday = 2 // Monday
        let components = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return cal.date(from: components) ?? date
    }
}
