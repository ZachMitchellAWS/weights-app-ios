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
    @Query private var entitlementItems: [Entitlements]
    @Query(filter: #Predicate<Exercises> { !$0.deleted }) private var exercises: [Exercises]

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
    @State private var isPopulating28Days = false
    @State private var isPopulatingToday = false
    @State private var showExerciseIds = false
    @State private var showMemberSince = false
    @State private var showTokenExpiry = false
    @State private var showUpsellPreview = false
    @State private var showExerciseIcons = false
    @State private var showAlertPreviews = false
    @State private var showEntitlementDetails = false
    @State private var showLogExportSheet = false
    @State private var exportedLogText = ""
    @State private var showSyncState = false
    @ObservedObject private var syncService = SyncService.shared
    @State private var isExportingLogs = false
    @State private var devTapCount = 0
    @State private var devTapTimer: Timer? = nil
    @State private var showForceResyncAlert = false
    @State private var showPlateCalculator = false
    @State private var plateCalcInput: String = ""
    @State private var isReplayingTransaction = false
    @State private var replayTransactionResult: String?
    @State private var isRestoringPurchases = false
    @State private var isSyncingPurchases = false
    @State private var showSyncResult = false
    @State private var syncResultIsPremium = false
    @State private var syncFailed = false
    @State private var copiedToast: String?
    @State private var showAPIValidation = false

    @State private var tempBodyweight: Double = 150
    @State private var repRangeDebounceTask: Task<Void, Never>?
    @State private var effortRepRangeDebounceTask: Task<Void, Never>?

    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var entitlement: Entitlements {
        if let entitlement = entitlementItems.first { return entitlement }
        let entitlement = Entitlements()
        modelContext.insert(entitlement)
        return entitlement
    }

    private var isPremiumEnabled: Bool {
        get { entitlement.isPremium }
        nonmutating set {
            entitlement.isPremium = newValue
            if !newValue {
                entitlement.subscriptionType = nil
                entitlement.expiresAt = nil
                entitlement.transactionId = nil
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
                // Branding Header
                Section {
                    VStack(spacing: 0) {
                        HStack(spacing: 16) {
                            Image("LiftTheBullIcon")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 60, height: 60)
                                .foregroundStyle(Color.appLogoColor)

                            VStack(alignment: .leading, spacing: 4) {
                                if entitlement.isActive {
                                    Text("Premium")
                                        .font(.system(size: 12, weight: .semibold))
                                        .textCase(.uppercase)
                                        .tracking(2)
                                        .foregroundStyle(Color.appAccent)
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(Color.appAccent, lineWidth: 1)
                                        )
                                }

                                Text("Lift the Bull")
                                    .font(.bebasNeue(size: 28))
                                    .foregroundStyle(.white)
                                    .onTapGesture {
                                        devTapCount += 1
                                        devTapTimer?.invalidate()
                                        devTapTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
                                            Task { @MainActor in
                                                devTapCount = 0
                                            }
                                        }
                                        if devTapCount >= 10 {
                                            devTapCount = 0
                                            showForceResyncAlert = true
                                        }
                                    }

                                if !entitlement.isActive {
                                    Button {
                                        showUpsellPreview = true
                                    } label: {
                                        HStack(spacing: 6) {
                                            Image(systemName: "star.fill")
                                            Text("Upgrade to Premium")
                                            Image(systemName: "chevron.right")
                                                .font(.caption2)
                                        }
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Color.appAccent)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }

                            Spacer()
                        }
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(white: 0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                entitlement.isActive
                                    ? Color.appLogoColor.opacity(0.5)
                                    : Color.appAccent.opacity(0.3),
                                lineWidth: 1.5
                            )
                    )
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
                }

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
                        .padding(.horizontal, 4)
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

                        // Restore Purchases
                        Button {
                            Task {
                                isRestoringPurchases = true
                                await PurchaseService.shared.restorePurchases()
                                isRestoringPurchases = false
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text("Restore Purchases")
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                                Spacer()
                                if isRestoringPurchases {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoringPurchases || isSyncingPurchases)

                        // Sync Purchases
                        Button {
                            Task {
                                isSyncingPurchases = true
                                do {
                                    let response = try await EntitlementsService.shared.processTransactions(originalTransactionIds: [])
                                    await EntitlementsService.shared.updateLocalEntitlement(
                                        from: response,
                                        transactionId: entitlement.transactionId ?? "",
                                        context: modelContext
                                    )
                                    syncResultIsPremium = entitlement.isActive
                                    syncFailed = false
                                } catch {
                                    print("Sync purchases failed: \(error)")
                                    syncFailed = true
                                }
                                isSyncingPurchases = false
                                showSyncResult = true
                            }
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .foregroundStyle(.white.opacity(0.4))
                                    .font(.system(size: 14))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text("Sync Purchases")
                                    .foregroundStyle(.white)
                                    .font(.subheadline)
                                Spacer()
                                if isSyncingPurchases {
                                    ProgressView()
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isRestoringPurchases || isSyncingPurchases)

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
                        .padding(.horizontal, 4)
                    }

                    if showSettings {
                        // Profile Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Profile")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.leading, 32)

                            Button {
                                tempBodyweight = userProperties.bodyweight ?? 150
                                showWeightInput = true
                            } label: {
                                HStack {
                                    Text("Bodyweight")
                                        .foregroundStyle(.white.opacity(0.7))
                                        .font(.subheadline)
                                        .padding(.leading, 40)
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

                        // Progress Options Section
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Progress Options")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                                .padding(.leading, 32)

                            // Available Change Plates
                            Button {
                                showPlateSelection = true
                            } label: {
                                HStack {
                                    Text("Available Change Plates")
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
                                        set: { userProperties.minReps = Int($0); try? modelContext.save(); scheduleRepRangeSync() }
                                    ),
                                    maxValue: Binding(
                                        get: { Double(userProperties.maxReps) },
                                        set: { userProperties.maxReps = Int($0); try? modelContext.save(); scheduleRepRangeSync() }
                                    ),
                                    bounds: 1...12,
                                    minSpan: Double(UserProperties.minRepRangeSpan)
                                )
                                .padding(.horizontal, 40)
                            }

                            effortRepRangesSection
                        }
                        .padding(.vertical, 4)
                    }
                }

                #if DEBUG
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
                        .padding(.horizontal, 4)
                    }

                    if showDeveloper {
                        // MARK: Test Data
                        Text("Test Data")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            Task {
                                await populateSimulatedData()
                            }
                        } label: {
                            HStack {
                                Text("Populate 28 Days of Data")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isPopulating28Days {
                                    ProgressView()
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isPopulating28Days)

                        Button {
                            Task {
                                await populateTodayData()
                            }
                        } label: {
                            HStack {
                                Text("Populate Today Data")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isPopulatingToday {
                                    ProgressView()
                                } else {
                                    Image(systemName: "calendar.badge.plus")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isPopulatingToday)

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

                        Button {
                            showAPIValidation = true
                        } label: {
                            HStack {
                                Text("API Validation")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "checkmark.shield")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        // MARK: Flows & Previews
                        Text("Flows & Previews")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            authViewModel.isNewUser = true
                            authViewModel.showPostAuthFlow = true
                        } label: {
                            HStack {
                                Text("Replay Onboarding")
                                    .foregroundStyle(.primary)
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
                                Spacer()
                                Image(systemName: "crown")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        Button {
                            showAlertPreviews = true
                        } label: {
                            HStack {
                                Text("Preview Alerts")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "bell.badge")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        Button {
                            showExerciseIcons = true
                        } label: {
                            HStack {
                                Text("Show Exercise Icons")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "photo.on.rectangle")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        // MARK: Entitlements
                        Text("Entitlements")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        HStack {
                            Text("Premium Status")
                                .foregroundStyle(.primary)
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
                                showEntitlementDetails.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Entitlements Details")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showEntitlementDetails ? "eye.fill" : "eye")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showEntitlementDetails {
                            EntitlementDetailsView(entitlement: entitlement)
                        }

                        Button {
                            Task {
                                isReplayingTransaction = true
                                replayTransactionResult = nil
                                do {
                                    let response = try await EntitlementsService.shared.processTransactions(
                                        originalTransactionIds: ["2000001123058480"]
                                    )
                                    await EntitlementsService.shared.updateLocalEntitlement(
                                        from: response,
                                        transactionId: "2000001123058480",
                                        context: modelContext
                                    )
                                    replayTransactionResult = "Success"
                                } catch {
                                    replayTransactionResult = "Error: \(error)"
                                }
                                isReplayingTransaction = false
                            }
                        } label: {
                            HStack {
                                Text("Replay Transaction")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isReplayingTransaction {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.clockwise.circle")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isReplayingTransaction)

                        if let result = replayTransactionResult {
                            Text(result)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(result.hasPrefix("Error") ? .red.opacity(0.8) : .green.opacity(0.8))
                        }

                        // MARK: Debug
                        Text("Debug")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            withAnimation {
                                showExerciseIds.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Show Exercise IDs")
                                    .foregroundStyle(.primary)
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
                                Spacer()
                                Image(systemName: showMemberSince ? "calendar.circle.fill" : "calendar.circle")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showMemberSince {
                            HStack {
                                Text("Member Since")
                                    .foregroundStyle(.white.opacity(0.7))
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
                                Spacer()
                                Image(systemName: showTokenExpiry ? "clock.fill" : "clock")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showTokenExpiry {
                            TokenExpiryView()
                        }

                        Text("User Samples")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.5))

                        ForEach(UserSamples.Cohort.allCases, id: \.self) { cohort in
                            Toggle(cohort.displayName, isOn: Binding(
                                get: { UserSamples.shared.isInCohort(cohort) },
                                set: { UserSamples.shared.setCohort(cohort, enabled: $0) }
                            ))
                            .font(.subheadline)
                            .tint(.appAccent)
                        }

                        // MARK: Experimental
                        Text("Experimental")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            withAnimation {
                                showPlateCalculator.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Plate Calculator Preview")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showPlateCalculator ? "eye.fill" : "eye")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showPlateCalculator {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Not currently used in the app")
                                    .font(.caption)
                                    .foregroundStyle(.white.opacity(0.4))

                                HStack {
                                    TextField("Total weight (lbs)", text: $plateCalcInput)
                                        .keyboardType(.decimalPad)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 150)

                                    if let weight = Double(plateCalcInput),
                                       let stack = PlateCalculator.calculateForSuggestion(
                                        totalWeight: weight,
                                        availablePlates: userProperties.availableChangePlates + [5, 10, 25, 35, 45]
                                       ) {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text("Per side:")
                                                .font(.caption2)
                                                .foregroundStyle(.white.opacity(0.5))
                                            Text(stack.plates.map { "\($0.formatted(.number.precision(.fractionLength(0...2))))" }.joined(separator: " + "))
                                                .font(.system(.caption, design: .monospaced))
                                                .foregroundStyle(.white.opacity(0.8))
                                        }
                                    }
                                }
                            }
                        }

                        // MARK: Sync Logs
                        Text("Sync Logs")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            isExportingLogs = true
                            do {
                                exportedLogText = try LogExporter.exportRecentLogs()
                                showLogExportSheet = true
                            } catch {
                                exportedLogText = "Failed to export logs: \(error.localizedDescription)"
                                showLogExportSheet = true
                            }
                            isExportingLogs = false
                        } label: {
                            HStack {
                                Text("Export Sync Logs")
                                Spacer()
                                if isExportingLogs {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(.blue)
                                }
                            }
                        }

                        // MARK: Sync State
                        Text("Sync State")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        Button {
                            withAnimation {
                                showSyncState.toggle()
                            }
                        } label: {
                            HStack {
                                Text("Show Sync State")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: showSyncState ? "eye.fill" : "eye")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        if showSyncState {
                            let state = syncService.currentSyncState
                            VStack(alignment: .leading, spacing: 6) {
                                Label("Sync Complete", systemImage: state.syncComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.syncComplete ? .green : .red.opacity(0.7))
                                Label("User Properties", systemImage: state.userPropertiesComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.userPropertiesComplete ? .green : .red.opacity(0.7))
                                Label("Exercises", systemImage: state.exercisesComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.exercisesComplete ? .green : .red.opacity(0.7))
                                Label("Sequences", systemImage: state.sequencesComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.sequencesComplete ? .green : .red.opacity(0.7))
                                Label("Lift Sets", systemImage: state.liftSetsComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.liftSetsComplete ? .green : .red.opacity(0.7))
                                Label("Estimated 1RMs", systemImage: state.estimated1RMsComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.estimated1RMsComplete ? .green : .red.opacity(0.7))

                                Divider()

                                HStack {
                                    Text("Lift Set Page Token")
                                        .foregroundStyle(.white.opacity(0.7))
                                    Spacer()
                                    Text(state.liftSetPageToken ?? "nil")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1)
                                }
                                HStack {
                                    Text("E1RM Page Token")
                                        .foregroundStyle(.white.opacity(0.7))
                                    Spacer()
                                    Text(state.estimated1RMPageToken ?? "nil")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                        .lineLimit(1)
                                }

                                Divider()

                                HStack {
                                    Text("Lift Sets Fetched")
                                        .foregroundStyle(.white.opacity(0.7))
                                    Spacer()
                                    Text("\(state.liftSetsFetched)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                                HStack {
                                    Text("E1RMs Fetched")
                                        .foregroundStyle(.white.opacity(0.7))
                                    Spacer()
                                    Text("\(state.estimated1RMsFetched)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.white.opacity(0.5))
                                }
                            }
                            .font(.caption)
                            .padding(.vertical, 4)
                        }

                        // MARK: Danger Zone
                        Text("Danger Zone")
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.5))

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
                    }
                } footer: {
                    if showDeveloper {
                        Text("Generates realistic training data for the past 28 days. Update user properties sends a test API call. Replay onboarding/welcome back shows the post-auth flows. Premium Status toggles premium features on/off for testing. Show Exercise IDs displays UUIDs for debugging. Delete all workout data removes all LiftSets and Estimated1RMs entries.")
                    }
                }
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
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
            .sheet(isPresented: $showExerciseIcons) {
                ExerciseIconsPreviewSheet(exercises: exercises)
            }
            .sheet(isPresented: $showAlertPreviews) {
                AlertPreviewsSheet()
            }
            .sheet(isPresented: $showAPIValidation) {
                APIValidationView()
            }
            .sheet(isPresented: $showLogExportSheet) {
                ShareSheet(activityItems: [exportedLogText])
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
                Text("This will permanently delete all LiftSets and Estimated1RMs entries. This action cannot be undone.")
            }
            .alert("Data Deleted", isPresented: $showDataDeletedAlert) {
                Button("OK") { }
            } message: {
                Text("Successfully deleted all workout data.")
            }
            .alert(syncFailed ? "Sync Failed" : (syncResultIsPremium ? "Premium Active" : "Free Plan"), isPresented: $showSyncResult) {
                Button("OK") { }
            } message: {
                if syncFailed {
                    Text("Something went wrong syncing your purchases. Please try again later.")
                } else if syncResultIsPremium {
                    Text("You're all set! Your premium subscription is active.")
                } else {
                    Text("No active premium subscription found. You're currently on the free plan.")
                }
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
            .alert("Force Re-Sync", isPresented: $showForceResyncAlert) {
                Button("Re-Sync", role: .destructive) {
                    Task {
                        await SyncService.shared.forceResync()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear sync state and re-download all data from the server. Existing local data will be deduplicated.")
            }
            .overlay(alignment: .bottom) {
                if let toast = copiedToast {
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
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

    private func scheduleRepRangeSync() {
        repRangeDebounceTask?.cancel()
        let minReps = userProperties.minReps
        let maxReps = userProperties.maxReps
        repRangeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await SyncService.shared.updateRepRange(minReps: minReps, maxReps: maxReps)
        }
    }

    private func scheduleEffortRepRangeSync() {
        effortRepRangeDebounceTask?.cancel()
        let easyMin = userProperties.easyMinReps
        let easyMax = userProperties.easyMaxReps
        let modMin = userProperties.moderateMinReps
        let modMax = userProperties.moderateMaxReps
        let hardMin = userProperties.hardMinReps
        let hardMax = userProperties.hardMaxReps
        effortRepRangeDebounceTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await SyncService.shared.updateEffortRepRange(
                easyMinReps: easyMin, easyMaxReps: easyMax,
                moderateMinReps: modMin, moderateMaxReps: modMax,
                hardMinReps: hardMin, hardMaxReps: hardMax
            )
        }
    }

    private var effortRepRangesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Effort Rep Ranges")
                .foregroundStyle(.white.opacity(0.7))
                .font(.subheadline)
                .padding(.leading, 40)

            // Easy
            HStack {
                Text("Easy")
                    .foregroundStyle(Color.setEasy)
                    .font(.caption)
                    .padding(.leading, 40)
                Spacer()
                Text("\(userProperties.easyMinReps)–\(userProperties.easyMaxReps) reps")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.caption)
            }
            RangeSliderView(
                minValue: Binding(
                    get: { Double(userProperties.easyMinReps) },
                    set: { userProperties.easyMinReps = Int($0); try? modelContext.save(); scheduleEffortRepRangeSync() }
                ),
                maxValue: Binding(
                    get: { Double(userProperties.easyMaxReps) },
                    set: { userProperties.easyMaxReps = Int($0); try? modelContext.save(); scheduleEffortRepRangeSync() }
                ),
                bounds: 1...12,
                minSpan: Double(UserProperties.minRepRangeSpan)
            )
            .padding(.horizontal, 40)

            // Moderate
            HStack {
                Text("Moderate")
                    .foregroundStyle(Color.setModerate)
                    .font(.caption)
                    .padding(.leading, 40)
                Spacer()
                Text("\(userProperties.moderateMinReps)–\(userProperties.moderateMaxReps) reps")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.caption)
            }
            RangeSliderView(
                minValue: Binding(
                    get: { Double(userProperties.moderateMinReps) },
                    set: { userProperties.moderateMinReps = Int($0); try? modelContext.save(); scheduleEffortRepRangeSync() }
                ),
                maxValue: Binding(
                    get: { Double(userProperties.moderateMaxReps) },
                    set: { userProperties.moderateMaxReps = Int($0); try? modelContext.save(); scheduleEffortRepRangeSync() }
                ),
                bounds: 1...12,
                minSpan: Double(UserProperties.minRepRangeSpan)
            )
            .padding(.horizontal, 40)

            // Hard
            HStack {
                Text("Hard")
                    .foregroundStyle(Color.setHard)
                    .font(.caption)
                    .padding(.leading, 40)
                Spacer()
                Text("\(userProperties.hardMinReps)–\(userProperties.hardMaxReps) reps")
                    .foregroundStyle(.white.opacity(0.5))
                    .font(.caption)
            }
            RangeSliderView(
                minValue: Binding(
                    get: { Double(userProperties.hardMinReps) },
                    set: { userProperties.hardMinReps = Int($0); try? modelContext.save(); scheduleEffortRepRangeSync() }
                ),
                maxValue: Binding(
                    get: { Double(userProperties.hardMaxReps) },
                    set: { userProperties.hardMaxReps = Int($0); try? modelContext.save(); scheduleEffortRepRangeSync() }
                ),
                bounds: 1...12,
                minSpan: Double(UserProperties.minRepRangeSpan)
            )
            .padding(.horizontal, 40)
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
                        .font(.title2.weight(.bold))
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
                            .font(.title2.weight(.bold))
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.trailing, 40)
                    }
                    .frame(height: 200)

                    Spacer()

                    // Buttons
                    HStack(spacing: 16) {
                        Button {
                            tempBodyweight = 150
                            userProperties.bodyweight = nil
                            try? modelContext.save()
                            showWeightInput = false
                            Task { await SyncService.shared.updateBodyweight(nil) }
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
                            Task { await SyncService.shared.updateBodyweight(tempBodyweight) }
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

    private func populateSimulatedData() async {
        isPopulating28Days = true

        // Clear all existing LiftSets and Estimated1RMs data first
        let allLiftSets = (try? modelContext.fetch(FetchDescriptor<LiftSets>())) ?? []
        for liftSet in allLiftSets {
            modelContext.delete(liftSet)
        }
        let allEstimated1RMs = (try? modelContext.fetch(FetchDescriptor<Estimated1RMs>())) ?? []
        for estimated1RM in allEstimated1RMs {
            modelContext.delete(estimated1RM)
        }

        let calendar = Calendar.current
        let now = Date()

        // Ensure we have exercises
        if exercises.isEmpty {
            isPopulating28Days = false
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
        var createdSets: [LiftSets] = []
        var createdEstimated1RMs: [Estimated1RMs] = []
        // Running best estimated 1RM per exercise (mirrors real logSet behavior)
        var runningBest1RM: [String: Double] = [:]

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
                // For BW+SL exercises, 1RM is total weight (bodyweight + additional)
                let bw = userProperties.bodyweight ?? 185.0
                if exerciseMaxes[exerciseName] == nil {
                    exerciseMaxes[exerciseName] = {
                        switch exerciseName {
                        case "Deadlift": return 225.0
                        case "Squat": return 200.0
                        case "Bench Press": return 165.0
                        case "Barbell Row": return 145.0
                        case "Overhead Press": return 100.0
                        case "Pull Ups": return bw + 50.0
                        case "Dips": return bw + 70.0
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

                    let set = LiftSets(exercise: exercise, reps: reps, weight: calculatedWeight)
                    if exercise.exerciseLoadType == .bodySingleLoad {
                        set.bodyweightUsed = bw
                    }
                    set.createdAt = currentTime
                    set.createdTimezone = TimeZone.current.identifier
                    modelContext.insert(set)
                    createdSets.append(set)

                    // Compute running best estimated 1RM (mirrors real logSet behavior)
                    let setEstimated1RM = OneRMCalculator.estimate1RM(weight: calculatedWeight, reps: reps)
                    let bestSoFar = runningBest1RM[exerciseName] ?? 0
                    let newBest = max(bestSoFar, setEstimated1RM)
                    runningBest1RM[exerciseName] = newBest

                    let estimated = Estimated1RMs(exercise: exercise, value: newBest, setId: set.id)
                    estimated.createdAt = currentTime
                    estimated.createdTimezone = TimeZone.current.identifier
                    modelContext.insert(estimated)
                    createdEstimated1RMs.append(estimated)

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

        // Sync to backend
        do {
            let setDtos = createdSets.map { LiftSetDTO(from: $0) }
            _ = try await APIService.shared.createLiftSets(setDtos)
            let e1rmDtos = createdEstimated1RMs.map { Estimated1RMDTO(from: $0) }
            _ = try await APIService.shared.createEstimated1RMs(e1rmDtos)
            showDataPopulatedAlert = true
        } catch {
            userPropertiesAlertMessage = "Data created locally but failed to sync: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isPopulating28Days = false
    }

    private func populateTodayData() async {
        isPopulatingToday = true

        let calendar = Calendar.current
        let now = Date()

        // Ensure we have exercises
        if exercises.isEmpty {
            isPopulatingToday = false
            return
        }

        // Helper function to round weight to nearest attainable increment (2.5 lbs)
        func roundToAttainable(_ weight: Double) -> Double {
            return (weight / 2.5).rounded() * 2.5
        }

        // Starting 1RM estimates for each exercise
        // For BW+SL exercises, 1RM is total weight (bodyweight + additional)
        let bw = userProperties.bodyweight ?? 185.0
        func getBase1RM(for exerciseName: String) -> Double {
            switch exerciseName {
            case "Deadlift": return 275.0
            case "Squat": return 245.0
            case "Bench Press": return 195.0
            case "Barbell Row": return 175.0
            case "Overhead Press": return 125.0
            case "Pull Ups": return bw + 65.0
            case "Dips": return bw + 90.0
            default: return 135.0
            }
        }

        // Start workout at a reasonable time today
        var currentTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        var createdSets: [LiftSets] = []
        var createdEstimated1RMs: [Estimated1RMs] = []

        for exercise in exercises {
            let currentMax = getBase1RM(for: exercise.name)

            // Get the existing best 1RM for this exercise from prior data
            let allLiftSets = (try? modelContext.fetch(FetchDescriptor<LiftSets>())) ?? []
            let existingSets = allLiftSets.filter { $0.exercise?.id == exercise.id }
            var runningBest = OneRMCalculator.current1RM(from: existingSets)

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

                let set = LiftSets(exercise: exercise, reps: reps, weight: calculatedWeight)
                if exercise.exerciseLoadType == .bodySingleLoad {
                    set.bodyweightUsed = bw
                }
                set.createdAt = currentTime
                set.createdTimezone = TimeZone.current.identifier
                modelContext.insert(set)
                createdSets.append(set)

                // Compute running best estimated 1RM (mirrors real logSet behavior)
                let setEstimated1RM = OneRMCalculator.estimate1RM(weight: calculatedWeight, reps: reps)
                runningBest = max(runningBest, setEstimated1RM)

                let estimated = Estimated1RMs(exercise: exercise, value: runningBest, setId: set.id)
                estimated.createdAt = currentTime
                estimated.createdTimezone = TimeZone.current.identifier
                modelContext.insert(estimated)
                createdEstimated1RMs.append(estimated)

                // Add some time between sets (2-4 minutes)
                currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...4), to: currentTime) ?? currentTime
            }

            // Rest between exercises (5-8 minutes)
            currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 5...8), to: currentTime) ?? currentTime
        }

        try? modelContext.save()

        // Sync to backend
        do {
            let setDtos = createdSets.map { LiftSetDTO(from: $0) }
            _ = try await APIService.shared.createLiftSets(setDtos)
            let e1rmDtos = createdEstimated1RMs.map { Estimated1RMDTO(from: $0) }
            _ = try await APIService.shared.createEstimated1RMs(e1rmDtos)
            showTodayDataPopulatedAlert = true
        } catch {
            userPropertiesAlertMessage = "Data created locally but failed to sync: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isPopulatingToday = false
    }

    private func updateUserProperties() async {
        isUpdatingProperties = true

        do {
            let request = UserPropertiesRequest(
                bodyweight: userProperties.bodyweight,
                availableChangePlates: userProperties.availableChangePlates,
                minReps: userProperties.minReps,
                maxReps: userProperties.maxReps,
                easyMinReps: userProperties.easyMinReps,
                easyMaxReps: userProperties.easyMaxReps,
                moderateMinReps: userProperties.moderateMinReps,
                moderateMaxReps: userProperties.moderateMaxReps,
                hardMinReps: userProperties.hardMinReps,
                hardMaxReps: userProperties.hardMaxReps
            )
            let response = try await APIService.shared.updateUserProperties(request)
            userPropertiesAlertMessage = "Successfully updated user properties\n\nbodyweight: \(response.bodyweight?.description ?? "nil")\nminReps: \(response.minReps?.description ?? "nil")\nmaxReps: \(response.maxReps?.description ?? "nil")"
            showUserPropertiesAlert = true
        } catch {
            userPropertiesAlertMessage = "Failed: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isUpdatingProperties = false
    }

    private func deleteAllWorkoutData() {
        // Delete all LiftSets items
        let allLiftSets = (try? modelContext.fetch(FetchDescriptor<LiftSets>())) ?? []
        for liftSet in allLiftSets {
            modelContext.delete(liftSet)
        }

        // Delete all Estimated1RMs items
        let allEstimated1RMs = (try? modelContext.fetch(FetchDescriptor<Estimated1RMs>())) ?? []
        for estimated1RM in allEstimated1RMs {
            modelContext.delete(estimated1RM)
        }

        // Save the changes
        try? modelContext.save()

        showDataDeletedAlert = true
    }

    private func hardDeleteAllData() {
        // Hard delete all LiftSets
        let allLiftSets = (try? modelContext.fetch(FetchDescriptor<LiftSets>())) ?? []
        for liftSet in allLiftSets {
            modelContext.delete(liftSet)
        }

        // Hard delete all Estimated1RMs
        let allEstimated1RMs = (try? modelContext.fetch(FetchDescriptor<Estimated1RMs>())) ?? []
        for estimated1RM in allEstimated1RMs {
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

        // Hard delete all WorkoutSequences
        let allSequences = (try? modelContext.fetch(FetchDescriptor<WorkoutSequence>())) ?? []
        for sequence in allSequences {
            modelContext.delete(sequence)
        }

        // Hard delete all WorkoutSplits
        let allSplits = (try? modelContext.fetch(FetchDescriptor<WorkoutSplit>())) ?? []
        for split in allSplits {
            modelContext.delete(split)
        }

        // Hard delete Entitlements
        let allEntitlements = (try? modelContext.fetch(FetchDescriptor<Entitlements>())) ?? []
        for entitlement in allEntitlements {
            modelContext.delete(entitlement)
        }

        // Clear active sequence/split preferences and migration flags
        WorkoutSequenceStore.setActiveSequenceId(nil)
        WorkoutSequenceStore.setActiveSplitId(nil)
        UserDefaults.standard.removeObject(forKey: "workoutSequencesMigratedToSplits")
        UserDefaults.standard.removeObject(forKey: "workoutSequencesMigratedToSwiftData")

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

// MARK: - Exercise Icons Preview Sheet

struct ExerciseIconsPreviewSheet: View {
    let exercises: [Exercises]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let iconSize = geometry.size.width * 0.75

                ZStack {
                    Color.black.ignoresSafeArea()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 40) {
                            ForEach(exercises.sorted { $0.name < $1.name }, id: \.id) { exercise in
                                ExerciseIconView(exercise: exercise, size: iconSize)
                                    .foregroundStyle(Color.appAccent)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.horizontal, (geometry.size.width - iconSize) / 2)
                    }
                    .scrollTargetBehavior(.viewAligned)
                    .contentMargins(.horizontal, 0, for: .scrollContent)
                }
            }
            .navigationTitle("Exercise Icons")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

// MARK: - Alert Previews Sheet

struct AlertPreviewsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var selectedPreview: AlertPreviewType? = nil

    enum AlertPreviewType: String, CaseIterable, Identifiable {
        case submitPR = "Set Logged (PR)"
        case submitNearMax = "Set Logged (Near Max)"
        case submitHard = "Set Logged (Hard)"
        case submitModerate = "Set Logged (Moderate)"
        case submitEasy = "Set Logged (Easy)"
        case cancel = "Not Logged"
        case confirmation = "Confirmation Dialog"

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 16) {
                        ForEach(AlertPreviewType.allCases) { previewType in
                            Button {
                                selectedPreview = previewType
                            } label: {
                                HStack {
                                    Text(previewType.rawValue)
                                        .foregroundStyle(.white)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.white.opacity(0.3))
                                }
                                .padding()
                                .background(Color(white: 0.15))
                                .cornerRadius(12)
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Alert Previews")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(Color.appAccent)
                }
            }
            .overlay {
                if let preview = selectedPreview {
                    alertPreview(for: preview)
                        .onTapGesture {
                            selectedPreview = nil
                        }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private func alertPreview(for type: AlertPreviewType) -> some View {
        switch type {
        case .submitPR:
            SubmitOverlayPreview(didIncrease: true, delta: 12.5, intensityLabel: "PR", intensityColor: .setPR)
        case .submitNearMax:
            SubmitOverlayPreview(didIncrease: false, delta: 0, intensityLabel: "Redline", intensityColor: .setNearMax)
        case .submitHard:
            SubmitOverlayPreview(didIncrease: false, delta: 0, intensityLabel: "Hard", intensityColor: .setHard)
        case .submitModerate:
            SubmitOverlayPreview(didIncrease: false, delta: 0, intensityLabel: "Moderate", intensityColor: .setModerate)
        case .submitEasy:
            SubmitOverlayPreview(didIncrease: false, delta: 0, intensityLabel: "Easy", intensityColor: .setEasy)
        case .cancel:
            CancelOverlayPreview()
        case .confirmation:
            ConfirmationOverlayPreview(onDismiss: { selectedPreview = nil })
        }
    }

}

// MARK: - Entitlement Details Subview

private struct EntitlementDetailsView: View {
    let entitlement: Entitlements

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("isPremium", value: "\(entitlement.isPremium)")
            row("isActive", value: "\(entitlement.isActive)")
            row("subscriptionType", value: entitlement.subscriptionType ?? "nil")
            row("expiresAt", value: entitlement.expiresAt?.formatted(.dateTime) ?? "nil")
            if let expiresAt = entitlement.expiresAt {
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    row("expiresIn", value: countdownString(from: context.date, to: expiresAt))
                }
            }
            row("transactionId", value: entitlement.transactionId ?? "nil")
            row("id", value: entitlement.id.uuidString)
        }
        .padding(.leading, 48)
        .padding(.vertical, 4)
    }

    private func row(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.5))
                .font(.system(.caption, design: .monospaced))
            Spacer()
            Text(value)
                .foregroundStyle(.white.opacity(0.7))
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func countdownString(from now: Date, to target: Date) -> String {
        let remaining = Int(target.timeIntervalSince(now))
        guard remaining > 0 else { return "expired" }
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
}

// MARK: - Alert Preview Components

private struct SubmitOverlayPreview: View {
    let didIncrease: Bool
    let delta: Double
    let intensityLabel: String
    let intensityColor: Color

    @State private var pulse = false
    @State private var iconScale: CGFloat = 0.5
    @State private var iconOpacity: Double = 0

    private let squareSize: CGFloat = 160

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                if didIncrease {
                    Image("LiftTheBullIcon")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 60, height: 60)
                        .foregroundStyle(Color.appLogoColor)
                        .scaleEffect(iconScale)
                        .opacity(iconOpacity)
                } else {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 44, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .scaleEffect(iconScale)
                        .opacity(iconOpacity)
                }

                if didIncrease {
                    VStack(spacing: 4) {
                        Text("Increased 1RM by")
                            .font(.subheadline)
                        Text("+\(delta.rounded1().formatted(.number.precision(.fractionLength(delta >= 100 ? 0 : 2)))) lbs")
                            .font(.title.weight(.semibold))
                            .foregroundStyle(Color.appLogoColor)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                } else {
                    VStack(spacing: 2) {
                        Text(intensityLabel)
                            .font(.bebasNeue(size: 28))
                            .foregroundStyle(.white)
                        Text("Set Logged")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .frame(width: squareSize, height: squareSize)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
            )
            .scaleEffect(pulse ? 1.02 : 1.0)
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                    iconScale = 1.0
                    iconOpacity = 1.0
                }
                withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true).delay(0.4)) {
                    pulse = true
                }
            }
        }
    }
}

private struct CancelOverlayPreview: View {
    @State private var pulse = false

    private let squareSize: CGFloat = 160

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 10) {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 44, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.white.opacity(0.7))

                Text("Not Logged")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(width: squareSize, height: squareSize)
            .background(Color(white: 0.2).opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
            )
            .scaleEffect(pulse ? 1.02 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.22).repeatCount(2, autoreverses: true)) {
                    pulse = true
                }
            }
        }
    }
}

private struct ConfirmationOverlayPreview: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture {
                    onDismiss()
                }

            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 72))
                        .frame(width: 90, height: 90)
                        .foregroundStyle(Color.appAccent)

                    Text("Bench Press")
                        .font(.bebasNeue(size: 24))
                        .foregroundStyle(Color.appAccent)
                }

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Text("185.00 lbs")
                            .font(.title2)
                            .foregroundStyle(.white)
                    }

                    Rectangle()
                        .fill(.white.opacity(0.2))
                        .frame(width: 1, height: 24)

                    HStack(spacing: 6) {
                        Text("8")
                            .font(.title2)
                            .foregroundStyle(.white)
                        Text("reps")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(Color(white: 0.08))
                .cornerRadius(12)

                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(height: 1)
                    .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("Cancel")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color(white: 0.2))
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDismiss()
                    } label: {
                        Text("Confirm")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.appAccent)
                            .cornerRadius(10)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .background(Color(white: 0.14))
            .cornerRadius(20)
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .strokeBorder(Color.appLogoColor.opacity(0.5), lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.5), radius: 30, y: 10)
            .padding(.horizontal, 32)
        }
    }
}
