//
//  APIConfig.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/23/26.
//

import Foundation

struct APIConfig {
    static let environment: String = Bundle.main.infoDictionary?["AppEnvironment"] as? String ?? "staging"
    static let baseURL: String = Bundle.main.infoDictionary?["APIBaseURL"] as? String ?? ""
    static let apiKey: String = Bundle.main.infoDictionary?["APIKey"] as? String ?? ""

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
