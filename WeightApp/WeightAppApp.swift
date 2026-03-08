//
//  WeightAppApp.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData

@main
struct WeightAppApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
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
            modelContainer = try ModelContainer(for: Exercise.self, LiftSet.self, UserProperties.self, Estimated1RM.self, EntitlementGrant.self, WorkoutSplit.self, SetPlan.self, AccessoryGoalCheckin.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
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
                            WelcomeView(splashVisible: showSplash) {
                                withAnimation(.easeInOut(duration: 0.4)) {
                                    showWelcome = false
                                }
                            }
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

                // Seed set plan defaults (splits are seeded after sync to avoid duplicates)
                SeedService.seedSetPlans(context: context)

                // Start listening for StoreKit transaction updates (renewals, etc.)
                transactionListenerTask = PurchaseService.shared.listenForTransactions()

                // Process any pending sync operations on app launch
                if authViewModel.isAuthenticated {
                    Task {
                        await SyncService.shared.processRetryQueue()
                        await SyncService.shared.processUserPropertiesRetryQueue()
                        await SyncService.shared.processSplitRetryQueue()
                        await SyncService.shared.processLiftSetRetryQueue()
                        await SyncService.shared.processEstimated1RMRetryQueue()
                        await SyncService.shared.processTemplateRetryQueue()
                        await SyncService.shared.processAccessoryGoalCheckinRetryQueue()

                        // Sync entitlement status from backend
                        await EntitlementsService.shared.syncEntitlementStatus()

                        // Resume incomplete sync if needed (e.g. app was killed mid-sync)
                        await SyncService.shared.resumeSyncIfNeeded()
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
        }
        .modelContainer(modelContainer)
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return AppDelegate.orientationLock
    }
}
