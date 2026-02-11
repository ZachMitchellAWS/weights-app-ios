//
//  AnalyticsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/6/26.
//

import SwiftUI

struct AnalyticsView: View {
    let allSets: [LiftSet]
    let allEstimated1RMs: [Estimated1RM]

    // Static flag to track if we've ever loaded (persists across view recreation)
    private static var hasEverLoaded = false
    @State private var isLoaded = AnalyticsView.hasEverLoaded

    var body: some View {
        Group {
            if isLoaded {
                ScrollView {
                    VStack(spacing: 16) {
                        MonthlySummaryWidget(allSets: allSets)

                        OneRMProgressionWidget(allSets: allSets)

                        ExerciseVolumeWidget(allSets: allSets)

                        WeeklyVolumeWidget(allSets: allSets)

                        IntensityDistributionWidget(allSets: allSets)

                        PRTimelineWidget(allSets: allSets)

                        FrequencyCalendarWidget(allSets: allSets)

                        TrainingRecencyWidget(allSets: allSets)

                        BestLiftsWidget(allSets: allSets)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
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
