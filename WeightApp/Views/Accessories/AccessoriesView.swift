//
//  AccessoriesView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/3/26.
//

import SwiftUI
import SwiftData

struct AccessoriesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<AccessoryGoalCheckin> { !$0.deleted }) private var allCheckins: [AccessoryGoalCheckin]
    @Query private var userPropertiesItems: [UserProperties]

    @State private var showStepsInput = false
    @State private var showProteinInput = false
    @State private var showBodyWeightInput = false
    @State private var showStepsGoalEditor = false
    @State private var showProteinGoalEditor = false
    @State private var showBodyWeightTargetEditor = false
    @State private var showStepsHistory = false
    @State private var showProteinHistory = false
    @State private var showBodyWeightHistory = false
    @State private var goalInputText = ""
    @AppStorage("contiguousAccessoryCharts") private var contiguousChart = false

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var stepsCheckins: [AccessoryGoalCheckin] {
        allCheckins.filter { $0.metricType == "steps" }
    }

    private var proteinCheckins: [AccessoryGoalCheckin] {
        allCheckins.filter { $0.metricType == "protein" }
    }

    private var bodyweightCheckins: [AccessoryGoalCheckin] {
        allCheckins.filter { $0.metricType == "bodyweight" }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Chart mode toggle
                HStack {
                    Spacer()
                    Picker("Chart Mode", selection: $contiguousChart) {
                        Text("All Days").tag(false)
                        Text("Logged Only").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                StepsWidget(
                    checkins: stepsCheckins,
                    goal: userProperties.stepsGoal,
                    contiguousChart: contiguousChart,
                    onAdd: { showStepsInput = true },
                    onEditGoal: {
                        goalInputText = userProperties.stepsGoal.map(String.init) ?? ""
                        showStepsGoalEditor = true
                    },
                    onShowHistory: { showStepsHistory = true }
                )

                ProteinWidget(
                    checkins: proteinCheckins,
                    goal: userProperties.proteinGoal,
                    contiguousChart: contiguousChart,
                    onAdd: { showProteinInput = true },
                    onEditGoal: {
                        goalInputText = userProperties.proteinGoal.map(String.init) ?? ""
                        showProteinGoalEditor = true
                    },
                    onShowHistory: { showProteinHistory = true }
                )

                BodyWeightWidget(
                    checkins: bodyweightCheckins,
                    target: userProperties.bodyweightTarget,
                    onAdd: { showBodyWeightInput = true },
                    onEditTarget: {
                        goalInputText = userProperties.bodyweightTarget.map { String(format: "%.1f", $0) } ?? ""
                        showBodyWeightTargetEditor = true
                    },
                    onShowHistory: { showBodyWeightHistory = true }
                )
            }
            .padding()
        }
        .navigationTitle("Accessories")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showStepsInput) {
            AccessoryInputSheet(metricType: "steps") { value, date in
                saveCheckin(metricType: "steps", value: value, date: date)
            }
        }
        .sheet(isPresented: $showProteinInput) {
            AccessoryInputSheet(metricType: "protein") { value, date in
                saveCheckin(metricType: "protein", value: value, date: date)
            }
        }
        .sheet(isPresented: $showBodyWeightInput) {
            AccessoryInputSheet(metricType: "bodyweight") { value, date in
                saveCheckin(metricType: "bodyweight", value: value, date: date)
            }
        }
        .sheet(isPresented: $showStepsHistory) {
            AccessoryHistoryView(
                metricType: "steps",
                checkins: stepsCheckins,
                onDelete: { deleteCheckin($0) }
            )
        }
        .sheet(isPresented: $showProteinHistory) {
            AccessoryHistoryView(
                metricType: "protein",
                checkins: proteinCheckins,
                onDelete: { deleteCheckin($0) }
            )
        }
        .sheet(isPresented: $showBodyWeightHistory) {
            AccessoryHistoryView(
                metricType: "bodyweight",
                checkins: bodyweightCheckins,
                onDelete: { deleteCheckin($0) }
            )
        }
        .alert("Steps Goal", isPresented: $showStepsGoalEditor) {
            TextField("e.g. 10000", text: $goalInputText)
                .keyboardType(.numberPad)
            Button("Save") {
                if let value = Int(goalInputText) {
                    userProperties.stepsGoal = value
                    syncGoals()
                }
            }
            Button("Clear", role: .destructive) {
                userProperties.stepsGoal = nil
                syncGoals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set your daily steps goal")
        }
        .alert("Protein Goal", isPresented: $showProteinGoalEditor) {
            TextField("e.g. 180", text: $goalInputText)
                .keyboardType(.numberPad)
            Button("Save") {
                if let value = Int(goalInputText) {
                    userProperties.proteinGoal = value
                    syncGoals()
                }
            }
            Button("Clear", role: .destructive) {
                userProperties.proteinGoal = nil
                syncGoals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set your daily protein goal (grams)")
        }
        .alert("Body Weight Target", isPresented: $showBodyWeightTargetEditor) {
            TextField("e.g. 175", text: $goalInputText)
                .keyboardType(.decimalPad)
            Button("Save") {
                if let value = Double(goalInputText) {
                    userProperties.bodyweightTarget = value
                    syncGoals()
                }
            }
            Button("Clear", role: .destructive) {
                userProperties.bodyweightTarget = nil
                syncGoals()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Set your target body weight (lbs)")
        }
    }

    private func saveCheckin(metricType: String, value: Double, date: Date = Date()) {
        let checkin = AccessoryGoalCheckin(metricType: metricType, value: value, date: date)
        modelContext.insert(checkin)
        try? modelContext.save()

        Task {
            await SyncService.shared.syncAccessoryGoalCheckin(checkin)
        }
    }

    private func deleteCheckin(_ checkin: AccessoryGoalCheckin) {
        checkin.deleted = true
        try? modelContext.save()

        Task {
            await SyncService.shared.deleteAccessoryGoalCheckin(checkin.id)
        }
    }

    private func syncGoals() {
        var request = UserPropertiesRequest()
        if let stepsGoal = userProperties.stepsGoal {
            request.stepsGoal = stepsGoal
        } else {
            request.clearStepsGoal = true
        }
        if let proteinGoal = userProperties.proteinGoal {
            request.proteinGoal = proteinGoal
        } else {
            request.clearProteinGoal = true
        }
        if let bodyweightTarget = userProperties.bodyweightTarget {
            request.bodyweightTarget = bodyweightTarget
        } else {
            request.clearBodyweightTarget = true
        }

        print("[AccessoriesView] syncGoals: stepsGoal=\(String(describing: request.stepsGoal)), proteinGoal=\(String(describing: request.proteinGoal)), bodyweightTarget=\(String(describing: request.bodyweightTarget)), clearSteps=\(request.clearStepsGoal), clearProtein=\(request.clearProteinGoal), clearBW=\(request.clearBodyweightTarget)")

        Task {
            do {
                let response = try await APIService.shared.updateUserProperties(request)
                print("[AccessoriesView] syncGoals SUCCESS: stepsGoal=\(String(describing: response.stepsGoal)), proteinGoal=\(String(describing: response.proteinGoal)), bodyweightTarget=\(String(describing: response.bodyweightTarget))")
            } catch {
                print("[AccessoriesView] syncGoals FAILED: \(error)")
                SyncRetryQueue.shared.addPendingUserPropertiesSync()
            }
        }
    }
}
