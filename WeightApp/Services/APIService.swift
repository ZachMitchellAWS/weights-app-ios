//
//  APIService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation

enum APIError: Error, LocalizedError {
    case invalidURL
    case networkError(Error)
    case invalidResponse
    case httpError(Int, String)
    case decodingError(Error)
    case unauthorized
    case noTokensStored

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid URL"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .httpError(let code, let message):
            return "HTTP \(code): \(message)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .unauthorized:
            return "Unauthorized"
        case .noTokensStored:
            return "No authentication tokens found"
        }
    }
}

class APIService {
    static let shared = APIService()

    private init() {}

    // MARK: - Generic Request Method

    private func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        headers: [String: String]? = nil,
        requiresAuth: Bool = false
    ) async throws -> T {
        // Refresh token if needed before making authenticated requests
        if requiresAuth {
            try await refreshTokenIfNeeded()
        }

        guard let url = URL(string: APIConfig.baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // Set headers
        var allHeaders = headers ?? APIConfig.commonHeaders
        if requiresAuth, let token = KeychainService.shared.getAccessToken() {
            allHeaders["Authorization"] = "Bearer \(token)"
        }

        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        // Set body if present
        if let body = body {
            request.httpBody = try JSONEncoder().encode(body)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }

            if !(200...299).contains(httpResponse.statusCode) {
                // Try to decode error message
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    throw APIError.httpError(httpResponse.statusCode, errorResponse.message)
                }
                throw APIError.httpError(httpResponse.statusCode, "Unknown error")
            }

            do {
                let decodedData = try JSONDecoder().decode(T.self, from: data)
                return decodedData
            } catch {
                throw APIError.decodingError(error)
            }
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    // MARK: - Token Management

    func refreshTokenIfNeeded() async throws {
        guard let tokenStorage = KeychainService.shared.getTokenStorage() else {
            throw APIError.noTokensStored
        }

        // Check if we should refresh (at 75% of lifetime)
        if tokenStorage.shouldRefresh && !tokenStorage.isExpired {
            try await refreshToken()
        } else if tokenStorage.isExpired {
            // Token is completely expired, force refresh
            try await refreshToken()
        }
    }

    // MARK: - Auth Endpoints

    func createUser(email: String, password: String) async throws -> AuthResponse {
        let body = CreateUserRequest(emailAddress: email, password: password)
        let response: AuthResponse = try await request(
            endpoint: "/auth/create-user",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders
        )

        // Store tokens
        KeychainService.shared.saveTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId,
            expiresIn: response.expiresIn
        )

        return response
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = LoginRequest(emailAddress: email, password: password)
        let response: AuthResponse = try await request(
            endpoint: "/auth/login",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders
        )

        // Store tokens
        KeychainService.shared.saveTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId,
            expiresIn: response.expiresIn
        )

        return response
    }

    func refreshToken() async throws {
        guard let refreshToken = KeychainService.shared.getRefreshToken() else {
            throw APIError.noTokensStored
        }

        let body = RefreshTokenRequest(refreshToken: refreshToken)
        let response: RefreshResponse = try await request(
            endpoint: "/auth/refresh",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders
        )

        // Update access token
        KeychainService.shared.updateAccessToken(
            accessToken: response.accessToken,
            userId: response.userId,
            expiresIn: response.expiresIn
        )
    }

    func logout() async throws {
        let _: MessageResponse = try await request(
            endpoint: "/auth/logout",
            method: "POST",
            requiresAuth: true
        )

        // Clear all stored tokens
        KeychainService.shared.clearTokens()
    }

    func initiatePasswordReset(email: String) async throws -> MessageResponse {
        let body = InitiatePasswordResetRequest(emailAddress: email)
        return try await request(
            endpoint: "/auth/initiate-password-reset",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders
        )
    }

    func confirmPasswordReset(email: String, code: String, newPassword: String) async throws -> MessageResponse {
        let body = ConfirmPasswordResetRequest(emailAddress: email, code: code, newPassword: newPassword)
        return try await request(
            endpoint: "/auth/confirm-password-reset",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders
        )
    }

    func updateUserProperties() async throws -> UserPropertiesResponse {
        let body = UserPropertiesRequest(placeholderBool: false)
        return try await request(
            endpoint: "/user/properties",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders,
            requiresAuth: true
        )
    }
}
