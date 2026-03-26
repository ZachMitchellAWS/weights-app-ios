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
        case freeNoTier
        case freeWithTier(StrengthTier)
    }

    var state: ViewState = .idle
    var latestTierUnlock: TierUnlockItem?

    private var audioPollTask: Task<Void, Never>?

    // MARK: - Cache Keys

    private static let cacheKey = "insights_cached_response"

    // MARK: - Cached Data

    var cachedInsight: WeeklyInsightsResponse? {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey) else { return nil }
        return try? JSONDecoder().decode(WeeklyInsightsResponse.self, from: data)
    }

    // MARK: - Lifecycle

    func onAppear(isPremium: Bool, hasLocalSetsThisWeek: Bool, overallTier: StrengthTier = .none) async {
        // Always load latest tier unlock from cache
        latestTierUnlock = NarrativeBadgeService.shared.cachedTierUnlocks.last

        // Always do a full refresh when navigating to narratives tab
        await NarrativeBadgeService.shared.refreshAllFromAPI()
        latestTierUnlock = NarrativeBadgeService.shared.cachedTierUnlocks.last

        guard isPremium else {
            if overallTier != .none {
                state = .freeWithTier(overallTier)
            } else {
                state = .freeNoTier
            }
            return
        }

        // Show cache immediately, then fetch
        if let cached = cachedInsight, let sections = cached.sections, !sections.isEmpty {
            state = .loaded(cached)
        } else {
            state = .loading
        }
        await fetchInsights(force: false, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)

        // If content is loaded but audio is still missing, poll for it
        startAudioPollIfNeeded(isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)
    }

    func cancelAudioPoll() {
        audioPollTask?.cancel()
        audioPollTask = nil
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
        if response.status == "processing" {
            state = .processing
            return
        }

        if let sections = response.sections, !sections.isEmpty {
            state = .loaded(response)
            saveCache(response)
            return
        }

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
    }

    // MARK: - Audio Polling

    /// If loaded content is missing audio URLs, poll at the same cadence as
    /// post-tier-unlock polling (15s / 30s / 45s / 60s) until audio resolves.
    private func startAudioPollIfNeeded(isPremium: Bool, hasLocalSetsThisWeek: Bool) {
        guard needsAudioPoll else { return }

        audioPollTask?.cancel()
        audioPollTask = Task {
            let delays = [15, 30, 45, 60]
            for delay in delays {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }

                // Re-fetch weekly insights
                await fetchInsights(force: true, isPremium: isPremium, hasLocalSetsThisWeek: hasLocalSetsThisWeek)

                // Re-fetch tier unlocks
                await NarrativeBadgeService.shared.fetchAndCacheTierUnlocks()
                latestTierUnlock = NarrativeBadgeService.shared.cachedTierUnlocks.last

                if !needsAudioPoll { return }
            }
        }
    }

    private var needsAudioPoll: Bool {
        let weeklyNeedsAudio: Bool
        if case .loaded(let response) = state,
           let sections = response.sections, !sections.isEmpty {
            weeklyNeedsAudio = sections.contains { $0.audioUrl == nil }
        } else {
            weeklyNeedsAudio = false
        }

        let tierNeedsAudio = latestTierUnlock != nil && latestTierUnlock?.audioUrl == nil

        return weeklyNeedsAudio || tierNeedsAudio
    }

    // MARK: - Helpers

    private func nextSundayFormatted() -> String {
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysUntilSunday = weekday == 1 ? 7 : (8 - weekday)
        guard let sunday = calendar.date(byAdding: .day, value: daysUntilSunday, to: today) else {
            return "Sunday"
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d"
        return formatter.string(from: sunday)
    }
}
