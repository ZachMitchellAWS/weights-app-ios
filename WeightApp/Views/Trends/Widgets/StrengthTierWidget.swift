//
//  StrengthTierWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/12/26.
//

import SwiftUI

struct StrengthTierWidget: View {
    let exercises: [Exercise]
    @Bindable var userProperties: UserProperties
    var isPremium: Bool = true
    @Binding var showUpsell: Bool

    private var biologicalSex: String { userProperties.biologicalSex ?? "male" }
    private var bodyweight: Double { userProperties.bodyweight ?? 0 }

    @State private var tierResult: TrendsCalculator.StrengthTierResult = TrendsCalculator.strengthTierAssessment(
        fromExercises: [],
        bodyweight: 0,
        biologicalSex: "male"
    )

    var body: some View {
        if isPremium {
            VStack(alignment: .leading, spacing: 12) {
                resultsView(tierResult)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(white: 0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            // .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.4), lineWidth: 1.5))
            .task(id: exercises.compactMap(\.currentE1RM).count) {
                tierResult = TrendsCalculator.strengthTierAssessment(
                    fromExercises: exercises,
                    bodyweight: bodyweight,
                    biologicalSex: biologicalSex
                )
            }
        } else {
            lockedContent
        }
    }

    // MARK: - Locked Content (Free Users)

    private var lockedContent: some View {
        // Fake results view — static, non-interactive
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Text("STRENGTH TIER")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))
                    .tracking(1.2)
                HStack(spacing: 10) {
                    Image("LiftTheBullIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .foregroundStyle(StrengthTier.elite.color)
                    Text("Advanced")
                        .font(.title.weight(.bold))
                        .foregroundStyle(StrengthTier.advanced.color)
                }
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(.white.opacity(0.15))
                    .frame(width: 180, height: 1)
                    .padding(.top, 8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Fake progress bar
            VStack(spacing: 4) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.white.opacity(0.1))
                            .frame(height: 6)
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color.appAccent)
                            .frame(width: geo.size.width * 0.72, height: 6)
                    }
                }
                .frame(height: 6)

                Text("72% to Elite")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.horizontal, 16)

            // Fake exercise rows — each a different tier for maximum color variety
            VStack(spacing: 0) {
                fakeExerciseRow(name: "Squat", lbs: 315, tier: .elite)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Bench Press", lbs: 225, tier: .advanced)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Deadlift", lbs: 405, tier: .legend)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Overhead Press", lbs: 135, tier: .intermediate)
                Divider().background(.white.opacity(0.1))
                fakeExerciseRow(name: "Barbell Rows", lbs: 185, tier: .beginner)
            }

        }
        .padding()
        .premiumLocked(
            title: "Unlock Strength Tiers",
            subtitle: "Discover your strength level across your lifts",
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func fakeExerciseRow(name: String, lbs: Int, tier: StrengthTier) -> some View {
        HStack(spacing: 10) {
            Image("LiftTheBullIcon")
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(StrengthTier.elite.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
                Text("\(lbs) \(userProperties.preferredWeightUnit.label)")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            Spacer()
            Text(tier.title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(tier <= .novice ? .white.opacity(0.6) : tier.color)
                .frame(width: 90)
                .padding(.vertical, 3)
                .background(tier <= .novice ? Color.white.opacity(0.1) : tier.color.opacity(0.15))
                .clipShape(Capsule())
        }
        .padding(.vertical, 8)
    }

    // MARK: - Results View

    @State private var expandedExercises: Set<String> = []

    private func resultsView(_ result: TrendsCalculator.StrengthTierResult) -> some View {
        let isChecklistMode = result.overallTier == .none
        let loggedCount = result.exerciseTiers.filter { $0.e1rm != nil }.count

        return VStack(spacing: 16) {
            // Centered header
            VStack(spacing: 6) {
                Text("STRENGTH TIER")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                if isChecklistMode {
                    Text("Log All 5 Lifts to Unlock")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("\(loggedCount) of 5 exercises logged")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                } else {
                    HStack(spacing: 10) {
                        Image(result.overallTier.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(StrengthTier.elite.color)

                        Text(result.overallTier.title)
                            .font(.title.weight(.bold))
                            .foregroundStyle(result.overallTier.color)
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Progress indicator
            if isChecklistMode {
                HStack(spacing: 12) {
                    ForEach(Array(result.exerciseTiers.enumerated()), id: \.offset) { _, item in
                        Circle()
                            .fill(item.e1rm != nil ? Color.appAccent : .white.opacity(0.15))
                            .overlay(
                                item.e1rm == nil
                                    ? Circle().stroke(.white.opacity(0.3), lineWidth: 1)
                                    : nil
                            )
                            .frame(width: 10, height: 10)
                    }
                }
                .frame(maxWidth: .infinity)
            } else if result.overallTier != .legend {
                let overallProgress = overallTierProgress(result)
                VStack(spacing: 4) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.white.opacity(0.1))
                                .frame(height: 6)
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color.appAccent)
                                .frame(width: geo.size.width * overallProgress, height: 6)
                        }
                    }
                    .frame(height: 6)

                    Text("\(Int(overallProgress * 100))% to \(result.overallTier.next?.title ?? "next tier")")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
                .padding(.horizontal, 16)
            }

            // Exercise rows
            VStack(spacing: 0) {
                ForEach(Array(result.exerciseTiers.enumerated()), id: \.element.exercise.id) { index, item in
                    VStack(spacing: 0) {
                        exerciseRow(item: item, isExpanded: expandedExercises.contains(item.exercise.name), checklistMode: isChecklistMode)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                guard !isChecklistMode else { return }
                                withAnimation(.easeInOut(duration: 0.25)) {
                                    if expandedExercises.contains(item.exercise.name) {
                                        expandedExercises.remove(item.exercise.name)
                                    } else {
                                        expandedExercises.insert(item.exercise.name)
                                    }
                                }
                            }

                        if !isChecklistMode && expandedExercises.contains(item.exercise.name) {
                            exerciseExpansion(for: item.exercise.name)
                                .transition(.opacity)
                        }

                        if index < result.exerciseTiers.count - 1 {
                            Divider()
                                .background(.white.opacity(0.1))
                        }
                    }
                }
            }

            // Static tier legend
            tierLegendBar

            // Explanation
            if isChecklistMode {
                Text("Log at least one set of each exercise above to see your strength tier.")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            } else {
                Text("Your overall tier is determined by your lowest lift. All five exercises must reach a tier for it to apply.")
                    .font(.caption2)
                    .italic()
                    .foregroundStyle(.white.opacity(0.3))
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func exerciseRow(item: (exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier), isExpanded: Bool, checklistMode: Bool = false) -> some View {
        let progress = checklistMode ? nil : progressToNextTier(item: item)

        return HStack(spacing: 10) {
            Image(item.exercise.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 22, height: 22)
                .foregroundStyle(StrengthTier.elite.color)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.exercise.name)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))

                if let e1rm = item.e1rm {
                    HStack(spacing: 0) {
                        Text("\(Int(userProperties.preferredWeightUnit.fromLbs(e1rm))) \(userProperties.preferredWeightUnit.label)")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))

                        if item.tier > .novice, bodyweight > 0 {
                            Text(" | ")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.2))
                            Text(String(format: "%.2f× BW", e1rm / bodyweight))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                } else {
                    Text("No data")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.3))
                }
            }

            Spacer()

            if checklistMode {
                // Checklist status icon
                Image(systemName: item.e1rm != nil ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(item.e1rm != nil ? Color.appAccent : .white.opacity(0.25))
            } else {
                // Progress bar — fixed position before fixed-width pill
                if let progress = progress {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.1))
                            .frame(width: 36, height: 4)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(item.tier.color)
                            .frame(width: 36 * progress, height: 4)
                    }
                    .frame(width: 36, height: 4)
                } else {
                    Spacer().frame(width: 36)
                }

                // Tier pill — fixed width so all rows align
                Text(item.tier.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(item.tier <= .novice ? .white.opacity(0.6) : item.tier.color)
                    .frame(width: 90)
                    .padding(.vertical, 3)
                    .background(
                        item.tier <= .novice ? Color.white.opacity(0.1) : item.tier.color.opacity(0.15)
                    )
                    .clipShape(Capsule())
            }

            // Expand/collapse indicator
            if !checklistMode {
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
        }
        .padding(.vertical, 8)
    }

    // MARK: - Per-Row Expansion

    private func exerciseExpansion(for exerciseName: String) -> some View {
        let sex = BiologicalSex(rawValue: biologicalSex) ?? .male
        let bw = bodyweight

        return VStack(alignment: .leading, spacing: 5) {
            ForEach(StrengthTier.allCases, id: \.rawValue) { tier in
                if let threshold = StrengthTierData.thresholds[exerciseName]?[sex]?[tier] {
                    HStack(spacing: 0) {
                        Circle().fill(tier.color).frame(width: 6, height: 6)
                            .padding(.trailing, 6)

                        Text(tier.title)
                            .font(.caption2)
                            .foregroundStyle(tier.color)
                            .frame(width: 80, alignment: .leading)

                        Spacer().frame(width: 8)

                        Text(expansionRangeLabel(threshold, bodyweight: bw))
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
        .padding(.leading, 8)
        .padding(.vertical, 6)
    }

    private func expansionRangeLabel(_ threshold: TierThreshold, bodyweight: Double) -> String {
        let unit = userProperties.preferredWeightUnit
        if threshold.isAbsolute {
            let minDisplay = Int(unit.fromLbs(threshold.min))
            let maxStr = threshold.max.map { "\(Int(unit.fromLbs($0)))" } ?? "+"
            return "\(minDisplay)–\(maxStr) \(unit.label)"
        } else {
            let minLbs = threshold.min * bodyweight
            let minDisplay = Int(unit.fromLbs(minLbs))
            if let max = threshold.max {
                let maxLbs = max * bodyweight
                let maxDisplay = Int(unit.fromLbs(maxLbs))
                return "\(minDisplay)–\(maxDisplay) \(unit.label) (\(String(format: "%.2g", threshold.min))–\(String(format: "%.2g", max))× BW)"
            } else {
                return "\(minDisplay)+ \(unit.label) (\(String(format: "%.2g", threshold.min))× BW+)"
            }
        }
    }

    // MARK: - Tier Legend

    private var tierLegendBar: some View {
        let tiers = StrengthTier.allCases.filter { $0 != .none }
        let topRow = Array(tiers.prefix(3))
        let bottomRow = Array(tiers.suffix(3))

        return VStack(spacing: 8) {
            HStack(spacing: 16) {
                ForEach(topRow, id: \.rawValue) { tier in
                    tierLegendItem(tier)
                }
            }
            HStack(spacing: 16) {
                ForEach(bottomRow, id: \.rawValue) { tier in
                    tierLegendItem(tier)
                }
            }
        }
    }

    private func tierLegendItem(_ tier: StrengthTier) -> some View {
        HStack(spacing: 5) {
            Circle().fill(tier.color).frame(width: 7, height: 7)
            Text(tier.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tier.color)
        }
    }

    // MARK: - Progress Calculation

    private func overallTierProgress(_ result: TrendsCalculator.StrengthTierResult) -> Double {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return 0 }
        let bw = bodyweight
        guard let nextTier = result.overallTier.next else { return 0 }

        // For each exercise, calculate progress toward the next overall tier
        // Exercises already at or above the target tier count as 100%
        var progresses: [Double] = []
        for item in result.exerciseTiers {
            if item.tier >= nextTier {
                progresses.append(1.0)
                continue
            }
            guard let e1rm = item.e1rm else {
                progresses.append(0)
                continue
            }
            let currentMin = StrengthTierData.currentTierMinimum(
                name: item.exercise.name, tier: item.tier, bodyweight: bw, sex: sex
            )
            guard let targetMin = StrengthTierData.nextTierMinimum(
                name: item.exercise.name, currentTier: item.tier, bodyweight: bw, sex: sex
            ) else {
                progresses.append(0)
                continue
            }
            let range = targetMin - currentMin
            guard range > 0 else { progresses.append(1.0); continue }
            progresses.append(min(max((e1rm - currentMin) / range, 0), 1.0))
        }

        guard !progresses.isEmpty else { return 0 }
        // Average across all exercises — reflects overall completion toward next tier
        return progresses.reduce(0, +) / Double(progresses.count)
    }

    private func progressToNextTier(item: (exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier)) -> Double? {
        guard let sex = BiologicalSex(rawValue: biologicalSex) else { return nil }
        let bw = bodyweight
        guard item.tier != .legend else { return nil }
        guard let e1rm = item.e1rm else { return 0 }

        let currentMin = StrengthTierData.currentTierMinimum(
            name: item.exercise.name,
            tier: item.tier,
            bodyweight: bw,
            sex: sex
        )
        guard let nextMin = StrengthTierData.nextTierMinimum(
            name: item.exercise.name,
            currentTier: item.tier,
            bodyweight: bw,
            sex: sex
        ) else { return nil }

        let range = nextMin - currentMin
        guard range > 0 else { return 1.0 }
        return min(max((e1rm - currentMin) / range, 0), 1.0)
    }
}

