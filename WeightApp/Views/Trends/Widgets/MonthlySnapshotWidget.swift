//
//  MonthlySnapshotWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/13/26.
//

import SwiftUI

struct MonthlySnapshotWidget: View {
    let allSets: [LiftSet]
    let allEstimated1RM: [Estimated1RM]

    @State private var summary: TrendsCalculator.PeriodSummary?
    @State private var distribution: TrendsCalculator.IntensityDistribution?

    private var buckets: [(bucket: TrendsCalculator.IntensityBucket, count: Int, percentage: Double)] {
        guard let dist = distribution else { return [] }
        return [
            (.easy, dist.easy, dist.percentage(for: .easy)),
            (.moderate, dist.moderate, dist.percentage(for: .moderate)),
            (.hard, dist.hard, dist.percentage(for: .hard)),
            (.redline, dist.redline, dist.percentage(for: .redline)),
            (.pr, dist.pr, dist.percentage(for: .pr))
        ].filter { $0.count > 0 }
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy"
        return formatter.string(from: Date())
    }

    private var weekRangeLabel: String {
        let range = TrendsCalculator.currentWeekRange()
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startStr = formatter.string(from: range.start)
        let endStr = formatter.string(from: range.end)
        let yearFormatter = DateFormatter()
        yearFormatter.dateFormat = ", yyyy"
        return "\(startStr) – \(endStr)\(yearFormatter.string(from: range.end))"
    }

    var body: some View {
        WidgetCard(title: "This Week") {
            if allSets.isEmpty {
                EmptyWidgetState(icon: "chart.bar.xaxis", message: "Log sets to see your weekly snapshot")
            } else if let summary {
                VStack(spacing: 12) {
                    // Intensity bar
                    if buckets.isEmpty {
                        // Aesthetic empty state for bar
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.06))
                            .frame(height: 28)
                            .overlay(
                                Text("No sets yet this week")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.25))
                            )
                    } else {
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
                    }

                    // 2x2 metric pills
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            MetricPill(
                                value: "\(summary.currentPeriodSets)",
                                label: "Total Sets",
                                detail: "12-Week Avg: \(summary.avgSets)"
                            )

                            MetricPill(
                                value: "\(summary.prCount)",
                                label: "Progress Sets",
                                detail: "12-Week Avg: \(summary.avgPRs)"
                            )
                        }

                        HStack(spacing: 8) {
                            MetricPill(
                                value: abbreviatedVolume(summary.currentPeriodVolume),
                                label: "Volume",
                                detail: "12-Week Avg: \(abbreviatedVolume(summary.avgVolume))"
                            )

                            MetricPill(
                                value: summary.mostTrainedExercise ?? "—",
                                label: "Most Trained",
                                detail: summary.mostTrainedExercise != nil ? "\(summary.mostTrainedCount) sets" : nil,
                                smallValue: true
                            )
                        }
                    }
                }
            }
        } trailing: {
            Text(weekRangeLabel)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .task(id: allSets.count) {
            summary = TrendsCalculator.weeklySummary(from: allSets)
            // Use days since Monday (week start) so distribution matches the week range
            let range = TrendsCalculator.currentWeekRange()
            let daysSinceWeekStart = max(1, Calendar.current.dateComponents([.day], from: range.start, to: Date()).day ?? 7)
            distribution = TrendsCalculator.intensityDistribution(from: allSets, estimated1RMs: allEstimated1RM, days: daysSinceWeekStart)
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
    var valueFont: Font = .title.weight(.bold)
    var smallValue: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .bottomLeading) {
                // Hidden spacer text to maintain consistent height
                Text("0")
                    .font(valueFont)
                    .hidden()

                Text(value)
                    .font(smallValue ? .callout.weight(.bold) : valueFont)
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(smallValue ? 0.7 : 1.0)
            }

            Text(label)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))

            if let detail = detail {
                Text(detail)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.35))
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
