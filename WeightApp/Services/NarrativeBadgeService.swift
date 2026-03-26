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
    private(set) var hasUnviewedTierUnlock: Bool = false
    private(set) var hasUnviewedWeekly: Bool = false

    private static let lastViewedKey = "insights_last_viewed_week"
    private static let cacheKey = "insights_cached_response"
    private static let tierUnlocksCacheKey = "tierUnlocksCachedResponse"
    private static let lastViewedTierKey = "narratives_last_viewed_tier"
    private static let lastAutoRefreshedKey = "narratives_last_auto_refreshed_at"

    // Legacy keys for migration cleanup
    private static let starterInsightCacheKey = "starterInsightCachedResponse"
    private static let starterInsightViewedKey = "starterInsightViewed"

    private init() {}

    // MARK: - Unified Refresh

    /// Called on app open (scenePhase -> .active). Throttled to every 6 hours.
    func refreshOnAppOpen() async {
        // Always re-evaluate badge from local cache first
        evaluateBadge()

        // Throttle API calls to every 6 hours
        let lastRefreshed = UserDefaults.standard.double(forKey: Self.lastAutoRefreshedKey)
        let hoursSince = lastRefreshed > 0 ? Date().timeIntervalSince1970 - lastRefreshed : .infinity
        guard hoursSince > 6 * 60 * 60 else { return }

        await refreshAllFromAPI()
    }

    /// Fetches BOTH tier unlocks and weekly insights from backend, updates caches.
    func refreshAllFromAPI() async {
        // Fetch tier unlocks
        await fetchAndCacheTierUnlocks()

        // Fetch weekly insights (silently fail for free users who get 403)
        do {
            let response = try await APIService.shared.getWeeklyInsights()
            if let sections = response.sections, !sections.isEmpty,
               let data = try? JSONEncoder().encode(response) {
                UserDefaults.standard.set(data, forKey: Self.cacheKey)
            }
        } catch { }

        // Update timestamp and re-evaluate badge
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastAutoRefreshedKey)
        evaluateBadge()
    }

    // MARK: - Badge Evaluation

    /// Re-evaluate badge state from local caches. No API calls.
    func evaluateBadge() {
        hasUnviewedWeekly = checkUnviewedWeekly()
        hasUnviewedTierUnlock = checkUnviewedTierUnlock()
        let shouldBadge = hasUnviewedWeekly || hasUnviewedTierUnlock
        hasNewNarrative = shouldBadge
        UNUserNotificationCenter.current().setBadgeCount(shouldBadge ? 1 : 0)
    }

    private func checkUnviewedWeekly() -> Bool {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let response = try? JSONDecoder().decode(WeeklyInsightsResponse.self, from: data),
              let weekStart = response.weekStartDate,
              let sections = response.sections, !sections.isEmpty else { return false }
        let lastViewed = UserDefaults.standard.string(forKey: Self.lastViewedKey)
        return lastViewed != weekStart
    }

    private func checkUnviewedTierUnlock() -> Bool {
        let cached = cachedTierUnlocks
        guard !cached.isEmpty else { return false }
        let lastViewedTier = UserDefaults.standard.string(forKey: Self.lastViewedTierKey)
        return cached.last?.tier != lastViewedTier
    }

    // MARK: - Mark Viewed

    /// Called when user opens the tier unlock detail view.
    func markTierUnlockViewed(tier: String) {
        UserDefaults.standard.set(tier, forKey: Self.lastViewedTierKey)
        hasUnviewedTierUnlock = false
        updateOverallBadge()
    }

    /// Called when user opens the weekly insights detail view.
    func markWeeklyViewed(weekStart: String) {
        UserDefaults.standard.set(weekStart, forKey: Self.lastViewedKey)
        hasUnviewedWeekly = false
        updateOverallBadge()
    }

    private func updateOverallBadge() {
        let shouldBadge = hasUnviewedWeekly || hasUnviewedTierUnlock
        hasNewNarrative = shouldBadge
        UNUserNotificationCenter.current().setBadgeCount(shouldBadge ? 1 : 0)
    }

    // MARK: - Clear on Logout

    /// Clears all narrative caches and badge state. Call on logout/account switch.
    func clearOnLogout() {
        UserDefaults.standard.removeObject(forKey: Self.lastViewedKey)
        UserDefaults.standard.removeObject(forKey: Self.cacheKey)
        UserDefaults.standard.removeObject(forKey: Self.tierUnlocksCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.lastViewedTierKey)
        UserDefaults.standard.removeObject(forKey: Self.lastAutoRefreshedKey)
        UserDefaults.standard.removeObject(forKey: Self.starterInsightCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.starterInsightViewedKey)
        hasNewNarrative = false
        hasUnviewedTierUnlock = false
        hasUnviewedWeekly = false
        UNUserNotificationCenter.current().setBadgeCount(0)
    }

    // MARK: - Tier Unlock Badge

    /// Called when client detects overall tier-up. POSTs to backend, then polls for generated content.
    /// Badge is set only once the narrative is actually ready in the cache.
    func triggerTierUnlock(tier: StrengthTier) async {
        guard tier != .none else { return }
        do {
            let _ = try await APIService.shared.postTierUnlock(tier: tier.title)
        } catch { }
        // Poll with front-loaded intervals: 5s, 5s, 5s, 10s, 15s, 20s (cumulative: 5, 10, 15, 25, 40, 60)
        await pollForNewNarrative(delays: [5, 5, 5, 10, 15, 20])
    }

    /// Poll backend for updated narratives. Stops early if cache changes AND has audio.
    /// Sets badge once new content is detected.
    private func pollForNewNarrative(delays: [Int]) async {
        let beforeTierUnlocks = cachedTierUnlocks
        for delay in delays {
            try? await Task.sleep(for: .seconds(delay))
            await refreshAllFromAPI()
            let after = cachedTierUnlocks
            if after != beforeTierUnlocks {
                hasNewNarrative = true
                if after.last?.audioUrl != nil {
                    return
                }
            }
        }
    }

    // MARK: - Tier Unlock Cache

    /// Fetch all tier unlocks from backend and cache locally.
    func fetchAndCacheTierUnlocks() async {
        do {
            let response = try await APIService.shared.getTierUnlocks()
            if let data = try? JSONEncoder().encode(response.tierUnlocks) {
                UserDefaults.standard.set(data, forKey: Self.tierUnlocksCacheKey)
            }
            // Client-side migration: clear old starter keys on first successful fetch
            UserDefaults.standard.removeObject(forKey: Self.starterInsightCacheKey)
            UserDefaults.standard.removeObject(forKey: Self.starterInsightViewedKey)
        } catch {
            // Silent fail — use existing cache
        }
    }

    /// Read cached tier unlocks from UserDefaults.
    var cachedTierUnlocks: [TierUnlockItem] {
        guard let data = UserDefaults.standard.data(forKey: Self.tierUnlocksCacheKey) else { return [] }
        return (try? JSONDecoder().decode([TierUnlockItem].self, from: data)) ?? []
    }
}
