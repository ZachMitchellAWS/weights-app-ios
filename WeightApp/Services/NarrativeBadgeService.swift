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
}
