//
//  BalanceOverTimeWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/27/26.
//

import SwiftUI
import Charts

struct BalanceOverTimeWidget: View {
    let allEstimated1RM: [Estimated1RM]
    let bodyweight: Double
    let sex: BiologicalSex
    let isPremium: Bool
    @Binding var showUpsell: Bool

    @State private var snapshots: [TrendsCalculator.WeeklyBalanceSnapshot] = []

    private var hasData: Bool { snapshots.count >= 2 }

    var body: some View {
        if isPremium {
            premiumContent
        } else {
            lockedContent
        }
    }

    // MARK: - Premium Content

    private var premiumContent: some View {
        WidgetCard(title: "Strength Balance", subtitle: "Tier spread over time") {
            if hasData {
                chartView(data: snapshots)
            } else {
                EmptyWidgetState(
                    icon: "chart.line.uptrend.xyaxis",
                    message: "Log sets for at least 2 weeks to see your balance trend"
                )
            }
        }
        .task(id: allEstimated1RM.count) {
            snapshots = TrendsCalculator.weeklyBalanceHistory(
                from: allEstimated1RM,
                bodyweight: bodyweight,
                sex: sex,
                weeks: 8
            )
        }
    }

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Strength Balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Tier spread over time")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            fakeChartView
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .premiumLocked(
            title: "Unlock Balance Trends",
            subtitle: "See how your exercise balance trends over time",
            showUpsell: $showUpsell
        )
    }

    // MARK: - Chart

    private func chartView(data: [TrendsCalculator.WeeklyBalanceSnapshot]) -> some View {
        Chart {
            // Category zone backgrounds via RuleMarks
            // Symmetrical (0) = green zone
            RuleMark(y: .value("Sym", 0.25))
                .lineStyle(StrokeStyle(lineWidth: 0))
                .foregroundStyle(.clear)

            // Data line
            ForEach(data) { point in
                LineMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Spread", 4 - point.tierSpread)
                )
                .foregroundStyle(colorForSpread(point.tierSpread))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Spread", 4 - point.tierSpread)
                )
                .foregroundStyle(colorForSpread(point.tierSpread))
                .symbolSize(30)
            }
        }
        .chartYScale(domain: 0.0...5.0)
        .chartYAxis {
            AxisMarks(values: [0, 1, 2, 3, 4]) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                    .foregroundStyle(.clear)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.inter(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .chartBackground { proxy in
            GeometryReader { geo in
                let bands: [(yTop: Double, yBottom: Double, color: Color, label: String)] = [
                    (4.5, 3.5, Color.setEasy, "Symmetrical"),
                    (3.5, 2.5, Color.setModerate, "Balanced"),
                    (2.5, 1.5, Color.appAccent, "Uneven"),
                    (1.5, 0.5, Color.setNearMax, "Skewed"),
                ]
                ForEach(bands.indices, id: \.self) { i in
                    let band = bands[i]
                    if let top = proxy.position(forY: band.yTop),
                       let bottom = proxy.position(forY: band.yBottom) {
                        let height = bottom - top
                        ZStack {
                            Rectangle()
                                .fill(band.color.opacity(0.12))
                            Text(band.label)
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(band.color.opacity(0.4))
                        }
                        .frame(width: geo.size.width, height: height)
                        .position(x: geo.size.width / 2, y: top + height / 2)
                    }
                }
            }
        }
        .frame(height: 180)
    }

    // MARK: - Fake Chart (Locked)

    private var fakeChartView: some View {
        let calendar = Calendar.current
        let now = Date()
        let fakeData: [(Date, Int)] = [3, 3, 2, 2, 2, 1, 1, 1].enumerated().compactMap { i, spread in
            guard let date = calendar.date(byAdding: .weekOfYear, value: -(7 - i), to: now) else { return nil }
            return (date, spread)
        }

        return Chart {
            ForEach(fakeData.indices, id: \.self) { i in
                LineMark(
                    x: .value("Week", fakeData[i].0, unit: .weekOfYear),
                    y: .value("Spread", 4 - fakeData[i].1)
                )
                .foregroundStyle(colorForSpread(fakeData[i].1))
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Week", fakeData[i].0, unit: .weekOfYear),
                    y: .value("Spread", 4 - fakeData[i].1)
                )
                .foregroundStyle(colorForSpread(fakeData[i].1))
                .symbolSize(24)
            }
        }
        .chartYScale(domain: 0...4)
        .chartYAxis {
            AxisMarks(values: [0, 1, 2, 3, 4]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let v = value.as(Int.self) {
                        Text(categoryLabel(for: v))
                            .font(.inter(size: 8))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(.white.opacity(0.08))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(.inter(size: 9))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(height: 180)
    }

    // MARK: - Helpers

    private func colorForSpread(_ spread: Int) -> Color {
        switch spread {
        case 0: return .setEasy           // Symmetrical — green
        case 1: return .setModerate       // Balanced — cyan
        case 2: return .appAccent         // Uneven — amber
        case 3: return .setNearMax        // Skewed — red
        default: return .setNearMax       // Lopsided — red
        }
    }

    private func categoryLabel(for spread: Int) -> String {
        switch spread {
        case 4: return "Symmetrical"
        case 3: return "Balanced"
        case 2: return "Uneven"
        case 1: return "Skewed"
        default: return "Lopsided"
        }
    }
}
