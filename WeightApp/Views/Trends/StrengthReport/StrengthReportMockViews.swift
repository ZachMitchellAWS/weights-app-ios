//
//  StrengthReportMockViews.swift
//  WeightApp
//
//  Developer-menu "Strength Report" UI mockups. Three interchangeable centerpiece
//  layouts (grid / rows / wheel) for the five fundamental lifts, wrapped in a full
//  report and presented as a dismissible sheet. Mock-only — fabricated data, no
//  persistence or networking, not referenced by the shipping app.
//

import SwiftUI

// MARK: - Layout selector

enum ReportLayout: String, Identifiable, CaseIterable {
    case grid, rows, wheel
    var id: String { rawValue }

    var navTitle: String {
        switch self {
        case .grid: return "Report · Grid"
        case .rows: return "Report · Rows"
        case .wheel: return "Report · Wheel"
        }
    }

    var centerpieceHint: String {
        switch self {
        case .grid, .rows: return "Brighter = performed more recently"
        case .wheel: return "Reach = tier progress · brightness = recency"
        }
    }
}

private func shortLiftName(_ name: String) -> String {
    switch name {
    case "Overhead Press": return "OHP"
    case "Barbell Rows": return "Rows"
    case "Bench Press": return "Bench"
    case "Deadlifts": return "Deadlift"
    case "Squats": return "Squat"
    default: return name
    }
}

private let gainColor = StrengthTier.advanced.color   // green

// MARK: - Grid centerpiece

struct LiftsGridCenterpiece: View {
    let lifts: [LiftReportItem]
    private let columns = [GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10),
                           GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(lifts) { LiftGridTile(lift: $0) }
        }
    }
}

private struct LiftGridTile: View {
    let lift: LiftReportItem

    var body: some View {
        VStack(spacing: 6) {
            Image(lift.icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .foregroundStyle(lift.tier.color)

            Text(shortLiftName(lift.name))
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text(ReportFmt.weight(lift.e1rm))
                .font(.interSemiBold(size: 15))
                .foregroundStyle(.white)

            Text(ReportFmt.delta(lift.e1rmDelta))
                .font(.caption2.weight(.semibold))
                .foregroundStyle(lift.e1rmDelta > 0 ? gainColor : .white.opacity(0.35))

            tierRing
        }
        .opacity(lift.recency)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var tierRing: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.12), lineWidth: 4)
            Circle()
                .trim(from: 0, to: lift.tierProgress)
                .stroke(lift.tier.color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(ReportFmt.tierAbbrev(lift.tier))
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(lift.tier.color)
        }
        .frame(width: 34, height: 34)
        .padding(.top, 2)
    }
}

// MARK: - Rows centerpiece

struct LiftsRowsCenterpiece: View {
    let lifts: [LiftReportItem]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(lifts.enumerated()), id: \.element.id) { index, lift in
                LiftRow(lift: lift)
                if index < lifts.count - 1 {
                    Divider().overlay(Color.white.opacity(0.06))
                }
            }
        }
    }
}

private struct LiftRow: View {
    let lift: LiftReportItem

    private var daysLabel: String {
        lift.daysSinceLastPerformed <= 7 ? "\(lift.daysSinceLastPerformed)d ago" : "not this week"
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(lift.icon)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(lift.tier.color)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(lift.name)
                        .font(.interSemiBold(size: 14))
                        .foregroundStyle(.white)
                    Spacer()
                    Text(ReportFmt.weight(lift.e1rm))
                        .font(.interSemiBold(size: 14))
                        .foregroundStyle(.white)
                }

                HStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.1)).frame(height: 5)
                            Capsule().fill(lift.tier.color)
                                .frame(width: geo.size.width * CGFloat(lift.tierProgress), height: 5)
                        }
                        .frame(height: 5)
                    }
                    .frame(height: 5)

                    Text(ReportFmt.tierAbbrev(lift.tier))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(lift.tier.color)
                        .frame(width: 40, alignment: .trailing)
                }

                HStack {
                    Text(ReportFmt.delta(lift.e1rmDelta))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(lift.e1rmDelta > 0 ? gainColor : .white.opacity(0.35))
                    Spacer()
                    Text(daysLabel)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
        .opacity(lift.recency)
        .padding(.vertical, 10)
    }
}

// MARK: - Wheel centerpiece (radial pentagon)

struct LiftsWheelCenterpiece: View {
    let lifts: [LiftReportItem]

