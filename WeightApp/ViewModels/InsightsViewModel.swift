//
//  InsightsViewModel.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/10/26.
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
class InsightsViewModel {

    // MARK: - State

    enum EmptyReason: Equatable {
        case noSetsLogged
        case setsLoggedWeekInProgress(sundayDate: String)
    }

    enum ViewState: Equatable {
        case idle
        case loading
        case loaded(WeeklyInsightsResponse)
        case processing
        case empty(EmptyReason)
        case error(String)
        case locked
    }

    var state: ViewState = .idle

    // MARK: - Cache Keys

    private static let cacheKey = "insights_cached_response"
    private static let lastFetchedKey = "insights_last_fetched_at"

    // MARK: - Cached Data

    var cachedInsight: WeeklyInsightsResponse? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(WeeklyInsightsResponse.self, from: data)
    }

    private var lastFetchedAt: Date? {
        let interval = UserDefaults.standard.double(forKey: Self.lastFetchedKey)
        return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
    }

    // MARK: - Lifecycle

    func onAppear(isPremium: Bool, hasLocalSetsThisWeek: Bool) async {
        // Free user → locked
        guard isPremium else {
            state = .locked
            return
        }

        // Show cache immediately if available
        if let cached = cachedInsight, let sections = cached.sections, !sections.isEmpty {
            state = .loaded(cached)
        }

        // Determine if we need to fetch
        let shouldFetch: Bool
        if cachedInsight == nil {
            shouldFetch = true
        } else if let lastFetch = lastFetchedAt {
            shouldFetch = Date().timeIntervalSince(lastFetch) > 12 * 60 * 60
        } else {
            shouldFetch = true
        }

        if shouldFetch {
            // Only show loading spinner if we have no cache
            if cachedInsight == nil {
                state = .loading
            }
            await fetchInsights(force: false, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
        }
    }

    // MARK: - Fetch

    func fetchInsights(force: Bool, isPremium: Bool = false, hasLocalSetsThisWeek: Bool = false) async {
        do {
            let response = try await APIService.shared.getWeeklyInsights()
            mapResponse(response, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
        } catch let error as APIError {
            switch error {
            case .httpError(let code, _) where code == 403:
                if isPremium {
                    state = .error("Unable to load insights. Pull to refresh to try again.")
                } else {
                    state = .locked
                }
            case .httpError(let code, _) where code == 503:
                state = .error("Insights are temporarily unavailable. Please try again later.")
            case .unauthorized:
                state = .error("Please sign in again to view insights.")
            default:
                state = .error("Something went wrong. Pull to refresh to try again.")
            }
        } catch {
            state = .error("Something went wrong. Pull to refresh to try again.")
        }
    }

    // MARK: - Response Mapping

    private func mapResponse(_ response: WeeklyInsightsResponse, hasLocalSetsThisWeek: Bool) {
        // 202 processing
        if response.status == "processing" {
            state = .processing
            return
        }

        // 200 with sections
        if let sections = response.sections, !sections.isEmpty {
            state = .loaded(response)
            saveCache(response)
            NarrativeBadgeService.shared.refresh()
            return
        }

        // 200 empty
        if hasLocalSetsThisWeek {
            let sundayDate = nextSundayFormatted()
            state = .empty(.setsLoggedWeekInProgress(sundayDate: sundayDate))
        } else {
            state = .empty(.noSetsLogged)
        }
    }

    // MARK: - Cache Management

    private func saveCache(_ response: WeeklyInsightsResponse) {
        if let data = try? JSONEncoder().encode(response) {
            UserDefaults.standard.set(data, forKey: Self.cacheKey)
        }
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastFetchedKey)
    }

    // MARK: - Helpers

    private func nextSundayFormatted() -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        // Sunday = 1, so days until Sunday = (8 - weekday) % 7, but if today is Sunday use 7
        let daysUntilSunday = weekday == 1 ? 7 : (8 - weekday)
        guard let sunday = calendar.date(byAdding: .day, value: daysUntilSunday, to: today) else {
            return "Sunday"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: sunday)
    }
}
