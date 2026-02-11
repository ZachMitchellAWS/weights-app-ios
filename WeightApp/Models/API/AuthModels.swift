//
//  AuthModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation

// MARK: - Request Models

struct CreateUserRequest: Codable {
    let emailAddress: String
    let password: String
}

struct LoginRequest: Codable {
    let emailAddress: String
    let password: String
}

struct RefreshTokenRequest: Codable {
    let refreshToken: String
}

struct InitiatePasswordResetRequest: Codable {
    let emailAddress: String
}

struct ConfirmPasswordResetRequest: Codable {
    let emailAddress: String
    let code: String
    let newPassword: String
}

// MARK: - Response Models

struct AuthResponse: Codable {
    let userId: String
    let emailAddress: String
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int
    let refreshTokenExpiresIn: Int
}

struct RefreshResponse: Codable {
    let userId: String
    let accessToken: String
    let accessTokenExpiresIn: Int
}

struct MessageResponse: Codable {
    let message: String
}

struct ErrorResponse: Codable {
    let message: String
}

struct UserPropertiesRequest: Codable {
    var bodyweight: Double?
    var availableChangePlates: [Double]?
    var minReps: Int?
    var maxReps: Int?
    var clearBodyweight: Bool = false

    private enum CodingKeys: String, CodingKey {
        case bodyweight, availableChangePlates, minReps, maxReps
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if clearBodyweight {
            try container.encodeNil(forKey: .bodyweight)
        } else if let bodyweight = bodyweight {
            try container.encode(bodyweight, forKey: .bodyweight)
        }
        if let plates = availableChangePlates {
            try container.encode(plates, forKey: .availableChangePlates)
        }
        if let minReps = minReps {
            try container.encode(minReps, forKey: .minReps)
        }
        if let maxReps = maxReps {
            try container.encode(maxReps, forKey: .maxReps)
        }
    }
}

struct UserPropertiesResponse: Codable {
    let userId: String
    let bodyweight: Double?
    let availableChangePlates: [Double]?
    let minReps: Int?
    let maxReps: Int?
    let createdDatetime: String
    let lastModifiedDatetime: String
}

// MARK: - Token Storage

struct TokenStorage {
    let accessToken: String
    let refreshToken: String
    let userId: String
    let expiresAt: Date
    let refreshTokenExpiresAt: Date?

    var isExpired: Bool {
        Date() >= expiresAt
    }

    var shouldRefresh: Bool {
        let timeUntilExpiry = expiresAt.timeIntervalSince(Date())
        let totalLifetime: TimeInterval = 15 * 60 // 15 minutes
        let refreshThreshold = totalLifetime * 0.75
        return timeUntilExpiry <= (totalLifetime - refreshThreshold)
    }

    var isRefreshTokenExpired: Bool {
        guard let refreshExpiry = refreshTokenExpiresAt else { return false }
        return Date() >= refreshExpiry
    }
}
