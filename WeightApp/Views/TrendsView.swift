//
//  TrendsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData

struct TrendsView: View {
    @ObservedObject var selectedSetData: SelectedSetData
    @ObservedObject private var syncService = SyncService.shared
    @Binding var selectedTab: Int
    @State private var trendsTab: TrendsTab = .analytics

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker
                TrendsPicker(selectedTab: $trendsTab)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Content based on selected tab
                // AnalyticsView: only rendered when selected (avoids expensive widget recomputation while on other tabs)
                // HistoryView: always in tree (preserves scroll position, delete mode state) but hidden via opacity
                ZStack {
                    if trendsTab == .analytics {
                        AnalyticsView()
                    }

                    HistoryView(
                        selectedSetData: selectedSetData,
                        selectedTab: $selectedTab,
                        isVisible: trendsTab == .history
                    )
                    .opacity(trendsTab == .history ? 1 : 0)
                    .allowsHitTesting(trendsTab == .history)
                }
            }
            .background(Color.black)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if syncService.isSyncingLiftSets {
                    HStack(spacing: 8) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: Color.appAccent))
                            .scaleEffect(0.8)

                        Text(syncService.liftSetSyncProgress ?? "Syncing...")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))

                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(white: 0.1))
                }
            }
        }
    }
}
