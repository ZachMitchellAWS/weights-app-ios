//
//  TrendsCalculator.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import Foundation
import SwiftUI

struct TrendsCalculator {
    // MARK: - Weekly Volume

    struct WeeklyVolume: Identifiable {
        let id = UUID()
        let weekStart: Date
        let volume: Double
    }

    static func weeklyVolume(from sets: [LiftSet], weeks: Int = 8) -> [WeeklyVolume] {
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

    static func exerciseWeeklyVolume(from sets: [LiftSet], exerciseName: String, weeks: Int = 8) -> [WeeklyVolume] {
        let exerciseSets = sets.filter { $0.exercise?.name == exerciseName }
        return weeklyVolume(from: exerciseSets, weeks: weeks)
    }

    // MARK: - Volume Bands

    struct VolumeBand {
        let threshold: Double   // percentage offset from average (-0.8, -0.5, -0.2, 0.2, 0.5, 0.8)
        let value: Double       // absolute volume value at this threshold
    }

    /// Computes reference lines for volume charts based on ~13-week rolling average.
    /// Returns the average and band thresholds at ±20%, ±50%, ±80%.
    static func volumeBands(from sets: [LiftSet], exerciseName: String? = nil) -> (average: Double, bands: [VolumeBand]) {
        let filtered: [LiftSet]
        if let name = exerciseName {
            filtered = sets.filter { $0.exercise?.name == name }
        } else {
            filtered = Array(sets)
        }

        let data = weeklyVolume(from: filtered, weeks: 13)
        guard !data.isEmpty else { return (0, []) }

        let avg = data.map(\.volume).reduce(0, +) / Double(data.count)
        guard avg > 0 else { return (0, []) }

        let thresholds: [Double] = [-0.8, -0.5, -0.2, 0.2, 0.5, 0.8]
        let bands = thresholds.map { t in
            VolumeBand(threshold: t, value: avg * (1.0 + t))
        }
        return (avg, bands)
    }

    /// Returns the color for a volume value based on its position relative to the average.
    static func volumeBandColor(volume: Double, average: Double) -> Color {
        guard average > 0 else { return .appAccent }
        let pct = (volume - average) / average

        if pct < -0.8 {
            return Color(white: 0.4)            // light gray — minimal activity
        } else if pct < -0.5 {
            return .setModerate                  // cyan
        } else if pct < -0.2 {
            return .setHard                      // purple
        } else if pct <= 0.2 {
            return .setEasy                      // green — near average
        } else {
            return .appAccent                    // amber — above average
        }
    }

    // MARK: - Intensity Distribution

    enum IntensityBucket: String, CaseIterable {
        case easy = "Easy"
        case moderate = "Moderate"
        case hard = "Hard"
        case redline = "Redline"
        case pr = "Progress"

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
            case 0.92...:     return .redline  // 92%+ (PR is handled by caller)
            case 0.82..<0.92: return .hard     // 82-91%
            case 0.70..<0.82: return .moderate // 70-81%
            default:          return .easy     // < 70%
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

    static func intensityDistribution(from sets: [LiftSet], estimated1RMs: [Estimated1RM] = [], days: Int = 30) -> IntensityDistribution {
        let calendar = Calendar.current
        guard let cutoffDate = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return IntensityDistribution()
        }

        var distribution = IntensityDistribution()

        // Mirrors HistoryView.buildEffortCache() exactly: all-time running max
        // per exercise, baseline sets use calibrated e1RM from Estimated1RM table.
        let e1rmBySetId = Dictionary(uniqueKeysWithValues: estimated1RMs.compactMap { e1rm -> (UUID, Double)? in
            return (e1rm.setId, e1rm.value)
        })
        let byExercise = Dictionary(grouping: sets) { $0.exercise?.id }

        for (_, exerciseSets) in byExercise {
            let sorted = exerciseSets.sorted { $0.createdAt < $1.createdAt }
            var runningMax: Double = 0

            for set in sorted {
                let estimated = OneRMCalculator.estimate1RM(weight: set.weight, reps: set.reps)
                let isInWindow = set.createdAt >= cutoffDate

                if set.isBaselineSet {
                    // Baseline: use calibrated e1RM (from Estimated1RM table) as reference
                    let baselineE1RM = e1rmBySetId[set.id] ?? estimated
                    if isInWindow {
                        let pct = baselineE1RM > 0 ? estimated / baselineE1RM : 0
                        let bucket = IntensityBucket.from(percent1RM: pct)
                        switch bucket {
                        case .pr: distribution.pr += 1
                        case .redline: distribution.redline += 1
                        case .hard: distribution.hard += 1
                        case .moderate: distribution.moderate += 1
                        case .easy: distribution.easy += 1
                        }
                    }
                    runningMax = max(runningMax, baselineE1RM)
                    continue
                }

                // Zero-weight sets: rep-based classification (same as history)
                if set.weight == 0 {
                    if isInWindow {
                        let bucket: IntensityBucket
                        switch set.reps {
                        case 12...: bucket = .redline
                        case 9..<12: bucket = .hard
                        case 6..<9: bucket = .moderate
                        default: bucket = .easy
                        }
                        switch bucket {
                        case .pr: distribution.pr += 1
                        case .redline: distribution.redline += 1
                        case .hard: distribution.hard += 1
                        case .moderate: distribution.moderate += 1
                        case .easy: distribution.easy += 1
                        }
                    }
                    continue
                }

                // Normal set: compare to all-time running max
                let isPR = runningMax > 0 && estimated > runningMax

                if isInWindow {
                    if isPR {
                        distribution.pr += 1
                    } else if runningMax > 0 {
                        let percent1RM = estimated / runningMax
                        let bucket = IntensityBucket.from(percent1RM: percent1RM)
                        switch bucket {
                        case .pr: distribution.pr += 1
                        case .redline: distribution.redline += 1
                        case .hard: distribution.hard += 1
                        case .moderate: distribution.moderate += 1
                        case .easy: distribution.easy += 1
                        }
                    } else {
                        // First set ever for this exercise — treat as PR
                        distribution.pr += 1
                    }
                }

                runningMax = max(runningMax, estimated)
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

    static func prTimeline(from sets: [LiftSet]) -> [PREvent] {
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

    // MARK: - PR Leaderboard

    struct ExercisePRSummary: Identifiable {
        let id: UUID           // exercise id
        let exerciseName: String
        let prCount: Int       // number of PR events in period
        let totalGain: Double  // e1RM at end of period minus e1RM at start of period
        let latestE1RM: Double // current e1RM value
    }

    static func prLeaderboard(from estimated1RMs: [Estimated1RM], days: Int = 90) -> [ExercisePRSummary] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!

        // Group by exercise
        let byExercise = Dictionary(grouping: estimated1RMs.filter { $0.exercise != nil }) {
            $0.exercise!.id
        }

        var results: [ExercisePRSummary] = []

        for (exerciseId, records) in byExercise {
            let sorted = records.sorted { $0.createdAt < $1.createdAt }
            guard let exerciseName = sorted.first?.exercise?.name else { continue }

            // Find baseline: the record at or just before the cutoff
            var baseline: Double? = nil
            var recordsInPeriod: [Estimated1RM] = []

            for record in sorted {
                if record.createdAt < cutoff {
                    baseline = record.value
                } else {
                    recordsInPeriod.append(record)
                }
            }

            guard !recordsInPeriod.isEmpty else { continue }

            // Count PRs: value increases over running max within the period
            var runningMax = baseline ?? 0
            var prCount = 0

            for record in recordsInPeriod {
                if record.value > runningMax {
                    prCount += 1
                    runningMax = record.value
                }
            }

            guard prCount > 0 else { continue }

            let baselineValue = baseline ?? recordsInPeriod.first!.value
            let finalValue = recordsInPeriod.last!.value
            let totalGain = finalValue - baselineValue

            results.append(ExercisePRSummary(
                id: exerciseId,
                exerciseName: exerciseName,
                prCount: prCount,
                totalGain: totalGain,
                latestE1RM: finalValue
            ))
        }

        // Sort by prCount desc, tiebreak by totalGain desc
        results.sort {
            if $0.prCount != $1.prCount { return $0.prCount > $1.prCount }
            return $0.totalGain > $1.totalGain
        }

        return Array(results.prefix(10))
    }

    // MARK: - Best Lifts

    struct BestLift: Identifiable {
        let id = UUID()
        let exerciseName: String
        let estimated1RM: Double
        let lastPRDate: Date?
    }

    static func bestLifts(from sets: [LiftSet], limit: Int = 5) -> [BestLift] {
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

    static func trainingFrequency(from sets: [LiftSet], weeks: Int = 12) -> [DayActivity] {
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

    // MARK: - Period Summary

    struct PeriodSummary {
        let currentPeriodSets: Int
        let avgSets: Int          // 12-week average
        let currentPeriodVolume: Double
        let avgVolume: Double     // 12-week average
        let prCount: Int
        let avgPRs: Int           // 12-week average
        let mostTrainedExercise: String?
        let mostTrainedCount: Int
    }

    /// Current week summary compared against 12-week average.
    /// Week starts Monday, matching the insights narrative week.
    static func weeklySummary(from sets: [LiftSet]) -> PeriodSummary {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.startOfWeek(for: now)
        guard let twelveWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -12, to: weekStart) else {
            return PeriodSummary(currentPeriodSets: 0, avgSets: 0, currentPeriodVolume: 0, avgVolume: 0, prCount: 0, avgPRs: 0, mostTrainedExercise: nil, mostTrainedCount: 0)
        }

        // Current week
        let currentSets = sets.filter { $0.createdAt >= weekStart }

        // Prior 12 weeks (for averaging)
        let priorSets = sets.filter { $0.createdAt >= twelveWeeksAgo && $0.createdAt < weekStart }

        let currentVolume = currentSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }
        let priorVolume = priorSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }

        // 12-week averages
        let avgSets = priorSets.count / 12
        let avgVolume = priorVolume / 12.0

        // PRs
        let allPREvents = prTimeline(from: sets)
        let currentPRs = allPREvents.filter { $0.date >= weekStart }.count
        let priorPRs = allPREvents.filter { $0.date >= twelveWeeksAgo && $0.date < weekStart }.count
        let avgPRs = priorPRs / 12

        // Most trained exercise this week
        let exerciseCounts = Dictionary(grouping: currentSets) { $0.exercise?.name ?? "Unknown" }
            .mapValues { $0.count }
        let mostTrained = exerciseCounts.max { $0.value < $1.value }

        return PeriodSummary(
            currentPeriodSets: currentSets.count,
            avgSets: avgSets,
            currentPeriodVolume: currentVolume,
            avgVolume: avgVolume,
            prCount: currentPRs,
            avgPRs: avgPRs,
            mostTrainedExercise: mostTrained?.key,
            mostTrainedCount: mostTrained?.value ?? 0
        )
    }

    /// Returns the current week's start and end dates (Monday-based).
    static func currentWeekRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let weekStart = calendar.startOfWeek(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? now
        return (weekStart, weekEnd)
    }

    // MARK: - 1RM Progression

    struct OneRMDataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let isPR: Bool
    }

    static func oneRMProgression(from estimated1RMs: [Estimated1RM], exerciseName: String) -> [OneRMDataPoint] {
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

    static func exerciseNames(from estimated1RMs: [Estimated1RM]) -> [String] {
        let names = Set(estimated1RMs.compactMap { $0.exercise?.name })
        return names.sorted()
    }

    static func exerciseNames(from sets: [LiftSet]) -> [String] {
        let names = Set(sets.compactMap { $0.exercise?.name })
        return names.sorted()
    }

    // MARK: - Strength Balance

    struct FundamentalExercise {
        let id: UUID
        let name: String
        let icon: String
        let ratioCoefficient: Double
    }

    static let fundamentalExercises: [FundamentalExercise] = [
        FundamentalExercise(id: Exercise.deadliftsId, name: "Deadlifts", icon: "DeadliftIcon", ratioCoefficient: 1.40),
        FundamentalExercise(id: Exercise.squatsId, name: "Squats", icon: "SquatIcon", ratioCoefficient: 1.25),
        FundamentalExercise(id: Exercise.benchPressId, name: "Bench Press", icon: "BenchPressIcon", ratioCoefficient: 1.00),
        FundamentalExercise(id: Exercise.barbellRowId, name: "Barbell Rows", icon: "BarbellRowIcon", ratioCoefficient: 0.825),
        FundamentalExercise(id: Exercise.overheadPressId, name: "Overhead Press", icon: "OverheadPressIcon", ratioCoefficient: 0.625),
    ]

    // MARK: - Balance Category

    enum BalanceCategory: Int, CaseIterable, Comparable {
        case lopsided = 0
        case skewed = 1
        case uneven = 2
        case balanced = 3
        case symmetrical = 4

        var title: String {
            switch self {
            case .lopsided: return "Lopsided"
            case .skewed: return "Skewed"
            case .uneven: return "Uneven"
            case .balanced: return "Balanced"
            case .symmetrical: return "Symmetrical"
            }
        }

        var color: Color {
            switch self {
            case .lopsided: return .setNearMax
            case .skewed: return .balanceWeak
            case .uneven: return .balanceMild
            case .balanced: return .balanceCoolMild
            case .symmetrical: return .balanceGood
            }
        }

        static func < (lhs: BalanceCategory, rhs: BalanceCategory) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    static func balanceCategory(from balances: [ExerciseBalance], bodyweight: Double, sex: BiologicalSex) -> BalanceCategory? {
        let exercisesWithData = balances.filter { $0.current1RM != nil }
        guard exercisesWithData.count >= 2 else { return nil }

        let tiers = exercisesWithData.compactMap { exercise -> StrengthTier? in
            guard let e1rm = exercise.current1RM else { return nil }
            return StrengthTierData.tierForExercise(
                name: exercise.exerciseName,
                e1rm: e1rm,
                bodyweight: bodyweight,
                sex: sex
            )
        }
        guard tiers.count >= 2 else { return nil }

        let spread = (tiers.max()?.rawValue ?? 0) - (tiers.min()?.rawValue ?? 0)

        switch spread {
        case 0: return .symmetrical
        case 1: return .balanced
        case 2: return .uneven
        case 3: return .skewed
        default: return .lopsided
        }
    }

    // MARK: - Balance Trend

    enum BalanceTrend {
        case declining, dipping, stable, rising, surging

        static func from(delta: Double) -> BalanceTrend {
            switch delta {
            case ...(-0.05): return .declining
            case -0.05 ..< -0.02: return .dipping
            case -0.02 ..< 0.02: return .stable
            case 0.02 ..< 0.05: return .rising
            default: return .surging
            }
        }

        var systemImage: String {
            switch self {
            case .declining, .dipping: return "arrowtriangle.down.fill"
            case .stable: return "minus"
            case .rising, .surging: return "arrowtriangle.up.fill"
            }
        }

        var color: Color {
            switch self {
            case .declining: return .trendDeclining
            case .dipping: return .trendDipping
            case .stable: return .trendStable
            case .rising: return .trendRising
            case .surging: return .trendSurging
            }
        }

        var label: String {
            switch self {
            case .declining: return "Declining"
            case .dipping: return "Dipping"
            case .stable: return "Stable"
            case .rising: return "Rising"
            case .surging: return "Surging"
            }
        }
    }

    struct ExerciseBalance: Identifiable {
        let id: UUID
        let exerciseName: String
        let icon: String
        let current1RM: Double?
        let balanceScore: Double?
        let balanceColor: Color
        let trendDelta: Double?
    }

    static func strengthBalance(from estimated1RMs: [Estimated1RM]) -> [ExerciseBalance] {
        let fundamentalIds = Set(fundamentalExercises.map(\.id))

        // Group by exercise, take most recent e1RM for each
        let grouped = Dictionary(grouping: estimated1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }) { $0.exercise!.id }

        var latestByExercise: [UUID: Double] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                latestByExercise[exerciseId] = mostRecent.value
            }
        }

        // Normalize each by ratio coefficient
        var normalizedValues: [(exercise: FundamentalExercise, normalized: Double, raw: Double)] = []
        for exercise in fundamentalExercises {
            if let e1rm = latestByExercise[exercise.id] {
                normalizedValues.append((exercise, e1rm / exercise.ratioCoefficient, e1rm))
            }
        }

        // Need at least 2 exercises with data
        guard normalizedValues.count >= 2 else {
            return fundamentalExercises.map { ex in
                let raw = latestByExercise[ex.id]
                return ExerciseBalance(
                    id: ex.id,
                    exerciseName: ex.name,
                    icon: ex.icon,
                    current1RM: raw,
                    balanceScore: nil,
                    balanceColor: .gray,
                    trendDelta: nil
                )
            }
        }

        let mean = normalizedValues.map(\.normalized).reduce(0, +) / Double(normalizedValues.count)

        return fundamentalExercises.map { ex in
            if let e1rm = latestByExercise[ex.id] {
                let normalized = e1rm / ex.ratioCoefficient
                let score = normalized / mean
                return ExerciseBalance(
                    id: ex.id,
                    exerciseName: ex.name,
                    icon: ex.icon,
                    current1RM: e1rm,
                    balanceScore: score,
                    balanceColor: Color.balanceColor(for: score),
                    trendDelta: nil
                )
            } else {
                return ExerciseBalance(
                    id: ex.id,
                    exerciseName: ex.name,
                    icon: ex.icon,
                    current1RM: nil,
                    balanceScore: nil,
                    balanceColor: .gray,
                    trendDelta: nil
                )
            }
        }
    }

    // MARK: - Balance Insight

    static func balanceInsight(from balances: [ExerciseBalance]) -> String {
        let scored = balances.filter { $0.balanceScore != nil }
        guard !scored.isEmpty else { return "" }

        let weak = scored.filter { $0.balanceScore! < 0.92 }.map(\.exerciseName)
        let strong = scored.filter { $0.balanceScore! > 1.08 }.map(\.exerciseName)

        if weak.isEmpty && strong.isEmpty {
            return "Your strength is well-proportioned across all lifts."
        }

        var parts: [String] = []

        if !weak.isEmpty {
            let names = weak.joined(separator: " and ")
            parts.append("Your \(names) \(weak.count == 1 ? "is" : "are") relatively weaker compared to your other lifts")
        }

        if !strong.isEmpty {
            let names = strong.joined(separator: " and ")
            if weak.isEmpty {
                parts.append("Your \(names) \(strong.count == 1 ? "is a relative strength" : "are relative strengths")")
            } else {
                parts.append("while your \(names) \(strong.count == 1 ? "is a relative strength" : "are relative strengths")")
            }
        }

        return parts.joined(separator: ", ") + "."
    }

    // MARK: - Strength Balance With Trend

    struct BalanceTrendResult {
        let balances: [ExerciseBalance]
        let trendDaysUsed: Int?
    }

    static func strengthBalanceWithTrend(from estimated1RMs: [Estimated1RM], trendDays: Int = 30, fallbackDays: Int = 7) -> BalanceTrendResult {
        let current = strengthBalance(from: estimated1RMs)

        let primaryCutoff = Calendar.current.date(byAdding: .day, value: -trendDays, to: Date())!
        let primaryRecords = estimated1RMs.filter { $0.createdAt <= primaryCutoff }
        let primaryHistorical = strengthBalance(from: primaryRecords)
        let hasPrimaryData = primaryHistorical.contains { $0.balanceScore != nil }

        let historical: [ExerciseBalance]
        let daysUsed: Int?

        if hasPrimaryData {
            historical = primaryHistorical
            daysUsed = trendDays
        } else {
            let fallbackCutoff = Calendar.current.date(byAdding: .day, value: -fallbackDays, to: Date())!
            let fallbackRecords = estimated1RMs.filter { $0.createdAt <= fallbackCutoff }
            let fallbackHistorical = strengthBalance(from: fallbackRecords)
            if fallbackHistorical.contains(where: { $0.balanceScore != nil }) {
                historical = fallbackHistorical
                daysUsed = fallbackDays
            } else {
                historical = []
                daysUsed = nil
            }
        }

        // Build lookup of historical scores by exercise id
        let historicalById = Dictionary(uniqueKeysWithValues: historical.compactMap { ex -> (UUID, Double)? in
            guard let score = ex.balanceScore else { return nil }
            return (ex.id, score)
        })

        let balances = current.map { exercise in
            let trendDelta: Double?
            if let currentScore = exercise.balanceScore, let historicalScore = historicalById[exercise.id] {
                trendDelta = currentScore - historicalScore
            } else {
                trendDelta = nil
            }
            return ExerciseBalance(
                id: exercise.id,
                exerciseName: exercise.exerciseName,
                icon: exercise.icon,
                current1RM: exercise.current1RM,
                balanceScore: exercise.balanceScore,
                balanceColor: exercise.balanceColor,
                trendDelta: trendDelta
            )
        }

        return BalanceTrendResult(balances: balances, trendDaysUsed: daysUsed)
    }

    static func balanceTrendInsight(from balances: [ExerciseBalance], trendDays: Int?) -> String? {
        let withTrend = balances.filter { $0.trendDelta != nil }
        guard !withTrend.isEmpty, let days = trendDays else { return nil }

        let period = days >= 30 ? "the past 30 days" : "the past week"

        let allStable = withTrend.allSatisfy { abs($0.trendDelta!) < 0.02 }
        if allStable {
            return "Your balance has been stable over \(period)."
        }

        // Find biggest mover by absolute delta
        let biggestMover = withTrend.max(by: { abs($0.trendDelta!) < abs($1.trendDelta!) })!
        let direction = biggestMover.trendDelta! > 0 ? "improved" : "declined"
        return "Over \(period), \(biggestMover.exerciseName) has \(direction) the most in balance."
    }

    // MARK: - Weekly Strength Balance History

    struct WeeklyBalanceSnapshot: Identifiable {
        let id = UUID()
        let weekStart: Date
        let tierSpread: Int          // 0 = Symmetrical, 4+ = Lopsided
        let category: BalanceCategory
    }

    /// Computes weekly balance category snapshots over the past N weeks.
    /// At each week boundary, uses the latest e1RM up to that point for each fundamental exercise.
    static func weeklyBalanceHistory(
        from estimated1RMs: [Estimated1RM],
        bodyweight: Double,
        sex: BiologicalSex,
        weeks: Int = 8
    ) -> [WeeklyBalanceSnapshot] {
        let calendar = Calendar.current
        let now = Date()
        let fundamentalIds = Set(fundamentalExercises.map(\.id))
        let relevant = estimated1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }

        var snapshots: [WeeklyBalanceSnapshot] = []

        for weeksAgo in (0..<weeks).reversed() {
            guard let weekEnd = calendar.date(byAdding: .weekOfYear, value: -weeksAgo, to: now) else { continue }
            let weekStart = calendar.startOfWeek(for: weekEnd)

            // Get latest e1RM for each exercise up to this week's end
            let recordsUpToWeek = relevant.filter { $0.createdAt <= weekEnd }
            let grouped = Dictionary(grouping: recordsUpToWeek) { $0.exercise!.id }

            var tiers: [StrengthTier] = []
            for exercise in fundamentalExercises {
                guard let records = grouped[exercise.id],
                      let latest = records.max(by: { $0.createdAt < $1.createdAt }) else { continue }
                let tier = StrengthTierData.tierForExercise(
                    name: exercise.name,
                    e1rm: latest.value,
                    bodyweight: bodyweight,
                    sex: sex
                )
                tiers.append(tier)
            }

            guard tiers.count >= 2 else { continue }

            let spread = (tiers.max()?.rawValue ?? 0) - (tiers.min()?.rawValue ?? 0)
            let category: BalanceCategory
            switch spread {
            case 0: category = .symmetrical
            case 1: category = .balanced
            case 2: category = .uneven
            case 3: category = .skewed
            default: category = .lopsided
            }

            snapshots.append(WeeklyBalanceSnapshot(weekStart: weekStart, tierSpread: spread, category: category))
        }

        return snapshots
    }

