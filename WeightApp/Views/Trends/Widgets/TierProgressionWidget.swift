//
//  TierProgressionWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/25/26.
//

import SwiftUI
import Charts

struct TierProgressionWidget: View {
    let allEstimated1RM: [Estimated1RM]
    let bodyweight: Double
    let sex: BiologicalSex
    let isPremium: Bool
    let weightUnit: WeightUnit
    @Binding var showUpsell: Bool

    @State private var selectedExercise: String

    init(
        allEstimated1RM: [Estimated1RM],
        bodyweight: Double,
        sex: BiologicalSex,
        isPremium: Bool,
        weightUnit: WeightUnit,
        showUpsell: Binding<Bool>
    ) {
        self.allEstimated1RM = allEstimated1RM
        self.bodyweight = bodyweight
        self.sex = sex
        self.isPremium = isPremium
        self.weightUnit = weightUnit
        self._showUpsell = showUpsell
        self._selectedExercise = State(initialValue: TrendsCalculator.fundamentalExercises.first?.name ?? "Bench Press")
    }

    private var exerciseNames: [String] {
        TrendsCalculator.fundamentalExercises.map(\.name)
    }

    private var dataPoints: [TrendsCalculator.OneRMDataPoint] {
        TrendsCalculator.oneRMProgression(from: allEstimated1RM, exerciseName: selectedExercise)
    }

    private var currentTier: StrengthTier {
        guard let latest = dataPoints.last else { return .novice }
        return StrengthTierData.tierForExercise(
            name: selectedExercise,
            e1rm: latest.value,
            bodyweight: bodyweight,
            sex: sex
        )
    }

    var body: some View {
        WidgetCard(title: "Tier Progression") {
            if isPremium {
                premiumContent
            } else {
                lockedContent
            }
        }
    }

    // MARK: - Premium Content

    @ViewBuilder
    private var premiumContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            exercisePicker

