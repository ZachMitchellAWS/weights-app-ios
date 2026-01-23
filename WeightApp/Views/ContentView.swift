//
//  ContentView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData
import Combine

class SelectedSetData: ObservableObject {
    @Published var exerciseId: UUID?
    @Published var reps: Int?
    @Published var weight: Double?
    @Published var rir: Int?
    @Published var shouldPopulate: Bool = false
}

struct ContentView: View {
    @State private var selectedTab = 1
    @StateObject private var selectedSetData = SelectedSetData()
    private let hapticFeedback = UIImpactFeedbackGenerator(style: .light)

    var body: some View {
        TabView(selection: $selectedTab) {
            TrendsView(selectedSetData: selectedSetData, selectedTab: $selectedTab)
                .tabItem { Label("History", systemImage: "clock") }
                .tag(0)

            CheckInView(selectedSetData: selectedSetData)
                .tabItem { Label("Check In", systemImage: "plus.circle") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .onChange(of: selectedTab) { _, _ in
            hapticFeedback.impactOccurred()
        }
    }
}
