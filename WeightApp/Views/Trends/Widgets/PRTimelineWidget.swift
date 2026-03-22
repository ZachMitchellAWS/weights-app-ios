//
//  PRTimelineWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct PRTimelineWidget: View {
    let allEstimated1RM: [Estimated1RM]
    var isPremium: Bool = true
    @Binding var showUpsell: Bool
    var weightUnit: WeightUnit = .lbs

    private var leaderboard: [TrendsCalculator.ExercisePRSummary] {
        TrendsCalculator.prLeaderboard(from: allEstimated1RM)
    }

    private var totalPRCount: Int {
        leaderboard.reduce(0) { $0 + $1.prCount }
    }

    var body: some View {
        if isPremium {
            WidgetCard(title: "Personal Records") {
                unlockedContent
            }
        } else {
            lockedContent
        }
    }

    // MARK: - Unlocked (Premium) Content

    @ViewBuilder
    private var unlockedContent: some View {
        if leaderboard.isEmpty {
            EmptyWidgetState(icon: "trophy.fill", message: "Set a PR to see your record history")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                summaryBar(prCount: totalPRCount)

                ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, entry in
                    PRLeaderboardRow(rank: index + 1, entry: entry, weightUnit: weightUnit)
                }
            }
        }
    }

    // MARK: - Locked (Free) Content

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            summaryBar(prCount: 23)

            PRLeaderboardRow.fake(rank: 1, name: "Bench Press", prCount: 8, gain: 15.3)
            PRLeaderboardRow.fake(rank: 2, name: "Squat", prCount: 6, gain: 22.1)
            PRLeaderboardRow.fake(rank: 3, name: "Deadlift", prCount: 5, gain: 18.7)
            PRLeaderboardRow.fake(rank: 4, name: "Overhead Press", prCount: 3, gain: 8.4)
            PRLeaderboardRow.fake(rank: 5, name: "Barbell Row", prCount: 1, gain: 5.2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumLocked(
            title: "Unlock PR Leaderboard",
            subtitle: "See which exercises are progressing fastest",
            blurRadius: 6,
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Shared Components

    private func summaryBar(prCount: Int) -> some View {
        HStack {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.setPR)

            Text("\(prCount) PRs in the last 90 days")
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.setPR)
        }
    }
}

private struct PRLeaderboardRow: View {
    let rank: Int
    let exerciseName: String
    let prCount: Int
    let totalGain: Double
    var weightUnit: WeightUnit = .lbs

    init(rank: Int, entry: TrendsCalculator.ExercisePRSummary, weightUnit: WeightUnit = .lbs) {
        self.rank = rank
        self.exerciseName = entry.exerciseName
        self.prCount = entry.prCount
        self.totalGain = entry.totalGain
        self.weightUnit = weightUnit
    }

    private init(rank: Int, name: String, prCount: Int, gain: Double) {
        self.rank = rank
        self.exerciseName = name
        self.prCount = prCount
        self.totalGain = gain
    }

    static func fake(rank: Int, name: String, prCount: Int, gain: Double) -> PRLeaderboardRow {
        PRLeaderboardRow(rank: rank, name: name, prCount: prCount, gain: gain)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("#\(rank)")
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.setPR.opacity(rank <= 3 ? 1.0 : 0.5))
                .frame(width: 24, alignment: .leading)

            Text(exerciseName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            Text("\(prCount) PR\(prCount == 1 ? "" : "s")")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            let displayGain = weightUnit.fromLbs(totalGain)
            Text(displayGain >= 0
                 ? "+\(String(format: "%.1f", displayGain)) \(weightUnit.label)"
                 : "\(String(format: "%.1f", displayGain)) \(weightUnit.label)")
                .font(.caption)
                .foregroundStyle(totalGain >= 0 ? Color.setEasy : .white.opacity(0.5))
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.vertical, 4)
    }
}
