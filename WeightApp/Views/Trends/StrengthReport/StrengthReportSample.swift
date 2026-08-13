//
//  StrengthReportSample.swift
//  WeightApp
//
//  Fabricated sample data for the developer-menu "Strength Report" UI mockups.
//  This file contains NO persistence or networking — every value is hand-authored
//  so the mockups render without real user data. Nothing here is used by the
//  shipping app; it exists purely to explore the redesigned report UI.
//

import SwiftUI

// MARK: - Recency fade

/// Progressive fade for "how recently was this lift performed".
/// A lift performed today is fully vivid (≈1.0); one untouched for ~14 days
/// decays to the floor. This lets the report avoid snapping to blank each Monday.
func recencyOpacity(daysSince: Int) -> Double {
    let floor = 0.18
    let window = 14.0
    let freshness = max(0.0, 1.0 - Double(daysSince) / window)
    return floor + (1.0 - floor) * freshness
}

// MARK: - Sample models

struct LiftReportItem: Identifiable {
    let id = UUID()
    let name: String
    let icon: String            // asset imageset name, e.g. "DeadliftIcon"
    let tier: StrengthTier
    let e1rm: Double            // lbs
    let e1rmDelta: Double       // lbs gained this period (0 = no increase)
    let setsThisWeek: Int       // sets logged Mon–Sun
    let weeklyVolume: Double    // lbs of tonnage this week
    let avgVolume: Double       // trailing per-week average tonnage
    let daysSinceLastPerformed: Int   // >= 14 reads as "not performed"
    let tierProgress: Double    // 0...1 toward the next tier

    var performedThisWeek: Bool { daysSinceLastPerformed <= 7 }
    var recency: Double { recencyOpacity(daysSince: daysSinceLastPerformed) }

    /// How far this lift got toward "its work is done for the week", 0...1.
    ///
    /// Deliberately NOT binary. Two routes reach 1.0, mirroring what already feeds
    /// the next-focus recommendation:
    ///   • e1RM increased by any amount — that's the actual goal, so it saturates
    ///     immediately regardless of set count.
    ///   • `setsSaturation` sets logged — the volume route, matching next-focus's
    ///     6-set recency cap.
    /// Anything less is partial credit rather than zero: one set is progress.
    var completion: Double {
        if e1rmDelta > 0 { return 1.0 }
        return min(Double(setsThisWeek) / Self.setsSaturation, 1.0)
    }

    /// Set count at which volume alone counts the lift as done for the week.
    static let setsSaturation: Double = 6

    var isComplete: Bool { completion >= 1.0 }

    /// Grey at zero, saturating to full accent at 1.0 — the same visual language as
    /// the Training Activity heatmap (`FrequencyCalendarWidget`), so a barely-touched
    /// lift reads as dim-but-present rather than absent.
    var completionColor: Color {
        guard completion > 0 else { return Color(white: 0.2) }
        return Color.appAccent.opacity(0.25 + 0.75 * completion)
    }
}

struct WeekPoint: Identifiable {
    let id = UUID()
    let label: String
    let value: Double
    let isCurrent: Bool
}

struct StrengthReportSample {
    let weekRangeText: String
    let overallTier: StrengthTier
    let overallTierProgress: Double
    let limitingLiftName: String
    let lifts: [LiftReportItem]
    let weekTrend: [WeekPoint]
    let biggestGain: String
    let mostVolume: String
    let needsAttention: String
    let aiSummary: String
}

// MARK: - Formatting helpers (mock-local; lbs only)

enum ReportFmt {
    static func weight(_ v: Double) -> String { "\(Int(v.rounded())) lb" }

    static func volume(_ v: Double) -> String {
        v >= 1000 ? String(format: "%.1fk", v / 1000) : "\(Int(v))"
    }

    static func delta(_ v: Double) -> String {
        v > 0 ? "▲ \(Int(v.rounded()))" : "—"
    }

    static func tierAbbrev(_ tier: StrengthTier) -> String {
        switch tier {
        case .none: return "—"
        case .novice: return "NOV"
        case .beginner: return "BEG"
        case .intermediate: return "INT"
        case .advanced: return "ADV"
        case .elite: return "ELITE"
        case .legend: return "LGND"
        }
    }
}

// MARK: - Scenarios

extension StrengthReportSample {

    private static let iconFor: [String: String] = Dictionary(
        uniqueKeysWithValues: TrendsCalculator.fundamentalExercises.map { ($0.name, $0.icon) }
    )

    private static func icon(_ name: String) -> String { iconFor[name] ?? "LiftTheBullIcon" }

    // Arrays are split into their own constants so each stays a small, fast-to-
    // type-check expression (large nested literals otherwise trip the compiler).

