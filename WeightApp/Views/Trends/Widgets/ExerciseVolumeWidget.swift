//
//  ExerciseVolumeWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import Charts

struct ExerciseVolumeWidget: View {
    let allSets: [LiftSets]

    @State private var selectedExercise: String?

    private var exerciseNames: [String] {
        TrendsCalculator.exerciseNames(from: allSets)
    }

    private var dataPoints: [TrendsCalculator.WeeklyVolume] {
        guard let exercise = selectedExercise ?? exerciseNames.first else { return [] }
        return TrendsCalculator.exerciseWeeklyVolume(from: allSets, exerciseName: exercise)
    }

    var body: some View {
        WidgetCard(title: "Exercise Volume") {
            if exerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.bar.fill", message: "Log sets to track volume")
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
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Volume", point.volume)
                )
                .foregroundStyle(Color.appAccent.gradient)
                .cornerRadius(4)
            }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    .foregroundStyle(Color.white.opacity(0.1))
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
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
