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
                    isPremium: isPremium,
                    showUpsell: $showUpsell
                )

                if hasEnoughData {
                    balanceChart
                    insightWidget
                    detailRows
                } else {
                    emptyState
                }

                PRTimelineWidget(allSets: allSets)

                BestLiftsWidget(allSets: allSets)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.hidden)
        .fullScreenCover(isPresented: $showUpsell) {
            UpsellView { _ in showUpsell = false }
        }
    }

    // MARK: - Balance Chart

    private var balanceChart: some View {
        WidgetCard(title: "Strength Balance", subtitle: "Ratio to ideal proportions") {
            Chart(balanceData) { exercise in
                BarMark(
                    xStart: .value("Start", 0.7),
                    xEnd: .value("Score", exercise.balanceScore ?? 0.7),
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

            // Legend
            HStack(spacing: 16) {
                legendDot(color: .balanceWeak, label: "Weak")
                legendDot(color: .balanceMild, label: "Mild")
                legendDot(color: .balanceGood, label: "Balanced")
                legendDot(color: .balanceCoolMild, label: "Strong")
                legendDot(color: .balanceStrong, label: "V. Strong")
            }
            .padding(.top, 4)
        }
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

    // MARK: - Insight Widget

    private var insightWidget: some View {
        WidgetCard(title: "Insight") {
            let insight = TrendsCalculator.balanceInsight(from: balanceData)
            Text(insightAttributedString(insight))
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
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
