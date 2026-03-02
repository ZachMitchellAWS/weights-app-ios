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
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        return FetchDescriptor<LiftSet>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff },
            sortBy: [SortDescriptor(\.createdAt)]
        )
    }
    @Query(setsDescriptor) private var allSets: [LiftSet]

    private static var estimated1RMsDescriptor: FetchDescriptor<Estimated1RM> {
        let cutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
        return FetchDescriptor<Estimated1RM>(
            predicate: #Predicate { !$0.deleted && $0.createdAt >= cutoff }
        )
    }
    @Query(estimated1RMsDescriptor) private var allEstimated1RM: [Estimated1RM]

    @Query(filter: #Predicate<Exercise> { !$0.deleted }, sort: \Exercise.createdAt) private var exercises: [Exercise]

    @Query private var entitlementRecords: [EntitlementGrant]
    @Environment(\.modelContext) private var modelContext
    @State private var showUpsell = false

    // Static flag to track if we've ever loaded (persists across view recreation)
    private static var hasEverLoaded = false
    @State private var isLoaded = AnalyticsView.hasEverLoaded

    private var isPremium: Bool { PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords) }

    var body: some View {
        Group {
            if isLoaded {
                ScrollView {
                    VStack(spacing: 16) {
                        MonthlySnapshotWidget(allSets: allSets)

                        FrequencyCalendarWidget(allSets: allSets)

                        TrainingRecencyWidget(allSets: allSets, isPremium: isPremium, showUpsell: $showUpsell)

                        OneRMProgressionWidget(allEstimated1RM: allEstimated1RM, allExerciseNames: exercises.map(\.name))

                        ExerciseVolumeWidget(allSets: allSets)

                        WeeklyVolumeWidget(allSets: allSets)

                        SetIntensityWidget(allSets: allSets, allEstimated1RM: allEstimated1RM)

                        PRTimelineWidget(allSets: allSets)

                        BestLiftsWidget(allSets: allSets)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .fullScreenCover(isPresented: $showUpsell) {
                    UpsellView { _ in showUpsell = false }
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
}
