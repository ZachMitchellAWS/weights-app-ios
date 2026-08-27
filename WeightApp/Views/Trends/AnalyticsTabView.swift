//
//  AnalyticsTabView.swift
//  WeightApp
//
//  Top-level Analytics tab, carrying over the history drill-down that used to live in
//  `TrendsView`. The history affordance only ever appeared on the analytics sub-tab, so
//  it belongs here entirely rather than in shared chrome.
//

import SwiftUI
import SwiftData

struct AnalyticsTabView: View {
    @ObservedObject var selectedSetData: SelectedSetData
    @Binding var selectedTab: AppTab

    @Query private var userPropertiesItems: [UserProperties]
    private var userProperties: UserProperties { userPropertiesItems.first ?? UserProperties() }

    @State private var showHistory = false
    @State private var isDeleteModeActive = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showHistory {
                    historyHeader

                    HistoryView(
                        selectedSetData: selectedSetData,
                        selectedTab: $selectedTab,
                        isVisible: true,
                        weightUnit: userProperties.preferredWeightUnit,
                        isDeleteModeActive: $isDeleteModeActive
                    )
                    .transition(.move(edge: .trailing))
                } else {
                    historyButtonRow

                    AnalyticsView()
                }
            }
            .background(Color.black)
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedTab) { _, newTab in
                // Leaving the tab drops out of the history drill-down, so returning
                // lands on analytics rather than mid-history.
                if newTab != .analytics && showHistory {
                    isDeleteModeActive = false
                    showHistory = false
                }
            }
        }
    }

    // MARK: - Chrome

    private var historyHeader: some View {
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
    }

    private var historyButtonRow: some View {
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
    }
}
