//
//  StrengthMilestonesWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/13/26.
//

import SwiftUI

struct StrengthMilestonesWidget: View {
    let allEstimated1RM: [Estimated1RM]
    let exercises: [Exercise]
    let bodyweight: Double?
    let biologicalSex: String?
    var isPremium: Bool = true
    var weightUnit: WeightUnit = .lbs
    @Binding var showUpsell: Bool

    @State private var milestoneResult: TrendsCalculator.MilestoneResult?

    var body: some View {
        if isPremium {
            unlockedContent
                .task(id: "\(exercises.compactMap(\.currentE1RMLocalCache).count)-\(allEstimated1RM.count)") {
                    if let bw = bodyweight, let sex = biologicalSex {
                        milestoneResult = TrendsCalculator.strengthMilestones(from: allEstimated1RM, exercises: exercises, bodyweight: bw, biologicalSex: sex)
                    } else {
                        milestoneResult = nil
                    }
                }
        } else {
            lockedContent
        }
    }

    // MARK: - Unlocked Content

    @ViewBuilder
    private var unlockedContent: some View {
        if let result = milestoneResult {
            MilestoneContentView(result: result, weightUnit: weightUnit)
        } else {
            WidgetCard(title: "Strength Milestones") {
                EmptyWidgetState(
                    icon: "medal.fill",
                    message: "Log sets for the 5 fundamental lifts to track your milestones"
                )
            }
        }
    }

    // MARK: - Locked Content

    // MARK: - Locked Content

    // Fake achieved pattern per tier row — ensures every color is well-represented
    // [Deadlifts, Squats, Bench, Row, OHP]
    private static let fakeAchievedPattern: [[Bool]] = [
        [true,  true,  true,  true,  true ],  // Novice — all done
        [true,  true,  true,  true,  true ],  // Beginner — all done
        [true,  true,  true,  true,  false],  // Intermediate — 4/5
        [true,  true,  false, true,  false],  // Advanced — 3/5
        [true,  false, false, false, false],  // Elite — 1/5
        [false, false, false, false, false],  // Legend — none
    ]

    private static let fakeExerciseNames = ["Deadlifts", "Squats", "Bench", "Row", "OHP"]

