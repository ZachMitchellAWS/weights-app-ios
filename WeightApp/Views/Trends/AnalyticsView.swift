//
//  AnalyticsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI
import SwiftData

struct AnalyticsView: View {
    private static var setsDescriptor: FetchDescriptor<LiftSet> {
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        return FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }
    @Query(setsDescriptor) private var allSets: [LiftSet]

    private static var estimated1RMsDescriptor: FetchDescriptor<Estimated1RM> {
        let cutoff = Calendar.current.date(byAdding: .month, value: -6, to: Date())!
        return FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff }
        )
    }
    @Query(estimated1RMsDescriptor) private var allEstimated1RM: [Estimated1RM]

    @Query(filter: #Predicate<Exercise> { !$0.deleted }, sort: \Exercise.createdAt) private var exercises: [Exercise]

    @Query private var entitlementRecords: [EntitlementGrant]
    @Query private var userPropertiesArray: [UserProperties]
    @Environment(\.modelContext) private var modelContext
    @State private var showUpsell = false
    @State private var showReportCardUpsell = false
    @State private var showShareSheet = false
    @State private var reportCardImage: UIImage? = nil
    @State private var isGenerating = false

    // Static flag to track if we've ever loaded (persists across view recreation)
    private static var hasEverLoaded = false
    @State private var isLoaded = AnalyticsView.hasEverLoaded

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var userProperties: UserProperties? {
        userPropertiesArray.first
    }

    private var canGenerate: Bool {
        userProperties?.bodyweight != nil && userProperties?.biologicalSex != nil && !allSets.isEmpty
    }

    /// Page index for the Progress Card feature in the upsell carousel
    /// (page 0 = overview, pages 1..N = features in order)
    private var progressCardUpsellPage: Int {
        let index = SubscriptionConfig.premiumFeatures.firstIndex { $0.title == "Progress Card" } ?? (SubscriptionConfig.premiumFeatures.count - 1)
        return index + 1
    }

    /// Page index for the Advanced Analytics feature in the upsell carousel
    private var analyticsUpsellPage: Int {
        let index = SubscriptionConfig.premiumFeatures.firstIndex { $0.title == "Advanced Analytics" } ?? 2
        return index + 1
    }

    var body: some View {
        Group {
            if isLoaded {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        reportCardButton

                        MonthlySnapshotWidget(allSets: allSets, allEstimated1RM: allEstimated1RM)

                        FrequencyCalendarWidget(allSets: allSets, isPremium: isPremium, showUpsell: $showUpsell)

                        TrainingRecencyWidget(allSets: allSets, isPremium: isPremium, showUpsell: $showUpsell)

                        TierProgressionWidget(
                            allEstimated1RM: allEstimated1RM,
                            bodyweight: userProperties?.bodyweight ?? 200.0,
                            sex: BiologicalSex(rawValue: userProperties?.biologicalSex ?? "male") ?? .male,
                            isPremium: isPremium,
                            weightUnit: userProperties?.preferredWeightUnit ?? .lbs,
                            showUpsell: $showUpsell
                        )

                        OneRMProgressionWidget(allEstimated1RM: allEstimated1RM, allExerciseNames: exercises.map(\.name))

                        WeeklyVolumeWidget(allSets: allSets, weightUnit: userProperties?.preferredWeightUnit ?? .lbs, isPremium: isPremium, showUpsell: $showUpsell)

                        ExerciseVolumeWidget(allSets: allSets, weightUnit: userProperties?.preferredWeightUnit ?? .lbs, isPremium: isPremium, showUpsell: $showUpsell)

                        SetIntensityWidget(allSets: allSets, allEstimated1RM: allEstimated1RM, weightUnit: userProperties?.preferredWeightUnit ?? .lbs, isPremium: isPremium, showUpsell: $showUpsell)

                        PRTimelineWidget(allEstimated1RM: allEstimated1RM, isPremium: isPremium, showUpsell: $showUpsell, weightUnit: userProperties?.preferredWeightUnit ?? .lbs)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .padding(.bottom, 60)
                }
                .fullScreenCover(isPresented: $showUpsell) {
                    UpsellView(initialPage: analyticsUpsellPage) { _ in showUpsell = false }
                }
                .fullScreenCover(isPresented: $showReportCardUpsell) {
                    UpsellView(initialPage: progressCardUpsellPage) { _ in showReportCardUpsell = false }
                }
                .sheet(isPresented: $showShareSheet) {
                    if let image = reportCardImage {
                        ShareSheet(activityItems: [
                            image,
                            "Check out my Progress Card from Lift the Bull!" as String
                        ])
                    }
                }
            } else {
                VStack {
                    Spacer()
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: Color.appAccent))
                    Spacer()
                }
            }
        }
        .background(Color.black)
        .task {
            guard !isLoaded else { return }
            // Small delay to allow tab switch animation to complete
            try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
            await MainActor.run {
                AnalyticsView.hasEverLoaded = true
                isLoaded = true
            }
        }
    }

    // MARK: - Report Card Button

    private var reportCardButton: some View {
        Button {
            if !isPremium {
                showReportCardUpsell = true
            } else if canGenerate {
                generateAndShare()
            }
        } label: {
            HStack(spacing: 8) {
                if isGenerating {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .appAccent))
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.appAccent)
                }
                Text("Progress Card")
                    .font(.interSemiBold(size: 15))
                    .bold()
                    .foregroundColor(.white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(Color.white.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.appAccent.opacity(0.4), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .disabled(isGenerating || (isPremium && !canGenerate))
    }

    private func generateAndShare() {
        guard let bw = userProperties?.bodyweight,
              let sex = userProperties?.biologicalSex else { return }
        isGenerating = true
        DispatchQueue.main.async {
            reportCardImage = ReportCardGenerator.generate(
                modelContext: modelContext,
                bodyweight: bw,
                biologicalSex: sex,
                weightUnit: userProperties?.preferredWeightUnit ?? .lbs
            )
            isGenerating = false
            if reportCardImage != nil {
                showShareSheet = true
            }
        }
    }
}
