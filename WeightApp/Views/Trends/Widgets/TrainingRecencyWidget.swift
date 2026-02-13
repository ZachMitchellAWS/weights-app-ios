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
        WidgetCard(title: "Exercise Activity", subtitle: "Days since last session") {
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

                    // Legend
                    HStack(spacing: 4) {
                        Text("Less Recent")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))

                        ForEach([31, 15, 9, 6, 3, 0] as [Int], id: \.self) { days in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(recencyColor(for: days <= 30 ? days : nil))
                                .frame(width: 10, height: 10)
                        }

                        Text("Recent")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    .padding(.top, 4)
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
        case 0...2:
            return Color.appAccent
        case 3...5:
            return Color.appAccent.opacity(0.65)
        case 6...8:
            return Color.appAccent.opacity(0.4)
        case 9...14:
            return Color.appAccent.opacity(0.22)
        default:
            return Color.appAccent.opacity(0.12)
        }
    }
}