    // Ordered to match `TrendsCalculator.fundamentalExercises` so the five-lift strip
    // reads the same here as everywhere else in the app.
    private static let strongLifts: [LiftReportItem] = [
        LiftReportItem(name: "Deadlifts", icon: icon("Deadlifts"), tier: .advanced,
                       e1rm: 405, e1rmDelta: 15, setsThisWeek: 5, weeklyVolume: 12_400, avgVolume: 9_000,
                       daysSinceLastPerformed: 1, tierProgress: 0.62),
        LiftReportItem(name: "Squats", icon: icon("Squats"), tier: .advanced,
                       e1rm: 335, e1rmDelta: 10, setsThisWeek: 4, weeklyVolume: 10_100, avgVolume: 9_600,
                       daysSinceLastPerformed: 2, tierProgress: 0.44),
        LiftReportItem(name: "Bench Press", icon: icon("Bench Press"), tier: .intermediate,
                       e1rm: 245, e1rmDelta: 5, setsThisWeek: 3, weeklyVolume: 8_000, avgVolume: 8_200,
                       daysSinceLastPerformed: 3, tierProgress: 0.71),
        // Complete on the VOLUME route rather than a gain — 6 sets, no e1RM increase.
        LiftReportItem(name: "Barbell Rows", icon: icon("Barbell Rows"), tier: .intermediate,
                       e1rm: 205, e1rmDelta: 0, setsThisWeek: 6, weeklyVolume: 6_500, avgVolume: 5_000,
                       daysSinceLastPerformed: 2, tierProgress: 0.30),
        // The laggard: real work done, but only halfway. Shows partial credit.
        LiftReportItem(name: "Overhead Press", icon: icon("Overhead Press"), tier: .beginner,
                       e1rm: 135, e1rmDelta: 0, setsThisWeek: 3, weeklyVolume: 3_000, avgVolume: 3_500,
                       daysSinceLastPerformed: 4, tierProgress: 0.52),
    ]

    // Nothing reaches 1.0 here, but three lifts are non-zero — the case that motivated
    // the spectrum: a light week should not render as five empty slots.
    private static let lightLifts: [LiftReportItem] = [
        LiftReportItem(name: "Deadlifts", icon: icon("Deadlifts"), tier: .advanced,
                       e1rm: 405, e1rmDelta: 0, setsThisWeek: 1, weeklyVolume: 2_800, avgVolume: 9_000,
                       daysSinceLastPerformed: 9, tierProgress: 0.62),
        LiftReportItem(name: "Squats", icon: icon("Squats"), tier: .advanced,
                       e1rm: 335, e1rmDelta: 0, setsThisWeek: 0, weeklyVolume: 0, avgVolume: 9_600,
                       daysSinceLastPerformed: 12, tierProgress: 0.44),
        LiftReportItem(name: "Bench Press", icon: icon("Bench Press"), tier: .intermediate,
                       e1rm: 245, e1rmDelta: 0, setsThisWeek: 3, weeklyVolume: 5_200, avgVolume: 8_200,
                       daysSinceLastPerformed: 2, tierProgress: 0.71),
        LiftReportItem(name: "Barbell Rows", icon: icon("Barbell Rows"), tier: .intermediate,
                       e1rm: 205, e1rmDelta: 0, setsThisWeek: 2, weeklyVolume: 4_100, avgVolume: 5_000,
                       daysSinceLastPerformed: 6, tierProgress: 0.30),
        LiftReportItem(name: "Overhead Press", icon: icon("Overhead Press"), tier: .beginner,
                       e1rm: 135, e1rmDelta: 0, setsThisWeek: 0, weeklyVolume: 0, avgVolume: 3_500,
                       daysSinceLastPerformed: 16, tierProgress: 0.52),
    ]

    private static let strongTrend: [WeekPoint] = [
        WeekPoint(label: "Jul 7", value: 27_000, isCurrent: false),
        WeekPoint(label: "Jul 14", value: 31_000, isCurrent: false),
        WeekPoint(label: "Jul 21", value: 26_500, isCurrent: false),
        WeekPoint(label: "Jul 28", value: 33_000, isCurrent: false),
        WeekPoint(label: "Aug 4", value: 40_000, isCurrent: true),
    ]

    private static let lightTrend: [WeekPoint] = [
        WeekPoint(label: "Jul 7", value: 27_000, isCurrent: false),
        WeekPoint(label: "Jul 14", value: 31_000, isCurrent: false),
        WeekPoint(label: "Jul 21", value: 26_500, isCurrent: false),
        WeekPoint(label: "Jul 28", value: 33_000, isCurrent: false),
        WeekPoint(label: "Aug 4", value: 12_100, isCurrent: true),
    ]

    /// A productive week: most lifts hit, several e1RM gains, volume above average.
    static let thisWeekStrong = StrengthReportSample(
        weekRangeText: "Mon Aug 4 – Sun Aug 10",
        overallTier: .beginner,
        overallTierProgress: 0.52,
        limitingLiftName: "Overhead Press",
        lifts: strongLifts,
        weekTrend: strongTrend,
        biggestGain: "Deadlifts +15 lb",
        mostVolume: "Deadlifts",
        needsAttention: "Overhead Press",
        aiSummary: "Strong week — your posterior chain led the way. Overhead Press is the lift to chase to raise your overall tier."
    )

    /// A light week: a couple of lifts stale (faded), no e1RM gains, volume down.
    static let lightWeek = StrengthReportSample(
        weekRangeText: "Mon Aug 4 – Sun Aug 10",
        overallTier: .beginner,
        overallTierProgress: 0.52,
        limitingLiftName: "Overhead Press",
        lifts: lightLifts,
        weekTrend: lightTrend,
        biggestGain: "—",
        mostVolume: "Bench Press",
        needsAttention: "Overhead Press · 16d",
        aiSummary: "A lighter week — nothing moved on the bar. A good week to get back under Squats and Overhead Press."
    )
}
