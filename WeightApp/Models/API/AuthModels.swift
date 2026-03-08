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

struct AppleSignInRequest: Codable {
    let identityToken: String
    let authorizationCode: String
    let email: String?
    let fullName: String?
}

// MARK: - Response Models

struct AuthResponse: Codable {
    let userId: String
    let emailAddress: String
    let accessToken: String
    let refreshToken: String
    let accessTokenExpiresIn: Int
    let refreshTokenExpiresIn: Int
    let isNewUser: Bool?
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
    var easyMinReps: Int?
    var easyMaxReps: Int?
    var moderateMinReps: Int?
    var moderateMaxReps: Int?
    var hardMinReps: Int?
    var hardMaxReps: Int?
    var clearBodyweight: Bool = false
    var activeSetPlanId: String?
    var clearActiveSetPlan: Bool = false
    var activeSplitId: String?
    var clearActiveSplit: Bool = false
    var stepsGoal: Int?
    var proteinGoal: Int?
    var bodyweightTarget: Double?
    var clearStepsGoal: Bool = false
    var clearProteinGoal: Bool = false
    var clearBodyweightTarget: Bool = false

    private enum CodingKeys: String, CodingKey {
        case bodyweight, availableChangePlates, minReps, maxReps
        case easyMinReps, easyMaxReps, moderateMinReps, moderateMaxReps, hardMinReps, hardMaxReps
        case activeSetPlanId = "activeSetPlanTemplateId"
        case activeSplitId
        case stepsGoal, proteinGoal, bodyweightTarget
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
        if let easyMinReps = easyMinReps {
            try container.encode(easyMinReps, forKey: .easyMinReps)
        }
        if let easyMaxReps = easyMaxReps {
            try container.encode(easyMaxReps, forKey: .easyMaxReps)
        }
        if let moderateMinReps = moderateMinReps {
            try container.encode(moderateMinReps, forKey: .moderateMinReps)
        }
        if let moderateMaxReps = moderateMaxReps {
            try container.encode(moderateMaxReps, forKey: .moderateMaxReps)
        }
        if let hardMinReps = hardMinReps {
            try container.encode(hardMinReps, forKey: .hardMinReps)
        }
        if let hardMaxReps = hardMaxReps {
            try container.encode(hardMaxReps, forKey: .hardMaxReps)
        }
        if clearActiveSetPlan {
            try container.encodeNil(forKey: .activeSetPlanId)
        } else if let activeSetPlanId = activeSetPlanId {
            try container.encode(activeSetPlanId, forKey: .activeSetPlanId)
        }
        if clearActiveSplit {
            try container.encodeNil(forKey: .activeSplitId)
        } else if let activeSplitId = activeSplitId {
            try container.encode(activeSplitId, forKey: .activeSplitId)
        }
        if clearStepsGoal {
            try container.encodeNil(forKey: .stepsGoal)
        } else if let stepsGoal = stepsGoal {
            try container.encode(stepsGoal, forKey: .stepsGoal)
        }
        if clearProteinGoal {
            try container.encodeNil(forKey: .proteinGoal)
        } else if let proteinGoal = proteinGoal {
            try container.encode(proteinGoal, forKey: .proteinGoal)
        }
        if clearBodyweightTarget {
            try container.encodeNil(forKey: .bodyweightTarget)
        } else if let bodyweightTarget = bodyweightTarget {
            try container.encode(bodyweightTarget, forKey: .bodyweightTarget)
        }
    }
}

struct UserPropertiesResponse: Codable {
    let userId: String
    let bodyweight: Double?
    let availableChangePlates: [Double]?
    let minReps: Int?
    let maxReps: Int?
    let easyMinReps: Int?
    let easyMaxReps: Int?
    let moderateMinReps: Int?
    let moderateMaxReps: Int?
    let hardMinReps: Int?
    let hardMaxReps: Int?
    let activeSetPlanId: String?
    let activeSplitId: String?
    let stepsGoal: Int?
    let proteinGoal: Int?
    let bodyweightTarget: Double?
    let createdDatetime: String
    let lastModifiedDatetime: String

    private enum CodingKeys: String, CodingKey {
        case userId, bodyweight, availableChangePlates, minReps, maxReps
        case easyMinReps, easyMaxReps, moderateMinReps, moderateMaxReps, hardMinReps, hardMaxReps
        case activeSetPlanId = "activeSetPlanTemplateId"
        case activeSplitId
        case stepsGoal, proteinGoal, bodyweightTarget
        case createdDatetime, lastModifiedDatetime
    }
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
