//
//  BalanceView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/7/26.
//

import SwiftUI
import SwiftData
import Charts

struct BalanceView: View {
    @Query private var userPropertiesArray: [UserProperties]
    @Query private var entitlementRecords: [EntitlementGrant]
    @Environment(\.modelContext) private var modelContext
    @State private var showUpsell = false

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var userProperties: UserProperties {
        if let props = userPropertiesArray.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private static var setsDescriptor: FetchDescriptor<LiftSet> {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        return FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }
    @Query(setsDescriptor) private var allSets: [LiftSet]

    private static var estimated1RMsDescriptor: FetchDescriptor<Estimated1RM> {
        return FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted }
        )
    }
    @Query(estimated1RMsDescriptor) private var allEstimated1RM: [Estimated1RM]

    private var balanceData: [TrendsCalculator.ExerciseBalance] {
        TrendsCalculator.strengthBalance(from: allEstimated1RM)
    }

    private var hasEnoughData: Bool {
        balanceData.filter { $0.balanceScore != nil }.count >= 2
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                StrengthTierWidget(
                    allEstimated1RM: allEstimated1RM,
                    userProperties: userProperties,
                    isPremium: true,
                    showUpsell: $showUpsell
                )

                StrengthMilestonesWidget(
                    allEstimated1RM: allEstimated1RM,
                    bodyweight: userProperties.bodyweight,
                    biologicalSex: userProperties.biologicalSex,
                    isPremium: true,
                    showUpsell: $showUpsell
                )

                if isPremium {
                    if hasEnoughData {
                        strengthBalanceWidget
                    } else {
                        emptyState
                    }
                } else {
                    lockedBalanceWidget
                }

                // BestLiftsWidget(allSets: allSets)

                Text("Strength estimates are approximations based on your logged sets and standard formulas. Always train within your limits and consult a qualified professional before beginning any exercise program.")
                    .font(.inter(size: 12))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView { _ in showUpsell = false }
        }
    }

    // MARK: - Strength Balance Widget

    private var bodyweight: Double {
        userProperties.bodyweight ?? 200.0
    }

    private var sex: BiologicalSex {
        BiologicalSex(rawValue: userProperties.biologicalSex ?? "male") ?? .male
    }

    private var balanceCategory: TrendsCalculator.BalanceCategory? {
        TrendsCalculator.balanceCategory(from: balanceData, bodyweight: bodyweight, sex: sex)
    }

    private var strengthBalanceWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            VStack(spacing: 6) {
                Text("STRENGTH BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                if let category = balanceCategory {
                    Text(category.title)
                        .font(.title.weight(.bold))
                        .foregroundStyle(category.color)
                }

            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            Chart(balanceData) { exercise in
                let clamped = min(max(exercise.balanceScore ?? 0.7, 0.7), 1.3)
                BarMark(
                    xStart: .value("Start", 0.7),
                    xEnd: .value("Score", clamped),
                    y: .value("Exercise", exercise.exerciseName)
                )
                .foregroundStyle(exercise.balanceColor)
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
            .frame(height: CGFloat(balanceData.count) * 44)

            // Category legend (commented out)
            // VStack(spacing: 6) {
            //     HStack(spacing: 16) {
            //         legendDot(color: TrendsCalculator.BalanceCategory.lopsided.color, label: "Lopsided")
            //         legendDot(color: TrendsCalculator.BalanceCategory.skewed.color, label: "Skewed")
            //         legendDot(color: TrendsCalculator.BalanceCategory.uneven.color, label: "Uneven")
            //     }
            //     HStack(spacing: 16) {
            //         legendDot(color: TrendsCalculator.BalanceCategory.balanced.color, label: "Balanced")
            //         legendDot(color: TrendsCalculator.BalanceCategory.symmetrical.color, label: "Symmetrical")
            //     }
            // }
            // .frame(maxWidth: .infinity)
            // .padding(.top, 4)

            Divider()
                .background(.white.opacity(0.1))
                .padding(.top, 8)

            let insight = TrendsCalculator.balanceInsight(from: balanceData)
            Text(insightAttributedString(insight))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
        }
        .padding()
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.5))
        }
    }


    private func insightAttributedString(_ text: String) -> AttributedString {
        var result = AttributedString(text)
        result.foregroundColor = .white.opacity(0.7)

        // Tint exercise names in their balance color
        for exercise in balanceData where exercise.balanceScore != nil {
            var searchRange = result.startIndex..<result.endIndex
            while let range = result[searchRange].range(of: exercise.exerciseName) {
                result[range].foregroundColor = exercise.balanceColor
                searchRange = range.upperBound..<result.endIndex
            }
        }

        return result
    }

    // MARK: - Detail Rows

    private var detailRows: some View {
        WidgetCard(title: "Current Estimated 1RM") {
            VStack(spacing: 0) {
                ForEach(balanceData) { exercise in
                    HStack(spacing: 12) {
                        // Color accent bar
                        RoundedRectangle(cornerRadius: 2)
                            .fill(exercise.balanceColor)
                            .frame(width: 4, height: 32)

                        // Exercise icon + name
                        Image(exercise.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 24, height: 24)

                        Text(exercise.exerciseName)
                            .font(.subheadline)
                            .foregroundStyle(.white)

                        Spacer()

                        // e1RM value
                        if let e1rm = exercise.current1RM {
                            Text("\(Int(e1rm)) lbs")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                        } else {
                            Text("No data")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .opacity(exercise.current1RM != nil ? 1.0 : 0.3)
                    .padding(.vertical, 8)

                    if exercise.id != balanceData.last?.id {
                        Divider()
                            .background(.white.opacity(0.1))
                    }
                }
            }
        }
    }

    // MARK: - Locked Balance Widget

    private struct FakeBalance: Identifiable {
        let id = UUID()
        let exerciseName: String
        let score: Double
        var color: Color { Color.balanceColor(for: score) }
    }

    private static let fakeBalanceData: [FakeBalance] = [
        FakeBalance(exerciseName: "Deadlift", score: 1.18),
        FakeBalance(exerciseName: "Squat", score: 1.00),
        FakeBalance(exerciseName: "Bench Press", score: 0.89),
        FakeBalance(exerciseName: "Overhead Press", score: 0.78),
        FakeBalance(exerciseName: "Barbell Row", score: 1.10),
    ]

    private var fakeInsightAttributedString: AttributedString {
        let text = "Your Overhead Press is relatively weaker compared to your other lifts, while your Deadlift is a relative strength."
        var result = AttributedString(text)
        result.foregroundColor = .white.opacity(0.7)

        let coloredNames: [(String, Double)] = [
            ("Overhead Press", 0.78),
            ("Deadlift", 1.18),
        ]
        for (name, score) in coloredNames {
            if let range = result.range(of: name) {
                result[range].foregroundColor = Color.balanceColor(for: score)
            }
        }
        return result
    }

    private var lockedBalanceWidget: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Category header
            VStack(spacing: 6) {
                Text("STRENGTH BALANCE")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .tracking(1.5)

                Text(TrendsCalculator.BalanceCategory.uneven.title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(TrendsCalculator.BalanceCategory.uneven.color)

            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)

            // Fake chart
            Chart(Self.fakeBalanceData) { exercise in
                BarMark(
                    xStart: .value("Start", 0.7),
                    xEnd: .value("Score", exercise.score),
                    y: .value("Exercise", exercise.exerciseName)
                )
                .foregroundStyle(exercise.color)
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
            .frame(height: CGFloat(Self.fakeBalanceData.count) * 44)

        }
        .padding()
        .premiumLocked(
            title: "Unlock Strength Balance",
            subtitle: "See how your lifts compare to ideal proportions",
            showUpsell: $showUpsell
        )
        .background(Color(white: 0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Empty State

    private var emptyState: some View {
        WidgetCard(title: "Strength Balance") {
            EmptyWidgetState(
                icon: "scalemass",
                message: "Log sets for at least 2 compound lifts to see your strength balance"
            )
        }
    }
}
