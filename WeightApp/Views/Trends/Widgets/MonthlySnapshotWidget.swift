//
//  MonthlySnapshotWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/13/26.
//

import SwiftUI

struct MonthlySnapshotWidget: View {
    let allSets: [LiftSet]

    private var summary: TrendsCalculator.MonthlySummary {
        TrendsCalculator.monthlySummary(from: allSets)
    }

    private var distribution: TrendsCalculator.IntensityDistribution {
        TrendsCalculator.intensityDistribution(from: allSets, days: 30)
    }

    private var buckets: [(bucket: TrendsCalculator.IntensityBucket, count: Int, percentage: Double)] {
        let dist = distribution
        return [
            (.easy, dist.easy, dist.percentage(for: .easy)),
            (.moderate, dist.moderate, dist.percentage(for: .moderate)),
            (.hard, dist.hard, dist.percentage(for: .hard)),
            (.redline, dist.redline, dist.percentage(for: .redline)),
            (.pr, dist.pr, dist.percentage(for: .pr))
        ].filter { $0.count > 0 }
    }

    private var monthName: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: Date())
    }

    var body: some View {
        WidgetCard(title: monthName, subtitle: "This month") {
            if allSets.isEmpty {
                EmptyWidgetState(icon: "chart.bar.xaxis", message: "Log sets to see your monthly snapshot")
            } else {
                VStack(spacing: 12) {
                    // Intensity bar
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            ForEach(buckets, id: \.bucket) { item in
                                Rectangle()
                                    .fill(colorFor(item.bucket))
                                    .frame(width: max(geometry.size.width * CGFloat(item.percentage / 100) - 2, 0))
                            }
                        }
                        .cornerRadius(6)
                    }
                    .frame(height: 28)

                    // Compact legend — only non-zero buckets
                    HStack(spacing: 6) {
                        ForEach(buckets, id: \.bucket) { item in
                            IntensityLegendItem(
                                color: colorFor(item.bucket),
                                label: item.bucket.rawValue,
                                percentage: Int(item.percentage)
                            )
                        }
                    }

                    // 2x2 metric pills
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            MetricPill(
                                value: "\(summary.currentMonthSets)",
                                label: "Sets",
                                detail: summary.previousMonthSets > 0 ? formatChange(summary.setsChange) : nil,
                                detailColor: summary.setsChange >= 0 ? .setEasy : .setNearMax
                            )

                            MetricPill(
                                value: "\(summary.prCount)",
                                label: "PRs",
                                detail: distribution.total > 0 ? "\(Int(distribution.percentage(for: .pr)))% of all sets" : nil,
                                detailColor: .white.opacity(0.5)
                            )
                        }

                        HStack(spacing: 8) {
                            MetricPill(
                                value: abbreviatedVolume(summary.currentMonthVolume),
                                label: "Volume",
                                detail: summary.previousMonthVolume > 0 ? formatChange(summary.volumeChange) : nil,
                                detailColor: summary.volumeChange >= 0 ? .setEasy : .setNearMax
                            )

                            MetricPill(
                                value: summary.mostTrainedExercise ?? "—",
                                label: "Most Trained",
                                detail: summary.mostTrainedExercise != nil ? "\(summary.mostTrainedCount) sets" : nil,
                                detailColor: .appAccent,
                                valueFont: .callout.weight(.bold)
                            )
                        }
                    }
                }
            }
        }
    }

    private func colorFor(_ bucket: TrendsCalculator.IntensityBucket) -> Color {
        switch bucket {
        case .easy: return .setEasy
        case .moderate: return .setModerate
        case .hard: return .setHard
        case .redline: return .setNearMax
        case .pr: return .setPR
        }
    }

    private func formatChange(_ value: Double) -> String {
        let sign = value >= 0 ? "+" : ""
        return "\(sign)\(Int(value))% vs last month"
    }

    private func abbreviatedVolume(_ volume: Double) -> String {
        if volume >= 1_000_000 {
            return String(format: "%.1fM", volume / 1_000_000)
        } else if volume >= 1_000 {
            return String(format: "%.0fk", volume / 1_000)
        } else {
            return "\(Int(volume))"
        }
    }
}

private struct MetricPill: View {
    let value: String
    let label: String
    let detail: String?
    let detailColor: Color
    var valueFont: Font = .title.weight(.bold)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(valueFont)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            if let detail = detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(detailColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                Text(" ")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.clear)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(white: 0.18))
        .cornerRadius(8)
    }
}

private struct IntensityLegendItem: View {
    let color: Color
    let label: String
    let percentage: Int

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(label) \(percentage)%")
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
        }
    }
}
