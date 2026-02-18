//
//  TrendsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData

struct TrendsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<LiftSets> { !$0.deleted }, sort: \LiftSets.createdAt) private var allSets: [LiftSets]
    @Query(filter: #Predicate<Estimated1RMs> { !$0.deleted }) private var allEstimated1RMs: [Estimated1RMs]
    @ObservedObject var selectedSetData: SelectedSetData
    @ObservedObject private var syncService = SyncService.shared
    @Binding var selectedTab: Int
    @State private var setToDelete: LiftSets? = nil
    @State private var showDeleteConfirmation = false
    @State private var isDeleteModeActive = false
    @State private var trendsTab: TrendsTab = .analytics

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented picker
                TrendsPicker(selectedTab: $trendsTab)
                    .padding(.top, 8)
                    .padding(.bottom, 12)

                // Content based on selected tab - using ZStack to keep both views in memory
                ZStack {
                    AnalyticsView(
                        allSets: allSets,
                        allEstimated1RMs: allEstimated1RMs
                    )
                    .opacity(trendsTab == .analytics ? 1 : 0)

                    HistoryView(
                        allSets: allSets,
                        allEstimated1RMs: allEstimated1RMs,
                        selectedSetData: selectedSetData,
                        selectedTab: $selectedTab,
                        isDeleteModeActive: $isDeleteModeActive,
                        setToDelete: $setToDelete,
                        showDeleteConfirmation: $showDeleteConfirmation
                    )
                    .opacity(trendsTab == .history ? 1 : 0)
                }
            }
            .background(Color.black)
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if trendsTab == .history && !allSets.isEmpty {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            isDeleteModeActive.toggle()
                        } label: {
                            Image(systemName: isDeleteModeActive ? "minus.circle.fill" : "minus.circle")
                                .foregroundStyle(isDeleteModeActive ? .red : Color.appAccent)
                        }
                    }
                }
            }
            .alert("Delete Set", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    if let set = setToDelete {
                        let setId = set.id
                        set.deleted = true

                        // Also mark the associated Estimated1RMs as deleted
                        var estimated1RMId: UUID? = nil
                        if let associated1RM = allEstimated1RMs.first(where: { $0.setId == setId }) {
                            associated1RM.deleted = true
                            estimated1RMId = associated1RM.id
                        }

                        try? modelContext.save()

                        Task {
                            await SyncService.shared.deleteLiftSet(setId)
                            // Also delete the associated Estimated1RMs from backend
                            if estimated1RMId != nil {
                                await SyncService.shared.deleteEstimated1RM(estimated1RMId: estimated1RMId!, liftSetId: setId)
                            }
                        }
                    }
                }
            } message: {
                if let set = setToDelete {
                    Text("Delete \(set.reps) × \(set.weight.rounded1().formatted(.number.precision(.fractionLength(2)))) lbs?")
                }
            }
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
