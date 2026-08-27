//
//  AdAttributionService.swift
//  WeightApp
//
//  Records which Apple Ads campaign produced this install, against the user who signed up
//  from it. Without it there is no link between a signup and the campaign, ad group or
//  keyword that paid for it, so cost-per-signup cannot be computed at all.
//
//  NO ATT PROMPT, NO IDFA. AdServices is explicitly exempt from App Tracking Transparency:
//  it returns campaign-level attribution for this install, not a cross-app identifier.
//  Nothing here needs `NSUserTrackingUsageDescription`, and adding one would prompt users
//  for permission this does not use.
//
//  Runs AFTER authentication, not at first launch. The app gates on auth almost
//  immediately, so by the time a userId exists the install is usually seconds old and the
//  token is still available — which removes the need to stash a payload in UserDefaults
//  and hope something later claims it.
//
//  ONCE PER INSTALL, FOREVER. The resolved flag is install-scoped and survives logout, so
//  signing out and back in as a different user does not re-run this. Only an uninstall
//  resets it.
//

import AdServices
import Foundation
import os

@MainActor
final class AdAttributionService {
    static let shared = AdAttributionService()

    private init() {}

    /// Set once a DEFINITIVE answer is in — attributed or organic. Not set on a failure,
    /// so an inconclusive attempt retries on the next launch.
    private let resolvedKey = "adAttributionResolved"
    /// Counts inconclusive attempts, so a device that can never resolve (Simulator, an
    /// unsupported OS) eventually stops asking instead of calling on every launch forever.
    private let attemptsKey = "adAttributionAttempts"
    private let maxAttempts = 5

    private let endpoint = URL(string: "https://api-adservices.apple.com/api/v1/")!

    /// Apple's documented shape. Every field is optional: an organic install comes back
    /// with `attribution: false` and none of the campaign fields.
    private struct AppleAttribution: Decodable {
        let attribution: Bool?
        let orgId: Int?
        let campaignId: Int?
        let conversionType: String?
        let clickDate: String?
        let adGroupId: Int?
        let countryOrRegion: String?
        let keywordId: Int?
        let adId: Int?
    }

    func syncIfNeeded() async {
        guard !UserDefaults.standard.bool(forKey: resolvedKey) else { return }

        let attempts = UserDefaults.standard.integer(forKey: attemptsKey)
        guard attempts < maxAttempts else { return }

        guard let payload = await fetchFromApple() else {
            // Inconclusive: no token, a 404 meaning "not ready yet", or the network was
            // down. Leave `resolved` unset so the next launch tries again.
            UserDefaults.standard.set(attempts + 1, forKey: attemptsKey)
            SyncLogger.api.debug("Ad attribution unresolved (attempt \(attempts + 1)/\(self.maxAttempts))")
            return
        }

        let isAttributed = payload.attribution == true

        // Production stores attributed installs only. Staging stores everything, because
        // an Xcode or TestFlight install always reports organic — without this the write
        // path could not be exercised at all before a live campaign ran against it.
        let shouldSend = isAttributed || APIConfig.environment == "staging"

        if shouldSend {
            do {
                try await APIService.shared.postAdAttribution(
                    AdAttributionRequest(
                        attribution: isAttributed,
                        orgId: payload.orgId,
                        campaignId: payload.campaignId,
                        conversionType: payload.conversionType,
                        clickDate: payload.clickDate,
                        adGroupId: payload.adGroupId,
                        countryOrRegion: payload.countryOrRegion,
                        keywordId: payload.keywordId,
                        adId: payload.adId
                    )
                )
            } catch {
                // Apple answered but we could not record it. That IS retryable, and it is
                // the one failure worth retrying — the attribution existed and we lost it.
                UserDefaults.standard.set(attempts + 1, forKey: attemptsKey)
                SyncLogger.api.error("Failed to post ad attribution: \(error.localizedDescription)")
                return
            }
        }

        UserDefaults.standard.set(true, forKey: resolvedKey)
        SyncLogger.api.info("Ad attribution resolved (attributed: \(isAttributed))")
    }

    /// Token → Apple's endpoint → payload. Returns nil for anything inconclusive.
    private func fetchFromApple() async -> AppleAttribution? {
        let token: String
        do {
            token = try AAAttribution.attributionToken()
        } catch {
            // Throws on Simulator and anywhere the framework cannot vend a token.
            SyncLogger.api.debug("No attribution token: \(error.localizedDescription)")
            return nil
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        // Apple requires the raw token as a plain-text body, not JSON.
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(token.utf8)
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return nil }

            // 404 means attribution is not ready yet rather than absent — Apple takes a
            // few seconds after install. Treated as inconclusive so it retries.
            guard http.statusCode == 200 else {
                SyncLogger.api.debug("Apple attribution HTTP \(http.statusCode)")
                return nil
            }

            return try JSONDecoder().decode(AppleAttribution.self, from: data)
        } catch {
            SyncLogger.api.debug("Apple attribution request failed: \(error.localizedDescription)")
            return nil
        }
    }
}
