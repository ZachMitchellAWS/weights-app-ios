//
//  BestLiftsWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct BestLiftsWidget: View {
    let allSets: [LiftSets]

    private var bestLifts: [TrendsCalculator.BestLift] {
        TrendsCalculator.bestLifts(from: allSets, limit: 5)
    }

    private var maxValue: Double {
        bestLifts.first?.estimated1RM ?? 0
    }

    var body: some View {
        WidgetCard(title: "Best Lifts", subtitle: "Estimated 1RM") {
            if bestLifts.isEmpty {
                EmptyWidgetState(icon: "trophy.fill", message: "Log sets to see your best lifts")
            } else {
                VStack(spacing: 8) {
                    ForEach(Array(bestLifts.enumerated()), id: \.element.id) { index, lift in
                        BestLiftRow(
                            rank: index + 1,
                            lift: lift,
                            maxValue: maxValue
                        )
                    }
                }
            }
        }
    }
}

private struct BestLiftRow: View {
    let rank: Int
    let lift: TrendsCalculator.BestLift
    let maxValue: Double

    private var barWidth: Double {
        guard maxValue > 0 else { return 0 }
        return lift.estimated1RM / maxValue
    }

    private var formattedDate: String? {
        guard let date = lift.lastPRDate else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(rank).")
                .font(.caption.weight(.bold))
                .foregroundStyle(rank == 1 ? Color.setPR : .white.opacity(0.5))
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(lift.exerciseName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    Text("\(Int(lift.estimated1RM))")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Color.appAccent)
                }

                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Color(white: 0.2))
                            .frame(height: 6)
                            .cornerRadius(3)

                        Rectangle()
                            .fill(rank == 1 ? Color.setPR : Color.appAccent)
                            .frame(width: geometry.size.width * barWidth, height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
            }
        }
        .padding(.vertical, 2)
    }
}
