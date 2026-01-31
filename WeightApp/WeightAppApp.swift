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

    let modelContainer: ModelContainer

    init() {
        // Lock to portrait orientation
        AppDelegate.orientationLock = .portrait

        // Create the model container
        do {
            modelContainer = try ModelContainer(for: Exercises.self, LiftSet.self, UserProperties.self, Estimated1RM.self)
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
                                OnboardingView {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        authViewModel.completePostAuthFlow()
                                    }
                                }
                                .transition(.opacity)
                            } else {
                                WelcomeBackView {
                                    withAnimation(.easeInOut(duration: 0.4)) {
                                        authViewModel.completePostAuthFlow()
                                    }
                                }
                                .transition(.opacity)
                            }
                        } else {
                            ContentView(authViewModel: authViewModel)
                                .transition(.opacity)
                        }
                    } else {
                        AuthView(authViewModel: authViewModel)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.4), value: authViewModel.isAuthenticated)
                .animation(.easeInOut(duration: 0.4), value: authViewModel.showPostAuthFlow)
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
                // Wire up ModelContext for SyncService and AuthViewModel
                let context = modelContainer.mainContext
                SyncService.shared.setModelContext(context)
                authViewModel.setModelContext(context)

                // Process any pending sync operations on app launch
                if authViewModel.isAuthenticated {
                    Task {
                        await SyncService.shared.processRetryQueue()
                        await SyncService.shared.processUserPropertiesRetryQueue()
                    }
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showSplash = false
                    }
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
