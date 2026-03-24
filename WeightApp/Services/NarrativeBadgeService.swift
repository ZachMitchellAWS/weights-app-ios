//
//  NarrativeBadgeService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/18/26.
//

import Foundation
import Observation
import UserNotifications
 
@MainActor
@Observable
class NarrativeBadgeService {
    static let shared = NarrativeBadgeService()

    var hasNewNarrative: Bool = false

    private static let lastViewedKey = "insights_last_viewed_week"
    private static let cacheKey = "insights_cached_response"
    private static let starterInsightViewedKey = "starterInsightViewed"

    private init() {}

    func refresh() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let response = try? JSONDecoder().decode(WeeklyInsightsResponse.self, from: data),
              let weekStart = response.weekStartDate,
              let sections = response.sections, !sections.isEmpty else {
            hasNewNarrative = false
            return
        }

        let lastViewed = UserDefaults.standard.string(forKey: Self.lastViewedKey)
        let isNew = lastViewed != weekStart
        hasNewNarrative = isNew

        if isNew {
            UNUserNotificationCenter.current().setBadgeCount(1)
        }
    }

    /// Fetches latest insights from the API, updates cache, then refreshes badge state.
    func refreshFromAPI() async {
        do {
            let response = try await APIService.shared.getWeeklyInsights()
            if let sections = response.sections, !sections.isEmpty,
               let data = try? JSONEncoder().encode(response) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        } catch {
            // Silently fail — we'll still check the existing cache
        }
        refresh()
    }

    func markViewed(weekStart: String) {
        UserDefaults.standard.set(weekStart, forKey: Self.lastViewedKey)
        hasNewNarrative = false
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - Starter Insight Badge

    private static let starterInsightCacheKey = "starterInsightCachedResponse"

    /// Call when a free user unlocks a tier. Sets badge if starter insight hasn't been viewed yet.
    func notifyTierUnlocked() {
        guard !UserDefaults.standard.bool(forKey: Self.starterInsightViewedKey) else { return }
        hasNewNarrative = true
    }

    /// Marks the starter insight as viewed, clearing the badge. Called when InsightsView appears in .freeWithTier state.
    func markStarterViewedIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.starterInsightViewedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.starterInsightViewedKey)
        hasNewNarrative = false
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    /// Fetches starter insight from backend and caches locally. Fire-and-forget at tier completion.
    func fetchAndCacheStarterInsight() async {
        do {
            let response = try await APIService.shared.getStarterInsight()
            if response.body != nil, let data = try? JSONEncoder().encode(response) {
                UserDefaults.standard.set(data, forKey: Self.starterInsightCacheKey)
                hasNewNarrative = true
            }
        } catch {
            // Silent fail — user will see placeholder, can retry on view
        }
    }

    var cachedStarterInsight: StarterInsightResponse? {
        guard let data = UserDefaults.standard.data(forKey: Self.starterInsightCacheKey) else { return nil }
        return try? JSONDecoder().decode(StarterInsightResponse.self, from: data)
    }

    /// Updates the cached starter insight (e.g., when audio URL arrives from polling).
    func updateCachedStarterInsight(_ response: StarterInsightResponse) {
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: Self.starterInsightCacheKey)
        }
    }
}
