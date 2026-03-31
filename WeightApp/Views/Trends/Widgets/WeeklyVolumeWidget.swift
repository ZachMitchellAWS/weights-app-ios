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
    let isPremium: Bool
    @Binding var showUpsell: Bool

    private var weeklyData: [TrendsCalculator.WeeklyVolume] {
        TrendsCalculator.weeklyVolume(from: allSets, weeks: 8)
    }

    private var volumeBandInfo: (average: Double, bands: [TrendsCalculator.VolumeBand]) {
        TrendsCalculator.volumeBands(from: allSets)
    }

    var body: some View {
        if isPremium {
            premiumContent
        } else {
            lockedContent
        }
    }

    // MARK: - Premium Content

    private var premiumContent: some View {
        WidgetCard(title: "Total Weekly Volume", subtitle: "Total \(weightUnit.label) lifted per week") {
            if weeklyData.isEmpty {
                EmptyWidgetState(icon: "chart.bar.fill", message: "Log sets to track your weekly volume")
            } else {
                chartView
            }
        }
    }

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Total Weekly Volume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Total \(weightUnit.label) lifted per week")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            fakeChart
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .premiumLocked(
            title: "Unlock Weekly Volume",
            subtitle: "Track your total training volume over time",
            showUpsell: $showUpsell
        )
    }

    // MARK: - Fake Chart (locked state)

    private static let fakeWeeklyData: [(weeksAgo: Int, volume: Double)] = [
        (7, 8200),   // gray — well below avg
        (6, 14500),  // purple — moderately below
        (5, 18000),  // green — near average
        (4, 22500),  // amber — above average
        (3, 16800),  // green — near average
        (2, 25100),  // amber — well above
        (1, 11200),  // cyan — somewhat below
        (0, 27400),  // amber — highest week
    ]

    private var fakeChart: some View {
        let calendar = Calendar.current
        let now = Date()
        let fakeAvg = 18000.0

        return Chart {
            ForEach(Self.fakeWeeklyData.indices, id: \.self) { i in
                let item = Self.fakeWeeklyData[i]
                let date = calendar.date(byAdding: .weekOfYear, value: -item.weeksAgo, to: now)!
                BarMark(
                    x: .value("Week", date, unit: .weekOfYear),
                    y: .value("Volume", item.volume)
                )
                .foregroundStyle(TrendsCalculator.volumeBandColor(volume: item.volume, average: fakeAvg))
                .cornerRadius(4)
            }

            RuleMark(y: .value("Avg", fakeAvg))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.white.opacity(0.35))
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
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

    // MARK: - Premium Chart

    private var chartView: some View {
        let bandInfo = volumeBandInfo

        return Chart {
            ForEach(weeklyData) { week in
                BarMark(
                    x: .value("Week", week.weekStart, unit: .weekOfYear),
                    y: .value("Volume", week.volume)
                )
                .foregroundStyle(TrendsCalculator.volumeBandColor(volume: week.volume, average: bandInfo.average))
                .cornerRadius(4)
            }

            if bandInfo.average > 0 {
                // Average line
                RuleMark(y: .value("Avg", bandInfo.average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.white.opacity(0.35))

                // Band reference lines
                ForEach(bandInfo.bands.indices, id: \.self) { i in
                    let band = bandInfo.bands[i]
                    if band.value > 0 {
                        RuleMark(y: .value("Band", band.value))
                            .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                            .foregroundStyle(Color.white.opacity(0.15))
                    }
                }
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

            AxisMarks(position: .trailing, values: bandYAxisValues(bandInfo)) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(bandLabel(v, bandInfo: bandInfo))
                            .font(.system(size: 8))
                            .foregroundStyle(Color.white.opacity(0.35))
                    }
                }
            }
        }
        .frame(height: 160)
    }

    // MARK: - Helpers

    private func bandYAxisValues(_ bandInfo: (average: Double, bands: [TrendsCalculator.VolumeBand])) -> [Double] {
        guard bandInfo.average > 0 else { return [] }
        var values = bandInfo.bands.map(\.value).filter { $0 > 0 }
        values.append(bandInfo.average)
        return values
    }

    private func bandLabel(_ value: Double, bandInfo: (average: Double, bands: [TrendsCalculator.VolumeBand])) -> String {
        let avg = bandInfo.average
        guard avg > 0 else { return "" }
        if abs(value - avg) < 1 { return "avg" }
        let pct = Int(round((value - avg) / avg * 100))
        return pct > 0 ? "+\(pct)%" : "\(pct)%"
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
