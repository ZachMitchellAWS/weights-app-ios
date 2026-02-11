//
//  ProgressOptionCard.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import SwiftUI

struct ProgressOptionCard: View {
    let suggestion: OneRMCalculator.Suggestion
    let isSelected: Bool
    let sortColumn: CheckInView.SortColumn
    let columnHighlighted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Weight
            Text(formatWeight(suggestion.weight.rounded1()))
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .weight ? Color.appAccent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 65)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // Reps
            Text("\(suggestion.reps)")
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .reps ? Color.appAccent : .white)
                .frame(width: 50)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // Projected 1RM
            Text(formatWeight(suggestion.projected1RM.rounded1()))
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .est1RM ? Color.appAccent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: 60)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // Gain
            let delta = suggestion.delta
            Text("\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(2))))")
                .font(.callout)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(columnHighlighted && sortColumn == .gain ? Color.appAccent : (delta > 0 ? .green : .white.opacity(0.7)))
                .frame(width: 65)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(white: 0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.appAccent : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
                )
        )
    }

    private func formatWeight(_ weight: Double) -> String {
        if weight.truncatingRemainder(dividingBy: 1) == 0 {
            return "\(Int(weight))"
        } else {
            return weight.formatted(.number.precision(.fractionLength(1)))
        }
    }
}

