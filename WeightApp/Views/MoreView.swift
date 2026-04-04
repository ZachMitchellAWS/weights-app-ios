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
    @Query private var entitlementRecords: [EntitlementGrant]
    @Query(filter: #Predicate<Exercise> { !$0.deleted }) private var exercises: [Exercise]

    @State private var showAccount = false
    @State private var showDeveloper = false
    @State private var showAbout = false

    @State private var showDataPopulatedAlert = false
    @State private var showTodayDataPopulatedAlert = false
    @State private var showUserPropertiesAlert = false
    @State private var showDeleteConfirmation = false
    @State private var showDataDeletedAlert = false
    @State private var showLogoutConfirmation = false
    @State private var showDeleteAccountSheet = false
    @State private var deleteConfirmationText = ""
    @State private var isDeletingAccount = false
    @State private var userPropertiesAlertMessage = ""
    @State private var isUpdatingProperties = false
    @State private var isPopulating28Days = false
    @State private var isPopulatingToday = false
    @State private var isPopulatingYesterday = false
    @State private var showYesterdayDataPopulatedAlert = false
    @State private var isSeedingMissing = false
    @State private var showSeedMissingAlert = false
    @State private var showSupportSafari = false
    @State private var seedMissingCount = 0
    @State private var isSeedingSetPlans = false
    @State private var showSeedSetPlansAlert = false
    @State private var isSeedingGroups = false
    @State private var showSeedGroupsAlert = false
    @State private var showExerciseIds = false
    @State private var showMemberSince = false
    @State private var showTokenExpiry = false
    @State private var showUpsellPreview = false
    @State private var showExerciseIcons = false
    @State private var showAlertPreviews = false
    @State private var showTierJourneyIntro = false
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
    @State private var isExportingIdealCard = false
    @State private var idealCardExportResult: String?
    @State private var showIdealCardShareSheet = false
    @State private var idealCardImage: UIImage?


    private var userProperties: UserProperties {
        if let props = userPropertiesItems.first { return props }
        let props = UserProperties()
        modelContext.insert(props)
        return props
    }

    private var isPremium: Bool {
        if FreeOverride.isEnabled { return false }
        return PremiumOverride.isEnabled || EntitlementGrant.isPremium(entitlementRecords)
    }

    private var isPremiumEnabled: Bool {
        get { PremiumOverride.isEnabled }
        nonmutating set { PremiumOverride.set(newValue) }
    }

    private var isFreeOverrideEnabled: Bool {
        get { FreeOverride.isEnabled }
        nonmutating set { FreeOverride.set(newValue) }
    }

    private var isUITestModeEnabled: Bool {
        get { UITestMode.isEnabled }
        nonmutating set { UITestMode.set(newValue) }
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
                                if isPremium {
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

                                if !isPremium {
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
                                isPremium
                                    ? Color.appLogoColor.opacity(0.5)
                                    : Color.appAccent.opacity(0.3),
                                lineWidth: 1.5
                            )
                    )
                    .contentShape(RoundedRectangle(cornerRadius: 12))
                    .onTapGesture {
                        if !isPremium {
                            showUpsellPreview = true
                        }
                    }
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
                                    EntitlementsService.shared.updateLocalEntitlements(
                                        from: response,
                                        context: modelContext
                                    )
                                    syncResultIsPremium = isPremium
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

                        // Delete Account Button
                        Button {
                            showDeleteAccountSheet = true
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.secondary.opacity(0.5))
                                    .font(.system(size: 12))
                                    .frame(width: 20)
                                    .padding(.leading, 24)
                                Text("Delete Account")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Settings Section
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "gearshape")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Settings")
                                .foregroundStyle(Color.appAccent)
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Accessories Section
                Section {
                    NavigationLink {
                        AccessoriesView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "square.grid.2x2")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Accessories")
                                .foregroundStyle(Color.appAccent)
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // Support Section
                Section {
                    Button {
                        showSupportSafari = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Support")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.forward")
                                .foregroundStyle(.white.opacity(0.25))
                                .font(.system(size: 12))
                        }
                        .padding(.horizontal, 4)
                    }
                    .sheet(isPresented: $showSupportSafari) {
                        SafariView(url: SubscriptionConfig.supportURL)
                            .ignoresSafeArea()
                    }
                }

                // Feedback Section
                Section {
                     NavigationLink {
                        FeedbackView()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "bubble.left.and.text.bubble.right")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("Feedback")
                                .foregroundStyle(Color.appAccent)
                        }
                        .padding(.horizontal, 4)
                    }
                }

                // About Section (Expandable)
                Section {
                    Button {
                        withAnimation {
                            showAbout.toggle()
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "info.circle")
                                .foregroundStyle(Color.appAccent)
                                .font(.system(size: 20))
                            Text("About")
                                .foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: showAbout ? "chevron.down" : "chevron.right")
                                .foregroundStyle(.white.opacity(0.3))
                                .font(.system(size: 14))
                        }
                        .padding(.horizontal, 4)
                    }

                    if showAbout {
                        // App Version
                        HStack(spacing: 10) {
                            Image(systemName: "number")
                                .foregroundStyle(.white.opacity(0.4))
                                .font(.system(size: 14))
                                .frame(width: 20)
                                .padding(.leading, 24)
                            Text("Version")
                                .foregroundStyle(.white)
                                .font(.subheadline)
                            Spacer()
                            Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.4))
                        }

                        // Terms & Conditions
                        SafariLinkRow(
                            icon: "doc.text",
                            title: "Terms & Conditions",
                            url: SubscriptionConfig.termsURL
                        )

                        // Privacy Policy
                        SafariLinkRow(
                            icon: "hand.raised",
                            title: "Privacy Policy",
                            url: SubscriptionConfig.privacyURL
                        )
                    }
                } footer: {
                    VStack(spacing: 4) {
                        Text("Lift the Bull")
                            .font(.subheadline)
                        Text("Anthroverse LLC")
                            .font(.caption)
                    }
                    .foregroundStyle(.white.opacity(0.4))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
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
                                Text("Populate 90 Days of Data")
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
                                await populateYesterdayData()
                            }
                        } label: {
                            HStack {
                                Text("Populate Yesterday (Last Set Test)")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isPopulatingYesterday {
                                    ProgressView()
                                } else {
                                    Image(systemName: "arrow.counterclockwise")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isPopulatingYesterday)

                        Button {
                            isSeedingMissing = true
                            seedMissingCount = SeedService.seedExercises(context: modelContext).count
                            isSeedingMissing = false
                            showSeedMissingAlert = true
                        } label: {
                            HStack {
                                Text("Seed Missing Exercises")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSeedingMissing {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isSeedingMissing)


                        Button {
                            isSeedingSetPlans = true
                            SeedService.seedSetPlans(context: modelContext)
                            isSeedingSetPlans = false
                            showSeedSetPlansAlert = true
                        } label: {
                            HStack {
                                Text("Seed Missing Set Plans")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSeedingSetPlans {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isSeedingSetPlans)

                        Button {
                            isSeedingGroups = true
                            SeedService.seedGroups(context: modelContext)
                            isSeedingGroups = false
                            showSeedGroupsAlert = true
                        } label: {
                            HStack {
                                Text("Seed Missing Groups")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isSeedingGroups {
                                    ProgressView()
                                } else {
                                    Image(systemName: "plus.circle")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isSeedingGroups)

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
                                Text("Post Logged Set Alerts")
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

                        Button {
                            showTierJourneyIntro = true
                        } label: {
                            HStack {
                                Text("Show Tier Journey Intro")
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "trophy")
                                    .foregroundStyle(Color.appAccent)
                            }
                        }

                        // MARK: Entitlements
                        Text("Entitlements")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.5))

                        HStack {
                            Text("Override Premium")
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isPremiumEnabled },
                                set: { isPremiumEnabled = $0 }
                            ))
                            .labelsHidden()
                            .tint(Color.appAccent)
                        }

                        HStack {
                            Text("Force Local Free")
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isFreeOverrideEnabled },
                                set: { isFreeOverrideEnabled = $0 }
                            ))
                            .labelsHidden()
                            .tint(.red)
                        }

                        HStack {
                            Text("Force Insight (No Audio)")
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { UserDefaults.standard.bool(forKey: "debugForceInsightNoAudio") },
                                set: { UserDefaults.standard.set($0, forKey: "debugForceInsightNoAudio") }
                            ))
                            .labelsHidden()
                            .tint(Color.appAccent)
                        }

                        HStack {
                            Text("Legacy Check-In")
                                .foregroundStyle(.primary)
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { isUITestModeEnabled },
                                set: { isUITestModeEnabled = $0 }
                            ))
                            .labelsHidden()
                            .tint(.purple)
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
                            EntitlementDetailsView(grants: entitlementRecords)
                        }

                        Button {
                            Task {
                                isReplayingTransaction = true
                                replayTransactionResult = nil
                                do {
                                    let response = try await EntitlementsService.shared.processTransactions(
                                        originalTransactionIds: ["2000001123058480"]
                                    )
                                    EntitlementsService.shared.updateLocalEntitlements(
                                        from: response,
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

                        // MARK: Export Narratives Card
                        Button {
                            exportNarrativesCard()
                        } label: {
                            HStack {
                                Text("Export Narratives Card")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isExportingNarrativesCard {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        if let result = narrativesCardExportResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        // MARK: Export Strength Balance Card
                        Button {
                            exportStrengthBalanceCard()
                        } label: {
                            HStack {
                                Text("Export Strength Balance Card")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isExportingBalanceCard {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        if let result = balanceCardExportResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        // MARK: Export Analytics Card
                        Button {
                            exportAnalyticsCard()
                        } label: {
                            HStack {
                                Text("Export Analytics Card")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isExportingAnalyticsCard {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        if let result = analyticsCardExportResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        // MARK: Export Set Plan Catalog Card
                        Button {
                            exportSetPlanCatalogCard()
                        } label: {
                            HStack {
                                Text("Export Set Plan Catalog Card")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isExportingSetPlanCard {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        if let result = setPlanCardExportResult {
                            Text(result)
                                .font(.caption)
                                .foregroundStyle(.green)
                        }

                        // MARK: Export Display Progress Card
                        Button {
                            exportDisplayProgressCard()
                        } label: {
                            HStack {
                                Text("Export Display Progress Card")
                                    .foregroundStyle(.primary)
                                Spacer()
                                if isExportingIdealCard {
                                    ProgressView()
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundStyle(Color.appAccent)
                                }
                            }
                        }
                        .disabled(isExportingIdealCard)

                        if let idealCardExportResult {
                            Text(idealCardExportResult)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(idealCardExportResult.hasPrefix("Error") ? .red.opacity(0.8) : .green.opacity(0.8))
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
                                    TextField("Total weight (\(userProperties.preferredWeightUnit.label))", text: $plateCalcInput)
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
                                Label("Exercise", systemImage: state.exercisesComplete ? "checkmark.circle.fill" : "xmark.circle")
                                    .foregroundStyle(state.exercisesComplete ? .green : .red.opacity(0.7))
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
                        Text("Generate      `s realistic training data for the past 28 days. Update user properties sends a test API call. Replay onboarding/welcome back shows the post-auth flows. Override Premium overrides entitlements to unlock premium features (staging only). Show Exercise IDs displays UUIDs for debugging. Delete all workout data removes all LiftSet and Estimated1RM entries.")
                    }
                }
                #endif
            }
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(isPresented: $showUpsellPreview) {
                UpsellView { _ in
                    showUpsellPreview = false
                }
            }
            .fullScreenCover(isPresented: $showTierJourneyIntro) {
                TierJourneyOverlay(
                    mode: .intro,
                    exerciseTiers: TrendsCalculator.fundamentalExercises.map { ($0, nil, .none) },
                    onDismiss: { showTierJourneyIntro = false },
                    onNavigateToExercise: { _ in showTierJourneyIntro = false },
                    onNavigateToStrength: { showTierJourneyIntro = false }
                )
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
            .sheet(isPresented: $showIdealCardShareSheet) {
                if let image = idealCardImage {
                    ShareSheet(activityItems: [image])
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
            .alert("Yesterday's Data Populated", isPresented: $showYesterdayDataPopulatedAlert) {
                Button("OK") { }
            } message: {
                Text("Created yesterday's sets at Easy/Moderate/Hard effort levels for all exercises. Switch effort modes in CheckIn to see the repeat-arrow indicator on matching tiles.")
            }
            .alert("Seed Missing Exercises", isPresented: $showSeedMissingAlert) {
                Button("OK") { }
            } message: {
                Text(seedMissingCount > 0
                     ? "Added \(seedMissingCount) new exercise\(seedMissingCount == 1 ? "" : "s")."
                     : "All exercises already exist — nothing to add.")
            }
            .alert("Seed Missing Set Plans", isPresented: $showSeedSetPlansAlert) {
                Button("OK") { }
            } message: {
                Text("Default set plans have been seeded.")
            }
            .alert("Seed Missing Groups", isPresented: $showSeedGroupsAlert) {
                Button("OK") { }
            } message: {
                Text("Default groups have been seeded.")
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
            .sheet(isPresented: $showDeleteAccountSheet) {
                deleteConfirmationText = ""
                isDeletingAccount = false
            } content: {
                NavigationStack {
                    VStack(spacing: 24) {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 40))
                                .foregroundStyle(.red)

                            Text("Delete Your Account?")
                                .font(.title2.bold())
                        }
                        .padding(.top, 24)

                        VStack(spacing: 12) {
                            Text("This will permanently delete your account and all associated data, including workout history, exercises, and settings.")

                            Text("Allow up to 7 days for processing. A confirmation email will be sent.")

                            Text("If you have an active subscription, [manage it here](https://apps.apple.com/account/subscriptions) first.")
                                .tint(.blue)
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)

                        VStack(spacing: 8) {
                            Text("Type DELETE to confirm")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            TextField("DELETE", text: $deleteConfirmationText)
                                .textFieldStyle(.roundedBorder)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.characters)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 24)

                        Button {
                            isDeletingAccount = true
                            Task {
                                do {
                                    let _ = try await APIService.shared.requestAccountDeletion()
                                    showDeleteAccountSheet = false
                                    await authViewModel.logout {
                                        hardDeleteAllData()
                                    }
                                } catch {
                                    isDeletingAccount = false
                                }
                            }
                        } label: {
                            HStack {
                                if isDeletingAccount {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text("Confirm Deletion")
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(deleteConfirmationText == "DELETE" && !isDeletingAccount ? Color.red : Color.red.opacity(0.3))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(deleteConfirmationText != "DELETE" || isDeletingAccount)
                        .padding(.horizontal, 24)

                        Spacer()
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") {
                                showDeleteAccountSheet = false
                            }
                        }
                    }
                }
                .presentationDetents([.large])
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

    private func showCopiedToast(_ message: String) {
        copiedToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copiedToast = nil
        }
    }

    // MARK: - Helper Functions

    private func populateSimulatedData() async {
        isPopulating28Days = true

        // Clear all existing LiftSet and Estimated1RM data first
        let allLiftSet = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
        for liftSet in allLiftSet { modelContext.delete(liftSet) }
        let allEstimated1RM = (try? modelContext.fetch(FetchDescriptor<Estimated1RM>())) ?? []
        for estimated1RM in allEstimated1RM { modelContext.delete(estimated1RM) }

        let calendar = Calendar.current
        let now = Date()

        if exercises.isEmpty { isPopulating28Days = false; return }

        func roundToIncrement(_ weight: Double) -> Double {
            (weight / 2.5).rounded() * 2.5
        }

        let bw = userProperties.bodyweight ?? 180.0

        // --- Training days per week ---
        // Day A (Mon): Pull — Deadlifts, Barbell Row, Pull Ups, Barbell Curls
        // Day B (Wed): Push — Bench Press, Overhead Press, Weighted Dips, Lateral Raises
        // Day C (Fri): Legs — Squats, Romanian Deadlifts, Bulgarian Split Squats, Standing Calf Raises
        // Day D (Sat, ~50% of weeks): Accessories — Flys, Rear Delt Flys, Back Extensions, Hanging Leg Raises

        struct DayPlan {
            let exerciseNames: [String]
            let isFundamental: [Bool] // true = 6 sets with PR, false = 3-4 accessory sets
        }

        let dayA = DayPlan(exerciseNames: ["Deadlifts", "Barbell Rows", "Pull Ups", "Barbell Curls"],
                           isFundamental: [true, true, true, false])
        let dayB = DayPlan(exerciseNames: ["Bench Press", "Overhead Press", "Weighted Dips", "Lateral Raises"],
                           isFundamental: [true, true, true, false])
        let dayC = DayPlan(exerciseNames: ["Squats", "Romanian Deadlifts", "Bulgarian Split Squats", "Standing Calf Raises"],
                           isFundamental: [true, false, false, false])
        let dayD = DayPlan(exerciseNames: ["Dumbbell Flys", "Rear Delt Flys", "Back Extensions", "Hanging Leg Raises"],
                           isFundamental: [false, false, false, false])

        // Starting 1RMs (mid-intermediate for ~180lb male)
        var exerciseMaxes: [String: Double] = [
            "Deadlifts": 315, "Squats": 265, "Bench Press": 205,
            "Barbell Rows": 155, "Overhead Press": 115,
            "Pull Ups": bw + 45, "Weighted Dips": bw + 55,
            "Romanian Deadlifts": 225, "Bulgarian Split Squats": 135,
            "Barbell Curls": 95, "Lateral Raises": 50,
            "Standing Calf Raises": 185, "Dumbbell Flys": 60,
            "Rear Delt Flys": 40, "Back Extensions": bw + 25,
            "Hanging Leg Raises": bw + 10,
        ]

        var runningBest1RM: [String: Double] = [:]
        var createdSets: [LiftSet] = []
        var createdEstimated1RM: [Estimated1RM] = []

        // Seeded RNG for reproducibility
        var rng = SplitMix64(seed: 42)

        for daysAgo in (1...90).reversed() {
            guard let workoutDate = calendar.date(byAdding: .day, value: -daysAgo, to: now) else { continue }
            let weekday = calendar.component(.weekday, from: workoutDate) // 1=Sun, 2=Mon, ...

            // Determine which plan (if any) for this day
            let plan: DayPlan?
            switch weekday {
            case 2: // Monday — Pull
                plan = Int.random(in: 0..<14, using: &rng) < 13 ? dayA : nil // ~7% miss rate
            case 4: // Wednesday — Push
                plan = Int.random(in: 0..<14, using: &rng) < 13 ? dayB : nil
            case 6: // Friday — Legs
                plan = Int.random(in: 0..<14, using: &rng) < 13 ? dayC : nil
            case 7: // Saturday — occasional accessories
                plan = Int.random(in: 0..<2, using: &rng) == 0 ? dayD : nil // ~50%
            default:
                plan = nil
            }

            guard let todayPlan = plan else { continue }

            // Weekly progression: ~1.5% per week for fundamentals, ~0.75% for accessories
            let weekNumber = (90 - daysAgo) / 7
            let isDeloadWeek = weekNumber % 6 == 5 // every 6th week is deload

            let hour = [7, 9, 12, 17, 18][(daysAgo - 1) % 5]
            let minute = [0, 15, 30, 45, 10][(daysAgo - 1) % 5]
            var currentTime = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: workoutDate) ?? workoutDate

            for (idx, exerciseName) in todayPlan.exerciseNames.enumerated() {
                guard let exercise = exercises.first(where: { $0.name == exerciseName }) else { continue }

                let isFundamental = todayPlan.isFundamental[idx]
                let baseMax = exerciseMaxes[exerciseName] ?? 100.0

                // Apply weekly progression with randomness
                let weeklyRate = isFundamental ? 0.015 : 0.0075
                let noise = Double.random(in: -0.02...0.02, using: &rng)
                let progressMultiplier = isDeloadWeek ? 0.90 : (1.0 + weeklyRate * Double(weekNumber) + noise)
                let currentMax = baseMax * progressMultiplier

                let isBWPlusLoad = exercise.loadType == ExerciseLoadType.bodyweightPlusSingleLoad.rawValue

                if isFundamental && !isDeloadWeek {
                    // 6 sets: 2 easy (10 reps), 2 moderate (8 reps), 1 hard (5 reps), 1 PR (2 reps)
                    let setConfigs: [(intensity: Double, reps: Int)] = [
                        (0.55, 10), (0.60, 10), (0.70, 8), (0.75, 8), (0.85, 5), (1.02, 2)
                    ]
                    for config in setConfigs {
                        let targetWeight = currentMax * config.intensity / (1.0 + Double(config.reps) / 30.0)
                        let weight = isBWPlusLoad ? roundToIncrement(max(targetWeight - bw, 0)) : roundToIncrement(targetWeight)
                        let effectiveWeight = isBWPlusLoad ? weight + bw : weight
                        let logWeight = isBWPlusLoad ? weight : weight

                        let set = LiftSet(exercise: exercise, reps: config.reps, weight: logWeight)
                        set.createdAt = currentTime
                        set.createdTimezone = TimeZone.current.identifier
                        modelContext.insert(set)
                        createdSets.append(set)

                        let setE1RM = OneRMCalculator.estimate1RM(weight: effectiveWeight, reps: config.reps)
                        let best = max(runningBest1RM[exerciseName] ?? 0, setE1RM)
                        runningBest1RM[exerciseName] = best

                        let estimated = Estimated1RM(exercise: exercise, value: best, setId: set.id)
                        estimated.createdAt = currentTime
                        estimated.createdTimezone = TimeZone.current.identifier
                        modelContext.insert(estimated)
                        createdEstimated1RM.append(estimated)

                        currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...4, using: &rng), to: currentTime) ?? currentTime
                    }
                } else {
                    // Accessory or deload: 3 sets, moderate intensity, no PR
                    let setConfigs: [(intensity: Double, reps: Int)] = isDeloadWeek
                        ? [(0.50, 10), (0.55, 10), (0.60, 8)]
                        : [(0.55, 10), (0.65, 8), (0.72, 8)]
                    for config in setConfigs {
                        let targetWeight = currentMax * config.intensity / (1.0 + Double(config.reps) / 30.0)
                        let weight = isBWPlusLoad ? roundToIncrement(max(targetWeight - bw, 0)) : roundToIncrement(targetWeight)
                        let effectiveWeight = isBWPlusLoad ? weight + bw : weight
                        let logWeight = isBWPlusLoad ? weight : weight

                        let set = LiftSet(exercise: exercise, reps: config.reps, weight: logWeight)
                        set.createdAt = currentTime
                        set.createdTimezone = TimeZone.current.identifier
                        modelContext.insert(set)
                        createdSets.append(set)

                        let setE1RM = OneRMCalculator.estimate1RM(weight: effectiveWeight, reps: config.reps)
                        let best = max(runningBest1RM[exerciseName] ?? 0, setE1RM)
                        runningBest1RM[exerciseName] = best

                        let estimated = Estimated1RM(exercise: exercise, value: best, setId: set.id)
                        estimated.createdAt = currentTime
                        estimated.createdTimezone = TimeZone.current.identifier
                        modelContext.insert(estimated)
                        createdEstimated1RM.append(estimated)

                        currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...3, using: &rng), to: currentTime) ?? currentTime
                    }
                }

                currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 4...7, using: &rng), to: currentTime) ?? currentTime
            }
        }

        // Update exercise.currentE1RM from running bests
        for exercise in exercises {
            if let best = runningBest1RM[exercise.name] {
                exercise.currentE1RM = best
                exercise.currentE1RMDate = Date()
            }
        }

        try? modelContext.save()

        // Sync to backend
        do {
            let setDtos = createdSets.map { LiftSetDTO(from: $0) }
            _ = try await APIService.shared.createLiftSet(setDtos)
            let e1rmDtos = createdEstimated1RM.map { Estimated1RMDTO(from: $0) }
            _ = try await APIService.shared.createEstimated1RM(e1rmDtos)
            showDataPopulatedAlert = true
        } catch {
            userPropertiesAlertMessage = "Data created locally but failed to sync: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isPopulating28Days = false
    }

    // Reproducible RNG for simulated data
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9e3779b97f4a7c15
            var z = state
            z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
            z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
            return z ^ (z >> 31)
        }
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
        let bw = userProperties.bodyweight ?? 185.0
        func getBase1RM(for exerciseName: String) -> Double {
            switch exerciseName {
            case "Deadlifts": return 335.0
            case "Squats": return 285.0
            case "Bench Press": return 225.0
            case "Barbell Rows": return 170.0
            case "Overhead Press": return 130.0
            case "Pull Ups": return bw + 55.0
            case "Weighted Dips": return bw + 65.0
            default: return 135.0
            }
        }

        // Start workout at a reasonable time today
        var currentTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
        var createdSets: [LiftSet] = []
        var createdEstimated1RM: [Estimated1RM] = []

        for exercise in exercises {
            let currentMax = getBase1RM(for: exercise.name)

            // Get the existing best 1RM for this exercise from prior data
            let allLiftSet = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
            let existingSets = allLiftSet.filter { $0.exercise?.id == exercise.id }
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

                let set = LiftSet(exercise: exercise, reps: reps, weight: calculatedWeight)
                set.createdAt = currentTime
                set.createdTimezone = TimeZone.current.identifier
                modelContext.insert(set)
                createdSets.append(set)

                // Compute running best estimated 1RM (mirrors real logSet behavior)
                let setEstimated1RM = OneRMCalculator.estimate1RM(weight: calculatedWeight, reps: reps)
                runningBest = max(runningBest, setEstimated1RM)

                let estimated = Estimated1RM(exercise: exercise, value: runningBest, setId: set.id)
                estimated.createdAt = currentTime
                estimated.createdTimezone = TimeZone.current.identifier
                modelContext.insert(estimated)
                createdEstimated1RM.append(estimated)

                // Add some time between sets (2-4 minutes)
                currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 2...4), to: currentTime) ?? currentTime
            }

            // Update exercise's cached currentE1RM
            exercise.currentE1RM = runningBest
            exercise.currentE1RMDate = currentTime

            // Rest between exercises (5-8 minutes)
            currentTime = calendar.date(byAdding: .minute, value: Int.random(in: 5...8), to: currentTime) ?? currentTime
        }

        try? modelContext.save()

        // Sync to backend
        do {
            let setDtos = createdSets.map { LiftSetDTO(from: $0) }
            _ = try await APIService.shared.createLiftSet(setDtos)
            let e1rmDtos = createdEstimated1RM.map { Estimated1RMDTO(from: $0) }
            _ = try await APIService.shared.createEstimated1RM(e1rmDtos)
            showTodayDataPopulatedAlert = true
        } catch {
            userPropertiesAlertMessage = "Data created locally but failed to sync: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isPopulatingToday = false
    }

    /// Populates yesterday with one set per effort level (Easy, Moderate, Hard) for every exercise,
    /// using weights/reps that exactly match effort suggestion tiles so the "last set" indicator appears.
    private func populateYesterdayData() async {
        isPopulatingYesterday = true

        let calendar = Calendar.current
        let now = Date()
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else {
            isPopulatingYesterday = false
            return
        }

        if exercises.isEmpty {
            isPopulatingYesterday = false
            return
        }

        func roundToIncrement(_ weight: Double, increment: Double) -> Double {
            return max(increment, (weight / increment).rounded() * increment)
        }

        var currentTime = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday) ?? yesterday
        var createdSets: [LiftSet] = []
        var createdEstimated1RM: [Estimated1RM] = []

        for exercise in exercises {
            let loadType = exercise.exerciseLoadType
            let increment: Double = loadType.isBarbell ? 5.0 : 2.5

            // Get this exercise's existing best 1RM
            let exerciseId = exercise.id
            let allEstimated = (try? modelContext.fetch(FetchDescriptor<Estimated1RM>())) ?? []
            let exerciseEstimated = allEstimated
                .filter { $0.exercise?.id == exerciseId }
                .sorted { $0.createdAt > $1.createdAt }
            let e1rm: Double = {
                if let latest = exerciseEstimated.first {
                    return latest.value
                }
                let allSets = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
                let exerciseSets = allSets.filter { !$0.deleted && $0.exercise?.id == exerciseId }
                return OneRMCalculator.current1RM(from: exerciseSets)
            }()

            guard e1rm > 0 else { continue }

            // For each effort level, pick one target percent and a rep count in the middle of the range,
            // then compute the weight the same way effortSuggestions does so we get an exact tile match.
            let effortConfigs: [(pct: Double, reps: Int)] = [
                (0.60, 6),  // Easy — 60% of e1RM, 6 reps → lands in 0...70% bounds
                (0.76, 6),  // Moderate — 76% of e1RM, 6 reps → lands in 70...82% bounds
                (0.87, 4),  // Hard — 87% of e1RM, 4 reps → lands in 82...92% bounds
            ]

            var runningBest = e1rm

            for config in effortConfigs {
                let targetE1RM = config.pct * e1rm
                // Mirror the exact weight formula from OneRMCalculator.effortSuggestions:
                // rawWeight = targetE1RM * 30 / (30 + reps), then round to increment
                let rawWeight = targetE1RM * 30.0 / (30.0 + Double(config.reps))
                let weight = roundToIncrement(rawWeight, increment: increment)

                let set = LiftSet(exercise: exercise, reps: config.reps, weight: weight)
                set.createdAt = currentTime
                set.createdTimezone = TimeZone.current.identifier
                modelContext.insert(set)
                createdSets.append(set)

                let setEstimated1RM = OneRMCalculator.estimate1RM(weight: weight, reps: config.reps)
                runningBest = max(runningBest, setEstimated1RM)

                let estimated = Estimated1RM(exercise: exercise, value: runningBest, setId: set.id)
                estimated.createdAt = currentTime
                estimated.createdTimezone = TimeZone.current.identifier
                modelContext.insert(estimated)
                createdEstimated1RM.append(estimated)

                currentTime = calendar.date(byAdding: .minute, value: 3, to: currentTime) ?? currentTime
            }

            // Update exercise's cached currentE1RM
            if runningBest > (exercise.currentE1RM ?? 0) {
                exercise.currentE1RM = runningBest
                exercise.currentE1RMDate = currentTime
            }

            currentTime = calendar.date(byAdding: .minute, value: 5, to: currentTime) ?? currentTime
        }

        try? modelContext.save()

        do {
            let setDtos = createdSets.map { LiftSetDTO(from: $0) }
            _ = try await APIService.shared.createLiftSet(setDtos)
            let e1rmDtos = createdEstimated1RM.map { Estimated1RMDTO(from: $0) }
            _ = try await APIService.shared.createEstimated1RM(e1rmDtos)
            showYesterdayDataPopulatedAlert = true
        } catch {
            userPropertiesAlertMessage = "Data created locally but failed to sync: \(error.localizedDescription)"
            showUserPropertiesAlert = true
        }

        isPopulatingYesterday = false
    }

    private func updateUserProperties() async {
        isUpdatingProperties = true

        do {
            let request = UserPropertiesRequest(
                bodyweight: userProperties.bodyweight,
                availableChangePlates: userProperties.availableChangePlates,
                minReps: userProperties.progressMinReps,
                maxReps: userProperties.progressMaxReps
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

    @MainActor
    @State private var balanceCardImage: UIImage? = nil
    @State private var balanceCardExportResult: String? = nil
    @State private var isExportingBalanceCard = false

    @State private var analyticsCardExportResult: String? = nil
    @State private var isExportingAnalyticsCard = false

    @State private var narrativesCardExportResult: String? = nil
    @State private var isExportingNarrativesCard = false

    @State private var setPlanCardExportResult: String? = nil
    @State private var isExportingSetPlanCard = false

    private func exportSetPlanCatalogCard() {
        isExportingSetPlanCard = true
        setPlanCardExportResult = nil

        let view = SetPlanCatalogCardView()
            .frame(width: 360, height: 780)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = .init(width: 360, height: 780)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let image = renderer.uiImage {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                setPlanCardExportResult = "Saved to Photos"
            } else {
                setPlanCardExportResult = "Export failed"
            }
            isExportingSetPlanCard = false
        }
    }

    private func exportNarrativesCard() {
        isExportingNarrativesCard = true
        narrativesCardExportResult = nil

        let view = NarrativesCardView()
            .frame(width: 360, height: 780)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = .init(width: 360, height: 780)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let image = renderer.uiImage {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                narrativesCardExportResult = "Saved to Photos"
            } else {
                narrativesCardExportResult = "Export failed"
            }
            isExportingNarrativesCard = false
        }
    }

    private func exportStrengthBalanceCard() {
        isExportingBalanceCard = true
        balanceCardExportResult = nil

        let view = StrengthBalanceCardView()
            .frame(width: 360, height: 780)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = .init(width: 360, height: 780)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let image = renderer.uiImage {
                balanceCardImage = image
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                balanceCardExportResult = "Saved to Photos"
            } else {
                balanceCardExportResult = "Export failed"
            }
            isExportingBalanceCard = false
        }
    }

    private func exportAnalyticsCard() {
        isExportingAnalyticsCard = true
        analyticsCardExportResult = nil

        let view = AdvancedAnalyticsCardView()
            .frame(width: 360, height: 780)
            .background(Color.black)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        renderer.proposedSize = .init(width: 360, height: 780)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let image = renderer.uiImage {
                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                analyticsCardExportResult = "Saved to Photos"
            } else {
                analyticsCardExportResult = "Export failed"
            }
            isExportingAnalyticsCard = false
        }
    }

    private func exportDisplayProgressCard() {
        isExportingIdealCard = true
        idealCardExportResult = nil

        let data = ReportCardData(
            dateRangeStart: Calendar.current.date(byAdding: .day, value: -90, to: Date())!,
            dateRangeEnd: Date(),
            overallTier: .advanced,
            previousOverallTier: .intermediate,
            exercises: [
                ExerciseReportData(name: "Deadlifts", icon: "DeadliftIcon", currentE1RM: 405, firstE1RM: 315, tier: .advanced, bwRatio: 2.25, tierProgress: 0.65),
                ExerciseReportData(name: "Squats", icon: "SquatIcon", currentE1RM: 335, firstE1RM: 265, tier: .advanced, bwRatio: 1.86, tierProgress: 0.40),
                ExerciseReportData(name: "Bench Press", icon: "BenchPressIcon", currentE1RM: 265, firstE1RM: 205, tier: .intermediate, bwRatio: 1.47, tierProgress: 0.75),
                ExerciseReportData(name: "Overhead Press", icon: "OverheadPressIcon", currentE1RM: 175, firstE1RM: 135, tier: .intermediate, bwRatio: 0.97, tierProgress: 0.55),
                ExerciseReportData(name: "Barbell Rows", icon: "BarbellRowIcon", currentE1RM: 245, firstE1RM: 185, tier: .intermediate, bwRatio: 1.36, tierProgress: 0.60),
            ],
            totalPRs: 24,
            totalSetsLogged: 847,
            totalVolume: 1_284_500,
            trainingWeeks: 13,
            trainingDays: 42,
            milestonesAchieved: 8,
            milestonesTotal: 30,
            balanceCategory: nil,
            intensity: IntensityBreakdown(easyPct: 0.22, moderatePct: 0.35, hardPct: 0.25, redlinePct: 0.12, prPct: 0.06),
            avgWeeklyVolume: 98_808,
            bodyweight: 180
        )

        let view = TrainingReportCardView(data: data, weightUnit: userProperties.preferredWeightUnit)
            .frame(width: 360, height: 780)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3

        if let image = renderer.uiImage {
            idealCardImage = image
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            idealCardExportResult = "Saved to Photos + share sheet"
            isExportingIdealCard = false
            showIdealCardShareSheet = true
        } else {
            idealCardExportResult = "Error: Failed to render image"
            isExportingIdealCard = false
        }
    }

    private func deleteAllWorkoutData() {
        // Delete all LiftSet items
        let allLiftSet = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
        for liftSet in allLiftSet {
            modelContext.delete(liftSet)
        }

        // Delete all Estimated1RM items
        let allEstimated1RM = (try? modelContext.fetch(FetchDescriptor<Estimated1RM>())) ?? []
        for estimated1RM in allEstimated1RM {
            modelContext.delete(estimated1RM)
        }

        // Clear cached currentE1RM on all exercises
        for exercise in exercises {
            exercise.currentE1RM = nil
            exercise.currentE1RMDate = nil
        }

        // Save the changes
        try? modelContext.save()

        showDataDeletedAlert = true
    }

    private func hardDeleteAllData() {
        // Hard delete all LiftSet
        let allLiftSet = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
        for liftSet in allLiftSet {
            modelContext.delete(liftSet)
        }

        // Hard delete all Estimated1RM
        let allEstimated1RM = (try? modelContext.fetch(FetchDescriptor<Estimated1RM>())) ?? []
        for estimated1RM in allEstimated1RM {
            modelContext.delete(estimated1RM)
        }

        // Hard delete all Exercise (both custom and built-in since they're synced)
        for exercise in exercises {
            modelContext.delete(exercise)
        }

        // Hard delete UserProperties
        for properties in userPropertiesItems {
            modelContext.delete(properties)
        }

        // Hard delete EntitlementGrants
        let allEntitlements = (try? modelContext.fetch(FetchDescriptor<EntitlementGrant>())) ?? []
        for grant in allEntitlements {
            modelContext.delete(grant)
        }

        // Hard delete ExerciseGroups
        let allGroups = (try? modelContext.fetch(FetchDescriptor<ExerciseGroup>())) ?? []
        for group in allGroups {
            modelContext.delete(group)
        }


        try? modelContext.save()
    }
}

// MARK: - Safari Link Row

private struct SafariLinkRow: View {
    let icon: String
    let title: String
    let url: URL
    @State private var showSafari = false

    var body: some View {
        Button {
            showSafari = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(.white.opacity(0.4))
                    .font(.system(size: 14))
                    .frame(width: 20)
                    .padding(.leading, 24)
                Text(title)
                    .foregroundStyle(.white)
                    .font(.subheadline)
                Spacer()
                Image(systemName: "arrow.up.forward")
                    .foregroundStyle(.white.opacity(0.25))
                    .font(.system(size: 12))
            }
        }
        .sheet(isPresented: $showSafari) {
            SafariView(url: url)
                .ignoresSafeArea()
        }
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
    let exercises: [Exercise]
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
        // Set logged overlays
        case submitPR = "Set Logged (PR)"
        case submitNearMax = "Set Logged (Redline)"
        case submitHard = "Set Logged (Hard)"
        case submitModerate = "Set Logged (Moderate)"
        case submitEasy = "Set Logged (Easy)"
        // Milestone overlays
        case milestoneNovice = "Milestone (Novice)"
        case milestoneBeginner = "Milestone (Beginner)"
        case milestoneIntermediate = "Milestone (Intermediate)"
        case milestoneAdvanced = "Milestone (Advanced)"
        case milestoneElite = "Milestone (Elite)"
        case milestoneLegend = "Milestone (Legend)"
        // Tier journey overlays
        case tierIntro = "Tier Journey (Intro)"
        case tierProgress1 = "Tier Journey (1 of 5)"
        case tierProgress3 = "Tier Journey (3 of 5)"
        case tierCompletionNovice = "Tier Unlocked (Novice)"
        case tierCompletionIntermediate = "Tier Unlocked (Intermediate)"
        case tierCompletionElite = "Tier Unlocked (Elite)"
        // Other
        case cancel = "Not Logged"
        case confirmation = "Confirmation Dialog"

        var id: String { rawValue }

        var section: String {
            switch self {
            case .submitPR, .submitNearMax, .submitHard, .submitModerate, .submitEasy:
                return "Set Logged"
            case .milestoneNovice, .milestoneBeginner, .milestoneIntermediate,
                 .milestoneAdvanced, .milestoneElite, .milestoneLegend:
                return "Milestone"
            case .tierIntro, .tierProgress1, .tierProgress3,
                 .tierCompletionNovice, .tierCompletionIntermediate, .tierCompletionElite:
                return "Tier Journey"
            case .cancel, .confirmation:
                return "Other"
            }
        }
    }

    private var sections: [(String, [AlertPreviewType])] {
        let ordered = ["Set Logged", "Milestone", "Tier Journey", "Other"]
        let grouped = Dictionary(grouping: AlertPreviewType.allCases, by: \.section)
        return ordered.compactMap { key in
            guard let items = grouped[key] else { return nil }
            return (key, items)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        ForEach(sections, id: \.0) { sectionName, items in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(sectionName)
                                    .font(.subheadline)
                                    .foregroundStyle(.white.opacity(0.5))
                                    .padding(.horizontal, 4)

                                ForEach(items) { previewType in
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
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                    }
                                }
                            }
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Post Logged Set Alerts")
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
        case .milestoneNovice:
            MilestoneOverlayPreview(tier: .novice, exerciseIcon: "BenchPressIcon", exerciseName: "Bench Press", targetLabel: "1 Set Logged")
        case .milestoneBeginner:
            MilestoneOverlayPreview(tier: .beginner, exerciseIcon: "SquatIcon", exerciseName: "Squats", targetLabel: "135 lbs")
        case .milestoneIntermediate:
            MilestoneOverlayPreview(tier: .intermediate, exerciseIcon: "DeadliftIcon", exerciseName: "Deadlifts", targetLabel: "225 lbs")
        case .milestoneAdvanced:
            MilestoneOverlayPreview(tier: .advanced, exerciseIcon: "BarbellRowIcon", exerciseName: "Barbell Rows", targetLabel: "185 lbs")
        case .milestoneElite:
            MilestoneOverlayPreview(tier: .elite, exerciseIcon: "OverheadPressIcon", exerciseName: "Overhead Press", targetLabel: "155 lbs")
        case .milestoneLegend:
            MilestoneOverlayPreview(tier: .legend, exerciseIcon: "", exerciseName: "All Exercises", targetLabel: "Legend Tier")
        case .tierIntro:
            TierJourneyOverlay(
                mode: .intro,
                exerciseTiers: TrendsCalculator.fundamentalExercises.map { ($0, nil, .none) },
                onDismiss: { selectedPreview = nil },
                onNavigateToExercise: { _ in selectedPreview = nil },
                onNavigateToStrength: { selectedPreview = nil }
            )
        case .tierProgress1:
            TierJourneyOverlay(
                mode: .progress(justLoggedId: Exercise.deadliftsId),
                exerciseTiers: tierProgressTiers(loggedCount: 1),
                onDismiss: { selectedPreview = nil },
                onNavigateToExercise: { _ in selectedPreview = nil },
                onNavigateToStrength: { selectedPreview = nil }
            )
        case .tierProgress3:
            TierJourneyOverlay(
                mode: .progress(justLoggedId: Exercise.benchPressId),
                exerciseTiers: tierProgressTiers(loggedCount: 3),
                onDismiss: { selectedPreview = nil },
                onNavigateToExercise: { _ in selectedPreview = nil },
                onNavigateToStrength: { selectedPreview = nil }
            )
        case .tierCompletionNovice:
            TierJourneyOverlay(
                mode: .completion(tier: .novice),
                exerciseTiers: TrendsCalculator.fundamentalExercises.map { ($0, 135.0, .novice) },
                onDismiss: { selectedPreview = nil },
                onNavigateToExercise: { _ in selectedPreview = nil },
                onNavigateToStrength: { selectedPreview = nil }
            )
        case .tierCompletionIntermediate:
            TierJourneyOverlay(
                mode: .completion(tier: .intermediate),
                exerciseTiers: TrendsCalculator.fundamentalExercises.map { ($0, 225.0, .intermediate) },
                onDismiss: { selectedPreview = nil },
                onNavigateToExercise: { _ in selectedPreview = nil },
                onNavigateToStrength: { selectedPreview = nil }
            )
        case .tierCompletionElite:
            TierJourneyOverlay(
                mode: .completion(tier: .elite),
                exerciseTiers: TrendsCalculator.fundamentalExercises.map { ($0, 405.0, .elite) },
                onDismiss: { selectedPreview = nil },
                onNavigateToExercise: { _ in selectedPreview = nil },
                onNavigateToStrength: { selectedPreview = nil }
            )
        case .cancel:
            CancelOverlayPreview()
        case .confirmation:
            ConfirmationOverlayPreview(onDismiss: { selectedPreview = nil })
        }
    }

    /// Sample exercise tiers for progress previews — first N exercises logged
    private func tierProgressTiers(loggedCount: Int) -> [(exercise: TrendsCalculator.FundamentalExercise, e1rm: Double?, tier: StrengthTier)] {
        TrendsCalculator.fundamentalExercises.enumerated().map { index, exercise in
            if index < loggedCount {
                return (exercise, 185.0, .novice)
            } else {
                return (exercise, nil, .none)
            }
        }
    }

}