            if dataPoints.isEmpty {
                EmptyWidgetState(
                    icon: "chart.line.uptrend.xyaxis",
                    message: "Log sets for \(selectedExercise) to see tier progression"
                )
            } else {
                tierChart(
                    dataPoints: dataPoints,
                    exercise: selectedExercise,
                    bw: bodyweight,
                    userSex: sex,
                    showAllTiers: false
                )
            }
        }
    }

    // MARK: - Locked Content

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            exercisePicker
            tierChart(
                dataPoints: Self.fakeDataPoints,
                exercise: "Bench Press",
                bw: 180,
                userSex: .male,
                showAllTiers: true,
                fakeBandOpacity: 0.20,
                lineColor: StrengthTier.advanced.color
            )
        }
        .premiumLocked(
            title: "Unlock Tier Progression",
            subtitle: "Track your strength journey through the tiers",
            showUpsell: $showUpsell
        )
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
                Text(selectedExercise)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isPremium ? currentTier.color : StrengthTier.advanced.color)

                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(isPremium ? currentTier.color : StrengthTier.advanced.color)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(white: 0.2))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Chart

    private func tierChart(
        dataPoints: [TrendsCalculator.OneRMDataPoint],
        exercise: String,
        bw: Double,
        userSex: BiologicalSex,
        showAllTiers: Bool,
        fakeBandOpacity: Double? = nil,
        lineColor: Color? = nil
    ) -> some View {
        let bands = tierBands(
            exercise: exercise,
            bw: bw,
            userSex: userSex,
            dataPoints: dataPoints,
            showAllTiers: showAllTiers
        )
        let yDomain = yDomain(dataPoints: dataPoints, bands: bands)
        let resolvedLineColor = lineColor ?? currentTier.color
        let activeTier: StrengthTier = showAllTiers ? .advanced : currentTier

        return Chart {
            // Tier zone bands
            ForEach(bands, id: \.tier) { band in
                let bandMin = max(band.minLbs, yDomain.lowerBound)
                let bandMax = min(band.maxLbs, yDomain.upperBound)
                if bandMax > bandMin {
                    RectangleMark(
                        yStart: .value("Min", bandMin),
                        yEnd: .value("Max", bandMax)
                    )
                    .foregroundStyle(
                        band.tier.color.opacity(
                            fakeBandOpacity ?? (band.tier == activeTier ? 0.15 : 0.08)
                        )
                    )
                }
            }

            // Progression line
            ForEach(dataPoints) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("e1RM", point.value)
                )
                .foregroundStyle(resolvedLineColor)
                .interpolationMethod(.linear)
                .lineStyle(StrokeStyle(lineWidth: 2))

                if point.isPR {
                    PointMark(
                        x: .value("Date", point.date),
                        y: .value("e1RM", point.value)
                    )
                    .foregroundStyle(Color.setPR)
                    .symbolSize(60)
                }
            }
        }
        .chartYScale(domain: yDomain)
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
        .chartOverlay { proxy in
            GeometryReader { geo in
                let plotArea = geo[proxy.plotFrame!]
                ForEach(bands, id: \.tier) { band in
                    let bandMin = max(band.minLbs, yDomain.lowerBound)
                    let bandMax = min(band.maxLbs, yDomain.upperBound)
                    if bandMax > bandMin {
                        let yTop = proxy.position(forY: bandMax) ?? 0
                        let yBot = proxy.position(forY: bandMin) ?? 0
                        let midY = (yTop + yBot) / 2

                        Text(band.tier.title)
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(band.tier.color.opacity(0.6))
                            .position(
                                x: plotArea.maxX - 30,
                                y: midY
                            )
                    }
                }
            }
        }
        .frame(height: 180)
        .clipShape(Rectangle())
    }

    // MARK: - Tier Band Computation

    private struct TierBand {
        let tier: StrengthTier
        let minLbs: Double
        let maxLbs: Double
    }

    private func tierBands(
        exercise: String,
        bw: Double,
        userSex: BiologicalSex,
        dataPoints: [TrendsCalculator.OneRMDataPoint],
        showAllTiers: Bool
    ) -> [TierBand] {
        guard let sexThresholds = StrengthTierData.thresholds[exercise]?[userSex] else { return [] }

        let activeTiers: [StrengthTier]
        if showAllTiers {
            activeTiers = StrengthTier.allCases.filter { $0 != .none }
        } else {
            // Show tiers from novice through one tier above current
            let current = currentTier
            let ceiling = current.next ?? current
            activeTiers = StrengthTier.allCases.filter { $0 != .none && $0 <= ceiling }
        }

        return activeTiers.compactMap { tier in
            guard let threshold = sexThresholds[tier] else { return nil }
            let minLbs: Double
            if threshold.isAbsolute {
                minLbs = threshold.min
            } else {
                minLbs = threshold.min * bw
            }

            let maxLbs: Double
            if let maxVal = threshold.max {
                maxLbs = threshold.isAbsolute ? maxVal : maxVal * bw
            } else {
                // Unbounded top tier — will be capped to yDomain ceiling
                maxLbs = .greatestFiniteMagnitude
            }

            return TierBand(tier: tier, minLbs: minLbs, maxLbs: maxLbs)
        }
    }

    private func yDomain(
        dataPoints: [TrendsCalculator.OneRMDataPoint],
        bands: [TierBand]
    ) -> ClosedRange<Double> {
        let dataValues = dataPoints.map(\.value)
        let dataMin = dataValues.min() ?? 0
        let dataMax = dataValues.max() ?? 100

        let bandMin = bands.map(\.minLbs).min() ?? dataMin
        let bandMax = bands.map { $0.maxLbs == .greatestFiniteMagnitude ? dataMax : $0.maxLbs }.max() ?? dataMax

        let floor = min(dataMin, bandMin) * 0.95
        let ceiling = max(dataMax, bandMax) * 1.05

        return floor...ceiling
    }

    // MARK: - Fake Data (locked state)

    private static let fakeDataPoints: [TrendsCalculator.OneRMDataPoint] = {
        let calendar = Calendar.current
        let now = Date()
        let points: [(monthsAgo: Int, value: Double, isPR: Bool)] = [
            (6, 95, true),
            (5, 115, true),
            (4, 135, true),
            (3, 165, true),
            (2, 200, true),
            (1, 245, true),
            (0, 275, true),
        ]
        return points.map { p in
            TrendsCalculator.OneRMDataPoint(
                date: calendar.date(byAdding: .month, value: -p.monthsAgo, to: now)!,
                value: p.value,
                isPR: p.isPR
            )
        }
    }()
}
