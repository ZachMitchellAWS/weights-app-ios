//
//  ContentView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import Combine

class SelectedSetData: ObservableObject {
    @Published var exerciseId: UUID?
    @Published var reps: Int?
    @Published var weight: Double?
    @Published var shouldPopulate: Bool = false
    @Published var pendingTrendsTab: TrendsTab? = nil
    @Published var pendingScrollToStrengthTop: Bool = false
}

struct LazyView<Content: View>: View {
    let build: () -> Content
    init(_ build: @autoclosure @escaping () -> Content) { self.build = build }
    var body: some View { build() }
}

struct ContentView: View {
    @ObservedObject var authViewModel: AuthViewModel
    var initialExerciseId: UUID? = nil

    @State private var selectedTab = 1
    @StateObject private var selectedSetData = SelectedSetData()
    private var narrativeBadge: NarrativeBadgeService { NarrativeBadgeService.shared }
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        TabView(selection: $selectedTab) {
            LazyView(TrendsView(selectedSetData: selectedSetData, selectedTab: $selectedTab))
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(0)
                .badge(narrativeBadge.hasNewNarrative ? 1 : 0)

            Group {
                if UITestMode.isEnabled {
                    LegacyCheckInView(selectedSetData: selectedSetData, initialExerciseId: initialExerciseId, selectedTab: $selectedTab)
                } else {
                    CheckInView(selectedSetData: selectedSetData, selectedTab: $selectedTab)
                }
            }
                .tabItem { Label("Lift", systemImage: "plus.circle") }
                .tag(1)

            MoreView(authViewModel: authViewModel)
                .tabItem { Label("More", systemImage: "arrow.forward.square") }
                .tag(2)
        }
        .tint(Color.appAccent)
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedTab) { _, newTab in
            hapticFeedback.impactOccurred()
            if newTab == 0 && narrativeBadge.hasNewNarrative {
                selectedSetData.pendingTrendsTab = .narratives
            }
        }
    }
}
