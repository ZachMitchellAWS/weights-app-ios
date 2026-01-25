//
//  SettingsView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var settingsItems: [AppSettings]
    @Query private var exercises: [Exercise]
    @Query private var liftSets: [LiftSet]
    @Query private var estimated1RMs: [Estimated1RM]
    @State private var showDataPopulatedAlert = false
    @State private var showUserPropertiesAlert = false
    @State private var showAccountDetail = false
    @State private var userPropertiesAlertMessage = ""
    @State private var isUpdatingProperties = false
    @State private var showPlateSelection = false
    @State private var showDeleteConfirmation = false
    @State private var showDataDeletedAlert = false

    private var settings: AppSettings {
        if let s = settingsItems.first { return s }
        let s = AppSettings()
        modelContext.insert(s)
        return s
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button {
                        showPlateSelection = true
                    } label: {
                        HStack {
                            Text("Plate Selection")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.system(size: 14))
                        }
                    }
                } header: {
                    Text("Equipment")
                } footer: {
                    Text("Configure available weight plates for your workouts.")
                }

                Section {
                    Button {
                        populateSimulatedData()
                        showDataPopulatedAlert = true
                    } label: {
                        HStack {
                            Text("Populate 7 Days of Data")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "wand.and.stars")
                                .foregroundStyle(Color.appAccent)
                        }
                    }

                    Button {
                        Task {
                            await updateUserProperties()
                        }
                    } label: {
                        HStack {
                            Text("Update User Properties")
                                .foregroundStyle(.primary)
                            Spacer()
                            if isUpdatingProperties {
                                ProgressView()
                            } else {
                                Image(systemName: "person.crop.circle.badge.checkmark")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                    }
                    .disabled(isUpdatingProperties)

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        HStack {
                            Text("Delete All Workout Data")
                                .foregroundStyle(.red)
                            Spacer()
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                    }
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Generates realistic training data for the past 7 days for testing purposes. Update user properties sends a test API call. Delete all workout data removes all LiftSet and Estimated1RM entries.")
                }

                Section {
                    Button {
                        showAccountDetail = true
                    } label: {
                        HStack {
                            Text("Account")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.system(size: 14))
                        }
                    }
                } footer: {
                    Text("View account information and logout.")
                }
            }
            .navigationTitle("Settings")
            .alert("Data Populated", isPresented: $showDataPopulatedAlert) {
                Button("OK") { }
            } message: {
                Text("Successfully generated 7 days of training data.")
            }
            .alert("User Properties", isPresented: $showUserPropertiesAlert) {
                Button("OK") { }
            } message: {
                Text(userPropertiesAlertMessage)
            }
            .alert("Delete All Workout Data?", isPresented: $showDeleteConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    deleteAllWorkoutData()
                }
            } message: {
                Text("This will permanently delete all LiftSet and Estimated1RM entries. This action cannot be undone.")
            }
            .alert("Data Deleted", isPresented: $showDataDeletedAlert) {
                Button("OK") { }
            } message: {
                Text("Successfully deleted all workout data.")
            }
            .fullScreenCover(isPresented: $showPlateSelection) {
                PlateSelectionView()
            }
            .fullScreenCover(isPresented: $showAccountDetail) {
                AccountDetailView(authViewModel: authViewModel)
            }
        }
    }

    private func populateSimulatedData() {
        let calendar = Calendar.current
        let now = Date()

        // Ensure we have exercises
        if exercises.isEmpty {
            return
        }

        // Training plan: alternate between push/pull/legs over 7 days
        let workoutPlans: [[String]] = [
            ["Bench Press", "Overhead Press", "Dip"], // Push
            ["Deadlifts", "Barbell Row", "Pull-Up"], // Pull
            ["Squat"], // Legs
        ]

        for daysAgo in (1...7).reversed() {
            guard let workoutDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }

            let workoutType = (daysAgo - 1) % 3
            let exerciseNames = workoutPlans[workoutType]

            // Vary workout time throughout the day
            let hour = [9, 12, 17, 19][(daysAgo - 1) % 4]
            let minute = [0, 15, 30, 45][(daysAgo - 1) % 4]

            var currentTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: workoutDate) ?? workoutDate

            for exerciseName in exerciseNames {
                guard let exercise = exercises.first(where: { $0.name == exerciseName }) else { continue }

                // Number of sets per exercise (3-5)
                let numSets = Int.random(in: 3...5)

                // Base weight for this exercise (varies by exercise type)
                let baseWeight: Double = {
                    switch exerciseName {
                    case "Deadlifts": return 200.0
                    case "Squat": return 185.0
                    case "Bench Press": return 155.0
                    case "Barbell Row": return 135.0
                    case "Overhead Press": return 95.0
                    case "Pull-Up": return 25.0
                    case "Dip": return 35.0
                    default: return 100.0
                    }
                }()

                for setNum in 0..<numSets {
                    // Simulate progressive fatigue
                    let weightVariation = Double(numSets - setNum - 1) * 5.0
                    let weight = baseWeight + weightVariation + Double.random(in: -2.5...2.5)

                    // Reps typically 5-10 for compound movements
                    let reps = Int.random(in: 5...10)

                    // RIR: earlier sets have more RIR, later sets closer to failure
                    let rir = setNum < 2 ? Int.random(in: 3...4) : Int.random(in: 0...2)

                    let set = LiftSet(exercise: exercise, reps: reps, weight: weight, rir: rir)
                    set.createdAt = currentTime
                    modelContext.insert(set)

                    // Add some time between sets (2-4 minutes)
                    currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...4), to: currentTime) ?? currentTime
                }

                // Rest between exercises (5-8 minutes)
                currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 5...8), to: currentTime) ?? currentTime
            }
        }

        try? modelContext.save()
    }

    private func updateUserProperties() async {
        isUpdatingProperties = true

        do {
            let response = try await APIService.shared.updateUserProperties()
            userPropertiesAlertMessage = "Successfully updated user properties\n\nplaceholderBool: \(response.placeholderBool)"
            showUserPropertiesAlert = true
        } catch {
            userPropertiesAlertMessage = "Failed: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isUpdatingProperties = false
    }

    private func deleteAllWorkoutData() {
        // Delete all LiftSet items
        for liftSet in liftSets {
            modelContext.delete(liftSet)
        }

        // Delete all Estimated1RM items
        for estimated1RM in estimated1RMs {
            modelContext.delete(estimated1RM)
        }

        // Save the changes
        try? modelContext.save()

        showDataDeletedAlert = true
    }
}
