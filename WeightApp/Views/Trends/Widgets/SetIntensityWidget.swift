//
//  SetIntensityWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/22/26.
//

import SwiftUI
import SwiftData
import Charts

struct SetIntensityWidget: View {
    let allSets: [LiftSet]
    let allEstimated1RM: [Estimated1RM]
    var weightUnit: WeightUnit = .lbs

    @Query(filter: #Predicate<Exercise> { !$0.deleted }, sort: \Exercise.createdAt) private var exercises: [Exercise]

    @State private var selectedExerciseName: String?
    @State private var showPROnly: Bool = false
    @State private var selectedChartBarIndex: Int? = nil

    private var exerciseNames: [String] {
        TrendsCalculator.exerciseNames(from: allSets)
    }

    private var selectedExercise: Exercise? {
        let name = selectedExerciseName ?? exerciseNames.first
        guard let name else { return nil }
        return exercises.first(where: { $0.name == name })
    }

    private var setsWithPRInfo: [LegacyCheckInView.SetWithPR] {
        guard let exercise = selectedExercise else { return [] }
        return LegacyCheckInView.computeSetsWithPRInfo(for: exercise, from: allSets, estimated1RMs: allEstimated1RM)
    }

    private var displayData: [LegacyCheckInView.SetWithPR] {
        if showPROnly {
            return setsWithPRInfo.filter { $0.increases1RM }
        }
        return setsWithPRInfo
    }

    var body: some View {
        WidgetCard(title: "Set Intensity") {
            if exerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.bar.fill", message: "Log sets to see intensity data")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        exercisePicker

                        Spacer()

                        if !setsWithPRInfo.isEmpty {
                            Button {
                                showPROnly.toggle()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: showPROnly ? "checkmark.square.fill" : "square")
                                        .font(.caption2)
                                        .foregroundStyle(Color.appAccent)
                                    Text("Show PRs Only")
                                        .font(.caption2)
                                        .foregroundStyle(.white.opacity(0.6))
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if setsWithPRInfo.isEmpty {
                        Text("No data for this exercise")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 20)
                    } else {
                        chartContent
                        legend
                    }
                }
            }
        }
        .onAppear {
            if selectedExerciseName == nil {
                selectedExerciseName = exerciseNames.first
            }
        }
    }

    private var exercisePicker: some View {
        Menu {
            ForEach(exerciseNames, id: \.self) { name in
                Button(name) {
                    selectedExerciseName = name
                    selectedChartBarIndex = nil
                }
            }
        } label: {
            HStack {
                Text(selectedExerciseName ?? "Select Exercise")
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

    private var chartContent: some View {
        ZStack {
            HStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            LegacyCheckInView.SetHistoryChart(setsWithPRInfo: displayData, showYAxis: false, selectedBarIndex: $selectedChartBarIndex)
                                .id("chart-end")
                        }
                    }
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            proxy.scrollTo("chart-end", anchor: .trailing)
                        }
                    }
                    .onChange(of: displayData.count) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                proxy.scrollTo("chart-end", anchor: .trailing)
                            }
                        }
                    }
                }

                LegacyCheckInView.SetHistoryChartYAxis(setsWithPRInfo: displayData)
            }

            if let index = selectedChartBarIndex, index < displayData.count {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()

                setDetailOverlay(for: displayData[index])
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
        }
        .frame(height: 120)
        .onTapGesture {
            selectedChartBarIndex = nil
        }
    }

    private func setDetailOverlay(for setInfo: LegacyCheckInView.SetWithPR) -> some View {
        let isZeroWeight = setInfo.set.weight == 0

        return VStack(spacing: 8) {
            if setInfo.increases1RM {
                HStack(spacing: 4) {
                    Image(systemName: "star.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("PR Set")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }

            VStack(spacing: 4) {
                Text("Weight: \(weightUnit.formatWeight2dp(setInfo.set.weight)) \(weightUnit.label)")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Text("Reps: \(setInfo.set.reps)")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                if !isZeroWeight {
                    Text("Intensity: \(Int(setInfo.percentageOfCurrent))% of current")
                        .font(.subheadline)
                        .foregroundStyle(.white)
                    Text("Est. 1RM: \(weightUnit.formatWeight2dp(setInfo.estimated1RM)) \(weightUnit.label)")
                        .font(.title3)
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 8, y: 4)
    }

    private var legend: some View {
        HStack(spacing: 10) {
            LegendItem(color: .setEasy, label: "Easy")
            LegendItem(color: .setModerate, label: "Moderate")
            LegendItem(color: .setHard, label: "Hard")
            LegendItem(color: .setNearMax, label: "Redline")
            LegendItem(color: .setPR, label: "e1RM ↑")
        }
    }
}
