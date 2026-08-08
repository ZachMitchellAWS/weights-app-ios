//
//  AmplitudeService.swift
//  WeightApp
//
//  Amplitude product-analytics transport. Separate from `AnalyticsService`
//  (which wraps Firebase for Google Ads conversion tracking) — Amplitude is a
//  parallel layer for behavioral analytics. Sends the typed `AppEvent` catalog,
//  attaches the backend userId + cohort user properties, and stamps common
//  properties on every event via `GlobalPropertiesPlugin`.
//
//  Staging vs production isolation: the API key is injected per build config
//  (AMPLITUDE_API_KEY in the xcconfig → Info.plist → APIConfig.amplitudeAPIKey),
//  so each environment points at a separate Amplitude project. If the key is
//  empty or still the production placeholder, the service no-ops rather than
//  crashing — safe to ship before a prod key is provisioned.
//

import Foundation
import AmplitudeSwift

final class AmplitudeService {
    static let shared = AmplitudeService()

    private var amplitude: Amplitude?

    private init() {}

    /// True once a real key is present and the SDK is live.
    var isEnabled: Bool { amplitude != nil }

    // MARK: - Lifecycle

    /// Initialize the SDK. Call once, early in `WeightAppApp.init()`.
    func configure() {
        let key = APIConfig.amplitudeAPIKey
        // No-op on empty / placeholder keys (e.g. production before provisioning).
        guard !key.isEmpty, !key.hasPrefix("REPLACE_WITH") else { return }

        #if DEBUG
        let logLevel: LogLevelEnum = .debug
        #else
        let logLevel: LogLevelEnum = .warn
        #endif

        let configuration = Configuration(
            apiKey: key,
            logLevel: logLevel,
            autocapture: [.sessions, .appLifecycles]
        )

        let instance = Amplitude(configuration: configuration)
        instance.add(plugin: GlobalPropertiesPlugin())
        amplitude = instance
    }

    // MARK: - Identity

    /// Associate subsequent events with the backend user id.
    func identify(userId: String) {
        amplitude?.setUserId(userId: userId)
    }

    /// Clear identity on logout so the next user on a shared device isn't merged
    /// into the previous user's stream (regenerates the anonymous device id too).
    func reset() {
        amplitude?.reset()
    }

    /// Sync durable per-user properties to Amplitude for segmentation: randomization cohorts,
    /// app version/build, and device language/locale/timezone. Called on launch; re-running picks
    /// up changes (e.g. an app update or a language/region switch).
    func syncUserProperties() {
        guard let amplitude else { return }
        let samples = UserSamples.shared
        amplitude.identify(userProperties: [
            "cohort_sample_50": samples.is50PercentUserSample,
            "cohort_sample_20": samples.is20PercentUserSample,
            "cohort_sample_10": samples.is10PercentUserSample,
            "cohort_sample_5": samples.is5PercentUserSample,
            "cohort_control_5": samples.is5PercentUserSampleControl,
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build_number": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "language": Locale.current.language.languageCode?.identifier ?? "unknown",
            "locale": Locale.current.identifier,
            "timezone": TimeZone.current.identifier,
        ])
    }

    // MARK: - Tracking

    func track(_ event: AppEvent) {
        amplitude?.track(eventType: event.name, eventProperties: event.properties)
    }
}

/// Enrichment plugin that stamps common properties on every outgoing event, so
/// call sites never have to repeat them. Event-specific properties win on the
/// (unlikely) event of a key collision.
private final nonisolated class GlobalPropertiesPlugin: EnrichmentPlugin {
    override func execute(event: BaseEvent) -> BaseEvent? {
        var props = event.eventProperties ?? [:]
        if props["environment"] == nil { props["environment"] = APIConfig.environment }
        if props["app_version"] == nil { props["app_version"] = Self.appVersion }
        if props["build_number"] == nil { props["build_number"] = Self.buildNumber }
        event.eventProperties = props
        return event
    }

    private static let appVersion =
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
    private static let buildNumber =
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown"
}
