//
//  InsightsModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/10/26.
//
//  Wire types for the tier-unlock insight — the Strength tab's generated narrative and audio clip.
//
//  This file also held `InsightSection`, `WeeklyInsightsResponse` and `StarterInsightResponse`,
//  for Weekly Progress Narratives and the superseded starter insight. Smart Sessions replaced
//  narratives and both are gone; the backend still serves `/insights/starter` for a lazy
//  server-side migration, but no client calls it.
//

import Foundation

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
