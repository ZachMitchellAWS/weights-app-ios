//
//  BodyWeightWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/3/26.
//

import SwiftUI
import SwiftData
import Charts

struct BodyWeightWidget: View {
    let checkins: [AccessoryGoalCheckin]
    let target: Double?
    let onAdd: () -> Void
    let onEditTarget: () -> Void
    let onShowHistory: () -> Void

    private var sortedCheckins: [AccessoryGoalCheckin] {
        checkins
            .filter { !$0.deleted }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private var last30DaysCheckins: [AccessoryGoalCheckin] {
        let calendar = Calendar.current
        let cutoff = calendar.date(byAdding: .day, value: -30, to: Date())!
        return sortedCheckins.filter { $0.createdAt >= cutoff }
    }

    private var latestWeight: Double? {
        sortedCheckins.last?.value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Body Weight")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(headerText)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                }

                Spacer()

                HStack(spacing: 12) {
                    Button(action: onEditTarget) {
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
            if last30DaysCheckins.count >= 2 {
                chartView
            } else if last30DaysCheckins.count == 1 {
                EmptyWidgetState(icon: "chart.line.uptrend.xyaxis", message: "Log at least 2 entries to see your trend")
            } else {
                EmptyWidgetState(icon: "scalemass", message: "Log your weight to track your trend")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var headerText: String {
        if let latest = latestWeight {
            let formatted = String(format: "%.1f", latest)
            if let target = target {
                return "\(formatted) lbs \u{2014} Target: \(String(format: "%.0f", target))"
            }
            return "\(formatted) lbs"
        }
        return "No entries"
    }

    private var yScaleDomain: ClosedRange<Double> {
        let values = last30DaysCheckins.map(\.value) + (target.map { [$0] } ?? [])
        let minVal = values.min() ?? 0
        let maxVal = values.max() ?? 0
        let padding = max((maxVal - minVal) * 0.15, 2.0)
        return (minVal - padding)...(maxVal + padding)
    }

    private var chartView: some View {
        Chart {
            ForEach(last30DaysCheckins, id: \.id) { checkin in
                LineMark(
                    x: .value("Date", checkin.createdAt),
                    y: .value("Weight", checkin.value)
                )
                .foregroundStyle(Color.appAccent)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2))

                PointMark(
                    x: .value("Date", checkin.createdAt),
                    y: .value("Weight", checkin.value)
                )
                .foregroundStyle(Color.appAccent)
                .symbolSize(30)
            }

            if let target = target {
                RuleMark(y: .value("Target", target))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .chartYScale(domain: yScaleDomain)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.08))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.4))
            }
        }
        .frame(height: 160)
    }
}
