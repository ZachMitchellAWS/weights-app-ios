//
//  TrainingRecencyWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/10/26.
//

import SwiftUI

struct TrainingRecencyWidget: View {
    let allSets: [LiftSet]

    private var recencyData: [TrendsCalculator.ExerciseRecency] {
        TrendsCalculator.exerciseRecency(from: allSets)
    }

    var body: some View {
        WidgetCard(title: "Exercise Recency", subtitle: "Last 30 days") {
            if recencyData.isEmpty {
                EmptyWidgetState(icon: "clock", message: "Log sets to see exercise recency")
            } else {
                VStack(spacing: 6) {
                    ForEach(recencyData) { item in
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(recencyColor(for: item.daysSinceLastSet))
                                .frame(width: 24, height: 24)

                            Text(item.exerciseName)
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.8))

                            Spacer()

                            Text(daysLabel(for: item.daysSinceLastSet))
                                .font(.system(size: 12, design: .rounded))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
        }
    }

    private func daysLabel(for days: Int?) -> String {
        guard let days = days else { return ">30d" }
        if days == 0 { return "Today" }
        if days < 7 { return "\(days)d ago" }
        if days < 14 { return "1w ago" }
        if days < 21 { return "2w ago" }
        if days < 28 { return "3w ago" }
        return "4w ago"
    }

    private func recencyColor(for days: Int?) -> Color {
        guard let days = days else {
            return Color(white: 0.2)
        }
        switch days {
        case 0...1:
            return Color.appAccent
        case 2...4:
            return Color.appAccent.opacity(0.65)
        case 5...9:
            return Color.appAccent.opacity(0.4)
        case 10...19:
            return Color.appAccent.opacity(0.22)
        default:
            return Color.appAccent.opacity(0.12)
        }
    }
}
