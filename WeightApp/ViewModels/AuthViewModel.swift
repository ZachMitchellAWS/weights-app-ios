//
//  AuthViewModel.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation
import Combine
import SwiftData

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

    nonisolated(unsafe) private var tokenRefreshTimer: Timer?
    private var modelContext: ModelContext?

    init() {
        checkAuthStatus()
        startTokenRefreshTimer()
    }

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    func checkAuthStatus() {
        isAuthenticated = KeychainService.shared.isAuthenticated()
        userId = KeychainService.shared.getUserId()
    }

    func completePostAuthFlow() {
        showPostAuthFlow = false
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

            // Perform initial sync for returning user (includes user properties sync)
            await SyncService.shared.performInitialSync(isNewUser: false)

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
            showPostAuthFlow = true
            isAuthenticated = true
            userId = response.userId

            // Perform initial sync for new user (includes user properties sync)
            await SyncService.shared.performInitialSync(isNewUser: true)

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

    func logout(onDataCleanup: @escaping () -> Void) async {
        isLoading = true
        errorMessage = nil

        do {
            try await APIService.shared.logout()
        } catch {
            errorMessage = error.localizedDescription
        }

        // Perform hard delete of all local data
        onDataCleanup()

        // Clear sync retry queue
        SyncService.shared.clearOnLogout()

        // Always clear tokens and log out, regardless of API success/failure
        KeychainService.shared.clearTokens()
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

        do {
            try await APIService.shared.refreshTokenIfNeeded()
        } catch {
            // Silently fail and retry on next attempt
            // This allows recovery from temporary network issues
        }
    }

    deinit {
        stopTokenRefreshTimer()
    }
}
