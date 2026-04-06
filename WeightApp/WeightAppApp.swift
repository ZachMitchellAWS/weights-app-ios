//
//  WeightAppApp.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData
import Sentry

@main
struct WeightAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var authViewModel = AuthViewModel()
    @State private var showSplash = true
    @State private var showWelcome = true
    @State private var showSafetyDisclaimer = true
    @State private var initialExerciseId: UUID? = nil
    @State private var showOnboarding = true
    @State private var showUpsell = false
    @State private var transactionListenerTask: Task<Void, Error>?

    let modelContainer: ModelContainer

    init() {
        // Initialize Sentry
        SentrySDK.start { options in
            options.dsn = "https://73f9a7fbe9001ee3fcbb9247a04f7803@o4511134320033792.ingest.us.sentry.io/4511134323638272"
            options.enableAutoSessionTracking = true
            options.enableAppHangTracking = true
            options.enableMetricKit = true
            #if DEBUG
            options.debug = true
            options.environment = "development"
            #else
            options.environment = APIConfig.environment == "production" ? "production" : "staging"
            #endif
        }

        // Clear stale keychain tokens on fresh install.
        // UserDefaults is wiped on uninstall but Keychain persists,
        // so if the flag is missing we know this is a new install.
        let hasLaunchedKey = "hasLaunchedBefore"
        if !UserDefaults.standard.bool(forKey: hasLaunchedKey) {
            KeychainService.shared.clearTokens()
            UserDefaults.standard.set(true, forKey: hasLaunchedKey)
        }

        // Lock to portrait orientation
        AppDelegate.orientationLock = .portrait

        // Create the model container
        do {
            modelContainer = try ModelContainer(
                for: Exercise.self, LiftSet.self, UserProperties.self,
                Estimated1RM.self, EntitlementGrant.self, SetPlan.self,
                AccessoryGoalCheckin.self, ExerciseGroup.self,
                migrationPlan: AppMigrationPlan.self
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
         }

        // Restore Sentry user identity from Keychain if logged in
        if let userId = KeychainService.shared.getUserId() {
            let sentryUser = Sentry.User(userId: userId)
            SentrySDK.setUser(sentryUser)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if authViewModel.isAuthenticated {
                        if authViewModel.showPostAuthFlow {
                            if authViewModel.isNewUser {
                                if showOnboarding {
                                    OnboardingView {
                                        authViewModel.markOnboardingComplete()
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            showOnboarding = false
                                        }
                                    }
                                    .transition(.opacity)
                                } else {
                                    // Upsell for new users
                                    UpsellView { didSubscribe in
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            authViewModel.completePostAuthFlow()
                                        }
                                    }
                                    .transition(.opacity)
                                }
                            } else {
                                WelcomeBackView {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        authViewModel.completePostAuthFlow()
                                    }
                                }
                                .transition(.opacity)
                            }
                        } else {
                            ContentView(authViewModel: authViewModel, initialExerciseId: initialExerciseId)
                                .transition(.opacity)
                                .onAppear {
                                    // Clear initial exercise ID after first use
                                    initialExerciseId = nil
                                }
                        }
                    } else {
                        if showWelcome {
                            WelcomeView(onContinue: {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    showWelcome = false
                                }
                            }, splashVisible: showSplash)
                            .transition(.opacity)
                        } else if showSafetyDisclaimer {
                            SafetyDisclaimerView {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    showSafetyDisclaimer = false
                                }
                            }
                            .transition(.opacity)
                        } else {
                            AuthView(authViewModel: authViewModel)
                                .transition(.opacity)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
                .animation(.easeInOut(duration: 0.4), value: authViewModel.showPostAuthFlow)
                .animation(.easeInOut(duration: 0.4), value: showOnboarding)
                .animation(.easeInOut(duration: 0.4), value: showUpsell)
                .animation(.easeInOut(duration: 0.4), value: showWelcome)
                .animation(.easeInOut(duration: 0.4), value: showSafetyDisclaimer)
                .preferredColorScheme(.dark)
                .opacity(showSplash ? 0 : 1)
                .ignoresSafeArea(.keyboard)

                if showSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // Initialize user samples on first launch
                UserSamples.shared.initializeIfNeeded()

                // Wire up ModelContainer/Context for SyncService, AuthViewModel, and EntitlementsService
                SyncService.shared.setModelContainer(modelContainer)
                let context = modelContainer.mainContext
                authViewModel.setModelContext(context)
                EntitlementsService.shared.setModelContext(context)

                // Seed set plan and group defaults
                SeedService.seedSetPlans(context: context)
                SeedService.seedGroups(context: context)

                // Refresh currentE1RMLocalCache from 12 months of Estimated1RM data
                do {
                    let cacheRefreshCutoff = Calendar.current.date(byAdding: .month, value: -12, to: Date())!
                    let e1rmDescriptor = FetchDescriptor<Estimated1RM>(
                        predicate: #Predicate { !$0.deleted && $0.createdAt >= cacheRefreshCutoff }
                    )
                    let allE1RMs = try context.fetch(e1rmDescriptor)
                    let grouped = Dictionary(grouping: allE1RMs.filter { $0.exercise != nil }) { $0.exercise!.id }
                    for (exerciseId, records) in grouped {
                        guard let maxRecord = records.max(by: { $0.value < $1.value }) else { continue }
                        if let exercise = records.first(where: { $0.exercise?.id == exerciseId })?.exercise {
                            exercise.currentE1RMLocalCache = maxRecord.value
                            exercise.currentE1RMDateLocalCache = maxRecord.createdAt
                        }
                    }
                    try context.save()
                } catch {
                    print("Failed to refresh currentE1RMLocalCache: \(error)")
                }

                // Start listening for StoreKit transaction updates (renewals, etc.)
                transactionListenerTask = PurchaseService.shared.listenForTransactions()

                // Process any pending sync operations on app launch
                if authViewModel.isAuthenticated {
                    Task {
                        await SyncService.shared.processRetryQueue()
                        await SyncService.shared.processUserPropertiesRetryQueue()
                        await SyncService.shared.processLiftSetRetryQueue()
                        await SyncService.shared.processEstimated1RMRetryQueue()
                        await SyncService.shared.processPlanRetryQueue()
                        await SyncService.shared.processGroupRetryQueue()
                        await SyncService.shared.processAccessoryGoalCheckinRetryQueue()

                        // Sync timezone to backend if changed
                        await SyncService.shared.syncTimezoneIfNeeded()

                        // Sync entitlement status from backend
                        await EntitlementsService.shared.syncEntitlementStatus()

                        // Resume incomplete sync if needed (e.g. app was killed mid-sync)
                        await SyncService.shared.resumeSyncIfNeeded()

                        // Silently re-register for push notifications if previously authorized
                        PushNotificationService.shared.refreshTokenIfAuthorized()

                        // Check for new narrative badge (throttled to every 6 hours)
                        await NarrativeBadgeService.shared.refreshOnAppOpen()
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
                }
            }
            .alert("Session Expired", isPresented: $authViewModel.sessionExpired) {
                Button("Sign In") {
                    authViewModel.dismissSessionExpiredAlert()
                }
            } message: {
                Text("Your session has expired. Please sign in again to continue.")
            }
            .onChange(of: authViewModel.isAuthenticated) { _, isAuthenticated in
                if !isAuthenticated {
                    showWelcome = true
                    showSafetyDisclaimer = true
                    showOnboarding = true
                }
            }
            .onChange(of: authViewModel.showPostAuthFlow) { _, showFlow in
                if showFlow {
                    showOnboarding = true
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active && authViewModel.isAuthenticated {
                    Task { await NarrativeBadgeService.shared.refreshOnAppOpen() }
                }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                // Universal link opened the app
                // TODO: Parse activity.webpageURL for deep link routing in the future
            }
        }
        .modelContainer(modelContainer)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        PushNotificationService.shared.handleNewToken(token)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNS registration failed: \(error)")
    }
}
