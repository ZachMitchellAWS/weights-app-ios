//
//  FrequencyCalendarWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct FrequencyCalendarWidget: View {
    let allSets: [LiftSet]
    var isPremium: Bool = true
    @Binding var showUpsell: Bool

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
        var calendar = Calendar.current
        calendar.firstWeekday = 2 // Monday
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
        if isPremium {
            WidgetCard(title: "Training Activity", subtitle: "Last 12 weeks") {
                if activityData.isEmpty {
                    EmptyWidgetState(icon: "calendar", message: "Log sets to see your training frequency")
                } else {
                    calendarGrid
                }
            }
        } else {
            lockedContent
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        VStack(spacing: 8) {
            // Day labels + Calendar grid
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 14)

                // Calendar grid
                ForEach(weeks, id: \.first) { week in
                    VStack(spacing: 3) {
                        ForEach(week, id: \.self) { day in
                            let setCount = activityByDate[Calendar.current.startOfDay(for: day)] ?? 0
                            Rectangle()
                                .fill(colorForActivity(setCount))
                                .aspectRatio(1, contentMode: .fit)
                                .cornerRadius(3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Legend
            HStack(spacing: 4) {
                Spacer()

                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))

                ForEach([0, 1, 3, 5, 8], id: \.self) { level in
                    Rectangle()
                        .fill(colorForActivity(level))
                        .frame(width: 12, height: 12)
                        .cornerRadius(2)
                }

                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()
            }
        }
    }

    // MARK: - Locked Content

    // Fake activity levels for a realistic-looking locked calendar (12 weeks x 7 days)
    private static let fakeActivityGrid: [[Int]] = [
        [0, 5, 0, 1, 0, 7, 0],
        [4, 0, 6, 0, 2, 0, 0],
        [0, 3, 0, 1, 0, 4, 0],
        [6, 0, 0, 0, 7, 0, 3],
        [0, 4, 0, 1, 0, 0, 0],
        [2, 0, 5, 0, 3, 0, 0],
        [0, 0, 0, 1, 0, 6, 0],
        [5, 0, 3, 0, 0, 0, 2],
        [0, 6, 0, 0, 4, 0, 0],
        [3, 0, 7, 0, 5, 0, 0],
        [0, 2, 0, 1, 0, 3, 0],
        [4, 0, 5, 0, 0, 7, 0],
    ]

    private var lockedContent: some View {
        VStack(spacing: 8) {
            // Day labels + Calendar grid
            HStack(alignment: .top, spacing: 3) {
                VStack(spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 14)

                ForEach(0..<12, id: \.self) { weekIndex in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { dayIndex in
                            let setCount = Self.fakeActivityGrid[weekIndex][dayIndex]
                            Rectangle()
                                .fill(fakeColorForActivity(setCount))
                                .aspectRatio(1, contentMode: .fit)
                                .cornerRadius(3)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            // Legend
            HStack(spacing: 4) {
                Spacer()

                Text("Less")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))

                ForEach([0, 1, 3, 5, 8], id: \.self) { level in
                    Rectangle()
                        .fill(fakeColorForActivity(level))
                        .frame(width: 12, height: 12)
                        .cornerRadius(2)
                }

                Text("More")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.4))

                Spacer()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .premiumLocked(
            title: "Unlock Training Activity",
            subtitle: "See your training frequency over time",
            blurRadius: 2,
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Color function for fake locked grid (uses fixed max of 8)
    private func fakeColorForActivity(_ setCount: Int) -> Color {
        if setCount == 0 { return Color(white: 0.2) }
        let intensity = Double(setCount) / 8.0
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
