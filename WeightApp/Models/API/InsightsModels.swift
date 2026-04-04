//
//  InsightsModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/10/26.
//

import Foundation

struct InsightSection: Codable, Equatable {
    let title: String
    let body: String
    let audioUrl: String?
    let audioUrlExpiresAt: String?

    var isAudioExpired: Bool {
        guard let expiresAt = audioUrlExpiresAt,
              let date = ISO8601DateFormatter().date(from: expiresAt) else { return true }
        return Date() >= date
    }

    var hasValidAudio: Bool {
        audioUrl != nil && !isAudioExpired
    }
}

struct StarterInsightResponse: Codable, Equatable {
    let body: String?
    let generatedAt: String?
    let audioUrl: String?
    let message: String?
}

struct TierUnlockItem: Codable, Equatable, Identifiable, Hashable {
    let tier: String
    let body: String
    let generatedAt: String?
    let audioUrl: String?
    let audioUrlExpiresAt: String?

    var id: String { tier }

    var isAudioExpired: Bool {
        guard let expiresAt = audioUrlExpiresAt,
              let date = ISO8601DateFormatter().date(from: expiresAt) else { return true }
        return Date() >= date
    }

    var hasValidAudio: Bool {
        audioUrl != nil && !isAudioExpired
    }

    var strengthTier: StrengthTier {
        switch tier.lowercased() {
        case "novice": return .novice
        case "beginner": return .beginner
        case "intermediate": return .intermediate
        case "advanced": return .advanced
        case "elite": return .elite
        case "legend": return .legend
        default: return .none
        }
    }
}

struct TierUnlocksListResponse: Codable, Equatable {
    let tierUnlocks: [TierUnlockItem]
}

struct TierUnlockResponse: Codable, Equatable {
    let tier: String?
    let body: String?
    let generatedAt: String?
    let audioUrl: String?
    let message: String?
}

struct WeeklyInsightsResponse: Codable, Equatable, Hashable {
    let weekStartDate: String?
    let weekEndDate: String?
    let generatedAt: String?
    let sections: [InsightSection]?
    let message: String?
    let status: String?
    let error: String?

    func hash(into hasher: inout Hasher) {
        hasher.combine(weekStartDate)
        hasher.combine(weekEndDate)
    }
}

extension InsightSection: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(title)
        hasher.combine(body)
    }
}