    private var lockedContent: some View {
        let tiers: [StrengthTier] = [.novice, .beginner, .intermediate, .advanced, .elite, .legend]

        return VStack(spacing: 10) {
            // Fake header
            VStack(spacing: 6) {
                Text("STRENGTH MILESTONES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Text("17 / 30 Achieved")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // 6 compact rows — one per tier, no headers
            ForEach(Array(tiers.enumerated()), id: \.element.rawValue) { tierIndex, tier in
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        let achieved = Self.fakeAchievedPattern[tierIndex][i]
                        VStack(spacing: 3) {
                            ZStack {
                                Circle()
                                    .stroke(tier.color.opacity(achieved ? 0.7 : 0.25), lineWidth: 2.5)
                                    .frame(width: 40, height: 40)

                                if achieved {
                                    Circle()
                                        .fill(tier.color.opacity(0.2))
                                        .frame(width: 40, height: 40)

                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(tier.color)
                                }
                            }

                            Text(Self.fakeExerciseNames[i])
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumLocked(
            title: "Unlock Strength Milestones",
            subtitle: "Track tier-based milestones for every fundamental lift",
            blurRadius: 6,
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Milestone Content View

private struct MilestoneContentView: View {
    let result: TrendsCalculator.MilestoneResult
    var weightUnit: WeightUnit = .lbs

    @State private var expandedTiers: Set<Int> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            VStack(spacing: 6) {
                Text("STRENGTH MILESTONES")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Text("\(result.achievedCount) / \(result.totalCount) Achieved")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(Color.appAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Tier batches
            ForEach(result.batches) { batch in
                TierBatchSection(
                    batch: batch,
                    isExpanded: expandedTiers.contains(batch.id),
                    isLegendAchieved: batch.tier == .legend && batch.allAchieved,
                    weightUnit: weightUnit
                ) {
                    toggleTier(batch.id)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .onAppear {
            expandedTiers = defaultExpandedTiers()
        }
    }

    private func defaultExpandedTiers() -> Set<Int> {
        let batches = result.batches
        guard !batches.isEmpty else { return [] }

        // Find the index of the current tier batch
        let tierIndex = batches.firstIndex(where: { $0.tier == result.currentTier }) ?? 0

        // Sliding window of 3, clamped at edges
        let windowStart = max(0, min(tierIndex - 1, batches.count - 3))
        let windowEnd = min(windowStart + 3, batches.count)

        var expanded = Set<Int>()
        for i in windowStart..<windowEnd {
            expanded.insert(batches[i].id)
        }
        return expanded
    }

    private func toggleTier(_ id: Int) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if expandedTiers.contains(id) {
                expandedTiers.remove(id)
            } else {
                expandedTiers.insert(id)
            }
        }
    }
}

// MARK: - Tier Batch Section

private struct TierBatchSection: View {
    let batch: TrendsCalculator.TierMilestoneBatch
    let isExpanded: Bool
    let isLegendAchieved: Bool
    var weightUnit: WeightUnit = .lbs
    let onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            Button(action: onToggle) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(batch.tier.color)
                        .frame(width: 10, height: 10)

                    Text(batch.tier.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)

                    Spacer()

                    if isLegendAchieved {
                        Image(systemName: "crown.fill")
                            .foregroundStyle(Color.appAccent)
                            .font(.caption)
                    } else if batch.allAchieved {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.appAccent)
                            .font(.caption)
                    } else {
                        Text("\(batch.achievedCount)/\(batch.milestones.count)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.3))
                }
            }
            .buttonStyle(.plain)

            // Expanded content — badge grid
            if isExpanded {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 5)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(batch.milestones) { milestone in
                        TierMilestoneBadge(
                            milestone: milestone,
                            tierColor: batch.tier.color,
                            isLegend: batch.tier == .legend,
                            weightUnit: weightUnit
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tier Milestone Badge

private struct TierMilestoneBadge: View {
    let milestone: TrendsCalculator.TierMilestone
    let tierColor: Color
    let isLegend: Bool
    var weightUnit: WeightUnit = .lbs

    private var badgeSize: CGFloat { 48 }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                if milestone.achieved {
                    // Achieved: filled circle with checkmark + icon
                    Circle()
                        .fill(tierColor.opacity(0.2))
                        .frame(width: badgeSize, height: badgeSize)

                    Circle()
                        .stroke(tierColor.opacity(0.7), lineWidth: 2.5)
                        .frame(width: badgeSize, height: badgeSize)

                    if isLegend {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(tierColor)
                    } else {
                        Image(milestone.exerciseIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 30, height: 30)
                            .foregroundStyle(tierColor)
                    }
                } else {
                    // Progress ring
                    Circle()
                        .stroke(tierColor.opacity(0.25), lineWidth: 2.5)
                        .frame(width: badgeSize, height: badgeSize)

                    Circle()
                        .trim(from: 0, to: milestone.progress)
                        .stroke(tierColor.opacity(0.7), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: badgeSize, height: badgeSize)
                        .rotationEffect(.degrees(-90))

                    Text("\(Int(milestone.progress * 100))%")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.white)
                }
            }

            // Exercise name
            Text(shortName(milestone.exerciseName))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Target label
            Text(milestone.isAbsoluteTarget
                 ? "\(Int(weightUnit.fromLbs(milestone.targetLbs))) \(weightUnit.label)"
                 : milestone.targetLabel)
                .font(.system(size: 8, weight: .regular))
                .foregroundStyle(.white.opacity(0.65))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private func shortName(_ name: String) -> String {
        switch name {
        case "Bench Press": return "Bench"
        case "Overhead Press": return "OHP"
        case "Barbell Rows": return "Row"
        default: return name
        }
    }
}
