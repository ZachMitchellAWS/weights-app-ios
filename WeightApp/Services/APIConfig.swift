//
//  APIConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation

struct APIConfig {
    // `nonisolated` because the project builds with SWIFT_DEFAULT_ACTOR_ISOLATION =
    // MainActor, which would otherwise make these main-actor-bound and unreadable from
    // background contexts — Amplitude's enrichment plugin, URLSession callbacks, and any
    // detached task that needs to know the environment.
    //
    // Safe by construction: immutable `let`s of a Sendable type, read once from the app
    // bundle, with no mutable state behind them.
    nonisolated static let environment: String = Bundle.main.infoDictionary?["AppEnvironment"] as? String ?? "staging"
    nonisolated static let baseURL: String = Bundle.main.infoDictionary?["APIBaseURL"] as? String ?? ""
    nonisolated static let apiKey: String = Bundle.main.infoDictionary?["APIKey"] as? String ?? ""
    nonisolated static let amplitudeAPIKey: String = Bundle.main.infoDictionary?["AmplitudeAPIKey"] as? String ?? ""

    /// Marketing version (`CFBundleShortVersionString`), e.g. "1.1.6".
    ///
    /// Optional rather than defaulted to "unknown" like the reads it replaces: this feeds
    /// `firstAppVersion`, where a literal "unknown" in the record would be worse than an absent
    /// attribute — absence already reads as "never recorded".
    nonisolated static let appVersion: String? =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String

    static var commonHeaders: [String: String] {
        [
            "x-api-key": apiKey,
            "Content-Type": "application/json"
        ]
    }

    static func authorizedHeaders(token: String) -> [String: String] {
        var headers = commonHeaders
        headers["Authorization"] = "Bearer \(token)"
        return headers
    }
}

enum PremiumOverride {
    private static let key = "premium_override"

    static var isEnabled: Bool {
        guard APIConfig.environment == "staging" else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Staging-only developer affordances.
///
/// Same hard guard as `PremiumOverride`: returns false on production regardless of what is in
/// UserDefaults, so a stray flag cannot switch anything on in a shipped build. The backend
/// enforces this independently — `POST /notifications/test` is not created as an API Gateway
/// resource outside staging at all, so even a build that ignored this would get a 403.
enum DeveloperOptions {
    /// Whether to show the push-notification test controls in Settings.
    static var showsNotificationTools: Bool {
        APIConfig.environment == "staging"
    }
}

enum FreeOverride {
    private static let key = "free_override"

    static var isEnabled: Bool {
        guard APIConfig.environment == "staging" else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Forces the Session tab back onto `MockSessionDraftService`.
///
/// Kept after the live endpoint landed because the mock is the only way to reach certain
/// UI states on demand — a generation that fails, or a five-lift day — without waiting on
/// the model to happen to produce one. Staging-only, like its neighbours.
enum MockSessionsOverride {
    private static let key = "mock_sessions_override"

    static var isEnabled: Bool {
        guard APIConfig.environment == "staging" else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

/// Makes Start Session return the hand-authored `SessionShowcase.plan` instead of calling
/// the API, and presents `SessionShowcase.context` as though the user had typed it.
///
/// For App Store screenshots. A real account cannot be made to produce a specific session
/// on demand — the generator answers the history it is given — so the alternative is
/// waiting for a lucky result and re-shooting when it changes. Staging-only like its
/// neighbours, which costs nothing here: the Developer section that exposes it is itself
/// behind the same check, and the app is visually identical between the two environments.
enum ShowcaseSessionOverride {
    private static let key = "showcase_session_override"

    static var isEnabled: Bool {
        guard APIConfig.environment == "staging" else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

enum UITestMode {
    private static let key = "ui_test_mode"

    static var isEnabled: Bool {
        guard APIConfig.environment == "staging" else { return false }
        return UserDefaults.standard.bool(forKey: key)
    }

    static func set(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: key)
    }
}

// MARK: - Pricing-state overrides
//
// Same hard staging guard as the five Bool overrides above, but three-valued rather than
// two, because "don't override" is a distinct state from "force off". A Bool pair would make
// `active == false` and `no opinion` indistinguishable, and the whole point of these is to
// inspect a state the real clock is not currently in.
//
// WHY OVERRIDES RATHER THAN DEV-MENU BUTTONS PER STATE. Both pricing paywalls and all twelve
// premium touchpoints read their state through `IntroOfferService`, which consults these first.
// So setting one here changes what a locked widget shows, not just what a Developer-menu
// preview shows — which is the only way to check that the real entry points behave. Eight
// dedicated buttons would have covered only the previews.

/// Forces the introductory window open or closed, ignoring the account's creation date.
enum IntroOfferStateOverride {
    private static let key = "intro_offer_state_override"

    enum Value: String, CaseIterable, Identifiable {
        case `default`, active, expired
        var id: String { rawValue }

        var label: String {
            switch self {
            case .default: return "Default"
            case .active:  return "Active"
            case .expired: return "Expired"
            }
        }
    }

    /// `.default` on production regardless of what is stored, matching `PremiumOverride`.
    static var value: Value {
        guard APIConfig.environment == "staging" else { return .default }
        return UserDefaults.standard.string(forKey: key).flatMap(Value.init) ?? .default
    }

    static func set(_ value: Value) {
        UserDefaults.standard.set(value.rawValue, forKey: key)
    }
}

/// Forces free-trial eligibility, ignoring what StoreKit reports for the subscription group.
///
/// Needed because the real signal is close to untestable on demand: consuming a trial in sandbox
/// is a purchase, and getting eligibility back means clearing the sandbox account's purchase
/// history. This makes the trial-consumed copy inspectable in one tap.
enum TrialStateOverride {
    private static let key = "trial_state_override"

    enum Value: String, CaseIterable, Identifiable {
        case `default`, available, consumed
        var id: String { rawValue }

        var label: String {
            switch self {
            case .default:   return "Default"
            case .available: return "Available"
            case .consumed:  return "Used"
            }
        }
    }

    static var value: Value {
        guard APIConfig.environment == "staging" else { return .default }
        return UserDefaults.standard.string(forKey: key).flatMap(Value.init) ?? .default
    }

    static func set(_ value: Value) {
        UserDefaults.standard.set(value.rawValue, forKey: key)
    }
}
