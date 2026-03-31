//
//  PushPullRatioWidget.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/27/26.
//

import SwiftUI

struct PushPullRatioWidget: View {
    let allSets: [LiftSet]
    let isPremium: Bool
    @Binding var showUpsell: Bool

    private var ratios: TrendsCalculator.MovementRatio {
        TrendsCalculator.movementRatios(from: allSets, days: 30)
    }

    private var hasData: Bool {
        ratios.totalVolume > 0
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
        WidgetCard(title: "Movement Ratios", subtitle: "Past 30 days") {
            if hasData {
                balanceBars(ratio: ratios, fake: false)
            } else {
                EmptyWidgetState(
                    icon: "arrow.left.arrow.right",
                    message: "Log sets with movement types to see your push/pull and upper/lower balance"
                )
            }
        }
    }

    // MARK: - Locked Content

    private static let fakeRatio = TrendsCalculator.MovementRatio(
        pushVolume: 42000,
        pullVolume: 35000,
        hingeVolume: 28000,
        squatVolume: 31000,
        coreVolume: 8000
    )

    private var lockedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Movement Ratios")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Past 30 days")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            balanceBars(ratio: Self.fakeRatio, fake: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .premiumLocked(
            title: "Unlock Movement Ratios",
            subtitle: "Track your push/pull and upper/lower ratios",
            showUpsell: $showUpsell
        )
    }

    // MARK: - Balance Bars

    private func balanceBars(ratio: TrendsCalculator.MovementRatio, fake: Bool) -> some View {
        VStack(spacing: 16) {
            // Push / Pull bar
            ratioBar(
                title: "Push / Pull",
                leftLabel: "Push",
                rightLabel: "Pull",
                leftValue: ratio.pushVolume,
                rightValue: ratio.pullVolume,
                leftColor: .setEasy,
                rightColor: .setModerate,
                ratioValue: ratio.pushPullRatio
            )

            // Upper / Lower bar
            ratioBar(
                title: "Upper / Lower",
                leftLabel: "Upper",
                rightLabel: "Lower",
                leftValue: ratio.upperVolume,
                rightValue: ratio.lowerVolume,
                leftColor: .setHard,
                rightColor: .appAccent,
                ratioValue: ratio.upperLowerRatio
            )

            // Volume breakdown
            Divider()
                .background(.white.opacity(0.1))

            volumeBreakdown(ratio: ratio)
        }
    }

    private func ratioBar(
        title: String,
        leftLabel: String,
        rightLabel: String,
        leftValue: Double,
        rightValue: Double,
        leftColor: Color,
        rightColor: Color,
        ratioValue: Double
    ) -> some View {
        let total = leftValue + rightValue
        let leftPct = total > 0 ? Int(round(ratioValue * 100)) : 50
        let rightPct = 100 - leftPct
        let isBalanced = leftPct >= 45 && leftPct <= 55

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                if isBalanced {
                    Text("Balanced")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.setEasy)
                }
            }

            // Bar with percentage labels
            HStack(spacing: 0) {
                Text("\(leftPct)%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, alignment: .leading)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        // Left segment
                        RoundedRectangle(cornerRadius: 4)
                            .fill(leftColor)
                            .frame(width: max(geo.size.width * CGFloat(ratioValue), 2))

                        // Right segment
                        RoundedRectangle(cornerRadius: 4)
                            .fill(rightColor)
                    }
                    .overlay {
                        // Ideal zone indicator (45-55%)
                        GeometryReader { barGeo in
                            let idealStart = barGeo.size.width * 0.45
                            let idealWidth = barGeo.size.width * 0.10
                            Rectangle()
                                .fill(.white.opacity(0.2))
                                .frame(width: idealWidth)
                                .position(x: idealStart + idealWidth / 2, y: barGeo.size.height / 2)
                        }
                    }
                }
                .frame(height: 20)

                Text("\(rightPct)%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, alignment: .trailing)
            }

            // Ideal range label below the bar
            GeometryReader { geo in
                let barInset: CGFloat = 72 // 36pt label on each side
                let barWidth = geo.size.width - barInset
                let idealCenter = 36 + barWidth * 0.5
                Text("ideal range")
                    .font(.system(size: 8))
                    .foregroundStyle(.white.opacity(0.3))
                    .position(x: idealCenter, y: 4)
            }
            .frame(height: 10)

            // Labels
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(leftColor)
                        .frame(width: 6, height: 6)
                    Text(leftLabel)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(rightLabel)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                    Circle()
                        .fill(rightColor)
                        .frame(width: 6, height: 6)
                }
            }
        }
    }

    // MARK: - Volume Breakdown

    private func volumeBreakdown(ratio: TrendsCalculator.MovementRatio) -> some View {
        let categories: [(name: String, volume: Double, color: Color, idealLow: Double, idealHigh: Double)] = [
            ("Push", ratio.pushVolume, .setEasy, 0.25, 0.30),
            ("Pull", ratio.pullVolume, .setModerate, 0.25, 0.30),
            ("Hinge", ratio.hingeVolume, .appAccent, 0.20, 0.25),
            ("Squat", ratio.squatVolume, .setHard, 0.20, 0.25),
        ]
        let total = categories.reduce(0.0) { $0 + $1.volume }

        return VStack(alignment: .leading, spacing: 8) {
            Text("Volume Breakdown")
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.7))

            // Stacked horizontal bar
            // Ideal cumulative boundaries: Push 25-30%, Pull 50-60%, Hinge 70-85%, Squat 100%
            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                ZStack(alignment: .leading) {
                    HStack(spacing: 1) {
                        ForEach(categories.indices, id: \.self) { i in
                            let cat = categories[i]
                            let pct = total > 0 ? cat.volume / total : 0.25
                            RoundedRectangle(cornerRadius: 3)
                                .fill(cat.color)
                                .frame(width: max(w * pct - 1, 0))
                        }
                    }

                    // Ideal boundary tick marks at cumulative ideal midpoints
                    // Push ends at ~27.5%, Push+Pull ends at ~55%, Push+Pull+Hinge ends at ~77.5%
                    let idealBoundaries: [Double] = [0.275, 0.55, 0.775]
                    ForEach(idealBoundaries.indices, id: \.self) { i in
                        Rectangle()
                            .fill(Color.white.opacity(0.35))
                            .frame(width: 1, height: h + 4)
                            .position(x: w * idealBoundaries[i], y: h / 2)
                    }
                }
            }
            .frame(height: 16)

            // Legend with percentages
            HStack(spacing: 0) {
                ForEach(categories.indices, id: \.self) { i in
                    let cat = categories[i]
                    let pct = total > 0 ? Int(round(cat.volume / total * 100)) : 25
                    HStack(spacing: 3) {
                        Circle()
                            .fill(cat.color)
                            .frame(width: 5, height: 5)
                        Text("\(cat.name) \(pct)%")
                            .font(.system(size: 9))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if i < categories.count - 1 {
                        Spacer()
                    }
                }
            }
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
