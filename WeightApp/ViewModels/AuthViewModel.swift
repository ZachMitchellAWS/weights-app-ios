//
//  AuthViewModel.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation
import Combine
import SwiftData
import AuthenticationServices
import Sentry
enum AuthResult {
    case success
    case userAlreadyExists
    case error
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var userId: String?
    @Published var isNewUser = false
    @Published var showPostAuthFlow = false
    @Published var sessionExpired = false

    nonisolated(unsafe) private var tokenRefreshTimer: Timer?
    private var modelContext: ModelContext?

    init() {
        checkAuthStatus()
        startTokenRefreshTimer()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    /// Tracks whether a newly created user still needs onboarding.
    /// Set to `true` in `createUser()`, cleared in `completePostAuthFlow()`.
    /// Existing users who never had this flag are unaffected.
    private static let onboardingPendingKey = "onboardingPending"

    private var isOnboardingPending: Bool {
        get { UserDefaults.standard.bool(forKey: Self.onboardingPendingKey) }
        set { UserDefaults.standard.set(newValue, forKey: Self.onboardingPendingKey) }
    }

    func checkAuthStatus() {
        // First check if we have tokens
        guard KeychainService.shared.isAuthenticated() else {
            isAuthenticated = false
            userId = nil
            return
        }

        // Check if refresh token is expired
        if let tokenStorage = KeychainService.shared.getTokenStorage(),
           tokenStorage.isRefreshTokenExpired {
            handleSessionExpired()
            return
        }

        isAuthenticated = true
        userId = KeychainService.shared.getUserId()

        // Resume onboarding if it was interrupted (e.g. force quit mid-onboarding)
        if isOnboardingPending {
            isNewUser = true
            showPostAuthFlow = true
        }
    }

    func completePostAuthFlow() {
        showPostAuthFlow = false
    }

    func markOnboardingComplete() {
        isOnboardingPending = false
    }

    func handleSessionExpired() {
        // Flip auth state FIRST so SwiftUI unmounts views holding @Query<Exercise>
        // references before we delete those rows. Deleting SwiftData rows while
        // authenticated views are still mounted causes a SwiftData fatal
        // (BackingData.swift:739 "Never access a full future backing data... with nil").
        SentrySDK.setUser(nil)
        KeychainService.shared.clearTokens()
        isOnboardingPending = false
        isAuthenticated = false
        userId = nil
        sessionExpired = true
        stopTokenRefreshTimer()

        // Defer destructive SwiftData work one runloop turn so SwiftUI can
        // process the auth-state change and tear down the authenticated view
        // hierarchy before the @Model rows disappear under them.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.hardDeleteAllData()
            SyncService.shared.clearOnLogout()
            NarrativeBadgeService.shared.clearOnLogout()
        }
    }

    private func hardDeleteAllData() {
        guard let modelContext else { return }

        let allLiftSets = (try? modelContext.fetch(FetchDescriptor<LiftSet>())) ?? []
        for item in allLiftSets { modelContext.delete(item) }

        let allEstimated1RM = (try? modelContext.fetch(FetchDescriptor<Estimated1RM>())) ?? []
        for item in allEstimated1RM { modelContext.delete(item) }

        let allExercises = (try? modelContext.fetch(FetchDescriptor<Exercise>())) ?? []
        for item in allExercises { modelContext.delete(item) }

        let allUserProperties = (try? modelContext.fetch(FetchDescriptor<UserProperties>())) ?? []
        for item in allUserProperties { modelContext.delete(item) }

        let allEntitlements = (try? modelContext.fetch(FetchDescriptor<EntitlementGrant>())) ?? []
        for item in allEntitlements { modelContext.delete(item) }

        let allGroups = (try? modelContext.fetch(FetchDescriptor<ExerciseGroup>())) ?? []
        for item in allGroups { modelContext.delete(item) }

        let allSetPlans = (try? modelContext.fetch(FetchDescriptor<SetPlan>())) ?? []
        for item in allSetPlans { modelContext.delete(item) }

        let allAccessoryCheckins = (try? modelContext.fetch(FetchDescriptor<AccessoryGoalCheckin>())) ?? []
        for item in allAccessoryCheckins { modelContext.delete(item) }

        try? modelContext.save()
    }

    func dismissSessionExpiredAlert() {
        sessionExpired = false
    }

