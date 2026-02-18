//
//  OneRMProgressionWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import Charts

struct OneRMProgressionWidget: View {
    let allEstimated1RMs: [Estimated1RMs]

    @State private var selectedExercise: String?

    private var exerciseNames: [String] {
        TrendsCalculator.exerciseNames(from: allEstimated1RMs)
    }

    private var dataPoints: [TrendsCalculator.OneRMDataPoint] {
        guard let exercise = selectedExercise ?? exerciseNames.first else { return [] }
        return TrendsCalculator.oneRMProgression(from: allEstimated1RMs, exerciseName: exercise)
    }

    var body: some View {
        WidgetCard(title: "1RM Progression") {
            if exerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.line.uptrend.xyaxis", message: "Log sets to track your progress")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    exercisePicker

                    if dataPoints.isEmpty {
                        Text("No data for this exercise")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        chartView
                    }
                }
            }
        }
        .onAppear {
            if selectedExercise == nil {
                selectedExercise = exerciseNames.first
            }
        }
    }

    private var exercisePicker: some View {
        Menu {
            ForEach(exerciseNames, id: \.self) { name in
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

    private var chartView: some View {
        Chart {
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("1RM", point.value)
                )
                .foregroundStyle(Color.appAccent)

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
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel()
                    .foregroundStyle(Color.white.opacity(0.5))
            }
        }
        .frame(height: 180)
    }
}