// MARK: - Entitlement Details Subview

private struct EntitlementDetailsView: View {
    let grants: [EntitlementGrant]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("isPremium", value: "\(PremiumOverride.isEnabled || EntitlementGrant.isPremium(grants))")
            row("freeOverride", value: "\(FreeOverride.isEnabled)")
            row("count", value: "\(grants.count)")

            ForEach(Array(grants.enumerated()), id: \.offset) { index, grant in
                Divider().overlay(Color.white.opacity(0.1))
                row("[\(index)] name", value: grant.entitlementName)
                row("[\(index)] isActive", value: "\(grant.isActive)")
                row("[\(index)] startUtc", value: grant.startUtc.formatted(.dateTime))
                row("[\(index)] endUtc", value: grant.endUtc.formatted(.dateTime))
                TimelineView(.periodic(from: .now, by: 1.0)) { context in
                    row("[\(index)] expiresIn", value: countdownString(from: context.date, to: grant.endUtc))
                }
            }
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
                        Text("+\(delta.rounded1().formatted(.number.precision(.fractionLength(0)))) lbs")
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

private struct MilestoneOverlayPreview: View {
    let tier: StrengthTier
    let exerciseIcon: String
    let exerciseName: String
    let targetLabel: String

    @State private var pulse = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()

            VStack(spacing: 12) {
                Text("Milestone Achieved")
                    .font(.bebasNeue(size: 24))
                    .foregroundStyle(tier.color)

                ZStack {
                    Circle()
                        .fill(tier.color.opacity(0.2))
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(tier.color.opacity(0.7), lineWidth: 3)
                        .frame(width: 72, height: 72)
                    if tier == .legend {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundStyle(tier.color)
                    } else {
                        Image(exerciseIcon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 40, height: 40)
                            .foregroundStyle(tier.color)
                    }
                }

                Text(exerciseName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))

                Text(targetLabel)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))

                Text("See Milestones")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(tier.color, in: Capsule())
                    .padding(.top, 4)
                    .padding(.bottom, 4)
            }
            .padding(16)
            .frame(width: 220)
            .background(Color(white: 0.12), in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(tier.color.opacity(0.5), lineWidth: 1.5)
            )
            .scaleEffect(pulse ? 1.02 : 1.0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.3).repeatCount(3, autoreverses: true).delay(0.2)) {
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
