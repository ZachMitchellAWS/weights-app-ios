//
//  ExerciseVolumeWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import Charts

struct ExerciseVolumeWidget: View {
    let allSets: [LiftSet]
    var weightUnit: WeightUnit = .lbs
    let isPremium: Bool
    @Binding var showUpsell: Bool

    @State private var selectedExercise: String?

    private var exerciseNames: [String] {
        TrendsCalculator.exerciseNames(from: allSets)
    }

    private var dataPoints: [TrendsCalculator.WeeklyVolume] {
        guard let exercise = selectedExercise ?? exerciseNames.first else { return [] }
        return TrendsCalculator.exerciseWeeklyVolume(from: allSets, exerciseName: exercise)
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
        WidgetCard(title: "Per-Exercise Volume", subtitle: "Total \(weightUnit.label) lifted per week") {
            if exerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.bar.fill", message: "Log sets to track volume")
            } else {
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
        } trailing: {
            if !exerciseNames.isEmpty {
                exercisePicker
            }
        }
        .onAppear {
            if selectedExercise == nil {
                selectedExercise = exerciseNames.first
            }
        }
    }

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Per-Exercise Volume")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Total \(weightUnit.label) lifted per week")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.4))
                }

                Spacer()

                // Fake picker
                HStack {
                    Text("Bench Press")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(Color.appAccent)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(white: 0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            fakeChart
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .premiumLocked(
            title: "Unlock Per-Exercise Volume",
            subtitle: "See volume trends for each exercise",
            showUpsell: $showUpsell
        )
    }

    // MARK: - Fake Chart (locked state)

    private static let fakeExerciseData: [(weeksAgo: Int, volume: Double)] = [
        (7, 1800),   // gray — very low
        (6, 3200),   // cyan — below avg
        (5, 4800),   // purple — moderately below
        (4, 6200),   // green — near average
        (3, 7500),   // amber — above average
        (2, 5100),   // green — near average
        (1, 8400),   // amber — high
        (0, 3600),   // cyan — below avg
    ]

    private var fakeChart: some View {
        let calendar = Calendar.current
        let now = Date()
        let fakeAvg = 5500.0

        return Chart {
            ForEach(Self.fakeExerciseData.indices, id: \.self) { i in
                let item = Self.fakeExerciseData[i]
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

    // MARK: - Exercise Picker

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

    // MARK: - Premium Chart

    private var volumeBandInfo: (average: Double, bands: [TrendsCalculator.VolumeBand]) {
        guard let exercise = selectedExercise ?? exerciseNames.first else { return (0, []) }
        return TrendsCalculator.volumeBands(from: allSets, exerciseName: exercise)
    }

    private var chartView: some View {
        let bandInfo = volumeBandInfo

        return Chart {
            ForEach(dataPoints) { point in
                BarMark(
                    x: .value("Week", point.weekStart, unit: .weekOfYear),
                    y: .value("Volume", point.volume)
                )
                .foregroundStyle(TrendsCalculator.volumeBandColor(volume: point.volume, average: bandInfo.average))
                .cornerRadius(4)
            }

            if bandInfo.average > 0 {
                RuleMark(y: .value("Avg", bandInfo.average))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.white.opacity(0.35))

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
        .frame(height: 180)
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
}
