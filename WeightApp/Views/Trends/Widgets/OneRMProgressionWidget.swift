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
}

struct OneRMProgressionWidget: View {
    let allEstimated1RMs: [Estimated1RMs]
    let allExerciseNames: [String]

    @State private var selectedExercise: String?

    private var dataPoints: [TrendsCalculator.OneRMDataPoint] {
        guard let exercise = selectedExercise ?? allExerciseNames.first else { return [] }
        return TrendsCalculator.oneRMProgression(from: allEstimated1RMs, exerciseName: exercise)
    }

    var body: some View {
        WidgetCard(title: "1RM Progression") {
            if allExerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.line.uptrend.xyaxis", message: "Log sets to track your progress")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    exercisePicker

                    OneRMProgressionChart(dataPoints: dataPoints)
                }
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
