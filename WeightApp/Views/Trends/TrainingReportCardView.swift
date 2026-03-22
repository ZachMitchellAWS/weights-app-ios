//
//  TrainingReportCardView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/18/26.
//

import SwiftUI

struct TrainingReportCardView: View {
    let data: ReportCardData
    var weightUnit: WeightUnit = .lbs

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private let cardBg = Color(white: 0.10)
    private let subtleBorder = Color(white: 0.18)

    var body: some View {
        VStack(spacing: 0) {
            headerSection
            Spacer().frame(height: 12)
            overallTierSection
            Spacer().frame(height: 10)
            exerciseSection
            Spacer().frame(height: 12)
            intensityBar
            Spacer().frame(height: 10)
            statsGrid
            Spacer(minLength: 6)
            footerSection
        }
        .padding(.horizontal, 20)
        .frame(width: 360, height: 780)
        .background(
            ZStack {
                Color.black
                RadialGradient(
                    colors: [data.overallTier.color.opacity(0.10), .clear],
                    center: .top,
                    startRadius: 40,
                    endRadius: 350
                )
            }
        )
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(spacing: 3) {
            Spacer().frame(height: 60)

            HStack(spacing: 8) {
                Image("LiftTheBullIcon")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.appLogoColor)
                    .frame(width: 22, height: 22)
                Text("LIFT THE BULL")
                    .font(.bebasNeue(size: 18))
                    .foregroundColor(.white)
                    .tracking(2)
            }

            Text("PROGRESS CARD")
                .font(.bebasNeue(size: 28))
                .foregroundColor(.appAccent)
                .tracking(1)

            Text("\(Self.dateFormatter.string(from: data.dateRangeStart)) — \(Self.dateFormatter.string(from: data.dateRangeEnd))")
                .font(.inter(size: 11))
                .foregroundColor(.white.opacity(0.45))

            Rectangle()
                .fill(Color.white.opacity(0.12))
                .frame(width: 80, height: 1)
                .padding(.top, 2)
        }
    }

    // MARK: - Overall Tier

    private var overallTierSection: some View {
        HStack(spacing: 12) {
            // Tier icon + name
            VStack(spacing: 4) {
                Image("LiftTheBullIcon")
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .foregroundColor(.appLogoColor)
                    .frame(width: 44, height: 44)

                Text(data.overallTier.title.uppercased())
                    .font(.bebasNeue(size: 30))
                    .foregroundColor(data.overallTier.color)

                if data.previousOverallTier != data.overallTier {
                    HStack(spacing: 5) {
                        Text(data.previousOverallTier.title)
                            .foregroundColor(data.previousOverallTier.color)
                        Image(systemName: "arrow.right")
                            .foregroundColor(.white.opacity(0.3))
                            .font(.system(size: 9))
                        Text(data.overallTier.title)
                            .foregroundColor(data.overallTier.color)
                    }
                    .font(.interSemiBold(size: 11))
                }
            }
            .frame(maxWidth: .infinity)

            Rectangle()
                .fill(subtleBorder)
                .frame(width: 1, height: 80)

            // Quick stats column
            VStack(alignment: .leading, spacing: 10) {
                quickStat(icon: "trophy.fill", label: "Records", value: "\(data.totalPRs)", color: .setPR)
                quickStat(icon: "star.fill", label: "Milestones", value: "\(data.milestonesAchieved)/\(data.milestonesTotal)", color: .appAccent)
                quickStat(icon: "flame.fill", label: "Days Trained", value: "\(data.trainingDays)", color: .setModerate)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(cardBg)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(data.overallTier.color.opacity(0.2), lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func quickStat(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(color)
                .frame(width: 14)
            Text(label)
                .font(.inter(size: 11))
                .foregroundColor(.white)
            Spacer()
            Text(value)
                .font(.interSemiBold(size: 13))
                .bold()
                .foregroundColor(color)
        }
    }

    // MARK: - Exercise Cards

    private var exerciseSection: some View {
        VStack(spacing: 5) {
            ForEach(Array(data.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseRow(exercise)
            }
        }
    }

    private func exerciseRow(_ exercise: ExerciseReportData) -> some View {
        HStack(spacing: 5) {
            // Icon
            Image(exercise.icon)
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(exercise.tier.color)
                .frame(width: 22, height: 22)

            Spacer().frame(width: 4)

            // Name + BW ratio — flexible
            VStack(alignment: .leading, spacing: 1) {
                Text(exercise.name)
                    .font(.interSemiBold(size: 12))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if let ratio = exercise.bwRatio {
                    Text(String(format: "%.1f× BW", ratio))
                        .font(.inter(size: 8))
                        .foregroundColor(.white.opacity(0.35))
                }
            }

            Spacer(minLength: 2)

            // e1RM value — fixed width for cross-row alignment
            Group {
                if let e1rm = exercise.currentE1RM {
                    HStack(alignment: .firstTextBaseline, spacing: 1) {
                        Text("\(Int(weightUnit.fromLbs(e1rm)))")
                            .font(.bebasNeue(size: 22))
                            .foregroundColor(.appAccent)
                        Text(weightUnit.label)
                            .font(.inter(size: 7))
                            .foregroundColor(.appAccent.opacity(0.5))
                    }
                } else {
                    Text("—")
                        .font(.bebasNeue(size: 22))
                        .foregroundColor(.white.opacity(0.2))
                }
            }
            .frame(width: 56, alignment: .trailing)

            // Delta pill — fixed width for consistency
            deltaPill(exercise)
                .frame(width: 48)

            // Tier pill + progress bar
            VStack(spacing: 5) {
                Text(exercise.tier.title)
                    .font(.interSemiBold(size: 9))
                    .foregroundColor(exercise.tier.color)
                    .frame(width: 64)
                    .frame(height: 20)
                    .background(exercise.tier.color.opacity(0.15))
                    .clipShape(Capsule())

                // Progress bar within tier
                if let progress = exercise.tierProgress {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 64, height: 2.5)
                        RoundedRectangle(cornerRadius: 1.25)
                            .fill(exercise.tier.color)
                            .frame(width: max(2, 64 * progress), height: 2.5)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func deltaPill(_ exercise: ExerciseReportData) -> some View {
        Group {
            if let delta = exercise.delta {
                let sign = delta > 0 ? "+" : ""
                let text = abs(delta) < 100 ? String(format: "%@%.1f", sign, delta) : "\(sign)\(Int(delta))"
                Text(text)
                    .font(.interSemiBold(size: 10))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(delta > 0 ? .setEasy : .setNearMax)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background((delta > 0 ? Color.setEasy : Color.setNearMax).opacity(0.15))
                    .clipShape(Capsule())
            } else if exercise.currentE1RM != nil {
                Text("NEW")
                    .font(.interSemiBold(size: 10))
                    .foregroundColor(.appAccent)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.appAccent.opacity(0.15))
                    .clipShape(Capsule())
            }
        }
    }

    // MARK: - Intensity Bar

    private var intensityBar: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let w = geo.size.width
                HStack(spacing: 1.5) {
                    intensitySegment(pct: data.intensity.easyPct, color: .setEasy, width: w)
                    intensitySegment(pct: data.intensity.moderatePct, color: .setModerate, width: w)
                    intensitySegment(pct: data.intensity.hardPct, color: .setHard, width: w)
                    intensitySegment(pct: data.intensity.redlinePct, color: .setNearMax, width: w)
                    intensitySegment(pct: data.intensity.prPct, color: .setPR, width: w)
                }
            }
            .frame(height: 24)
            .clipShape(RoundedRectangle(cornerRadius: 5))

            // Legend row — evenly distributed
            HStack {
                Spacer()
                intensityLegendItem(color: .setEasy, label: "Easy")
                Spacer()
                intensityLegendItem(color: .setModerate, label: "Moderate")
                Spacer()
                intensityLegendItem(color: .setHard, label: "Hard")
                Spacer()
                intensityLegendItem(color: .setNearMax, label: "Redline")
                Spacer()
                intensityLegendItem(color: .setPR, label: "1RM Progress")
                Spacer()
            }
        }
    }

    private func intensitySegment(pct: Double, color: Color, width: CGFloat) -> some View {
        let usable = width - 4 * 1.5 // subtract inter-segment spacing
        let segWidth = max(0, pct * usable)
        return color.frame(width: segWidth)
    }

    private func intensityLegendItem(color: Color, label: String) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.inter(size: 9))
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Stats Grid

    private var statsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                statCell(value: "\(data.totalSetsLogged)", label: "Sets Logged", icon: "figure.strengthtraining.traditional", color: .white)
                Rectangle().fill(subtleBorder).frame(width: 0.5, height: 48)
                statCell(value: "\(data.trainingWeeks) wks", label: "Training Span", icon: "clock.fill", color: .white)
            }

            Rectangle().fill(subtleBorder).frame(height: 0.5)

            HStack(spacing: 0) {
                statCell(value: formattedVolume, label: "Total Volume", icon: "scalemass.fill", color: .appAccent)
                Rectangle().fill(subtleBorder).frame(width: 0.5, height: 48)
                statCell(value: formattedAvgWeekly, label: "Avg Weekly Vol", icon: "chart.line.uptrend.xyaxis", color: .appAccent)
            }
        }
        .background(cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func statCell(value: String, label: String, icon: String, color: Color) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(color.opacity(0.4))
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.bebasNeue(size: 20))
                    .foregroundColor(color)
                Text(label)
                    .font(.inter(size: 8))
                    .foregroundColor(.white.opacity(0.35))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    private var formattedVolume: String {
        if data.totalVolume >= 1_000_000 {
            return String(format: "%.1fM", data.totalVolume / 1_000_000)
        } else if data.totalVolume >= 1_000 {
            let k = data.totalVolume / 1_000
            if k >= 100 {
                return "\(Int(k))K"
            }
            return String(format: "%.1fK", k)
        }
        return "\(Int(data.totalVolume))"
    }

    private var formattedAvgWeekly: String {
        if data.avgWeeklyVolume >= 1_000 {
            return String(format: "%.1fK", data.avgWeeklyVolume / 1_000)
        }
        return "\(Int(data.avgWeeklyVolume))"
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack(spacing: 4) {
            Image("LiftTheBullIcon")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundColor(.white.opacity(0.25))
                .frame(width: 12, height: 12)
            Text("Lift the Bull")
                .font(.inter(size: 10))
                .foregroundColor(.white.opacity(0.25))
        }
        .padding(.bottom, 16)
    }
}
