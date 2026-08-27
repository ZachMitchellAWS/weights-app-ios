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

    @State private var selectedTab: AppTab = .lift
    @StateObject private var selectedSetData = SelectedSetData()
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)
    @ObservedObject private var notificationRouter = NotificationRouter.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            LazyView(StrengthTabView(selectedSetData: selectedSetData, selectedTab: $selectedTab))
                .tabItem { Label(AppTab.strength.title, systemImage: AppTab.strength.systemImage) }
                .tag(AppTab.strength)

            LazyView(ProgramTabView(selectedTab: $selectedTab))
                .tabItem { Label(AppTab.session.title, systemImage: AppTab.session.systemImage) }
                .tag(AppTab.session)

            Group {
                if UITestMode.isEnabled {
                    LegacyCheckInView(selectedSetData: selectedSetData, initialExerciseId: initialExerciseId, selectedTab: $selectedTab)
                } else {
                    CheckInView(selectedSetData: selectedSetData, selectedTab: $selectedTab)
                }
            }
                .tabItem { Label(AppTab.lift.title, systemImage: AppTab.lift.systemImage) }
                .tag(AppTab.lift)

            LazyView(AnalyticsTabView(selectedSetData: selectedSetData, selectedTab: $selectedTab))
                .tabItem { Label(AppTab.analytics.title, systemImage: AppTab.analytics.systemImage) }
                .tag(AppTab.analytics)

            MoreView(authViewModel: authViewModel, selectedSetData: selectedSetData)
                .tabItem { Label(AppTab.more.title, systemImage: AppTab.more.systemImage) }
                .tag(AppTab.more)
        }
        .tint(Color.appAccent)
        .toolbarBackground(Color.black, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
        .onChange(of: selectedSetData.pendingShowSettings) { _, pending in
            if pending {
                selectedTab = .more
            }
        }
        // A tapped session reminder lands on the Lift tab. Handled here rather than in
        // the tap handler because AppDelegate has no access to the tab selection.
        .onChange(of: notificationRouter.pendingDestination) { _, destination in
            guard destination == .liftTab else { return }
            selectedTab = .lift
            notificationRouter.pendingDestination = nil
        }
        .onAppear {
            // Covers a cold launch from a notification tap, where the destination is
            // published before this view exists to observe the change.
            if notificationRouter.pendingDestination == .liftTab {
                selectedTab = .lift
                notificationRouter.pendingDestination = nil
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            hapticFeedback.impactOccurred()
            let crumb = Breadcrumb(level: .info, category: "navigation")
            crumb.message = "Tab: \(newTab.title)"
            SentrySDK.addBreadcrumb(crumb)
            AmplitudeService.shared.track(.tabSwitched(tab: newTab.title))
        }
    }
}