    // MARK: - Movement Ratios

    struct MovementRatio {
        let pushVolume: Double
        let pullVolume: Double
        let hingeVolume: Double
        let squatVolume: Double
        let coreVolume: Double

        var upperVolume: Double { pushVolume + pullVolume }
        var lowerVolume: Double { hingeVolume + squatVolume }

        /// 0.0 = all pull, 0.5 = balanced, 1.0 = all push
        var pushPullRatio: Double {
            let total = pushVolume + pullVolume
            guard total > 0 else { return 0.5 }
            return pushVolume / total
        }

        /// 0.0 = all lower, 0.5 = balanced, 1.0 = all upper
        var upperLowerRatio: Double {
            let total = upperVolume + lowerVolume
            guard total > 0 else { return 0.5 }
            return upperVolume / total
        }

        var totalVolume: Double { pushVolume + pullVolume + hingeVolume + squatVolume + coreVolume }
    }

    static func movementRatios(from sets: [LiftSet], days: Int = 30) -> MovementRatio {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .day, value: -days, to: Date()) else {
            return MovementRatio(pushVolume: 0, pullVolume: 0, hingeVolume: 0, squatVolume: 0, coreVolume: 0)
        }

        let recent = sets.filter { $0.createdAt >= cutoff && !$0.deleted }

