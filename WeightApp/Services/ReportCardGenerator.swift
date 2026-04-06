//
//  ReportCardGenerator.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/18/26.
//

import UIKit
import SwiftUI
import SwiftData

// MARK: - Data Models

struct ExerciseReportData {
    let name: String
    let icon: String
    let currentE1RMLocalCache: Double?
    let firstE1RM: Double?
    let tier: StrengthTier
    let bwRatio: Double? // e1RM / bodyweight
    let tierProgress: Double? // 0..1 progress within current tier toward next

    var delta: Double? {
        guard let current = currentE1RMLocalCache, let first = firstE1RM else { return nil }
        let diff = current - first
        return diff == 0 ? nil : diff
    }
}

struct IntensityBreakdown {
    let easyPct: Double
    let moderatePct: Double
    let hardPct: Double
    let redlinePct: Double
    let prPct: Double
}

struct ReportCardData {
    let dateRangeStart: Date
    let dateRangeEnd: Date
    let overallTier: StrengthTier
    let previousOverallTier: StrengthTier
    let exercises: [ExerciseReportData]
    let totalPRs: Int
    let totalSetsLogged: Int
    let totalVolume: Double
    let trainingWeeks: Int
    let trainingDays: Int
    let milestonesAchieved: Int
    let milestonesTotal: Int
    let balanceCategory: TrendsCalculator.BalanceCategory?
    let intensity: IntensityBreakdown
    let avgWeeklyVolume: Double
    let bodyweight: Double
}

// MARK: - Generator

@MainActor
enum ReportCardGenerator {

    static func generate(modelContext: ModelContext, bodyweight: Double, biologicalSex: String, weightUnit: WeightUnit = .lbs) -> UIImage? {
        let setsDescriptor = FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let allSets = try? modelContext.fetch(setsDescriptor),
              let allE1RMs = try? modelContext.fetch(e1rmDescriptor),
              !allSets.isEmpty else {
            return nil
        }

        let data = buildReportData(
            allSets: allSets,
            allE1RMs: allE1RMs,
            bodyweight: bodyweight,
            biologicalSex: biologicalSex
        )

        let view = TrainingReportCardView(data: data, weightUnit: weightUnit)
            .frame(width: 360, height: 780)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }

    private static func buildReportData(
        allSets: [LiftSet],
        allE1RMs: [Estimated1RM],
        bodyweight: Double,
        biologicalSex: String
    ) -> ReportCardData {
        let sex = BiologicalSex(rawValue: biologicalSex) ?? .male
        let fundamentalIds = Set(TrendsCalculator.fundamentalExercises.map(\.id))

        // Group e1RMs by exercise
        let grouped = Dictionary(grouping: allE1RMs.filter { rec in
            guard let eid = rec.exercise?.id else { return false }
            return fundamentalIds.contains(eid)
        }) { $0.exercise!.id }

        // Build per-exercise data
        var exercises: [ExerciseReportData] = []
        var previousTiers: [StrengthTier] = []

        for fundamental in TrendsCalculator.fundamentalExercises {
            let records = grouped[fundamental.id] ?? []
            let sorted = records.sorted { $0.createdAt < $1.createdAt }

            let firstE1RM = sorted.first?.value
            let currentE1RMLocalCache = sorted.last?.value

            let currentTier: StrengthTier
            if let e1rm = currentE1RMLocalCache {
                currentTier = StrengthTierData.tierForExercise(
                    name: fundamental.name, e1rm: e1rm, bodyweight: bodyweight, sex: sex
                )
            } else {
                currentTier = .novice
            }

            let previousTier: StrengthTier
            if let e1rm = firstE1RM {
                previousTier = StrengthTierData.tierForExercise(
                    name: fundamental.name, e1rm: e1rm, bodyweight: bodyweight, sex: sex
                )
            } else {
                previousTier = .novice
            }
            previousTiers.append(previousTier)

            let bwRatio = currentE1RMLocalCache.map { $0 / bodyweight }

            // Tier progress (0..1 within current tier toward next)
            let progress: Double? = {
                guard let e1rm = currentE1RMLocalCache, currentTier != .legend else { return currentTier == .legend ? 1.0 : nil }
                let currentMin = StrengthTierData.currentTierMinimum(
                    name: fundamental.name, tier: currentTier, bodyweight: bodyweight, sex: sex
                )
                guard let nextMin = StrengthTierData.nextTierMinimum(
                    name: fundamental.name, currentTier: currentTier, bodyweight: bodyweight, sex: sex
                ) else { return nil }
                let range = nextMin - currentMin
                guard range > 0 else { return 1.0 }
                return min(max((e1rm - currentMin) / range, 0), 1.0)
            }()

            exercises.append(ExerciseReportData(
                name: fundamental.name,
                icon: fundamental.icon,
                currentE1RMLocalCache: currentE1RMLocalCache,
                firstE1RM: firstE1RM,
                tier: currentTier,
                bwRatio: bwRatio,
                tierProgress: progress
            ))
        }

        // Current overall tier
        let currentTierResult = TrendsCalculator.strengthTierAssessment(
            from: allE1RMs, bodyweight: bodyweight, biologicalSex: biologicalSex
        )

        // Previous overall tier
        let previousOverallTier = previousTiers.min() ?? .novice

        // PR count
        let prEvents = TrendsCalculator.prTimeline(from: allSets)

        // Volume
        let totalVolume = allSets.reduce(0.0) { $0 + $1.weight * Double($1.reps) }

        // Date range
        let earliestDate = allSets.first?.createdAt ?? Date()
        let now = Date()

        // Training weeks
        let weeks = max(1, Calendar.current.dateComponents([.weekOfYear], from: earliestDate, to: now).weekOfYear ?? 0)

        // Training days (unique days with sets)
        let uniqueDays = Set(allSets.map { Calendar.current.startOfDay(for: $0.createdAt) })

        // Milestones
        let milestoneResult = TrendsCalculator.strengthMilestones(
            from: allE1RMs, bodyweight: bodyweight, biologicalSex: biologicalSex
        )

        // Balance
        let balances = TrendsCalculator.strengthBalance(from: allE1RMs)
        let balanceCat = TrendsCalculator.balanceCategory(from: balances, bodyweight: bodyweight, sex: sex)

        // Intensity distribution (all-time)
        let dist = TrendsCalculator.intensityDistribution(from: allSets, days: 99999)
        let total = max(1, Double(dist.total))
        let intensity = IntensityBreakdown(
            easyPct: Double(dist.easy) / total,
            moderatePct: Double(dist.moderate) / total,
            hardPct: Double(dist.hard) / total,
            redlinePct: Double(dist.redline) / total,
            prPct: Double(dist.pr) / total
        )

        // Avg weekly volume
        let avgWeekly = totalVolume / Double(weeks)

        return ReportCardData(
            dateRangeStart: earliestDate,
            dateRangeEnd: now,
            overallTier: currentTierResult.overallTier,
            previousOverallTier: previousOverallTier,
            exercises: exercises,
            totalPRs: prEvents.count,
            totalSetsLogged: allSets.count,
            totalVolume: totalVolume,
            trainingWeeks: weeks,
            trainingDays: uniqueDays.count,
            milestonesAchieved: milestoneResult?.achievedCount ?? 0,
            milestonesTotal: milestoneResult?.totalCount ?? 30,
            balanceCategory: balanceCat,
            intensity: intensity,
            avgWeeklyVolume: avgWeekly,
            bodyweight: bodyweight
        )
    }
}
