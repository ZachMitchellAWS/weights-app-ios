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
    @State private var initialExerciseId: UUID? = nil
    @State private var showUpsell = false

    let modelContainer: ModelContainer

    init() {
        // Lock to portrait orientation
        AppDelegate.orientationLock = .portrait

        // Create the model container
        do {
            modelContainer = try ModelContainer(for: Exercises.self, LiftSet.self, UserProperties.self, Estimated1RM.self, PremiumEntitlement.self)
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
                            // Show onboarding for new users, welcome back for returning users
                            if authViewModel.isNewUser {
                                if showUpsell {
                                    // Show upsell after onboarding
                                    UpsellView { didSubscribe in
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            showUpsell = false
                                            authViewModel.completePostAuthFlow()
                                        }
                                    }
                                    .transition(.opacity)
                                } else {
                                    // Show onboarding first
                                    OnboardingView { selectedExerciseId in
                                        initialExerciseId = selectedExerciseId
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            showUpsell = true
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
                        AuthView(authViewModel: authViewModel)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
                .animation(.easeInOut(duration: 0.4), value: authViewModel.showPostAuthFlow)
                .animation(.easeInOut(duration: 0.4), value: showUpsell)
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

                // Wire up ModelContext for SyncService and AuthViewModel
                let context = modelContainer.mainContext
                SyncService.shared.setModelContext(context)
                authViewModel.setModelContext(context)

                // Process any pending sync operations on app launch
                if authViewModel.isAuthenticated {
                    Task {
                        await SyncService.shared.processRetryQueue()
                        await SyncService.shared.processUserPropertiesRetryQueue()
                        await SyncService.shared.processLiftSetRetryQueue()
                        await SyncService.shared.processEstimated1RMRetryQueue()
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
