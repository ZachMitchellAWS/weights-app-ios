//
//  StrengthReportComponents.swift
//  WeightApp
//
//  Shared subviews for the developer-menu "Strength Report" UI mockups.
//  Aesthetic matches the Strength sub-tab (BalanceView): dark Color(white:0.14)
//  cards, amber accent, StrengthTier colors, Bebas/Inter fonts. Mock-only.
//

import SwiftUI

// MARK: - Palette (mock-local)

private enum ReportColor {
    static let card = Color(white: 0.14)
    static let above = StrengthTier.advanced.color                 // green — at/above average
    static let below = Color(red: 0.90, green: 0.42, blue: 0.36)   // soft red — below average
    static let gain = StrengthTier.advanced.color                  // green — e1RM increase
    static let track = Color.white.opacity(0.08)
}

// MARK: - Header

struct ReportHeaderView: View {
    let sample: StrengthReportSample

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("STRENGTH REPORT")
                .font(.bebasNeue(size: 40))
                .foregroundStyle(.white)
                .tracking(1)

            // Week range with a subtle ‹ › paging affordance (non-functional in mock).
            HStack(spacing: 10) {
                Image(systemName: "chevron.left")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.25))
                Text(sample.weekRangeText)
                    .font(.interSemiBold(size: 14))
                    .foregroundStyle(Color.appAccent)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.25))
            }

            Text("Last 7 days · Mon–Sun")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.4))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Overall tier hero

struct OverallTierHero: View {
    let sample: StrengthReportSample

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OVERALL STRENGTH TIER")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.6))
                .tracking(1.5)

            HStack(alignment: .firstTextBaseline) {
                Text(sample.overallTier.title)
                    .font(.system(.largeTitle, design: .default).weight(.bold))
                    .foregroundStyle(sample.overallTier.color)
                Spacer()
                if let next = sample.overallTier.next {
                    Text("→ \(next.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }

            // Progress toward next tier
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(sample.overallTier.color)
                        .frame(width: geo.size.width * sample.overallTierProgress)
                }
            }
            .frame(height: 6)

            HStack(spacing: 4) {
                Image(systemName: "arrow.down.right.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                Text("Limited by \(sample.limitingLiftName)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ReportColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Volume vs average

struct VolumeVsAverageChart: View {
    let lifts: [LiftReportItem]

    private var maxVolume: Double {
        max(1, lifts.map { max($0.weeklyVolume, $0.avgVolume) }.max() ?? 1)
    }

    var body: some View {
        VStack(spacing: 12) {
            ForEach(lifts) { lift in
                HStack(spacing: 10) {
                    Text(lift.name)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 92, alignment: .leading)
                        .lineLimit(1)

                    GeometryReader { geo in
                        let w = geo.size.width
                        let fill = w * CGFloat(lift.weeklyVolume / maxVolume)
                        let avgX = w * CGFloat(lift.avgVolume / maxVolume)
                        let above = lift.weeklyVolume >= lift.avgVolume
                        ZStack(alignment: .leading) {
                            Capsule().fill(ReportColor.track).frame(height: 10)
                            Capsule()
                                .fill(above ? ReportColor.above : ReportColor.below)
                                .frame(width: fill, height: 10)
                            // trailing-average marker
                            Rectangle()
                                .fill(Color.white.opacity(0.7))
                                .frame(width: 2, height: 16)
                                .offset(x: max(0, avgX - 1))
                        }
                        .frame(height: 16)
                    }
                    .frame(height: 16)

                    Text(ReportFmt.volume(lift.weeklyVolume))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(width: 44, alignment: .trailing)
                }
            }

            HStack(spacing: 6) {
                Rectangle().fill(Color.white.opacity(0.7)).frame(width: 2, height: 11)
                Text("marker = your trailing weekly average")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
                Spacer()
            }
            .padding(.top, 2)
        }
    }
}

// MARK: - Week over week

struct WeekTrendChart: View {
    let points: [WeekPoint]
    private let chartHeight: CGFloat = 96

    private var maxValue: Double { max(1, points.map(\.value).max() ?? 1) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(points) { p in
                VStack(spacing: 6) {
                    Text(ReportFmt.volume(p.value))
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(p.isCurrent ? Color.appAccent : .white.opacity(0.4))

                    RoundedRectangle(cornerRadius: 4)
                        .fill(p.isCurrent ? Color.appAccent : Color.white.opacity(0.22))
                        .frame(height: max(4, chartHeight * CGFloat(p.value / maxValue)))

                    Text(p.label)
                        .font(.system(size: 9))
                        .foregroundStyle(p.isCurrent ? .white.opacity(0.8) : .white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: chartHeight + 34, alignment: .bottom)
    }
}

// MARK: - Highlight chips

struct HighlightChips: View {
    let sample: StrengthReportSample

    var body: some View {
        HStack(spacing: 10) {
            chip(icon: "arrow.up.forward", tint: ReportColor.gain,
                 caption: "Biggest gain", value: sample.biggestGain)
            chip(icon: "flame.fill", tint: Color.appAccent,
                 caption: "Most volume", value: sample.mostVolume)
            chip(icon: "exclamationmark.triangle.fill", tint: ReportColor.below,
                 caption: "Needs work", value: sample.needsAttention)
        }
    }

    private func chip(icon: String, tint: Color, caption: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.interSemiBold(size: 13))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .background(ReportColor.card)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - AI summary (placeholder for a future backend)

struct AISummaryLine: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(Color.appAccent.opacity(0.8))
            VStack(alignment: .leading, spacing: 4) {
                Text(text)
                    .font(.callout.italic())
                    .foregroundStyle(.white.opacity(0.7))
                Text("AI SUMMARY · PREVIEW")
                    .font(.system(size: 9).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.3))
                    .tracking(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(ReportColor.card.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.appAccent.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Small section label used above cards

struct ReportSectionLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
            .tracking(1.5)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
