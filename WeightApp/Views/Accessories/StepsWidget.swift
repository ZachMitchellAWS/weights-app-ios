//
//  StepsWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/3/26.
//

import SwiftUI
import SwiftData
import Charts

struct StepsWidget: View {
    let checkins: [AccessoryGoalCheckin]
    let goal: Int?
    let contiguousChart: Bool
    let onAdd: () -> Void
    let onEditGoal: () -> Void
    let onShowHistory: () -> Void

    @State private var selectedDay: Date?

    private var todayTotal: Double {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        return checkins
            .filter { !$0.deleted && calendar.startOfDay(for: $0.createdAt) == today }
            .reduce(0) { $0 + $1.value }
    }

    private var last7Days: [DayTotal] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let allDays = (0..<7).reversed().map { daysAgo -> DayTotal in
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            let total = checkins
                .filter { !$0.deleted && calendar.startOfDay(for: $0.createdAt) == day }
                .reduce(0) { $0 + $1.value }
            return DayTotal(date: day, total: total, isToday: daysAgo == 0)
        }

        if contiguousChart {
            return allDays.filter { $0.total > 0 }
        }
        return allDays
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Steps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(headerText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: onEditGoal) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Button(action: onShowHistory) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 16))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    Button(action: onAdd) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(Color.appAccent)
                    }
                }
            }

            // Chart
            if last7Days.contains(where: { $0.total > 0 }) {
                chartView
            } else {
                EmptyWidgetState(icon: "figure.walk", message: "Log steps to see your trends")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var headerText: String {
        let formatted = Int(todayTotal).formatted()
        if let goal = goal {
            return "\(formatted) / \(goal.formatted()) steps"
        }
        return "\(formatted) steps"
    }

    private func barOpacity(for day: DayTotal) -> Double {
        if selectedDay == nil {
            return day.isToday ? 1.0 : 0.5
        }
        return day.date == selectedDay ? 1.0 : 0.3
    }

    private var chartView: some View {
        Chart {
            ForEach(last7Days) { day in
                if contiguousChart {
                    BarMark(
                        x: .value("Day", day.weekdayLabel),
                        y: .value("Steps", day.total)
                    )
                    .foregroundStyle(Color.appAccent.opacity(barOpacity(for: day)))
                    .cornerRadius(4)
                } else {
                    BarMark(
                        x: .value("Day", day.date, unit: .day),
                        y: .value("Steps", day.total)
                    )
                    .foregroundStyle(Color.appAccent.opacity(barOpacity(for: day)))
                    .cornerRadius(4)
                }

                if day.date == selectedDay {
                    if contiguousChart {
                        RuleMark(x: .value("Selected", day.weekdayLabel))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 4) {
                                stepsAnnotation(for: day)
                            }
                    } else {
                        RuleMark(x: .value("Selected", day.date, unit: .day))
                            .foregroundStyle(.clear)
                            .annotation(position: .top, spacing: 4) {
                                stepsAnnotation(for: day)
                            }
                    }
                }
            }

            if let goal = goal {
                RuleMark(y: .value("Goal", goal))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .chartOverlay { proxy in
            GeometryReader { geometry in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(
                        SpatialTapGesture()
                            .onEnded { value in
                                let origin = geometry[proxy.plotFrame!].origin
                                let location = CGPoint(
                                    x: value.location.x - origin.x,
                                    y: value.location.y - origin.y
                                )
                                if contiguousChart {
                                    if let tappedLabel: String = proxy.value(atX: location.x) {
                                        if let day = last7Days.first(where: { $0.weekdayLabel == tappedLabel }) {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                selectedDay = selectedDay == day.date ? nil : day.date
                                            }
                                        }
                                    }
                                } else {
                                    if let tappedDate: Date = proxy.value(atX: location.x) {
                                        let calendar = Calendar.current
                                        let tappedDay = calendar.startOfDay(for: tappedDate)
                                        if last7Days.contains(where: { $0.date == tappedDay }) {
                                            withAnimation(.easeInOut(duration: 0.15)) {
                                                selectedDay = selectedDay == tappedDay ? nil : tappedDay
                                            }
                                        }
                                    }
                                }
                            }
                    )
            }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel {
                    if let steps = value.as(Double.self) {
                        Text(formatSteps(steps))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private func stepsAnnotation(for day: DayTotal) -> some View {
        Text("\(day.date.formatted(.dateTime.weekday(.abbreviated))): \(Int(day.total).formatted()) steps")
            .font(.caption2.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(white: 0.22))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func formatSteps(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}

struct DayTotal: Identifiable {
    let date: Date
    let total: Double
    let isToday: Bool
    var id: Date { date }

    var weekdayLabel: String {
        date.formatted(.dateTime.weekday(.abbreviated))
    }
}