    func login(email: String, password: String) async -> AuthResult {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await APIService.shared.login(email: email, password: password)
            isNewUser = false
            showPostAuthFlow = true
            isAuthenticated = true
            userId = response.userId

            let sentryUser = Sentry.User(userId: response.userId)
            sentryUser.email = email
            SentrySDK.setUser(sentryUser)

            AnalyticsService.logLogin(userId: response.userId)

            // Perform initial sync for returning user (includes user properties sync)
            await SyncService.shared.performInitialSync(isNewUser: false)
            await EntitlementsService.shared.syncEntitlementStatus()

            isLoading = false
            return .success
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return .error
        }
    }

    func createUser(email: String, password: String) async -> AuthResult {
        isLoading = true
        errorMessage = nil

        do {
            let response = try await APIService.shared.createUser(email: email, password: password)
            isNewUser = true
            isOnboardingPending = true
            showPostAuthFlow = true
            isAuthenticated = true
            userId = response.userId

            let sentryUser = Sentry.User(userId: response.userId)
            sentryUser.email = email
            SentrySDK.setUser(sentryUser)

            AnalyticsService.logSignUp(userId: response.userId)

            // Perform initial sync for new user (includes user properties sync)
            await SyncService.shared.performInitialSync(isNewUser: true)
            await EntitlementsService.shared.syncEntitlementStatus()

            isLoading = false
            return .success
        } catch let error as APIError {
            if case .httpError(let statusCode, _) = error, statusCode == 409 {
                errorMessage = nil // Don't show error message for 409
                isLoading = false
                return .userAlreadyExists
            }
            errorMessage = error.localizedDescription
            isLoading = false
            return .error
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return .error
        }
    }

    func signInWithApple() async -> AuthResult {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await AppleSignInService.shared.signIn()
            return try await completeAppleSignIn(result)
        } catch let error as AppleSignInService.AppleSignInError {
            if case .cancelled = error {
                isLoading = false
                return .error
            }
            errorMessage = error.localizedDescription
            isLoading = false
            return .error
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return .error
        }
    }

    func handleAppleAuthorization(_ authorization: ASAuthorization) async -> AuthResult {
        isLoading = true
        errorMessage = nil

        do {
            let result = try AppleSignInService.shared.handleAuthorization(authorization)
            return try await completeAppleSignIn(result)
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
            return .error
        }
    }

    private func completeAppleSignIn(_ result: AppleSignInService.AppleSignInResult) async throws -> AuthResult {
        var fullName: String? = nil
        if let nameComponents = result.fullName {
            let formatter = PersonNameComponentsFormatter()
            let formattedName = formatter.string(from: nameComponents)
            if !formattedName.isEmpty {
                fullName = formattedName
            }
        }

        let response = try await APIService.shared.authenticateWithApple(
            identityToken: result.identityToken,
            authorizationCode: result.authorizationCode,
            email: result.email,
            fullName: fullName
        )
        isNewUser = response.isNewUser ?? false
        if isNewUser {
            isOnboardingPending = true
        }
        showPostAuthFlow = true
        isAuthenticated = true
        userId = response.userId

        let sentryUser = Sentry.User(userId: response.userId)
        SentrySDK.setUser(sentryUser)

        if isNewUser {
            AnalyticsService.logSignUp(userId: response.userId, method: "apple")
        } else {
            AnalyticsService.logLogin(userId: response.userId, method: "apple")
        }

        await SyncService.shared.performInitialSync(isNewUser: isNewUser)
        await EntitlementsService.shared.syncEntitlementStatus()
        isLoading = false
        return .success
    }

    func logout(onDataCleanup: @escaping () -> Void) async {
        isLoading = true
        errorMessage = nil

        do {
            try await APIService.shared.logout()
        } catch {
            errorMessage = error.localizedDescription
        }

        // Flip auth state and clear tokens FIRST so the Keychain is cleared
        // even if the SwiftData cleanup below crashes. If we cleared tokens
        // after onDataCleanup() (the old order) and that step faulted, the
        // user would relaunch into a ghost-auth state — local tokens still
        // present, but the server-side refresh token already invalidated.
        SentrySDK.setUser(nil)
        KeychainService.shared.clearTokens()
        stopTokenRefreshTimer()
        isOnboardingPending = false
        isAuthenticated = false
        userId = nil

        // Give SwiftUI one render pass to unmount authenticated views before
        // we delete the @Model rows they reference. Without this, SwiftData
        // fatals at BackingData.swift:739 when a still-mounted view re-renders
        // against an already-deleted Exercise/LiftSet/etc.
        try? await Task.sleep(for: .milliseconds(50))

        onDataCleanup()
        SyncService.shared.clearOnLogout()
        NarrativeBadgeService.shared.clearOnLogout()

        isLoading = false
    }

    // MARK: - Token Refresh Timer

    private func startTokenRefreshTimer() {
        // Check every 5 minutes if we need to refresh
        tokenRefreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshTokenIfNeeded()
            }
        }
    }

    nonisolated private func stopTokenRefreshTimer() {
        tokenRefreshTimer?.invalidate()
        tokenRefreshTimer = nil
    }

    private func refreshTokenIfNeeded() async {
        guard isAuthenticated else { return }

        // Check if refresh token is expired before attempting refresh
        if let tokenStorage = KeychainService.shared.getTokenStorage(),
           tokenStorage.isRefreshTokenExpired {
            handleSessionExpired()
            return
        }

        do {
            try await APIService.shared.refreshTokenIfNeeded()
        } catch let error as APIError {
            // If we get unauthorized, the refresh token is likely expired/invalid
            if case .unauthorized = error {
                handleSessionExpired()
            }
            // For other errors, silently fail and retry on next attempt
            // This allows recovery from temporary network issues
        } catch {
            // Silently fail and retry on next attempt
        }
    }

    deinit {
        stopTokenRefreshTimer()
    }
}
