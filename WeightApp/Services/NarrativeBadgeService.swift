//
//  NarrativeBadgeService.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/18/26.
//
//  Owns the Strength tab's tier-unlock insight — the short generated narrative and its audio clip
//  that `StrengthInsightWidget` plays after a user reaches a new overall strength tier.
//
//  The name is historical. This class used to serve Weekly Progress Narratives as well, which is
//  where "narrative" and the `narratives_*` UserDefaults keys come from. Narratives were replaced
//  by Smart Sessions and removed; the keys are left spelled as they are because renaming them
//  would orphan the cache on every installed device for no benefit.
//
//  What that removal left behind, and what to know before touching this:
//
//    - `refreshAllFromAPI()` used to fetch weekly insights AND tier unlocks in one pass. Only the
//      tier-unlock half remains, but the function is still the one the post-unlock poll and app
//      launch both go through, so it is edited rather than replaced.
//    - `narratives_last_auto_refreshed_at` throttles that whole function, tier unlocks included.
//      Its name says narratives; its job is not narratives-specific.
//    - There is no app-icon badge any more. It was driven solely by unviewed weekly narratives.
//

import Foundation
import Observation

@MainActor
@Observable
class NarrativeBadgeService {
    static let shared = NarrativeBadgeService()

    private(set) var hasUnviewedTierUnlock: Bool = false
    private(set) var tierUnlocks: [TierUnlockItem] = []

    private static let tierUnlocksCacheKey = "tierUnlocksCachedResponse"
    private static let lastViewedTierKey = "narratives_last_viewed_tier"
    private static let lastAutoRefreshedKey = "narratives_last_auto_refreshed_at"

    // Legacy keys, cleared on first successful fetch and on logout. Predate tier unlocks.
    private static let starterInsightCacheKey = "starterInsightCachedResponse"
    private static let starterInsightViewedKey = "starterInsightViewed"

    private init() {
        tierUnlocks = cachedTierUnlocks
    }

    // MARK: - Refresh

    /// Called on app open (scenePhase -> .active). Throttled to every 6 hours.
    func refreshOnAppOpen() async {
        evaluateBadge()

        let lastRefreshed = UserDefaults.standard.double(forKey: Self.lastAutoRefreshedKey)
        let hoursSince = lastRefreshed > 0 ? Date().timeIntervalSince1970 - lastRefreshed : .infinity
        guard hoursSince > 6 * 60 * 60 else { return }

        await refreshAllFromAPI()
    }

    /// Fetches tier unlocks from the backend and updates the local cache.
    ///
    /// Kept as its own function, and kept named this, because `pollForNewNarrative` calls it in a
    /// loop after a tier unlock — the poll is the reason the timestamp is written here rather than
    /// in `refreshOnAppOpen`.
    func refreshAllFromAPI() async {
        await fetchAndCacheTierUnlocks()
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastAutoRefreshedKey)
        evaluateBadge()
    }

    // MARK: - Badge Evaluation

    /// Re-evaluate badge state from local caches. No API calls.
    func evaluateBadge() {
        hasUnviewedTierUnlock = checkUnviewedTierUnlock()
    }

    private func checkUnviewedTierUnlock() -> Bool {
        let cached = cachedTierUnlocks
        guard !cached.isEmpty else { return false }
        let lastViewedTier = UserDefaults.standard.string(forKey: Self.lastViewedTierKey)
        return cached.last?.tier != lastViewedTier
    }

    // MARK: - Mark Viewed

    /// Called when the user opens the tier unlock detail view.
    ///
    /// NOTE: currently has no caller, so `hasUnviewedTierUnlock` only clears on logout. That
    /// predates the narratives removal and is left alone here rather than fixed in passing.
    func markTierUnlockViewed(tier: String) {
        UserDefaults.standard.set(tier, forKey: Self.lastViewedTierKey)
        hasUnviewedTierUnlock = false
    }

    // MARK: - Clear on Logout

    /// Clears cached insights and badge state. Call on logout/account switch.
    func clearOnLogout() {
        UserDefaults.standard.removeObject(forKey: Self.tierUnlocksCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.lastViewedTierKey)
        UserDefaults.standard.removeObject(forKey: Self.lastAutoRefreshedKey)
        UserDefaults.standard.removeObject(forKey: Self.starterInsightCacheKey)
        UserDefaults.standard.removeObject(forKey: Self.starterInsightViewedKey)
        tierUnlocks = []
        hasUnviewedTierUnlock = false
    }

    // MARK: - Tier Unlock

    /// Called when the client detects an overall tier-up. POSTs to the backend, then polls until
    /// the generated narrative and its audio are ready.
    func triggerTierUnlock(tier: StrengthTier) async {
        guard tier != .none else { return }
        do {
            let _ = try await APIService.shared.postTierUnlock(tier: tier.title)
        } catch { }
        // Poll every 5s for up to 60s total
        await pollForNewNarrative(delays: Array(repeating: 5, count: 12))
    }

    /// Poll the backend for the new tier unlock. Stops early once the cache changes AND the audio
    /// URL has landed — generation and TTS complete separately, so a body without audio is not
    /// yet the finished article.
    private func pollForNewNarrative(delays: [Int]) async {
        let beforeTierUnlocks = cachedTierUnlocks
        for delay in delays {
            try? await Task.sleep(for: .seconds(delay))
            await refreshAllFromAPI()
            let after = cachedTierUnlocks
            if after != beforeTierUnlocks && after.last?.audioUrl != nil {
                return
            }
        }
    }

    // MARK: - Tier Unlock Cache

    /// Fetch all tier unlocks from the backend and cache locally.
    func fetchAndCacheTierUnlocks() async {
        do {
            let response = try await APIService.shared.getTierUnlocks()
            if let data = try? JSONEncoder().encode(response.tierUnlocks) {
                UserDefaults.standard.set(data, forKey: Self.tierUnlocksCacheKey)
            }
            // Client-side migration: clear old starter keys on first successful fetch
            UserDefaults.standard.removeObject(forKey: Self.starterInsightCacheKey)
            UserDefaults.standard.removeObject(forKey: Self.starterInsightViewedKey)
            tierUnlocks = cachedTierUnlocks
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