    // Canonical order so the pentagon shape is stable across scenarios.
    private var ordered: [LiftReportItem] {
        let order = TrendsCalculator.fundamentalExercises.map(\.name)
        return lifts.sorted {
            (order.firstIndex(of: $0.name) ?? 0) < (order.firstIndex(of: $1.name) ?? 0)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, 300)
            let center = CGPoint(x: geo.size.width / 2, y: 150)
            let radius = s / 2 - 52

            ZStack {
                // Guide rings
                ForEach([0.34, 0.67, 1.0], id: \.self) { f in
                    ringPath(fraction: CGFloat(f), center: center, radius: radius)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                // Axes
                ForEach(ordered.indices, id: \.self) { i in
                    Path { p in
                        p.move(to: center)
                        p.addLine(to: point(i, 1.0, center, radius))
                    }
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
                // Data polygon
                dataPath(center: center, radius: radius)
                    .fill(Color.appAccent.opacity(0.18))
                dataPath(center: center, radius: radius)
                    .stroke(Color.appAccent.opacity(0.85), lineWidth: 2)
                // Vertex dots (brightness = recency)
                ForEach(ordered.indices, id: \.self) { i in
                    Circle()
                        .fill(ordered[i].tier.color)
                        .frame(width: 9, height: 9)
                        .opacity(ordered[i].recency)
                        .position(point(i, CGFloat(ordered[i].tierProgress), center, radius))
                }
                // Labels
                ForEach(ordered.indices, id: \.self) { i in
                    wheelLabel(ordered[i])
                        .position(labelPoint(i, center, radius))
                }
            }
        }
        .frame(height: 300)
    }

    private func wheelLabel(_ lift: LiftReportItem) -> some View {
        VStack(spacing: 1) {
            Text(shortLiftName(lift.name))
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
            Text(ReportFmt.tierAbbrev(lift.tier))
                .font(.system(size: 8))
                .foregroundStyle(lift.tier.color)
        }
        .opacity(max(0.45, lift.recency))
    }

    // Geometry helpers
    private func point(_ i: Int, _ frac: CGFloat, _ center: CGPoint, _ radius: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(ordered.count)
        return CGPoint(x: center.x + cos(angle) * frac * radius,
                       y: center.y + sin(angle) * frac * radius)
    }

    private func labelPoint(_ i: Int, _ center: CGPoint, _ radius: CGFloat) -> CGPoint {
        let angle = -CGFloat.pi / 2 + CGFloat(i) * 2 * .pi / CGFloat(ordered.count)
        return CGPoint(x: center.x + cos(angle) * (radius + 26),
                       y: center.y + sin(angle) * (radius + 22))
    }

    private func ringPath(fraction: CGFloat, center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for i in ordered.indices {
                let pt = point(i, fraction, center, radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }

    private func dataPath(center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            for i in ordered.indices {
                let pt = point(i, CGFloat(ordered[i].tierProgress), center, radius)
                if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
            }
            p.closeSubpath()
        }
    }
}

// MARK: - Assembled report

struct StrengthReportMockView: View {
    let sample: StrengthReportSample
    let layout: ReportLayout

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ReportHeaderView(sample: sample)
                OverallTierHero(sample: sample)

                WidgetCard(title: "The Five Lifts", subtitle: layout.centerpieceHint) {
                    centerpiece
                }

                WidgetCard(title: "Volume vs Your Average",
                           subtitle: "This week vs your trailing weekly average") {
                    VolumeVsAverageChart(lifts: sample.lifts)
                }

                WidgetCard(title: "Week Over Week", subtitle: "Total tonnage · Mon–Sun") {
                    WeekTrendChart(points: sample.weekTrend)
                }

                VStack(alignment: .leading, spacing: 10) {
                    ReportSectionLabel(text: "HIGHLIGHTS")
                    HighlightChips(sample: sample)
                }

                AISummaryLine(text: sample.aiSummary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .background(Color.black.ignoresSafeArea())
    }

    @ViewBuilder private var centerpiece: some View {
        switch layout {
        case .grid: LiftsGridCenterpiece(lifts: sample.lifts)
        case .rows: LiftsRowsCenterpiece(lifts: sample.lifts)
        case .wheel: LiftsWheelCenterpiece(lifts: sample.lifts)
        }
    }
}

// MARK: - Presentation sheet (developer menu)

struct StrengthReportPreviewSheet: View {
    let layout: ReportLayout
    @Environment(\.dismiss) private var dismiss
    @State private var scenario: Scenario = .strong

    enum Scenario: String, CaseIterable, Identifiable {
        case strong = "Strong week"
        case light = "Light week"
        var id: String { rawValue }
        var sample: StrengthReportSample {
            self == .strong ? .thisWeekStrong : .lightWeek
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 0) {
                    Picker("Scenario", selection: $scenario) {
                        ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    StrengthReportMockView(sample: scenario.sample, layout: layout)
                }
            }
            .navigationTitle(layout.navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Color.appAccent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
