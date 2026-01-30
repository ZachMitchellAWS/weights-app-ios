//
//  MoreView.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData

struct MoreView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Environment(\.modelContext) private var modelContext
    @Query private var userPropertiesItems: [UserProperties]
    @Query private var exercises: [Exercises]
    @Query private var liftSets: [LiftSet]
    @Query private var estimated1RMs: [Estimated1RM]

    @State private var showAccount = false
    @State private var showSettings = false
    @State private var showDeveloper = false
    @State private var showWeightInput = false
    @State private var showPlateSelection = false

    @State private var showDataPopulatedAlert = false
    @State private var showTodayDataPopulatedAlert = false
    @State private var showUserPropertiesAlert = false
    @State private var showDeleteConfirmation = false
    @State private var showDataDeletedAlert = false
    @State private var showLogoutConfirmation = false
    @State private var userPropertiesAlertMessage = ""
    @State private var isUpdatingProperties = false

    @State private var tempBodyweight: Double = 0

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var email: String {
        KeychainService.shared.getEmail() ?? "Not available"
    }

    private var userId: String {
        KeychainService.shared.getUserId() ?? "Not available"
    }

    private var createdDate: String {
        guard let createdDatetimeString = KeychainService.shared.getCreatedDatetime() else {
            return "Not available"
        }

        // Parse ISO8601 datetime and format it
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        if let date = formatter.date(from: createdDatetimeString) {
            let displayFormatter = DateFormatter()
            displayFormatter.dateStyle = .long
            displayFormatter.timeStyle = .short
            return displayFormatter.string(from: date)
        }

        return createdDatetimeString
    }

    var body: some View {
        NavigationStack {
            Form {
                // Account Section (Top, Expandable)
                Section {
                    Button {
                        withAnimation {
                            showAccount.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.circle")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Account")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: showAccount ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.system(size: 14))
                        }
                    }

                    if showAccount {
                        // Email
                        HStack {
                            Text("Email")
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.leading, 32)
                            Spacer()
                            Text(email)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                                .textSelection(.enabled)
                        }

                        // User ID
                        HStack {
                            Text("User ID")
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.leading, 32)
                            Spacer()
                            Text(userId)
                                .foregroundStyle(.white)
                                .font(.system(.body, design: .monospaced))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                                .textSelection(.enabled)
                        }

                        // Created Date
                        HStack {
                            Text("Created")
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.leading, 32)
                            Spacer()
                            Text(createdDate)
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.trailing)
                        }

                        // Logout Button
                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            HStack {
                                Text("Logout")
                                    .padding(.leading, 32)
                                Spacer()
                                if authViewModel.isLoading {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.right.square")
                                }
                            }
                        }
                        .disabled(authViewModel.isLoading)
                    }
                }

                // Settings Section (Expandable)
                Section {
                    Button {
                        withAnimation {
                            showSettings.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Settings")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: showSettings ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.system(size: 14))
                        }
                    }

                    if showSettings {
                        // Profile Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Profile")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.leading, 32)

                            Button {
                                tempBodyweight = userProperties.bodyweight ?? 0
                                showWeightInput = true
                            } label: {
                                HStack {
                                    Text("Bodyweight")
                                        .foregroundStyle(.primary)
                                        .padding(.leading, 32)
                                    Spacer()
                                    if let bodyweight = userProperties.bodyweight {
                                        Text("\(bodyweight, specifier: "%.1f") lbs")
                                            .foregroundStyle(.white.opacity(0.5))
                                    } else {
                                        Text("Not Set")
                                            .foregroundStyle(.white.opacity(0.5))
                                    }
                                }
                            }
                        }
                        .padding(.vertical, 4)

                        // Equipment Section
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Equipment")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.7))
                                .padding(.leading, 32)
                                .padding(.top, 8)

                            Button {
                                showPlateSelection = true
                            } label: {
                                HStack {
                                    Text("Available Plate Increments")
                                        .foregroundStyle(.primary)
                                        .padding(.leading, 32)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.white.opacity(0.3))
                                        .font(.system(size: 14))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Developer Section (Bottom, Expandable)
                Section {
                    Button {
                        withAnimation {
                            showDeveloper.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "hammer")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Developer")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: showDeveloper ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.system(size: 14))
                        }
                    }

                    if showDeveloper {
                        Button {
                            populateSimulatedData()
                            showDataPopulatedAlert = true
                        } label: {
                            HStack {
                                Text("Populate 7 Days of Data")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: "wand.and.stars")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        Button {
                            populateTodayData()
                            showTodayDataPopulatedAlert = true
                        } label: {
                            HStack {
                                Text("Populate Today Data")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: "calendar.badge.plus")
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
                                    .padding(.leading, 32)
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

                        Button {
                            authViewModel.isNewUser = true
                            authViewModel.showPostAuthFlow = true
                        } label: {
                            HStack {
                                Text("Replay Onboarding")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: "arrow.counterclockwise")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        Button {
                            authViewModel.isNewUser = false
                            authViewModel.showPostAuthFlow = true
                        } label: {
                            HStack {
                                Text("Replay Welcome Back")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: "hand.wave")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        Button(role: .destructive) {
                            showDeleteConfirmation = true
                        } label: {
                            HStack {
                                Text("Delete All Workout Data")
                                    .foregroundStyle(.red)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                } footer: {
                    if showDeveloper {
                        Text("Generates realistic training data for the past 7 days. Update user properties sends a test API call. Replay onboarding/welcome back shows the post-auth flows. Delete all workout data removes all LiftSet and Estimated1RM entries.")
                    }
                }
            }
            .navigationTitle("More")
            .sheet(isPresented: $showWeightInput) {
                weightInputSheet
            }
            .fullScreenCover(isPresented: $showPlateSelection) {
                PlateSelectionView()
            }
            .alert("Data Populated", isPresented: $showDataPopulatedAlert) {
                Button("OK") { }
            } message: {
                Text("Successfully generated 7 days of training data.")
            }
            .alert("Today's Data Populated", isPresented: $showTodayDataPopulatedAlert) {
                Button("OK") { }
            } message: {
                Text("Successfully generated today's training data for all exercises.")
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
            .alert("Logout", isPresented: $showLogoutConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Logout", role: .destructive) {
                    Task {
                        await authViewModel.logout {
                            hardDeleteAllData()
                        }
                    }
                }
            } message: {
                Text("Are you sure you want to logout? All local data will be deleted.")
            }
        }
    }

    // MARK: - Weight Input Sheet

    private var weightInputSheet: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 16) {
                    Spacer()
                        .frame(height: 8)

                    Text("Set Bodyweight")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)

                    Text("Your bodyweight is used for calculating 1RM on bodyweight exercises")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Spacer()
                        .frame(height: 20)

                    // Weight Picker
                    HStack(spacing: 0) {
                        Picker("Weight", selection: $tempBodyweight) {
                            ForEach(Array(stride(from: 50.0, through: 500.0, by: 0.5)), id: \.self) { weight in
                                Text("\(weight, specifier: "%.1f")")
                                    .tag(weight)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(maxWidth: .infinity)

                        Text("lbs")
                            .font(.title2)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 40)
                    }
                    .frame(height: 200)

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button {
                            tempBodyweight = 0
                            userProperties.bodyweight = nil
                            try? modelContext.save()
                            showWeightInput = false
                        } label: {
                            Text("Clear")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.white.opacity(0.1))
                                .cornerRadius(12)
                        }

                        Button {
                            userProperties.bodyweight = tempBodyweight
                            try? modelContext.save()
                            showWeightInput = false
                        } label: {
                            Text("Done")
                                .font(.headline)
                                .foregroundStyle(.black)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(Color.appAccent)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .presentationDetents([.height(500)])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Helper Functions

    private func populateSimulatedData() {
        // Clear all existing LiftSet and Estimated1RM data first
        for liftSet in liftSets {
            modelContext.delete(liftSet)
        }
        for estimated1RM in estimated1RMs {
            modelContext.delete(estimated1RM)
        }

        // Simulated user bodyweight for bodyweight exercises
        let simulatedBodyweight: Double = 180.0

        // Set the user's bodyweight for proper 1RM calculations
        userProperties.bodyweight = simulatedBodyweight

        let calendar = Calendar.current
        let now = Date()

        // Ensure we have exercises
        if exercises.isEmpty {
            return
        }

        // Helper function to round weight to nearest attainable increment (2.5 lbs)
        func roundToAttainable(_ weight: Double) -> Double {
            return (weight / 2.5).rounded() * 2.5
        }

        // Training plan: alternate between push/pull/legs over 7 days
        let workoutPlans: [[String]] = [
            ["Bench Press", "Overhead Press", "Dips"], // Push
            ["Deadlift", "Barbell Row", "Pull Ups"], // Pull
            ["Squat"], // Legs
        ]

        // Track max 1RM per exercise for progression (for bodyweight exercises, this is TOTAL load including bodyweight)
        var exerciseMaxes: [String: Double] = [:]

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

                // Starting 1RM for this exercise (if not already tracked)
                // For bodyweight exercises, this represents TOTAL load (bodyweight + added weight)
                if exerciseMaxes[exerciseName] == nil {
                    exerciseMaxes[exerciseName] = {
                        switch exerciseName {
                        case "Deadlift": return 225.0
                        case "Squat": return 200.0
                        case "Bench Press": return 165.0
                        case "Barbell Row": return 145.0
                        case "Overhead Press": return 100.0
                        case "Pull Ups": return simulatedBodyweight + 30.0  // 180 + 30 = 210 lbs total
                        case "Dips": return simulatedBodyweight + 40.0      // 180 + 40 = 220 lbs total
                        default: return 100.0
                        }
                    }()
                }

                let currentMax = exerciseMaxes[exerciseName]!

                // Pattern: 2 Easy, 2 Moderate, 2 Hard, 1 Redline, 1 PR
                let numSets = 8

                // Intensity percentages for each set (percentage of current 1RM)
                let intensities: [Double] = [0.52, 0.58, 0.65, 0.70, 0.76, 0.82, 0.90, 1.03]

                for setNum in 0..<numSets {
                    let intensity = intensities[setNum]
                    let target1RM = currentMax * intensity

                    // Choose reps: higher reps for easier sets, lower for harder
                    let reps: Int
                    switch setNum {
                    case 0, 1: reps = 10 // Easy warmup sets
                    case 2, 3: reps = 8  // Moderate sets
                    case 4, 5: reps = 6  // Hard sets
                    case 6: reps = 4     // Redline set
                    case 7: reps = 2     // PR set
                    default: reps = 6
                    }

                    // Calculate weight needed to hit target 1RM with these reps
                    // Using Brzycki formula: 1RM = weight * (36 / (37 - reps))
                    let calculatedWeight = roundToAttainable(target1RM * (37.0 - Double(reps)) / 36.0)

                    // For bodyweight exercises, subtract bodyweight to get added weight only
                    let isBodyweightExercises = exercise.exerciseLoadType == .bodyweightPlusSingleLoad
                    let weightToStore = isBodyweightExercises ? max(0, calculatedWeight - simulatedBodyweight) : calculatedWeight

                    let set = LiftSet(exercise: exercise, reps: reps, weight: weightToStore)
                    set.createdAt = currentTime
                    set.createdTimezone = TimeZone.current.identifier
                    modelContext.insert(set)

                    // Update max if this is a PR (last set)
                    if setNum == 7 {
                        exerciseMaxes[exerciseName] = target1RM
                    }

                    // Add some time between sets (2-4 minutes)
                    currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...4), to: currentTime) ?? currentTime
                }

                // Rest between exercises (5-8 minutes)
                currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 5...8), to: currentTime) ?? currentTime
            }
        }

        try? modelContext.save()
    }

    private func populateTodayData() {
        // Simulated user bodyweight for bodyweight exercises
        let simulatedBodyweight: Double = userProperties.bodyweight ?? 180.0

        let calendar = Calendar.current
        let now = Date()

        // Ensure we have exercises
        if exercises.isEmpty {
            return
        }

        // Helper function to round weight to nearest attainable increment (2.5 lbs)
        func roundToAttainable(_ weight: Double) -> Double {
            return (weight / 2.5).rounded() * 2.5
        }

        // Starting 1RM estimates for each exercise
        func getBase1RM(for exerciseName: String) -> Double {
            switch exerciseName {
            case "Deadlift": return 275.0
            case "Squat": return 245.0
            case "Bench Press": return 195.0
            case "Barbell Row": return 175.0
            case "Overhead Press": return 125.0
            case "Pull Ups": return simulatedBodyweight + 45.0
            case "Dips": return simulatedBodyweight + 55.0
            default: return 135.0
            }
        }

        // Start workout at a reasonable time today
        var currentTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now

        for exercise in exercises {
            let currentMax = getBase1RM(for: exercise.name)

            // Pattern: 2 Easy, 2 Moderate, 2 Hard, 1 Redline, 1 PR
            let intensities: [Double] = [0.52, 0.58, 0.65, 0.70, 0.76, 0.82, 0.90, 1.02]

            for setNum in 0..<intensities.count {
                let intensity = intensities[setNum]
                let target1RM = currentMax * intensity

                // Choose reps: higher reps for easier sets, lower for harder
                let reps: Int
                switch setNum {
                case 0, 1: reps = 10 // Easy warmup sets
                case 2, 3: reps = 8  // Moderate sets
                case 4, 5: reps = 6  // Hard sets
                case 6: reps = 4     // Redline set
                case 7: reps = 2     // PR set
                default: reps = 6
                }

                // Calculate weight needed to hit target 1RM with these reps
                // Using Brzycki formula: 1RM = weight * (36 / (37 - reps))
                let calculatedWeight = roundToAttainable(target1RM * (37.0 - Double(reps)) / 36.0)

                // For bodyweight exercises, subtract bodyweight to get added weight only
                let isBodyweightExercise = exercise.exerciseLoadType == .bodyweightPlusSingleLoad
                let weightToStore = isBodyweightExercise ? max(0, calculatedWeight - simulatedBodyweight) : calculatedWeight

                let set = LiftSet(exercise: exercise, reps: reps, weight: weightToStore)
                set.createdAt = currentTime
                set.createdTimezone = TimeZone.current.identifier
                modelContext.insert(set)

                // Add some time between sets (2-4 minutes)
                currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...4), to: currentTime) ?? currentTime
            }

            // Rest between exercises (5-8 minutes)
            currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 5...8), to: currentTime) ?? currentTime
        }

        try? modelContext.save()
    }

    private func updateUserProperties() async {
        isUpdatingProperties = true

        do {
            let response = try await APIService.shared.updateUserProperties(bodyweight: userProperties.bodyweight)
            userPropertiesAlertMessage = "Successfully updated user properties\n\nbodyweight: \(response.bodyweight?.description ?? "nil")"
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

    private func hardDeleteAllData() {
        // Hard delete all LiftSets
        for liftSet in liftSets {
            modelContext.delete(liftSet)
        }

        // Hard delete all Estimated1RMs
        for estimated1RM in estimated1RMs {
            modelContext.delete(estimated1RM)
        }

        // Hard delete all custom Exercises (keep built-in ones)
        for exercise in exercises where exercise.isCustom {
            modelContext.delete(exercise)
        }

        // Hard delete UserProperties
        for properties in userPropertiesItems {
            modelContext.delete(properties)
        }

        try? modelContext.save()
    }
}
