//
//  IntensityDistributionWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct IntensityDistributionWidget: View {
    let allSets: [LiftSet]

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

    var body: some View {
        WidgetCard(title: "Set Intensity", subtitle: "Last 30 Days") {
            if distribution.total == 0 {
                EmptyWidgetState(icon: "flame.fill", message: "Log sets to see intensity breakdown")
            } else {
                VStack(spacing: 12) {
                    // Stacked bar
                    GeometryReader { geometry in
                        HStack(spacing: 2) {
                            ForEach(buckets, id: \.bucket) { item in
                                Rectangle()
                                    .fill(colorFor(item.bucket))
                                    .frame(width: geometry.size.width * CGFloat(item.percentage / 100))
                            }
                        }
                        .cornerRadius(6)
                    }
                    .frame(height: 24)

                    // Legend
                    HStack(spacing: 16) {
                        ForEach(buckets.prefix(4), id: \.bucket) { item in
                            IntensityLegendItem(
                                color: colorFor(item.bucket),
                                label: item.bucket.rawValue,
                                percentage: Int(item.percentage)
                            )
                        }
                    }

                    if let prBucket = buckets.first(where: { $0.bucket == .pr }) {
                        HStack {
                            Circle()
                                .fill(Color.setPR)
                                .frame(width: 8, height: 8)

                            Text("\(prBucket.count) PRs (\(Int(prBucket.percentage))%)")
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Color.setPR)
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
}

private struct IntensityLegendItem: View {
    let color: Color
    let label: String
    let percentage: Int

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)

            Text("\(label)")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))

            Text("\(percentage)%")
                .font(.caption2.weight(.medium))
                .foregroundStyle(.white.opacity(0.8))
        }
    }
}
