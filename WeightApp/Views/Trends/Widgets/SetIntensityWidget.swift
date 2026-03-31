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
    let isPremium: Bool
    @Binding var showUpsell: Bool

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
        if isPremium {
            premiumContent
        } else {
            lockedContent
        }
    }

    // MARK: - Premium Content

    private var premiumContent: some View {
        WidgetCard(title: "Set Intensity") {
            if exerciseNames.isEmpty {
                EmptyWidgetState(icon: "chart.bar.fill", message: "Log sets to see intensity data")
            } else {
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
        } trailing: {
            if !exerciseNames.isEmpty {
                HStack(spacing: 8) {
                    if !setsWithPRInfo.isEmpty {
                        Button {
                            showPROnly.toggle()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showPROnly ? "checkmark.square.fill" : "square")
                                    .font(.caption2)
                                    .foregroundStyle(Color.appAccent)
                                Text("PRs Only")
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.6))
                            }
                        }
                        .buttonStyle(.plain)
                    }

                    exercisePicker
                }
            }
        }
        .onAppear {
            if selectedExerciseName == nil {
                selectedExerciseName = exerciseNames.first
            }
        }
    }

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Fake exercise picker
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

            // Fake colorful bar chart
            fakeIntensityChart

            legend
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .premiumLocked(
            title: "Unlock Set Intensity",
            subtitle: "See the intensity breakdown of every set",
            showUpsell: $showUpsell
        )
    }

    // MARK: - Fake Intensity Chart

    private struct FakeBar: Identifiable {
        let id: Int
        let height: CGFloat
        let color: Color
    }

    private static let fakeBars: [FakeBar] = [
        FakeBar(id: 0, height: 0.45, color: .setEasy),
        FakeBar(id: 1, height: 0.52, color: .setEasy),
        FakeBar(id: 2, height: 0.60, color: .setModerate),
        FakeBar(id: 3, height: 0.55, color: .setEasy),
        FakeBar(id: 4, height: 0.68, color: .setModerate),
        FakeBar(id: 5, height: 0.75, color: .setHard),
        FakeBar(id: 6, height: 0.62, color: .setModerate),
        FakeBar(id: 7, height: 0.80, color: .setHard),
        FakeBar(id: 8, height: 0.70, color: .setModerate),
        FakeBar(id: 9, height: 0.85, color: .setHard),
        FakeBar(id: 10, height: 0.90, color: .setNearMax),
        FakeBar(id: 11, height: 0.78, color: .setHard),
        FakeBar(id: 12, height: 0.65, color: .setModerate),
        FakeBar(id: 13, height: 0.92, color: .setNearMax),
        FakeBar(id: 14, height: 1.0, color: .setPR),
        FakeBar(id: 15, height: 0.72, color: .setModerate),
        FakeBar(id: 16, height: 0.88, color: .setNearMax),
        FakeBar(id: 17, height: 0.58, color: .setEasy),
        FakeBar(id: 18, height: 0.82, color: .setHard),
        FakeBar(id: 19, height: 0.95, color: .setNearMax),
        FakeBar(id: 20, height: 1.0, color: .setPR),
    ]

    private var fakeIntensityChart: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(Self.fakeBars) { bar in
                RoundedRectangle(cornerRadius: 2)
                    .fill(bar.color)
                    .frame(height: 120 * bar.height)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: 120)
    }

    // MARK: - Exercise Picker

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
            LegendItem(color: .setPR, label: "Progress")
        }
    }
}