        var push = 0.0, pull = 0.0, hinge = 0.0, squat = 0.0, core = 0.0

        for set in recent {
            let volume = set.weight * Double(set.reps)
            guard let movementType = set.exercise?.movementType else { continue }
            switch movementType.lowercased() {
            case "push": push += volume
            case "pull": pull += volume
            case "hinge": hinge += volume
            case "squat": squat += volume
            case "core": core += volume
            default: break
            }
        }

        return MovementRatio(pushVolume: push, pullVolume: pull, hingeVolume: hinge, squatVolume: squat, coreVolume: core)
    }

    static func weeklyMovementRatios(from sets: [LiftSet], weeks: Int = 8) -> [(weekStart: Date, ratio: MovementRatio)] {
        let calendar = Calendar.current
        guard let cutoff = calendar.date(byAdding: .weekOfYear, value: -weeks, to: Date()) else {
            return []
        }

        let recent = sets.filter { $0.createdAt >= cutoff && !$0.deleted }
        let grouped = Dictionary(grouping: recent) { set -> Date in
            calendar.startOfWeek(for: set.createdAt)
        }

        var result: [(weekStart: Date, ratio: MovementRatio)] = []
        for (weekStart, weekSets) in grouped {
            var push = 0.0, pull = 0.0, hinge = 0.0, squat = 0.0, core = 0.0
            for set in weekSets {
                let volume = set.weight * Double(set.reps)
                guard let movementType = set.exercise?.movementType else { continue }
                switch movementType.lowercased() {
                case "push": push += volume
                case "pull": pull += volume
                case "hinge": hinge += volume
                case "squat": squat += volume
                case "core": core += volume
                default: break
                }
            }
            result.append((weekStart: weekStart, ratio: MovementRatio(pushVolume: push, pullVolume: pull, hingeVolume: hinge, squatVolume: squat, coreVolume: core)))
        }

        return result.sorted { $0.weekStart < $1.weekStart }
    }

    // MARK: - Strength Tier Assessment

    struct StrengthTierResult {
        let overallTier: StrengthTier
        let exerciseTiers: [(exercise: FundamentalExercise, e1rm: Double?, tier: StrengthTier)]
        let limitingExercise: FundamentalExercise
    }

    static func strengthTierAssessment(
        from estimated1RMs: [Estimated1RM],
        bodyweight: Double,
        biologicalSex: String
    ) -> StrengthTierResult {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else {
            // Unknown sex — default everything to none
            let tiers = fundamentalExercises.map { ($0, nil as Double?, StrengthTier.none) }
            return StrengthTierResult(
                overallTier: .none,
                exerciseTiers: tiers,
                limitingExercise: fundamentalExercises[0]
            )
        }

        let fundamentalIds = Set(fundamentalExercises.map(\.id))

        // Group by exercise, take most recent e1RM for each
        let grouped = Dictionary(grouping: estimated1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }) { $0.exercise!.id }

        var latestByExercise: [UUID: Double] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                latestByExercise[exerciseId] = mostRecent.value
            }
        }

        // Determine tier for each exercise
        var exerciseTiers: [(exercise: FundamentalExercise, e1rm: Double?, tier: StrengthTier)] = []
        var lowestTier: StrengthTier = .legend
        var limitingExercise = fundamentalExercises[0]

        for exercise in fundamentalExercises {
            if let e1rm = latestByExercise[exercise.id] {
                let tier = StrengthTierData.tierForExercise(
                    name: exercise.name,
                    e1rm: e1rm,
                    bodyweight: bodyweight,
                    sex: sex
                )
                exerciseTiers.append((exercise, e1rm, tier))
                if tier < lowestTier {
                    lowestTier = tier
                    limitingExercise = exercise
                }
            } else {
                // No data = None (no sets logged yet)
                exerciseTiers.append((exercise, nil, .none))
                if StrengthTier.none < lowestTier {
                    lowestTier = .none
                    limitingExercise = exercise
                }
            }
        }

        return StrengthTierResult(
            overallTier: lowestTier,
            exerciseTiers: exerciseTiers,
            limitingExercise: limitingExercise
        )
    }

    /// Hybrid overload: uses Estimated1RM records as primary source, falls back to exercise.currentE1RMLocalCache
    /// for exercises not present in the recent query window.
    static func strengthTierAssessment(
        from estimated1RMs: [Estimated1RM],
        exercises: [Exercise],
        bodyweight: Double,
        biologicalSex: String
    ) -> StrengthTierResult {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else {
            let tiers = fundamentalExercises.map { ($0, nil as Double?, StrengthTier.none) }
            return StrengthTierResult(overallTier: .none, exerciseTiers: tiers, limitingExercise: fundamentalExercises[0])
        }

        let fundamentalIds = Set(fundamentalExercises.map(\.id))

        // Primary: latest e1RM from Estimated1RM records per exercise
        let grouped = Dictionary(grouping: estimated1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }) { $0.exercise!.id }

        var latestByExercise: [UUID: Double] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                latestByExercise[exerciseId] = mostRecent.value
            }
        }

        // Fallback: exercise.currentE1RMLocalCache
        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.compactMap { ex -> (UUID, Exercise)? in
            (ex.id, ex)
        })

        var exerciseTiers: [(exercise: FundamentalExercise, e1rm: Double?, tier: StrengthTier)] = []
        var lowestTier: StrengthTier = .legend
        var limitingExercise = fundamentalExercises[0]

        for fundamental in fundamentalExercises {
            // Try authoritative source first, then cache fallback
            let e1rm = latestByExercise[fundamental.id] ?? exerciseById[fundamental.id]?.currentE1RMLocalCache
            if let e1rm {
                let tier = StrengthTierData.tierForExercise(name: fundamental.name, e1rm: e1rm, bodyweight: bodyweight, sex: sex)
                exerciseTiers.append((fundamental, e1rm, tier))
                if tier < lowestTier {
                    lowestTier = tier
                    limitingExercise = fundamental
                }
            } else {
                exerciseTiers.append((fundamental, nil, .none))
                if StrengthTier.none < lowestTier {
                    lowestTier = .none
                    limitingExercise = fundamental
                }
            }
        }

        return StrengthTierResult(overallTier: lowestTier, exerciseTiers: exerciseTiers, limitingExercise: limitingExercise)
    }

    // MARK: - Next Focus Exercise

    /// Returns the fundamental exercise the user should train next, based on tier progress and recency.
    /// Returns nil if all exercises are at Legend tier.
    static func nextFocusExercise(
        exerciseTiers: [(exercise: FundamentalExercise, e1rm: Double?, tier: StrengthTier)],
        lastTrainedDates: [UUID: Date],
        bodyweight: Double,
        sex: BiologicalSex
    ) -> FundamentalExercise? {
        // If all at Legend, nothing to suggest
        guard !exerciseTiers.allSatisfy({ $0.tier == .legend }) else { return nil }

        let now = Date()
        var bestExercise: FundamentalExercise?
        var bestScore = -1.0

        for entry in exerciseTiers {
            let exercise = entry.exercise
            let tier = entry.tier

            // tierScore: base from tier rank, refined by within-tier progress
            let tierBase: Double
            switch tier {
            case .none:         tierBase = 1.0
            case .novice:       tierBase = 1.0
            case .beginner:     tierBase = 0.8
            case .intermediate: tierBase = 0.6
            case .advanced:     tierBase = 0.4
            case .elite:        tierBase = 0.2
            case .legend:       tierBase = 0.0
            }

            var withinTierProgress = 0.0
            if let e1rm = entry.e1rm, tier != .legend {
                let currentMin = StrengthTierData.currentTierMinimum(
                    name: exercise.name, tier: tier, bodyweight: bodyweight, sex: sex
                )
                if let nextMin = StrengthTierData.nextTierMinimum(
                    name: exercise.name, currentTier: tier, bodyweight: bodyweight, sex: sex
                ) {
                    let range = nextMin - currentMin
                    if range > 0 {
                        withinTierProgress = min(1.0, max(0.0, (e1rm - currentMin) / range))
                    }
                }
            }

            let tierScore = max(0.0, tierBase - withinTierProgress * 0.2)

            // recencyScore: days since last trained, /14, capped at 1.0
            let recencyScore: Double
            if let lastDate = lastTrainedDates[exercise.id] {
                let daysSince = now.timeIntervalSince(lastDate) / 86400.0
                recencyScore = min(1.0, max(0.0, daysSince / 14.0))
            } else {
                recencyScore = 1.0
            }

            let score = 0.7 * tierScore + 0.3 * recencyScore

            if score > bestScore {
                bestScore = score
                bestExercise = exercise
            }
        }

        return bestExercise
    }

    // MARK: - Strength Milestones (Tier-Based)

    struct TierMilestone: Identifiable {
        let id = UUID()
        let exerciseName: String
        let exerciseIcon: String
        let targetLbs: Double
        let targetLabel: String
        let isAbsoluteTarget: Bool // true when targetLabel is in lbs (not BW-relative)
        let currentE1RMLocalCache: Double
        let achieved: Bool
        let progress: Double
    }

    struct TierMilestoneBatch: Identifiable {
        let id: Int
        let tier: StrengthTier
        let milestones: [TierMilestone]
        let allAchieved: Bool
        let achievedCount: Int
    }

    struct MilestoneResult {
        let batches: [TierMilestoneBatch]
        let currentTier: StrengthTier
        let achievedCount: Int
        let totalCount: Int
    }

    static func strengthMilestones(
        from estimated1RMs: [Estimated1RM],
        bodyweight: Double,
        biologicalSex: String
    ) -> MilestoneResult? {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return nil }

        let fundamentalIds = Set(fundamentalExercises.map(\.id))

        // Get latest e1RM per fundamental exercise
        let grouped = Dictionary(grouping: estimated1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }) { $0.exercise!.id }

        var latestByExercise: [UUID: Double] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                latestByExercise[exerciseId] = mostRecent.value
            }
        }

        // All tiers including Novice (easy starter milestones)
        let tiers: [StrengthTier] = [.novice, .beginner, .intermediate, .advanced, .elite, .legend]

        var batches: [TierMilestoneBatch] = []
        var overallAchieved = 0
        var overallTotal = 0

        for tier in tiers {
            var milestones: [TierMilestone] = []

            for exercise in fundamentalExercises {
                guard let threshold = StrengthTierData.thresholds[exercise.name]?[sex]?[tier] else { continue }

                let targetLbs: Double
                let targetLabel: String

                if tier == .novice {
                    // Novice milestone = log at least one set (binary achievement)
                    let beginnerMin = StrengthTierData.thresholds[exercise.name]?[sex]?[.beginner]?.min ?? 0
                    targetLbs = beginnerMin * bodyweight
                    targetLabel = "≥1 set"
                } else if threshold.isAbsolute {
                    targetLbs = threshold.min
                    targetLabel = "\(Int(threshold.min))"
                } else {
                    targetLbs = threshold.min * bodyweight
                    // Format multiplier: "1× BW", "1.25× BW", "0.5× BW"
                    if threshold.min == floor(threshold.min) {
                        targetLabel = "\(Int(threshold.min))× BW"
                    } else {
                        targetLabel = "\(String(format: "%g", threshold.min))× BW"
                    }
                }

                let current = latestByExercise[exercise.id] ?? 0
                let achieved: Bool
                let progress: Double
                if tier == .novice {
                    // Binary: achieved if any set has been logged (e1RM > 0)
                    achieved = current > 0
                    progress = current > 0 ? 1.0 : 0.0
                } else {
                    achieved = targetLbs > 0 && current >= targetLbs
                    progress = targetLbs > 0 ? min(current / targetLbs, 1.0) : 0
                }

                milestones.append(TierMilestone(
                    exerciseName: exercise.name,
                    exerciseIcon: exercise.icon,
                    targetLbs: targetLbs,
                    targetLabel: targetLabel,
                    isAbsoluteTarget: threshold.isAbsolute,
                    currentE1RMLocalCache: current,
                    achieved: achieved,
                    progress: progress
                ))
            }

            let batchAchieved = milestones.filter(\.achieved).count
            overallAchieved += batchAchieved
            overallTotal += milestones.count

            batches.append(TierMilestoneBatch(
                id: tier.rawValue,
                tier: tier,
                milestones: milestones,
                allAchieved: batchAchieved == milestones.count,
                achievedCount: batchAchieved
            ))
        }

        // Overall tier = lowest tier across all 5 exercises (same as StrengthTierWidget logic)
        var lowestTier: StrengthTier = .legend
        for exercise in fundamentalExercises {
            let exerciseTier: StrengthTier
            if let current = latestByExercise[exercise.id] {
                exerciseTier = StrengthTierData.tierForExercise(
                    name: exercise.name,
                    e1rm: current,
                    bodyweight: bodyweight,
                    sex: sex
                )
            } else {
                exerciseTier = .none
            }
            if exerciseTier < lowestTier {
                lowestTier = exerciseTier
            }
        }

        return MilestoneResult(
            batches: batches,
            currentTier: lowestTier,
            achievedCount: overallAchieved,
            totalCount: overallTotal
        )
    }

    /// Lightweight overload that reads `exercise.currentE1RMLocalCache` instead of iterating Estimated1RM arrays.
    static func strengthMilestones(
        fromExercises exercises: [Exercise],
        bodyweight: Double,
        biologicalSex: String
    ) -> MilestoneResult? {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return nil }

        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.compactMap { ex -> (UUID, Exercise)? in
            (ex.id, ex)
        })

        var latestByExercise: [UUID: Double] = [:]
        for fundamental in fundamentalExercises {
            if let ex = exerciseById[fundamental.id], let e1rm = ex.currentE1RMLocalCache {
                latestByExercise[fundamental.id] = e1rm
            }
        }

        let tiers: [StrengthTier] = [.novice, .beginner, .intermediate, .advanced, .elite, .legend]

        var batches: [TierMilestoneBatch] = []
        var overallAchieved = 0
        var overallTotal = 0

        for tier in tiers {
            var milestones: [TierMilestone] = []

            for exercise in fundamentalExercises {
                guard let threshold = StrengthTierData.thresholds[exercise.name]?[sex]?[tier] else { continue }

                let targetLbs: Double
                let targetLabel: String

                if tier == .novice {
                    let beginnerMin = StrengthTierData.thresholds[exercise.name]?[sex]?[.beginner]?.min ?? 0
                    targetLbs = beginnerMin * bodyweight
                    targetLabel = "≥1 set"
                } else if threshold.isAbsolute {
                    targetLbs = threshold.min
                    targetLabel = "\(Int(threshold.min))"
                } else {
                    targetLbs = threshold.min * bodyweight
                    if threshold.min == floor(threshold.min) {
                        targetLabel = "\(Int(threshold.min))× BW"
                    } else {
                        targetLabel = "\(String(format: "%g", threshold.min))× BW"
                    }
                }

                let current = latestByExercise[exercise.id] ?? 0
                let achieved: Bool
                let progress: Double
                if tier == .novice {
                    achieved = current > 0
                    progress = current > 0 ? 1.0 : 0.0
                } else {
                    achieved = targetLbs > 0 && current >= targetLbs
                    progress = targetLbs > 0 ? min(current / targetLbs, 1.0) : 0
                }

                milestones.append(TierMilestone(
                    exerciseName: exercise.name,
                    exerciseIcon: exercise.icon,
                    targetLbs: targetLbs,
                    targetLabel: targetLabel,
                    isAbsoluteTarget: threshold.isAbsolute,
                    currentE1RMLocalCache: current,
                    achieved: achieved,
                    progress: progress
                ))
            }

            let batchAchieved = milestones.filter(\.achieved).count
            overallAchieved += batchAchieved
            overallTotal += milestones.count

            batches.append(TierMilestoneBatch(
                id: tier.rawValue,
                tier: tier,
                milestones: milestones,
                allAchieved: batchAchieved == milestones.count,
                achievedCount: batchAchieved
            ))
        }

        var lowestTier: StrengthTier = .legend
        for exercise in fundamentalExercises {
            let exerciseTier: StrengthTier
            if let current = latestByExercise[exercise.id] {
                exerciseTier = StrengthTierData.tierForExercise(
                    name: exercise.name,
                    e1rm: current,
                    bodyweight: bodyweight,
                    sex: sex
                )
            } else {
                exerciseTier = .none
            }
            if exerciseTier < lowestTier {
                lowestTier = exerciseTier
            }
        }

        return MilestoneResult(
            batches: batches,
            currentTier: lowestTier,
            achievedCount: overallAchieved,
            totalCount: overallTotal
        )
    }

    /// Hybrid overload: uses Estimated1RM as primary, falls back to exercise.currentE1RMLocalCache.
    static func strengthMilestones(
        from estimated1RMs: [Estimated1RM],
        exercises: [Exercise],
        bodyweight: Double,
        biologicalSex: String
    ) -> MilestoneResult? {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return nil }

        let fundamentalIds = Set(fundamentalExercises.map(\.id))

        // Primary: latest e1RM from Estimated1RM records per exercise
        let grouped = Dictionary(grouping: estimated1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }) { $0.exercise!.id }

        var latestByExercise: [UUID: Double] = [:]
        for (exerciseId, records) in grouped {
            if let mostRecent = records.max(by: { $0.createdAt < $1.createdAt }) {
                latestByExercise[exerciseId] = mostRecent.value
            }
        }

        // Fallback: exercise.currentE1RMLocalCache
        let exerciseById = Dictionary(uniqueKeysWithValues: exercises.compactMap { ex -> (UUID, Exercise)? in
            (ex.id, ex)
        })
        for fundamental in fundamentalExercises where latestByExercise[fundamental.id] == nil {
            if let ex = exerciseById[fundamental.id], let e1rm = ex.currentE1RMLocalCache {
                latestByExercise[fundamental.id] = e1rm
            }
        }

        let tiers: [StrengthTier] = [.novice, .beginner, .intermediate, .advanced, .elite, .legend]

        var batches: [TierMilestoneBatch] = []
        var overallAchieved = 0
        var overallTotal = 0

        for tier in tiers {
            var milestones: [TierMilestone] = []

            for exercise in fundamentalExercises {
                guard let threshold = StrengthTierData.thresholds[exercise.name]?[sex]?[tier] else { continue }

                let targetLbs: Double
                let targetLabel: String

                if tier == .novice {
                    let beginnerMin = StrengthTierData.thresholds[exercise.name]?[sex]?[.beginner]?.min ?? 0
                    targetLbs = beginnerMin * bodyweight
                    targetLabel = "≥1 set"
                } else if threshold.isAbsolute {
                    targetLbs = threshold.min
                    targetLabel = "\(Int(threshold.min))"
                } else {
                    targetLbs = threshold.min * bodyweight
                    if threshold.min == floor(threshold.min) {
                        targetLabel = "\(Int(threshold.min))× BW"
                    } else {
                        targetLabel = "\(String(format: "%g", threshold.min))× BW"
                    }
                }

                let current = latestByExercise[exercise.id] ?? 0
                let achieved: Bool
                let progress: Double
                if tier == .novice {
                    achieved = current > 0
                    progress = current > 0 ? 1.0 : 0.0
                } else {
                    achieved = targetLbs > 0 && current >= targetLbs
                    progress = targetLbs > 0 ? min(current / targetLbs, 1.0) : 0
                }

                milestones.append(TierMilestone(
                    exerciseName: exercise.name,
                    exerciseIcon: exercise.icon,
                    targetLbs: targetLbs,
                    targetLabel: targetLabel,
                    isAbsoluteTarget: threshold.isAbsolute,
                    currentE1RMLocalCache: current,
                    achieved: achieved,
                    progress: progress
                ))
            }

            let batchAchieved = milestones.filter(\.achieved).count
            overallAchieved += batchAchieved
            overallTotal += milestones.count

            batches.append(TierMilestoneBatch(
                id: tier.rawValue,
                tier: tier,
                milestones: milestones,
                allAchieved: batchAchieved == milestones.count,
                achievedCount: batchAchieved
            ))
        }

        var lowestTier: StrengthTier = .legend
        for exercise in fundamentalExercises {
            let exerciseTier: StrengthTier
            if let current = latestByExercise[exercise.id] {
                exerciseTier = StrengthTierData.tierForExercise(
                    name: exercise.name,
                    e1rm: current,
                    bodyweight: bodyweight,
                    sex: sex
                )
            } else {
                exerciseTier = .none
            }
            if exerciseTier < lowestTier {
                lowestTier = exerciseTier
            }
        }

        return MilestoneResult(
            batches: batches,
            currentTier: lowestTier,
            achievedCount: overallAchieved,
            totalCount: overallTotal
        )
    }

    // MARK: - Exercise Recency

    struct ExerciseRecency: Identifiable {
        let id = UUID()
        let exerciseName: String
        let daysSinceLastSet: Int? // nil = no sets in last 30 days
    }

    static func exerciseRecency(from sets: [LiftSet], days: Int = 30) -> [ExerciseRecency] {
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
