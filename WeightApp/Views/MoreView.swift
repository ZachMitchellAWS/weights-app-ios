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
    @Query private var premiumEntitlementItems: [PremiumEntitlement]
    @Query(filter: #Predicate<Exercises> { !$0.deleted }) private var exercises: [Exercises]
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
    @State private var showExerciseIds = false
    @State private var showMemberSince = false
    @State private var showTokenExpiry = false
    @State private var showUpsellPreview = false
    @State private var copiedToast: String?

    @State private var tempBodyweight: Double = 0

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var premiumEntitlement: PremiumEntitlement {
        if let entitlement = premiumEntitlementItems.first { return entitlement }
        let entitlement = PremiumEntitlement()
        modelContext.insert(entitlement)
        return entitlement
    }

    private var isPremiumEnabled: Bool {
        get { premiumEntitlement.isPremium }
        nonmutating set {
            premiumEntitlement.isPremium = newValue
            if !newValue {
                premiumEntitlement.subscriptionType = nil
                premiumEntitlement.expiresAt = nil
                premiumEntitlement.transactionId = nil
            }
            try? modelContext.save()
        }
    }

    private var email: String {
        KeychainService.shared.getEmail() ?? "Not available"
    }

    private var userId: String {
        KeychainService.shared.getUserId() ?? "Not available"
    }

    private var memberSinceDate: String {
        guard let createdDatetimeString = KeychainService.shared.getCreatedDatetime() else {
            return "Not available"
        }

        // Try multiple ISO8601 format variations
        let formatOptions: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
            [.withFullDate, .withFullTime, .withFractionalSeconds],
            [.withFullDate, .withFullTime],
            [.withFullDate]
        ]

        for options in formatOptions {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = options
            if let date = formatter.date(from: createdDatetimeString) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MMMM d, yyyy"
                return displayFormatter.string(from: date)
            }
        }

        // Last resort: try DateFormatter with common patterns
        let fallbackFormats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ]
        for format in fallbackFormats {
            let parser = DateFormatter()
            parser.dateFormat = format
            parser.locale = Locale(identifier: "en_US_POSIX")
            if let date = parser.date(from: createdDatetimeString) {
                let displayFormatter = DateFormatter()
                displayFormatter.dateFormat = "MMMM d, yyyy"
                return displayFormatter.string(from: date)
            }
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
                        Button {
                            UIPasteboard.general.string = email
                            showCopiedToast("Email copied")
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "envelope")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text(email)
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.white.opacity(0.25))
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)

                        // User ID
                        Button {
                            UIPasteboard.general.string = userId
                            showCopiedToast("User ID copied")
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "number")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text(userId)
                                    .foregroundStyle(.white.opacity(0.7))
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                Spacer()
                                Image(systemName: "doc.on.doc")
                                    .foregroundStyle(.white.opacity(0.25))
                                    .font(.system(size: 12))
                            }
                        }
                        .buttonStyle(.plain)

                        // Member Since (hidden, available in Developer section)
                        // HStack(spacing: 10) {
                        //     Image(systemName: "calendar")
                        //         .foregroundStyle(.white.opacity(0.4))
                        //         .font(.system(size: 14))
                        //         .frame(width: 20)
                        //         .padding(.leading, 24)
                        //     Text("Member since \(memberSinceDate)")
                        //         .foregroundStyle(.white.opacity(0.7))
                        //         .font(.subheadline)
                        //     Spacer()
                        // }

                        // Premium Status
                        if isPremiumEnabled {
                            HStack(spacing: 10) {
                                Image(systemName: "crown.fill")
                                    .foregroundStyle(Color.appAccent)
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text("Premium")
                                    .foregroundStyle(Color.appAccent)
                                    .font(.subheadline.weight(.medium))
                                Spacer()
                            }
                        } else {
                            Button {
                                showUpsellPreview = true
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "crown")
                                        .foregroundStyle(.white.opacity(0.4))
                                        .font(.system(size: 14))
                                        .frame(width: 20)
                                        .padding(.leading, 24)
                                    Text("Free Plan")
                                        .foregroundStyle(.white.opacity(0.7))
                                        .font(.subheadline)
                                    Spacer()
                                    Text("Upgrade")
                                        .foregroundStyle(Color.appAccent)
                                        .font(.caption.weight(.medium))
                                }
                            }
                            .buttonStyle(.plain)
                        }

                        // Logout Button
                        Button(role: .destructive) {
                            showLogoutConfirmation = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.right.square")
                                    .foregroundStyle(.red.opacity(0.7))
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text("Logout")
                                Spacer()
                                if authViewModel.isLoading {
                                    ProgressView()
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
                        // Profile Section (commented out for now)
                        // VStack(alignment: .leading, spacing: 8) {
                        //     Text("Profile")
                        //         .font(.subheadline)
                        //         .foregroundStyle(.white.opacity(0.7))
                        //         .padding(.leading, 32)
                        //
                        //     Button {
                        //         tempBodyweight = userProperties.bodyweight ?? 0
                        //         showWeightInput = true
                        //     } label: {
                        //         HStack {
                        //             Text("Bodyweight")
                        //                 .foregroundStyle(.primary)
                        //                 .padding(.leading, 32)
                        //             Spacer()
                        //             if let bodyweight = userProperties.bodyweight {
                        //                 Text("\(bodyweight, specifier: "%.1f") lbs")
                        //                     .foregroundStyle(.white.opacity(0.5))
                        //             } else {
                        //                 Text("Not Set")
                        //                     .foregroundStyle(.white.opacity(0.5))
                        //             }
                        //         }
                        //     }
                        // }
                        // .padding(.vertical, 4)

                        // Progress Options Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Progress Options")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.leading, 32)

                            // Plate Increments
                            Button {
                                showPlateSelection = true
                            } label: {
                                HStack {
                                    Text("Plate Increments")
                                        .foregroundStyle(.white.opacity(0.7))
                                        .font(.subheadline)
                                        .padding(.leading, 40)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.white.opacity(0.3))
                                        .font(.system(size: 12))
                                }
                            }

                            // Rep Range
                            VStack(alignment: .leading, spacing: 10) {
                                HStack {
                                    Text("Rep Range")
                                        .foregroundStyle(.white.opacity(0.7))
                                        .font(.subheadline)
                                        .padding(.leading, 40)
                                    Spacer()
                                    Text("\(userProperties.minReps)–\(userProperties.maxReps) reps")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .font(.subheadline)
                                }

                                RangeSliderView(
                                    minValue: Binding(
                                        get: { Double(userProperties.minReps) },
                                        set: { userProperties.minReps = Int($0); try? modelContext.save() }
                                    ),
                                    maxValue: Binding(
                                        get: { Double(userProperties.maxReps) },
                                        set: { userProperties.maxReps = Int($0); try? modelContext.save() }
                                    ),
                                    bounds: 1...12,
                                    minSpan: Double(UserProperties.minRepRangeSpan)
                                )
                                .padding(.horizontal, 40)
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
                                Text("Populate 28 Days of Data")
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

                        Button {
                            showUpsellPreview = true
                        } label: {
                            HStack {
                                Text("Show Premium Upsell")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: "crown")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        // Premium Status Toggle
                        HStack {
                            Text("Premium Status")
                                .foregroundStyle(.primary)
                                .padding(.leading, 32)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isPremiumEnabled },
                                set: { isPremiumEnabled = $0 }
                            ))
                            .labelsHidden()
                            .tint(Color.appAccent)
                        }

                        Button {
                            withAnimation {
                                showExerciseIds.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Show Exercise IDs")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: showExerciseIds ? "eye.fill" : "eye")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showExerciseIds {
                            ForEach(exercises.sorted { $0.name < $1.name }, id: \.id) { exercise in
                                HStack {
                                    Text(exercise.name)
                                        .foregroundStyle(.white.opacity(0.7))
                                        .padding(.leading, 48)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(exercise.id.uuidString.prefix(8) + "...")
                                        .foregroundStyle(.white.opacity(0.5))
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                }
                            }
                        }

                        Button {
                            withAnimation {
                                showMemberSince.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Show Member Since")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: showMemberSince ? "calendar.circle.fill" : "calendar.circle")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showMemberSince {
                            HStack {
                                Text("Member Since")
                                    .foregroundStyle(.white.opacity(0.7))
                                    .padding(.leading, 48)
                                Spacer()
                                Text(memberSinceDate)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .font(.system(.caption, design: .monospaced))
                            }
                        }

                        Button {
                            withAnimation {
                                showTokenExpiry.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Token Expiry Info")
                                    .foregroundStyle(.primary)
                                    .padding(.leading, 32)
                                Spacer()
                                Image(systemName: showTokenExpiry ? "clock.fill" : "clock")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showTokenExpiry {
                            TokenExpiryView()
                                .padding(.leading, 32)
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
                        Text("Generates realistic training data for the past 28 days. Update user properties sends a test API call. Replay onboarding/welcome back shows the post-auth flows. Premium Status toggles premium features on/off for testing. Show Exercise IDs displays UUIDs for debugging. Delete all workout data removes all LiftSet and Estimated1RM entries.")
                    }
                }
            }
            .navigationTitle("More")
            .sheet(isPresented: $showWeightInput) {
                weightInputSheet
            }
            .fullScreenCover(isPresented: $showPlateSelection) {
                AvailableChangePlatesView()
            }
            .fullScreenCover(isPresented: $showUpsellPreview) {
                UpsellView { _ in
                    showUpsellPreview = false
                }
            }
            .alert("Data Populated", isPresented: $showDataPopulatedAlert) {
                Button("OK") { }
            } message: {
                Text("Successfully generated 28 days of training data.")
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
            .overlay(alignment: .bottom) {
                if let toast = copiedToast {
                    Text(toast)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(Color(white: 0.25))
                        )
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: copiedToast)
        }
    }

    private func showCopiedToast(_ message: String) {
        copiedToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedToast = nil
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

        // Training plan: alternate between push/pull/legs over 28 days
        let workoutPlans: [[String]] = [
            ["Bench Press", "Overhead Press", "Dips"], // Push
            ["Deadlift", "Barbell Row", "Pull Ups"], // Pull
            ["Squat"], // Legs
        ]

        // Track max 1RM per exercise for progression
        var exerciseMaxes: [String: Double] = [:]

        for daysAgo in (1...28).reversed() {
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
                if exerciseMaxes[exerciseName] == nil {
                    exerciseMaxes[exerciseName] = {
                        switch exerciseName {
                        case "Deadlift": return 225.0
                        case "Squat": return 200.0
                        case "Bench Press": return 165.0
                        case "Barbell Row": return 145.0
                        case "Overhead Press": return 100.0
                        case "Pull Ups": return 50.0
                        case "Dips": return 70.0
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

                    let set = LiftSet(exercise: exercise, reps: reps, weight: calculatedWeight)
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
            case "Pull Ups": return 65.0
            case "Dips": return 90.0
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

                let set = LiftSet(exercise: exercise, reps: reps, weight: calculatedWeight)
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
            let response = try await APIService.shared.updateUserProperties(availableChangePlates: userProperties.availableChangePlates)
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

        // Hard delete all Exercises (both custom and built-in since they're synced)
        for exercise in exercises {
            modelContext.delete(exercise)
        }

        // Hard delete UserProperties
        for properties in userPropertiesItems {
            modelContext.delete(properties)
        }

        try? modelContext.save()
    }
}

// MARK: - Token Expiry View

struct TokenExpiryView: View {
    // Access token lifetime is 15 minutes (900 seconds)
    private let accessTokenLifetime: TimeInterval = 15 * 60
    // Auto-refresh triggers at 75% of lifetime (11.25 min elapsed = 3.75 min remaining)
    private let refreshThresholdRemaining: TimeInterval = 3.75 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0)) { context in
            let tokenInfo = getTokenInfo(at: context.date)

            VStack(alignment: .leading, spacing: 12) {
                // Access Token Expiry
                TokenCountdownRow(
                    label: "Access Token",
                    countdown: tokenInfo.accessTokenCountdown,
                    isExpired: tokenInfo.accessTokenExpired,
                    color: tokenInfo.accessTokenExpired ? .red : .green
                )

                // Auto-Refresh Countdown
                TokenCountdownRow(
                    label: "Auto-Refresh In",
                    countdown: tokenInfo.autoRefreshCountdown,
                    isExpired: tokenInfo.shouldRefreshNow,
                    expiredText: "Now",
                    color: tokenInfo.shouldRefreshNow ? .orange : .blue
                )

                // Refresh Token Expiry
                TokenCountdownRow(
                    label: "Refresh Token",
                    countdown: tokenInfo.refreshTokenCountdown,
                    isExpired: tokenInfo.refreshTokenExpired,
                    color: tokenInfo.refreshTokenExpired ? .red : (tokenInfo.refreshTokenTracked ? .green : .gray)
                )
            }
            .padding(.vertical, 8)
        }
    }

    private struct TokenInfo {
        let accessTokenCountdown: String
        let accessTokenExpired: Bool
        let autoRefreshCountdown: String
        let shouldRefreshNow: Bool
        let refreshTokenCountdown: String
        let refreshTokenExpired: Bool
        let refreshTokenTracked: Bool
    }

    private func getTokenInfo(at date: Date) -> TokenInfo {
        guard let tokenStorage = KeychainService.shared.getTokenStorage() else {
            return TokenInfo(
                accessTokenCountdown: "No token",
                accessTokenExpired: true,
                autoRefreshCountdown: "No token",
                shouldRefreshNow: true,
                refreshTokenCountdown: "No token",
                refreshTokenExpired: true,
                refreshTokenTracked: false
            )
        }

        let timeUntilExpiry = tokenStorage.expiresAt.timeIntervalSince(date)
        let accessTokenExpired = timeUntilExpiry <= 0

        // Access token countdown
        let accessTokenCountdown: String
        if accessTokenExpired {
            accessTokenCountdown = "Expired"
        } else {
            accessTokenCountdown = formatCountdown(timeUntilExpiry)
        }

        // Auto-refresh countdown (time until shouldRefresh becomes true)
        // shouldRefresh triggers when timeUntilExpiry <= refreshThresholdRemaining
        let timeUntilAutoRefresh = timeUntilExpiry - refreshThresholdRemaining
        let shouldRefreshNow = timeUntilAutoRefresh <= 0

        let autoRefreshCountdown: String
        if accessTokenExpired {
            autoRefreshCountdown = "Expired"
        } else if shouldRefreshNow {
            autoRefreshCountdown = "Now"
        } else {
            autoRefreshCountdown = formatCountdown(timeUntilAutoRefresh)
        }

        // Refresh token countdown
        let refreshTokenCountdown: String
        let refreshTokenExpired: Bool
        let refreshTokenTracked: Bool

        if let refreshExpiry = tokenStorage.refreshTokenExpiresAt {
            refreshTokenTracked = true
            let timeUntilRefreshExpiry = refreshExpiry.timeIntervalSince(date)
            refreshTokenExpired = timeUntilRefreshExpiry <= 0

            if refreshTokenExpired {
                refreshTokenCountdown = "Expired"
            } else {
                refreshTokenCountdown = formatLongCountdown(timeUntilRefreshExpiry)
            }
        } else {
            refreshTokenTracked = false
            refreshTokenExpired = false
            refreshTokenCountdown = "Not tracked"
        }

        return TokenInfo(
            accessTokenCountdown: accessTokenCountdown,
            accessTokenExpired: accessTokenExpired,
            autoRefreshCountdown: autoRefreshCountdown,
            shouldRefreshNow: shouldRefreshNow,
            refreshTokenCountdown: refreshTokenCountdown,
            refreshTokenExpired: refreshTokenExpired,
            refreshTokenTracked: refreshTokenTracked
        )
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }

    private func formatLongCountdown(_ seconds: TimeInterval) -> String {
        let totalSeconds = Int(seconds)
        let days = totalSeconds / 86400
        let hours = (totalSeconds % 86400) / 3600
        let minutes = (totalSeconds % 3600) / 60

        if days > 0 {
            return String(format: "%dd %dh %dm", days, hours, minutes)
        } else if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        } else {
            return String(format: "%dm", minutes)
        }
    }
}

