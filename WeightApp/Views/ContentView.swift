//
//  ContentView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import Combine
import Sentry

class SelectedSetData: ObservableObject {
    @Published var exerciseId: UUID?
    @Published var reps: Int?
    @Published var weight: Double?
    @Published var shouldPopulate: Bool = false
    @Published var pendingTrendsTab: TrendsTab? = nil
    @Published var pendingScrollToStrengthTop: Bool = false
    @Published var pendingScrollToMilestones: Bool = false
    @Published var pendingShowSettings: Bool = false
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
    @ObservedObject private var notificationRouter = NotificationRouter.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            LazyView(TrendsView(selectedSetData: selectedSetData, selectedTab: $selectedTab))
                .tabItem { Label("Progress", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(0)
                .badge(narrativeBadge.hasNewNarrative && selectedTab != 0 ? 1 : 0)

            Group {
                if UITestMode.isEnabled {
                    LegacyCheckInView(selectedSetData: selectedSetData, initialExerciseId: initialExerciseId, selectedTab: $selectedTab)
                } else {
                    CheckInView(selectedSetData: selectedSetData, selectedTab: $selectedTab)
                }
            }
                .tabItem { Label("Lift", systemImage: "plus.circle") }
                .tag(1)

            MoreView(authViewModel: authViewModel, selectedSetData: selectedSetData)
                .tabItem { Label("More", systemImage: "arrow.forward.square") }
                .tag(2)
        }
        .tint(Color.appAccent)
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedSetData.pendingShowSettings) { _, pending in
            if pending {
                selectedTab = 2
            }
        }
        // A tapped session reminder lands on the Lift tab. Handled here rather than in
        // the tap handler because AppDelegate has no access to the tab selection.
        .onChange(of: notificationRouter.pendingDestination) { _, destination in
            guard destination == .liftTab else { return }
            selectedTab = 1
            notificationRouter.pendingDestination = nil
        }
        .onAppear {
            // Covers a cold launch from a notification tap, where the destination is
            // published before this view exists to observe the change.
            if notificationRouter.pendingDestination == .liftTab {
                selectedTab = 1
                notificationRouter.pendingDestination = nil
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            hapticFeedback.impactOccurred()
            let crumb = Breadcrumb(level: .info, category: "navigation")
            crumb.message = "Tab: \(["Progress", "Lift", "More"][newTab])"
            SentrySDK.addBreadcrumb(crumb)
            AmplitudeService.shared.track(.tabSwitched(tab: ["Progress", "Lift", "More"][newTab]))
            if newTab == 0 && narrativeBadge.hasNewNarrative {
                selectedSetData.pendingTrendsTab = .narratives
            }
        }
    }
}
