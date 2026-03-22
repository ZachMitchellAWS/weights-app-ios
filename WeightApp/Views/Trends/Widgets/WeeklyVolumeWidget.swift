//
//  WeeklyVolumeWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import Charts

struct WeeklyVolumeWidget: View {
    let allSets: [LiftSet]
    var weightUnit: WeightUnit = .lbs

    private var weeklyData: [TrendsCalculator.WeeklyVolume] {
        TrendsCalculator.weeklyVolume(from: allSets, weeks: 8)
    }

    private var maxVolume: Double {
        weeklyData.map(\.volume).max() ?? 0
    }

    var body: some View {
        WidgetCard(title: "Weekly Volume", subtitle: "Total \(weightUnit.label) lifted per week") {
            if weeklyData.isEmpty {
                EmptyWidgetState(icon: "chart.bar.fill", message: "Log sets to track your weekly volume")
            } else {
                chartView
            }
        }
    }

    private var chartView: some View {
        Chart {
            ForEach(weeklyData) { week in
                BarMark(
                    x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Volume", week.volume)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.appAccent.opacity(0.6), Color.appAccent],
                        startPoint: .bottom,
                        endPoint: .top
                    )
                )
                .cornerRadius(4)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel(format: .dateTime.week(.defaultDigits))
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel {
                    if let volume = value.as(Double.self) {
                        Text(formatVolume(volume))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }
                }
            }
        }
        .frame(height: 160)
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