struct TokenCountdownRow: View {
    let label: String
    let countdown: String
    let isExpired: Bool
    var expiredText: String = "Expired"
    let color: Color

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.7))
                .font(.subheadline)
            Spacer()
            Text(isExpired && countdown != "Now" ? expiredText : countdown)
                .foregroundStyle(color)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.medium)
        }
    }
}

// MARK: - Range Slider View

struct RangeSliderView: View {
    @Binding var minValue: Double
    @Binding var maxValue: Double
    let bounds: ClosedRange<Double>
    let minSpan: Double

    private let thumbSize: CGFloat = 22
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width - thumbSize
            let range = bounds.upperBound - bounds.lowerBound

            ZStack(alignment: .leading) {
                // Background track
                Capsule()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbSize / 2)

                // Active range track
                Capsule()
                    .fill(Color.appAccent)
                    .frame(
                        width: CGFloat((maxValue - minValue) / range) * totalWidth,
                        height: trackHeight
                    )
                    .offset(x: thumbSize / 2 + CGFloat((minValue - bounds.lowerBound) / range) * totalWidth)

                // Min thumb
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: CGFloat((minValue - bounds.lowerBound) / range) * totalWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let raw = bounds.lowerBound + Double(value.location.x / totalWidth) * range
                                let stepped = (raw).rounded()
                                let clamped = min(max(stepped, bounds.lowerBound), maxValue - minSpan)
                                minValue = clamped
                            }
                    )

                // Max thumb
                Circle()
                    .fill(Color.appAccent)
                    .frame(width: thumbSize, height: thumbSize)
                    .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                    .offset(x: CGFloat((maxValue - bounds.lowerBound) / range) * totalWidth)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let raw = bounds.lowerBound + Double(value.location.x / totalWidth) * range
                                let stepped = (raw).rounded()
                                let clamped = min(max(stepped, minValue + minSpan), bounds.upperBound)
                                maxValue = clamped
                            }
                    )
            }
        }
        .frame(height: thumbSize)
    }
}
