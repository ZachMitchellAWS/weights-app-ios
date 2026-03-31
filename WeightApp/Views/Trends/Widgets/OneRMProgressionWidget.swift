//
//  OneRMProgressionWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import Charts

struct OneRMProgressionChart: View {
    let dataPoints: [TrendsCalculator.OneRMDataPoint]

    private var xDomain: ClosedRange<Date> {
        guard let first = dataPoints.first?.date,
              let last = dataPoints.last?.date else { return Date()...Date() }
        let span = last.timeIntervalSince(first)
        let padding = Swift.max(span * 0.05, 86400)
        return first.addingTimeInterval(-padding)...last.addingTimeInterval(padding)
    }

    private var yDomain: ClosedRange<Double> {
        let values = dataPoints.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...100 }
        let range = hi - lo
        let padding = Swift.max(range * 0.15, 2.0)
        return (lo - padding)...(hi + padding)
    }

    var body: some View {
        if dataPoints.isEmpty {
            Text("No data for this exercise")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 20)
        } else {
            Chart {
                ForEach(dataPoints) { point in
                    AreaMark(
                        x: .value("Date", point.date),
                        yStart: .value("Baseline", yDomain.lowerBound),
                        yEnd: .value("1RM", point.value)
                    )
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.appAccent.opacity(0.18), Color.appAccent.opacity(0.0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.linear)

                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("1RM", point.value)
                    )
                    .foregroundStyle(Color.appAccent)
                    .interpolationMethod(.linear)
                    .lineStyle(StrokeStyle(lineWidth: 2))

                    if point.isPR {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value("1RM", point.value)
                        )
                        .foregroundStyle(Color.setPR)
                        .symbolSize(60)
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartXScale(domain: xDomain)
            .chartPlotStyle { plotArea in
                plotArea.clipShape(Rectangle())
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .font(.inter(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel()
                        .font(.inter(size: 9))
                        .foregroundStyle(Color.white.opacity(0.4))
                }
            }
            .frame(height: 180)
        }
    }
}

struct OneRMProgressionWidget: View {
    let allEstimated1RM: [Estimated1RM]
    let allExerciseNames: [String]

    @State private var selectedExercise: String?

    private var dataPoints: [TrendsCalculator.OneRMDataPoint] {
        guard let exercise = selectedExercise ?? allExerciseNames.first else { return [] }
        return TrendsCalculator.oneRMProgression(from: allEstimated1RM, exerciseName: exercise)
    }

    var body: some View {
        WidgetCard(title: "1RM Progression") {
            if allExerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.line.uptrend.xyaxis", message: "Log sets to track your progress")
            } else {
                OneRMProgressionChart(dataPoints: dataPoints)
            }
        } trailing: {
            if !allExerciseNames.isEmpty {
                exercisePicker
            }
        }
        .onAppear {
            if selectedExercise == nil {
                selectedExercise = allExerciseNames.first
            }
        }
    }

    private var exercisePicker: some View {
        Menu {
            ForEach(allExerciseNames, id: \.self) { name in
                Button(name) {
                    selectedExercise = name
                }
            }
        } label: {
            HStack {
                Text(selectedExercise ?? "Select Exercise")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.appAccent)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(Color.appAccent)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.2))
            .cornerRadius(8)
        }
    }
}
