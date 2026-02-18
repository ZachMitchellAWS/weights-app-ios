//
//  EntitlementsService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/17/26.
//

import Foundation
import SwiftData

// MARK: - Response DTOs

struct EntitlementsResponse: Codable {
    let activeEntitlements: [EntitlementGrant]
}

struct EntitlementGrant: Codable {
    let userId: String
    let startUtc: String
    let endUtc: String
    let entitlementName: String
}

struct EntitlementStatusResponse: Codable {
    let accountStatus: String
    let expirationUtc: String?
}

// MARK: - Request DTOs

private struct ProcessTransactionsRequest: Encodable {
    let apple: AppleTransactions

    struct AppleTransactions: Encodable {
        let originalTransactionIds: [String]
    }
}

// MARK: - Service

class EntitlementsService {
    static let shared = EntitlementsService()

    private var modelContext: ModelContext?

    private init() {}

    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }

    // MARK: - API Methods

    /// Send original transaction IDs to the backend for entitlement processing
    func processTransactions(originalTransactionIds: [String]) async throws -> EntitlementsResponse {
        try await APIService.shared.refreshTokenIfNeeded()

        guard let url = URL(string: APIConfig.baseURL + "/entitlements") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        var headers = APIConfig.commonHeaders
        if let token = KeychainService.shared.getAccessToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let body = ProcessTransactionsRequest(
            apple: .init(originalTransactionIds: originalTransactionIds)
        )
        request.httpBody = try JSONEncoder().encode(body)

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

        return try JSONDecoder().decode(EntitlementsResponse.self, from: data)
    }

    /// Get the current entitlement status from the backend
    func getStatus() async throws -> EntitlementStatusResponse {
        try await APIService.shared.refreshTokenIfNeeded()

        guard let url = URL(string: APIConfig.baseURL + "/entitlements/status") else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        var headers = APIConfig.commonHeaders
        if let token = KeychainService.shared.getAccessToken() {
            headers["Authorization"] = "Bearer \(token)"
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

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

        return try JSONDecoder().decode(EntitlementStatusResponse.self, from: data)
    }

    // MARK: - Sync

    /// Fetch entitlement status from backend and update local SwiftData model
    @MainActor
    func syncEntitlementStatus() async {
        guard let context = modelContext else {
            print("EntitlementsService: ModelContext not set")
            return
        }

        do {
            let status = try await getStatus()
            updateLocalEntitlement(status: status, context: context)
        } catch {
            print("EntitlementsService: Failed to sync status: \(error)")
        }
    }

    /// Update local Entitlements from a server status response
    @MainActor
    func updateLocalEntitlement(status: EntitlementStatusResponse, context: ModelContext) {
        let descriptor = FetchDescriptor<Entitlements>()
        let entitlement: Entitlements
        if let existing = try? context.fetch(descriptor).first {
            entitlement = existing
        } else {
            entitlement = Entitlements()
            context.insert(entitlement)
        }

        entitlement.isPremium = status.accountStatus == "premium"

        if let expirationString = status.expirationUtc {
            entitlement.expiresAt = parseISO8601(expirationString)
        } else {
            entitlement.expiresAt = nil
        }

        try? context.save()
    }

    /// Update local Entitlements from entitlements response after a purchase
    @MainActor
    func updateLocalEntitlement(from response: EntitlementsResponse, transactionId: String, context: ModelContext) {
        let descriptor = FetchDescriptor<Entitlements>()
        let entitlement: Entitlements
        if let existing = try? context.fetch(descriptor).first {
            entitlement = existing
        } else {
            entitlement = Entitlements()
            context.insert(entitlement)
        }

        if let grant = response.activeEntitlements.first {
            entitlement.isPremium = true
            entitlement.transactionId = transactionId

            // Determine subscription type from entitlement name
            if grant.entitlementName.contains("monthly") {
                entitlement.subscriptionType = "monthly"
            } else if grant.entitlementName.contains("yearly") {
                entitlement.subscriptionType = "yearly"
            }

            entitlement.expiresAt = parseISO8601(grant.endUtc)
        }

        try? context.save()
    }

    // MARK: - Helpers

    private func parseISO8601(_ string: String) -> Date? {
        // Backend format: "2025-12-01T09:32:55.000"
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }
}
