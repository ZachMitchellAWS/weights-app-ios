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
    var weightColumnHighlighted: Bool = false
    var accentColor: Color = .setPR

    var body: some View {
        HStack(spacing: 0) {
            // Weight
            Text(formatWeight(suggestion.weight.rounded1()))
                .font(.callout)
                .foregroundStyle((columnHighlighted && sortColumn == .weight) || weightColumnHighlighted ? Color.appAccent : .white)
                .animation(.easeInOut(duration: 0.15), value: weightColumnHighlighted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // Reps
            Text("\(suggestion.reps)")
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .reps ? Color.appAccent : .white)
                .frame(maxWidth: .infinity)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // Projected 1RM
            Text(formatWeight(suggestion.projected1RM.rounded1()))
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .est1RM ? Color.appAccent : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

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
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? accentColor.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? accentColor : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
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

struct EffortOptionCard: View {
    let suggestion: OneRMCalculator.EffortSuggestion
    let isSelected: Bool
    var sortColumn: CheckInView.EffortSortColumn = .weight
    var columnHighlighted: Bool = false
    var accentColor: Color = .setEasy

    var body: some View {
        HStack(spacing: 0) {
            // Weight
            Text(formatWeight(suggestion.weight.rounded1()))
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .weight ? Color.appAccent : .white)
                .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // Reps
            Text("\(suggestion.reps)")
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .reps ? Color.appAccent : .white)
                .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                .frame(maxWidth: .infinity)

            Divider()
                .background(.white.opacity(0.2))
                .frame(height: 20)

            // % Est. 1RM
            Text("\(suggestion.percent1RM, specifier: "%.1f")%")
                .font(.callout)
                .foregroundStyle(columnHighlighted && sortColumn == .percent1RM ? Color.appAccent : .white.opacity(0.8))
                .animation(.easeInOut(duration: 0.15), value: columnHighlighted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? accentColor.opacity(0.08) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? accentColor : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
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

