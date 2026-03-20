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
    @State private var trendsTab: TrendsTab = .strength
    @State private var showHistory = false
    @State private var isDeleteModeActive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showHistory {
                    // History header with back chevron, title, and edit toggle
                    HStack {
                        Button {
                            isDeleteModeActive = false
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showHistory = false
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                    .font(.body.weight(.semibold))
                                Text("Back")
                                    .font(.body)
                            }
                            .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("History")
                            .font(.headline)
                            .foregroundStyle(.white)

                        Spacer()

                        Button {
                            isDeleteModeActive.toggle()
                        } label: {
                            Image(systemName: isDeleteModeActive ? "minus.circle.fill" : "minus.circle")
                                .font(.title3)
                                .foregroundStyle(isDeleteModeActive ? .red : Color.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                    HistoryView(
                        selectedSetData: selectedSetData,
                        selectedTab: $selectedTab,
                        isVisible: true,
                        isDeleteModeActive: $isDeleteModeActive
                    )
                    .transition(.move(edge: .trailing))
                } else {
                    // History icon row
                    HStack {
                        Spacer()
                        Button {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                showHistory = true
                            }
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.title3)
                                .foregroundStyle(Color.appAccent)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 6)

                    ZStack(alignment: .bottom) {
                        ScrollView {
                            // Content based on selected tab
                            ZStack {
                                if trendsTab == .strength {
                                    BalanceView()
                                }

                                if trendsTab == .analytics {
                                    AnalyticsView()
                                }

                                if trendsTab == .narratives {
                                    InsightsView()
                                }
                            }
                            .transition(.move(edge: .leading))
                            .padding(.bottom, 70)
                        }

                        // Floating picker at bottom
                        TrendsPicker(selectedTab: $trendsTab)
                            .padding(.top, 10)
                            .padding(.bottom, 6)
                            .background(Color(white: 0.10).ignoresSafeArea(.container, edges: .bottom))
                    }
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedTab) { _, newTab in
                if newTab == 0 && showHistory {
                    isDeleteModeActive = false
                    showHistory = false
                }
                if newTab == 0 {
                    consumePendingTrendsTab()
                }
            }
            .onAppear {
                consumePendingTrendsTab()
            }
            .onChange(of: selectedSetData.pendingTrendsTab) {
                if selectedTab == 0 {
                    consumePendingTrendsTab()
                }
            }
            .safeAreaInset(edge: .bottom) {
                if syncService.isSyncingLiftSet {
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

    private func consumePendingTrendsTab() {
        if let tab = selectedSetData.pendingTrendsTab {
            trendsTab = tab
            selectedSetData.pendingTrendsTab = nil
        }
    }
}
