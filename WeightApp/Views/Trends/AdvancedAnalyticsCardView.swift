//
//  AdvancedAnalyticsCardView.swift
//  WeightApp
//
//  Static display card for the Advanced Analytics visualization.
//  Exported as an image for the Go Premium upsell.
//

import SwiftUI
import Charts

struct AdvancedAnalyticsCardView: View {
    var body: some View {
        VStack(spacing: 17) {
            thisWeekWidget
            trainingActivityWidget
            setIntensityWidget
            perExerciseVolumeWidget
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 360, height: 780)
        .background(Color.black)
    }

    // MARK: - Widget 1: This Week (compact — bar + legend only)

    private var thisWeekWidget: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Title row with date range on right
            HStack {
                Text("This Week")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("Apr 7 – Apr 13, 2026")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }

            // Intensity bar — standard plan proportions with a touch of redline
            // Easy 18%, Moderate 30%, Hard 25%, Redline 10%, Progress 17%
            GeometryReader { geo in
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.setEasy)
                        .frame(width: geo.size.width * 0.18)
                    RoundedRectangle(cornerRadius: 4).fill(Color.setModerate)
                        .frame(width: geo.size.width * 0.30)
                    RoundedRectangle(cornerRadius: 4).fill(Color.setHard)
                        .frame(width: geo.size.width * 0.25)
                    RoundedRectangle(cornerRadius: 4).fill(Color.setNearMax)
                        .frame(width: geo.size.width * 0.10)
                    RoundedRectangle(cornerRadius: 4).fill(Color.appAccent)
                }
                .cornerRadius(6)
            }
            .frame(height: 24)

            // Legend (centered)
            HStack(spacing: 5) {
                Spacer(minLength: 0)
                legendDot(color: .setEasy, label: "Easy 18%")
                legendDot(color: .setModerate, label: "Mod 30%")
                legendDot(color: .setHard, label: "Hard 25%")
                legendDot(color: .setNearMax, label: "Red 10%")
                legendDot(color: .appAccent, label: "Progress 17%")
                Spacer(minLength: 0)
            }

            // Total Sets and Progress Sets (horizontal pills)
            HStack(spacing: 6) {
                HStack(spacing: 10) {
                    Text("36")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Total Sets")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(white: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                HStack(spacing: 10) {
                    Text("4")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                    Text("Progress Sets")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.5))
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(white: 0.18))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(12)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Widget 2: Training Activity

    private var trainingActivityWidget: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Training Activity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("Last 12 Weeks")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(.bottom, 10)

            // Calendar grid: 12 weeks × 7 days
            // Labels (14w + 6 trailing) = 20pt. Offset left by half that so grid is centered.
            HStack(alignment: .top, spacing: 2) {
                // Day labels — height matches cell size: (160 - 6×3 spacing) / 7 ≈ 20.3
                VStack(spacing: 3) {
                    ForEach(["M", "T", "W", "T", "F", "S", "S"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                            .frame(height: 20.3)
                    }
                }
                .frame(width: 14)
                .padding(.trailing, 6)

                ForEach(fakeActivityGrid.indices, id: \.self) { weekIdx in
                    VStack(spacing: 3) {
                        ForEach(fakeActivityGrid[weekIdx].indices, id: \.self) { dayIdx in
                            Rectangle()
                                .fill(activityColor(fakeActivityGrid[weekIdx][dayIdx]))
                                .aspectRatio(1, contentMode: .fit)
                                .cornerRadius(2)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: 160)
            .offset(x: -10)
        }
        .padding(12)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // Realistic training patterns — not strictly periodic
    private var fakeActivityGrid: [[Int]] {
        [
            [6, 3, 6, 0, 6, 0, 0],  // week 1: M/Tu(light)/W/F
            [6, 0, 4, 3, 6, 0, 0],  // week 2: M/W(light)/Th(light)/F
            [8, 0, 6, 0, 6, 3, 0],  // week 3: heavy M/W/F + Sa
            [0, 6, 0, 6, 0, 6, 0],  // week 4: Tu/Th/Sa
            [3, 0, 3, 0, 0, 0, 0],  // week 5: deload
            [6, 0, 6, 4, 6, 0, 0],  // week 6: M/W/Th(moderate)/F
            [8, 3, 6, 0, 8, 0, 0],  // week 7: heavy M/Tu(light)/W/F
            [6, 6, 0, 6, 0, 6, 0],  // week 8: M/Tu/Th/Sa (4 days)
            [6, 0, 6, 0, 6, 3, 0],  // week 9: M/W/F + Sa(light)
            [6, 4, 0, 0, 6, 0, 0],  // week 10: M/Tu(moderate)/F
            [6, 0, 8, 3, 6, 0, 0],  // week 11: M/W(heavy)/Th(light)/F
            [8, 0, 6, 4, 8, 4, 0],  // week 12: heavy M/W/Th/F + Sa
        ]
    }

    private func activityColor(_ setCount: Int) -> Color {
        switch setCount {
        case 0: return Color(white: 0.2)
        case 1...2: return Color.appAccent.opacity(0.2)
        case 3...4: return Color.appAccent.opacity(0.4)
        case 5...6: return Color.appAccent.opacity(0.65)
        default: return Color.appAccent
        }
    }

    // MARK: - Widget 3: Set Intensity

    private var setIntensityWidget: some View {
        let barData: [(height: CGFloat, color: Color)] = [
            (0.45, .setEasy), (0.50, .setEasy), (0.62, .setModerate), (0.68, .setModerate), (0.80, .setHard), (1.0, .appAccent),
            (0.48, .setEasy), (0.52, .setEasy), (0.65, .setModerate), (0.70, .setModerate), (0.82, .setHard), (1.0, .appAccent),
            (0.46, .setEasy), (0.53, .setEasy), (0.63, .setModerate), (0.72, .setModerate), (0.85, .setHard), (0.95, .setNearMax),
            (0.50, .setEasy), (0.55, .setEasy), (0.67, .setModerate), (0.71, .setModerate), (0.83, .setHard), (1.0, .appAccent),
            (0.47, .setEasy), (0.51, .setEasy), (0.64, .setModerate), (0.69, .setModerate), (0.81, .setHard), (0.96, .setNearMax),
            (0.49, .setEasy), (0.54, .setEasy), (0.66, .setModerate), (0.73, .setModerate), (0.84, .setHard), (1.0, .appAccent),
        ]

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Set Intensity")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 3) {
                    Text("Deadlifts")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.appAccent)
                }
            }

            HStack(spacing: 0) {
                HStack(alignment: .bottom, spacing: 2) {
                    ForEach(barData.indices, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(barData[i].color)
                            .frame(height: 80 * barData[i].height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: 80)

                // Y-axis labels
                VStack {
                    Text("265")
                    Spacer()
                    Text("200")
                    Spacer()
                    Text("135")
                }
                .font(.system(size: 8))
                .foregroundStyle(.white.opacity(0.4))
                .frame(width: 28, height: 80)
                .padding(.leading, 4)
            }

            HStack(spacing: 10) {
                Spacer()
                legendItem(color: .setEasy, label: "Easy")
                legendItem(color: .setModerate, label: "Moderate")
                legendItem(color: .setHard, label: "Hard")
                legendItem(color: .setNearMax, label: "Redline")
                legendItem(color: .appAccent, label: "Progress")
                Spacer()
            }
        }
        .padding(12)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Widget 4: Per-Exercise Volume

    private var perExerciseVolumeWidget: some View {
        let calendar = Calendar.current
        let now = Date()
        // 20 weeks for thinner bars
        let fakeData: [(weekOffset: Int, volume: Double, color: Color)] = [
            (-19, 10000, Color(white: 0.4)),
            (-18, 13500, .setModerate),
            (-17, 16000, .setEasy),
            (-16, 12000, Color(white: 0.4)),
            (-15, 15500, .setModerate),
            (-14, 18000, .setEasy),
            (-13, 8200, Color(white: 0.4)),
            (-12, 14500, .setModerate),
            (-11, 20000, .setEasy),
            (-10, 22500, .appAccent),
            (-9, 16800, .setEasy),
            (-8, 25100, .appAccent),
            (-7, 11200, .setModerate),
            (-6, 27400, .appAccent),
            (-5, 19500, .setEasy),
            (-4, 15000, .setModerate),
            (-3, 23000, .appAccent),
            (-2, 18500, .setEasy),
            (-1, 26000, .appAccent),
            (0, 21000, .setEasy),
        ]
        let chartData = fakeData.map { item in
            (date: calendar.date(byAdding: .weekOfYear, value: item.weekOffset, to: now)!,
             volume: item.volume,
             color: item.color)
        }
        let avg = 18000.0

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                Text("Per-Exercise Volume")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                HStack(spacing: 3) {
                    Text("Deadlifts")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Color.appAccent)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.appAccent)
                }
            }

            Chart {
                ForEach(chartData.indices, id: \.self) { i in
                    let item = chartData[i]
                    BarMark(
                        x: .value("Week", item.date, unit: .weekOfYear),
                        y: .value("Volume", item.volume)
                    )
                    .foregroundStyle(item.color)
                    .cornerRadius(3)
                }

                RuleMark(y: .value("Avg", avg))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(Color.white.opacity(0.35))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .weekOfYear, count: 5)) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 9))
                        .foregroundStyle(Color.white.opacity(0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(Color.white.opacity(0.1))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text(formatVolume(v))
                                .font(.system(size: 9))
                                .foregroundStyle(Color.white.opacity(0.5))
                        }
                    }
                }
            }
            .frame(height: 120)
        }
        .padding(12)
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Helpers

    private func compactPill(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(white: 0.18))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
        }
    }

    private func legendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 9))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
                .fixedSize()
        }
    }

    private func formatVolume(_ value: Double) -> String {
        if value >= 1000 {
            return String(format: "%.0fk", value / 1000)
        }
        return String(format: "%.0f", value)
    }
}
