//
//  StrengthBalanceCardView.swift
//  WeightApp
//
//  Static display card for the Strength Balance visualization.
//  Exported as an image for the Go Premium upsell.
//

import SwiftUI
import Charts

struct StrengthBalanceCardView: View {
    var body: some View {
        VStack(spacing: 14) {
            // Widget 1: Balance Assessment
            balanceAssessmentWidget

            // Widget 2: Movement Ratios + Volume Breakdown
            movementRatiosWidget

            // Widget 3: Balance Over Time
            balanceOverTimeWidget
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 360, height: 780)
        .background(Color.black)
    }

    // MARK: - Widget 1: Balance Assessment

    private var balanceAssessmentWidget: some View {
        // Order matches TrendsCalculator.fundamentalExercises
        let exercises: [(name: String, score: Double)] = [
            ("Deadlifts", 1.15),
            ("Squats", 1.05),
            ("Bench Press", 0.95),
            ("Overhead Press", 0.78),
            ("Barbell Rows", 1.02),
        ]

        return VStack(spacing: 8) {
            // Category header (matches BalanceView)
            VStack(spacing: 6) {
                Text("STRENGTH BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Text("Uneven")
                    .font(.title.weight(.bold))
                    .foregroundStyle(Color.appAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Horizontal bars (matches BalanceView chart exactly)
            Chart(exercises.indices, id: \.self) { i in
                let ex = exercises[i]
                let clamped = min(max(ex.score, 0.7), 1.3)
                BarMark(
                    xStart: .value("Start", 0.7),
                    xEnd: .value("Score", clamped),
                    y: .value("Exercise", ex.name)
                )
                .foregroundStyle(balanceColor(for: ex.score))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .chartXScale(domain: 0.7...1.3)
            .chartXAxis {
                AxisMarks(values: [0.7, 0.85, 1.0, 1.15, 1.3]) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: value.as(Double.self) == 1.0 ? [] : [4, 4]))
                        .foregroundStyle(.white.opacity(value.as(Double.self) == 1.0 ? 0.3 : 0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(v == 1.0 ? "Ideal" : String(format: "%.0f%%", v * 100))
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let name = value.as(String.self) {
                            Text(name)
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
            .frame(height: 220) // 5 exercises × 44pt
        }
        .padding()
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func balanceColor(for score: Double) -> Color {
        if score >= 1.08 { return Color(red: 0.13, green: 0.77, blue: 0.37) }
        if score >= 0.97 { return Color(red: 0.21, green: 0.72, blue: 0.79) }
        if score >= 0.92 { return Color(red: 0.96, green: 0.62, blue: 0.04) }
        return Color(red: 0.94, green: 0.27, blue: 0.27)
    }

    // MARK: - Widget 2: Movement Ratios

    private var movementRatiosWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Movement Ratios")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("Past 30 days")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Push / Pull — balanced
            ratioSection(
                title: "Push / Pull",
                leftLabel: "Push",
                rightLabel: "Pull",
                leftPct: 52,
                leftColor: .setEasy,
                rightColor: .setModerate,
                isBalanced: true
            )

            // Upper / Lower — not balanced (more interesting)
            ratioSection(
                title: "Upper / Lower",
                leftLabel: "Upper",
                rightLabel: "Lower",
                leftPct: 62,
                leftColor: .setHard,
                rightColor: .appAccent,
                isBalanced: false
            )

            Spacer().frame(height: 4)

            // Volume Breakdown (fused into this widget)
            GeometryReader { geo in
                HStack(spacing: 1) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.setEasy)
                        .frame(width: geo.size.width * 0.28)
                    RoundedRectangle(cornerRadius: 3).fill(Color.setModerate)
                        .frame(width: geo.size.width * 0.26)
                    RoundedRectangle(cornerRadius: 3).fill(Color.appAccent)
                        .frame(width: geo.size.width * 0.24)
                    RoundedRectangle(cornerRadius: 3).fill(Color.setHard)
                }
            }
            .frame(height: 16)

            HStack(spacing: 0) {
                legendDot(color: .setEasy, label: "Push 28%")
                Spacer()
                legendDot(color: .setModerate, label: "Pull 26%")
                Spacer()
                legendDot(color: .appAccent, label: "Hinge 24%")
                Spacer()
                legendDot(color: .setHard, label: "Squat 22%")
            }
        }
        .padding()
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func ratioSection(title: String, leftLabel: String, rightLabel: String, leftPct: Int, leftColor: Color, rightColor: Color, isBalanced: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                Text("\(leftPct)%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, alignment: .leading)

                GeometryReader { geo in
                    HStack(spacing: 1) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(leftColor)
                            .frame(width: geo.size.width * CGFloat(leftPct) / 100)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(rightColor)
                    }
                }
                .frame(height: 20)

                Text("\(100 - leftPct)%")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white)
                    .frame(width: 36, alignment: .trailing)
            }

            HStack {
                HStack(spacing: 4) {
                    Circle().fill(leftColor).frame(width: 6, height: 6)
                    Text(leftLabel).font(.caption2).foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 4) {
                    Text(rightLabel).font(.caption2).foregroundStyle(.white.opacity(0.5))
                    Circle().fill(rightColor).frame(width: 6, height: 6)
                }
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle().fill(color).frame(width: 5, height: 5)
            Text(label).font(.system(size: 9)).foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Widget 4: Balance Over Time

    private var balanceOverTimeWidget: some View {
        // Data trending from Skewed→Balanced — color reflects CURRENT state (Balanced = cyan)
        // Trending up then back down — ends in Uneven to match top widget
        let dataPoints: [(week: Int, spread: Int)] = [
            (1, 3), (2, 3), (3, 2), (4, 1), (5, 1), (6, 1), (7, 2), (8, 2)
        ]

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Strength Balance")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("Tier spread over time")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            Chart(dataPoints, id: \.week) { point in
                LineMark(
                    x: .value("Week", point.week),
                    y: .value("Spread", 4 - point.spread)
                )
                // Color reflects current (latest) state: Uneven = amber
                .foregroundStyle(Color.appAccent)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Week", point.week),
                    y: .value("Spread", 4 - point.spread)
                )
                .foregroundStyle(spreadColor(point.spread))
                .symbolSize(30)
            }
            .chartYScale(domain: 0.0...5.0)
            .chartYAxis {
                AxisMarks(values: [0, 1, 2, 3, 4]) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                        .foregroundStyle(.clear)
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 1)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        if let v = value.as(Int.self) {
                            Text("W\(v)")
                                .font(.inter(size: 8))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                }
            }
            .chartBackground { proxy in
                GeometryReader { geo in
                    let plotArea = geo[proxy.plotFrame!]
                    let bands: [(yTop: Double, yBottom: Double, color: Color, label: String)] = [
                        (4.5, 3.5, .setEasy, "Symmetrical"),
                        (3.5, 2.5, .setModerate, "Balanced"),
                        (2.5, 1.5, .appAccent, "Uneven"),
                        (1.5, 0.5, .setNearMax, "Skewed"),
                    ]
                    ForEach(bands.indices, id: \.self) { i in
                        let band = bands[i]
                        if let top = proxy.position(forY: band.yTop),
                           let bottom = proxy.position(forY: band.yBottom) {
                            let height = bottom - top
                            ZStack {
                                Rectangle()
                                    .fill(band.color.opacity(0.12))
                                Text(band.label)
                                    .font(.system(size: 7, weight: .medium))
                                    .foregroundStyle(band.color.opacity(0.5))
                            }
                            .frame(width: plotArea.width + 32, height: height)
                            .position(x: plotArea.midX, y: top + height / 2)
                        }
                    }
                }
            }
            .frame(height: 140)
        }
        .padding()
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func spreadColor(_ spread: Int) -> Color {
        switch spread {
        case 0: return .setEasy
        case 1: return .setModerate
        case 2: return .appAccent
        default: return .setNearMax
        }
    }
}
