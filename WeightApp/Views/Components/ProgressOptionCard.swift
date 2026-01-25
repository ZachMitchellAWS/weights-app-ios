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

    var body: some View {
        HStack(spacing: 12) {
            // Weight
            VStack(spacing: 2) {
                Text("WEIGHT")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appLabel)
                Text(formatWeight(suggestion.weight.rounded1()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 65)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 36)

            // Reps
            VStack(spacing: 2) {
                Text("REPS")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appLabel)
                Text("\(suggestion.reps)")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 50)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 36)

            // Projected 1RM
            VStack(spacing: 2) {
                Text("EST. 1RM")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appLabel)
                Text(formatWeight(suggestion.projected1RM.rounded1()))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(width: 60)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 36)

            // Gain
            let delta = suggestion.delta
            VStack(spacing: 2) {
                Text("GAIN")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color.appLabel)
                Text("\(delta >= 0 ? "+" : "")\(delta.formatted(.number.precision(.fractionLength(2))))")
                    .font(.title3.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(delta > 0 ? .green : .white.opacity(0.7))
            }
            .frame(width: 65)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
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

