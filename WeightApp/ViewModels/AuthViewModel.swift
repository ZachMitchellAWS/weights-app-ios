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
        SentrySDK.setUser(nil)

        // Clear all tokens
        KeychainService.shared.clearTokens()

        // Clear sync retry queue and narrative badge
        SyncService.shared.clearOnLogout()
        NarrativeBadgeService.shared.clearOnLogout()

        // Hard delete all local data
        hardDeleteAllData()

        // Update state
        isOnboardingPending = false
        isAuthenticated = false
        userId = nil
        sessionExpired = true
        stopTokenRefreshTimer()
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

        onDataCleanup()
        SyncService.shared.clearOnLogout()
        NarrativeBadgeService.shared.clearOnLogout()
        KeychainService.shared.clearTokens()
        SentrySDK.setUser(nil)
        isOnboardingPending = false
        isAuthenticated = false
        userId = nil
        stopTokenRefreshTimer()
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
