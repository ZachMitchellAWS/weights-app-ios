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
    case notImplemented(String)

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
        case .notImplemented(let feature):
            return "\(feature)"
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

        // Store tokens and email
        KeychainService.shared.saveTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId,
            accessTokenExpiresIn: response.accessTokenExpiresIn,
            refreshTokenExpiresIn: response.refreshTokenExpiresIn,
            email: response.emailAddress
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

        // Store tokens and email
        KeychainService.shared.saveTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId,
            accessTokenExpiresIn: response.accessTokenExpiresIn,
            refreshTokenExpiresIn: response.refreshTokenExpiresIn,
            email: response.emailAddress
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
            accessTokenExpiresIn: response.accessTokenExpiresIn
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

    func authenticateWithApple(identityToken: String, authorizationCode: String, email: String?, fullName: String?) async throws -> AuthResponse {
        let body = AppleSignInRequest(identityToken: identityToken, authorizationCode: authorizationCode, email: email, fullName: fullName)
        let response: AuthResponse = try await request(
            endpoint: "/auth/apple-signin",
            method: "POST",
            body: body,
            headers: APIConfig.commonHeaders
        )

        KeychainService.shared.saveTokens(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            userId: response.userId,
            accessTokenExpiresIn: response.accessTokenExpiresIn,
            refreshTokenExpiresIn: response.refreshTokenExpiresIn,
            email: response.emailAddress
        )

        return response
    }

    // Note: User properties use String timestamps with standard JSONDecoder (not .iso8601),
    // while checkin DTOs use Date with .iso8601 decoder via requestWithDateDecoding(). This is intentional.
    func getUserProperties() async throws -> UserPropertiesResponse {
        return try await request(
            endpoint: "/user/properties",
            method: "GET",
            requiresAuth: true
        )
    }

    func updateUserProperties(_ request: UserPropertiesRequest) async throws -> UserPropertiesResponse {
        return try await self.request(
            endpoint: "/user/properties",
            method: "POST",
            body: request,
            headers: APIConfig.commonHeaders,
            requiresAuth: true
        )
    }

    // MARK: - Exercise Sync Endpoints

    func getExercises() async throws -> GetExercisesResponse {
        return try await requestWithDateDecoding(
            endpoint: "/checkin/exercises",
            method: "GET",
            requiresAuth: true
        )
    }

    func upsertExercises(_ exercises: [ExerciseDTO]) async throws -> UpsertExercisesResponse {
        let body = UpsertExercisesRequest(exercises: exercises)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/exercises",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func deleteExercises(_ exerciseIds: [UUID]) async throws -> DeleteExercisesResponse {
        let body = DeleteExercisesRequest(exerciseItemIds: exerciseIds)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/exercises",
            method: "DELETE",
            body: body,
            requiresAuth: true
        )
    }

    // MARK: - Lift Set Sync Endpoints

    func getLiftSets(limit: Int = 100, pageToken: String? = nil) async throws -> GetLiftSetsResponse {
        var endpoint = "/checkin/lift-sets?limit=\(limit)"
        if let pageToken = pageToken {
            endpoint += "&pageToken=\(pageToken)"
        }
        return try await requestWithDateDecoding(
            endpoint: endpoint,
            method: "GET",
            requiresAuth: true
        )
    }

    func createLiftSets(_ liftSets: [LiftSetDTO]) async throws -> CreateLiftSetsResponse {
        let body = CreateLiftSetsRequest(liftSets: liftSets)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/lift-sets",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func deleteLiftSets(_ liftSetIds: [UUID]) async throws -> DeleteLiftSetsResponse {
        let body = DeleteLiftSetsRequest(liftSetIds: liftSetIds)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/lift-sets",
            method: "DELETE",
            body: body,
            requiresAuth: true
        )
    }

    // MARK: - Estimated 1RM Sync Endpoints

    func getEstimated1RMs(limit: Int = 100, pageToken: String? = nil) async throws -> GetEstimated1RMsResponse {
        var endpoint = "/checkin/estimated-1rm?limit=\(limit)"
        if let pageToken = pageToken {
            endpoint += "&pageToken=\(pageToken)"
        }
        return try await requestWithDateDecoding(
            endpoint: endpoint,
            method: "GET",
            requiresAuth: true
        )
    }

    func createEstimated1RMs(_ estimated1RMs: [Estimated1RMDTO]) async throws -> CreateEstimated1RMsResponse {
        let body = CreateEstimated1RMsRequest(estimated1RMs: estimated1RMs)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/estimated-1rm",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func deleteEstimated1RMs(liftSetIds: [UUID]) async throws -> DeleteEstimated1RMsResponse {
        let body = DeleteEstimated1RMsRequest(liftSetIds: liftSetIds)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/estimated-1rm",
            method: "DELETE",
            body: body,
            requiresAuth: true
        )
    }

    // MARK: - Sequence Sync Endpoints

    func getSequences() async throws -> GetSequencesResponse {
        return try await requestWithDateDecoding(
            endpoint: "/checkin/sequences",
            method: "GET",
            requiresAuth: true
        )
    }

    func upsertSequences(_ sequences: [SequenceDTO]) async throws -> UpsertSequencesResponse {
        let body = UpsertSequencesRequest(sequences: sequences)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/sequences",
            method: "POST",
            body: body,
            requiresAuth: true
        )
    }

    func deleteSequences(_ sequenceIds: [UUID]) async throws -> DeleteSequencesResponse {
        let body = DeleteSequencesRequest(sequenceIds: sequenceIds)
        return try await requestWithDateDecoding(
            endpoint: "/checkin/sequences",
            method: "DELETE",
            body: body,
            requiresAuth: true
        )
    }

    // MARK: - Request Method with Date Decoding

    private func requestWithDateDecoding<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        requiresAuth: Bool = false
    ) async throws -> T {
        if requiresAuth {
            try await refreshTokenIfNeeded()
        }

        guard let url = URL(string: APIConfig.baseURL + endpoint) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        var allHeaders = APIConfig.commonHeaders
        if requiresAuth, let token = KeychainService.shared.getAccessToken() {
            allHeaders["Authorization"] = "Bearer \(token)"
        }

        for (key, value) in allHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        if let body = body {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(body)
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
                if let errorResponse = try? JSONDecoder().decode(ErrorResponse.self, from: data) {
                    throw APIError.httpError(httpResponse.statusCode, errorResponse.message)
                }
                throw APIError.httpError(httpResponse.statusCode, "Unknown error")
            }

            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let decodedData = try decoder.decode(T.self, from: data)
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
}
