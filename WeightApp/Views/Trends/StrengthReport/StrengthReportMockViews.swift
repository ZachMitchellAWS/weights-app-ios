//
//  StrengthReportMockViews.swift
//  WeightApp
//
//  Developer-menu mockup for the proposed "Training" sub-tab — a weekly training
//  snapshot that would eventually replace Narratives on the Progress tab.
//
//  NOTHING HERE IS WIRED INTO THE SHIPPING APP. It renders from the hand-authored
//  `StrengthReportSample` scenarios and is reachable only from More → Developer
//  (staging builds). No SwiftData, no networking.
//
//  Design intent — the three Progress sub-tabs answer different questions:
//    • Strength  — what am I? (tier + milestones; a state, path-independent)
//    • Analytics — what have I done? (quantities, all exercises, months)
//    • Training  — how is THIS WEEK going? (a scorecard against an intent)
//
//  So this deliberately echoes the Strength tab's hero recipe (centred all-caps
//  label → big bold value → progress bar) while scoping everything to Mon–Sun.
//  It uses system fonts, like the Strength tab; Bebas Neue is Narratives' signature
//  and would pull this back toward the tab we're replacing.
//

import SwiftUI

// MARK: - Weekly snapshot hero

/// The above-the-fold card. Coverage leads (the headline count), progress rides
/// along inside the same five-lift strip, so neither goal needs a second screen.
struct WeeklySnapshotHero: View {
    let sample: StrengthReportSample

    private var completeCount: Int {
        sample.lifts.filter(\.isComplete).count
    }

    /// Average completion across all five, so partial work still moves the bar even
    /// when nothing has reached 1.0 — the light-week case.
    private var aggregate: Double {
        guard !sample.lifts.isEmpty else { return 0 }
        return sample.lifts.map(\.completion).reduce(0, +) / Double(sample.lifts.count)
    }

    var body: some View {
        VStack(spacing: 16) {
            // Scope, stated up front — this is what separates the tab from Strength.
            VStack(spacing: 6) {
                Text("THIS WEEK")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)
                Text(sample.weekRangeText)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Headline — same slot the Strength tab gives your tier.
            VStack(spacing: 4) {
                Text("\(completeCount) of \(sample.lifts.count)")
                    .font(.title.weight(.bold))
                    .foregroundStyle(completeCount > 0 ? Color.appAccent : .white.opacity(0.5))
                Text("LIFTS TRAINED")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .tracking(1.2)
            }

            // Aggregate bar carries the partial credit the headline count can't.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(.white.opacity(0.1))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.appAccent)
                        .frame(width: max(0, geo.size.width * aggregate))
                }
            }
            .frame(height: 6)

            Divider().background(.white.opacity(0.1))

            HStack(alignment: .top, spacing: 0) {
                ForEach(sample.lifts) { lift in
                    LiftCompletionColumn(lift: lift)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding()
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// One of the five lifts. Carries coverage (fill) and progress (delta) at once.
private struct LiftCompletionColumn: View {
    let lift: LiftReportItem

    var body: some View {
        VStack(spacing: 6) {
            Image(lift.icon)
                .resizable()
                .scaledToFit()
                .frame(width: 26, height: 26)
                .foregroundStyle(lift.completionColor)

            Text(shortLiftName(lift.name))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(lift.completion > 0 ? 0.7 : 0.3))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            // Per-lift spectrum. Same ramp as the icon so the column reads as one unit.
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(.white.opacity(0.1))
                    .frame(width: 34, height: 4)
                RoundedRectangle(cornerRadius: 2)
                    .fill(lift.completionColor)
                    .frame(width: 34 * lift.completion, height: 4)
            }

            // An e1RM gain is the goal, so it wins the label slot when present;
            // otherwise show the work that did happen rather than a bare dash.
            Group {
                if lift.e1rmDelta > 0 {
                    Text("▲\(Int(lift.e1rmDelta))")
                        .foregroundStyle(Color.appAccent)
                } else if lift.setsThisWeek > 0 {
                    Text("\(lift.setsThisWeek) set\(lift.setsThisWeek == 1 ? "" : "s")")
                        .foregroundStyle(.white.opacity(0.45))
                } else {
                    Text("—")
                        .foregroundStyle(.white.opacity(0.25))
                }
            }
            .font(.system(size: 10, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
    }
}

/// Trims the long names so five columns fit without wrapping.
private func shortLiftName(_ name: String) -> String {
    switch name {
    case "Deadlifts": return "DEAD"
    case "Squats": return "SQUAT"
    case "Bench Press": return "BENCH"
    case "Barbell Rows": return "ROW"
    case "Overhead Press": return "OHP"
    default: return name.uppercased()
    }
}

// MARK: - Assembled mockup

struct WeeklyTrainingMockView: View {
    let sample: StrengthReportSample

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                WeeklySnapshotHero(sample: sample)

                // Everything below the hero is intentionally sparse for now — the
                // brief was the first screen, not a long report. Supporting cards
                // (volume vs average, week-over-week, movement-category lens) come
                // in later iterations; `StrengthReportComponents.swift` still holds
                // the chart pieces from the previous mockup for that.
                Text("Above-the-fold only — supporting cards to follow")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.25))
                    .frame(maxWidth: .infinity)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black)
    }
}

// MARK: - Dev sheet

struct StrengthReportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var scenario: Scenario = .strong

    enum Scenario: String, CaseIterable, Identifiable {
        case strong = "Strong week"
        case light = "Light week"
        var id: String { rawValue }

        var sample: StrengthReportSample {
            switch self {
            case .strong: return .thisWeekStrong
            case .light: return .lightWeek
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Scenario", selection: $scenario) {
                    ForEach(Scenario.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                WeeklyTrainingMockView(sample: scenario.sample)
            }
            .background(Color.black)
            .navigationTitle("Training · This Week")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}
