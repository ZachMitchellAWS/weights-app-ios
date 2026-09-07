//
//  WeightAppApp.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import SwiftUI
import SwiftData
import Sentry
import FirebaseCore
import FirebaseAnalytics

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
    @State private var showOnboardingTutorial = false
    @AppStorage("hasSeenOnboardingTutorial") private var hasSeenOnboardingTutorial = false
    @AppStorage("hasSeenLiftTutorialAfterTierUnlock") private var hasSeenLiftTutorialAfterTierUnlock = false
    @ObservedObject private var tutorialPresenter = TutorialPresenter.shared
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
            #endif
            options.environment = APIConfig.environment
        }

        // Initialize Firebase for Google Ads conversion tracking — PRODUCTION ONLY.
        //
        // Not configuring it at all is the only thing that stops `first_open`.
        // `first_open` is an AUTOMATIC Firebase event: the SDK emits it during startup,
        // the app never logs it, and so `AnalyticsService.envName()`'s `_staging` suffix —
        // which keeps every event we DO log out of the production conversion actions —
        // cannot touch it. `Analytics.setAnalyticsCollectionEnabled(false)` after
        // `configure()` is likewise too late; it is racing the event it means to suppress.
        //
        // That mattered because staging and production are indistinguishable to Firebase:
        // one project, one GoogleService-Info.plist, and `APP_BUNDLE_ID_SUFFIX` is empty in
        // BOTH xcconfigs, so both resolve to `io.anthroverse.WeightApp`. Every simulator run,
        // device build and TestFlight install was firing an unsuffixed `first_open` into the
        // property Google Ads optimises against — and every delete-and-reinstall fired
        // another, since a reinstall mints a new app instance id.
        //
        // Nothing is lost by going dark on staging. Firebase here is *only* Google Ads
        // conversion tracking (see AnalyticsService); product analytics is Amplitude, which
        // is already keyed per build config. Push is APNs via AppDelegate, not FCM, so it is
        // unaffected — FirebaseMessaging is not even a dependency.
        //
        // The alternative — a staging bundle-id suffix and a second Firebase app — is
        // cleaner in the abstract and costs new provisioning profiles plus an App Store
        // Connect entry, to preserve data that has no reader.
        if AnalyticsService.isEnabled {
            FirebaseApp.configure()
            Analytics.setDefaultEventParameters(["environment": APIConfig.environment])
        }

        // Initialize Amplitude product analytics. Key is injected per build config
        // (AMPLITUDE_API_KEY → Info.plist), so staging/production hit separate
        // Amplitude projects; no-ops if the key is unset.
        AmplitudeService.shared.configure()

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
            AmplitudeService.shared.identify(userId: userId)
        }
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                Group {
                    if authViewModel.isAuthenticated {
                        if authViewModel.showPostAuthFlow {
                            if authViewModel.isNewUser {
                                // Onboarding, then the upsell, then the tab view.
                                //
                                // Restored from the block that was preserved here while it
                                // was disabled. Two deviations from that block, both
                                // deliberate:
                                //
                                // 1. The `OnboardingView` call keeps the arguments it
                                //    gained while the upsell was off — `isDevelopmentPreview`
                                //    and the `onboardingCompleted` event. The preserved copy
                                //    predates both, and pasting it back verbatim would have
                                //    silently dropped them.
                                // 2. The tutorial-popup chain is NOT revived. It guarded on
                                //    `tutorialPopupEnabled`, which is not declared anywhere,
                                //    and it set `showOnboardingTutorial`, which nothing
                                //    renders any more — the live tutorial goes through
                                //    `TutorialPresenter`. The tutorial is also switched off
                                //    by a later decision than the one that wrote this block.
                                //
                                // `showOnboarding` is the gate between the two steps, so
                                // finishing onboarding no longer ends the post-auth flow —
                                // the upsell's own completion does.
                                if showOnboarding {
                                    OnboardingView(isDevelopmentPreview: authViewModel.isOnboardingDebugPreview) {
                                        authViewModel.markOnboardingComplete()
                                        AnalyticsService.logOnboardingComplete()
                                        AmplitudeService.shared.track(.onboardingCompleted)
                                        withAnimation(.easeInOut(duration: 0.4)) {
                                            showOnboarding = false
                                        }
                                    }
                                    .transition(.opacity)
                                } else {
                                    // Opens on whatever `premiumFeatures` leads with, which
                                    // is Smart Sessions.
                                    UpsellView(source: SubscriptionConfig.UpsellSource.postOnboarding) { _ in
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

                if tutorialPresenter.showLiftTutorial,
                   let resource = ResourceCatalog.all.first {
                    OnboardingTutorialPopup(resource: resource) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tutorialPresenter.showLiftTutorial = false
                        }
                        // Once the tour card closes (watched or skipped), point the
                        // user at where they can find it again. Slight delay so it
                        // sequences after the tutorial's exit animation.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            withAnimation(.easeInOut(duration: 0.25)) {
                                tutorialPresenter.showResourcesHint = true
                            }
                        }
                    }
                    .transition(.opacity)
                    .zIndex(2)
                }

                if tutorialPresenter.showResourcesHint {
                    ResourcesHintPopup(resource: ResourceCatalog.all.first) {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            tutorialPresenter.showResourcesHint = false
                        }
                    }
                    .transition(.opacity)
                    .zIndex(3)
                }
            }
            .onAppear {
                // Initialize user samples on first launch
                UserSamples.shared.initializeIfNeeded()

                // Sync per-user Amplitude properties (cohorts, app version/build, language/locale/timezone)
                AmplitudeService.shared.syncUserProperties()

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

                        // Sync device metadata (timezone/locale/language) to backend if changed
                        await SyncService.shared.syncDeviceMetadataIfNeeded()

                        // Retry the onboarding-complete push if it failed offline at completion time
                        await SyncService.shared.syncOnboardingCompleteIfNeeded()

                        // Push newly-added built-in set plans to the backend. Same shape as
                        // its neighbours: runs every launch, no-ops unless the catalog
                        // version moved. It lives HERE rather than in `performInitialSync`
                        // because that returns early once sync is complete — so an existing
                        // install, the only cohort that needs this, would never reach it.
                        await SyncService.shared.syncBuiltInCatalogIfNeeded()

                        // Which Apple Ads campaign produced this install, recorded against
                        // the user who signed up from it. Here rather than in AuthViewModel
                        // because this block is the only place covering all four ways a
                        // user becomes authenticated — login, signup, Apple Sign-In, and
                        // token restore on launch. Once resolved it never runs again for
                        // the life of the install, including after signing in as someone
                        // else.
                        await AdAttributionService.shared.syncIfNeeded()

                        // Sync entitlement status from backend
                        await EntitlementsService.shared.syncEntitlementStatus()

                        // Resume incomplete sync if needed (e.g. app was killed mid-sync)
                        await SyncService.shared.resumeSyncIfNeeded()

                        // Silently re-register for push notifications if previously authorized
                        PushNotificationService.shared.refreshTokenIfAuthorized()

                        // The session reminder is scheduled on whichever device ran
                        // onboarding, so unlocking the tier on another device only
                        // reaches this one via sync. Reconcile here.
                        let unlocked = try? modelContainer.mainContext
                            .fetch(FetchDescriptor<UserProperties>())
                            .first?.hasMetStrengthTierConditions
                        if unlocked == true {
                            PushNotificationService.shared.cancelSessionReminder(reason: "tier_unlocked")
                        }

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
                    // Periodic re-push of device metadata; change-detected, so it's a no-op network-wise
                    // unless the timezone/locale/language actually changed since last sync.
                    Task { await SyncService.shared.syncDeviceMetadataIfNeeded() }
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

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Required for BOTH foreground presentation and tap handling. Without a
        // delegate, a reminder that fires while the app is open is silently dropped
        // by iOS, and taps can't be routed or measured.
        UNUserNotificationCenter.current().delegate = self
        return true
    }

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

// MARK: - Notification handling

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Show the reminder even when the app is already open. "Today" fires two hours
    /// out, so the app being foregrounded at that moment is a likely case, not an
    /// edge one.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        if notification.request.identifier == PushNotificationService.sessionReminderIdentifier {
            let intent = PushNotificationService.shared.pendingReminderIntent ?? "unknown"
            AmplitudeService.shared.track(.sessionReminderDelivered(intent: intent))
        }
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.notification.request.identifier
        if identifier == PushNotificationService.sessionReminderIdentifier {
            let intent = PushNotificationService.shared.pendingReminderIntent ?? "unknown"
            AmplitudeService.shared.track(.sessionReminderOpened(intent: intent))
            // It has been delivered, so drop the bookkeeping without emitting a
            // cancellation — otherwise a later logout would report it as cancelled.
            PushNotificationService.shared.clearReminderRecord()
            NotificationRouter.shared.pendingDestination = .liftTab
        }
        completionHandler()
    }
}
