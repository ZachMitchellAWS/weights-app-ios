//
//  FrequencyCalendarWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct FrequencyCalendarWidget: View {
    let allSets: [LiftSet]

    private var activityData: [TrendsCalculator.DayActivity] {
        TrendsCalculator.trainingFrequency(from: allSets, weeks: 12)
    }

    private var activityByDate: [Date: Int] {
        Dictionary(uniqueKeysWithValues: activityData.map { ($0.date, $0.setCount) })
    }

    private var maxSets: Int {
        activityData.map(\.setCount).max() ?? 1
    }

    private var weeks: [[Date]] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        guard let startDate = calendar.date(byAdding: .weekOfYear, value: -11, to: today) else { return [] }
        let weekStart = calendar.startOfWeek(for: startDate)

        var result: [[Date]] = []
        var currentWeekStart = weekStart

        for _ in 0..<12 {
            var week: [Date] = []
            for dayOffset in 0..<7 {
                if let day = calendar.date(byAdding: .day, value: dayOffset, to: currentWeekStart) {
                    week.append(day)
                }
            }
            result.append(week)
            if let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: currentWeekStart) {
                currentWeekStart = nextWeek
            }
        }

        return result
    }

    var body: some View {
        WidgetCard(title: "Training Activity", subtitle: "Last 12 weeks") {
            if activityData.isEmpty {
                EmptyWidgetState(icon: "calendar", message: "Log sets to see your training frequency")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Day labels
                    HStack(alignment: .top, spacing: 2) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("M").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            Text("T").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            Text("W").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            Text("T").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            Text("F").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            Text("S").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                            Text("S").font(.system(size: 8)).foregroundStyle(.white.opacity(0.4))
                        }
                        .frame(width: 12)

                        // Calendar grid
                        HStack(spacing: 2) {
                            ForEach(weeks, id: \.first) { week in
                                VStack(spacing: 2) {
                                    ForEach(week, id: \.self) { day in
                                        let setCount = activityByDate[Calendar.current.startOfDay(for: day)] ?? 0
                                        Rectangle()
                                            .fill(colorForActivity(setCount))
                                            .frame(width: 10, height: 10)
                                            .cornerRadius(2)
                                    }
                                }
                            }
                        }
                    }

                    // Legend
                    HStack(spacing: 4) {
                        Text("Less")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))

                        ForEach([0, 1, 3, 5, 8], id: \.self) { level in
                            Rectangle()
                                .fill(colorForActivity(level))
                                .frame(width: 10, height: 10)
                                .cornerRadius(2)
                        }

                        Text("More")
                            .font(.system(size: 8))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
            }
        }
    }

    private func colorForActivity(_ setCount: Int) -> Color {
        guard maxSets > 0 else { return Color(white: 0.2) }

        if setCount == 0 {
            return Color(white: 0.2)
        }

        let intensity = Double(setCount) / Double(maxSets)

        switch intensity {
        case 0.75...:
            return Color.appAccent
        case 0.5..<0.75:
            return Color.appAccent.opacity(0.75)
        case 0.25..<0.5:
            return Color.appAccent.opacity(0.5)
        default:
            return Color.appAccent.opacity(0.3)
        }
    }
}
