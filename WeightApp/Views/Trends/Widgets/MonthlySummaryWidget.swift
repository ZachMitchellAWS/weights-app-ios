//
//  MonthlySummaryWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct MonthlySummaryWidget: View {
    let allSets: [LiftSet]

    private var summary: TrendsCalculator.MonthlySummary {
        TrendsCalculator.monthlySummary(from: allSets)
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        WidgetCard(title: monthName) {
            if allSets.isEmpty {
                EmptyWidgetState(icon: "calendar", message: "Log sets to see your monthly summary")
            } else {
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        StatCard(
                            value: "\(summary.currentMonthSets)",
                            label: "Sets",
                            change: summary.setsChange,
                            showChange: summary.previousMonthSets > 0
                        )

                        StatCard(
                            value: "\(summary.prCount)",
                            label: "PRs",
                            change: nil,
                            showChange: false
                        )
                    }

                    if let exercise = summary.mostTrainedExercise {
                        HStack {
                            Text("Most Trained:")
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.5))

                            Text("\(exercise) (\(summary.mostTrainedCount))")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.appAccent)
                        }
                    }
                }
            }
        }
    }
}

private struct StatCard: View {
    let value: String
    let label: String
    let change: Double?
    let showChange: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title.weight(.bold))
                .foregroundStyle(.white)

            HStack(spacing: 4) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))

                if showChange, let change = change {
                    Text(formatChange(change))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(change >= 0 ? Color.setEasy : Color.setNearMax)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(white: 0.18))
        .cornerRadius(8)
    }

    private func formatChange(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value))%"
    }
}
