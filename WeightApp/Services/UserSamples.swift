//
//  UserSamples.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/8/26.
//

import Foundation

final class UserSamples {
    static let shared = UserSamples()

    // UserDefaults keys
    private let prefix = "UserSamples."
    private let initializedKey = "UserSamples.initialized"

    // Cohort definitions
    enum Cohort: String, CaseIterable {
        case sample50 = "50PercentSample"
        case sample20 = "20PercentSample"
        case sample10 = "10PercentSample"
        case sample5 = "5PercentSample"
        case control5 = "5PercentControl"

        var probability: Double {
            switch self {
            case .sample50: return 0.50
            case .sample20: return 0.20
            case .sample10: return 0.10
            case .sample5: return 0.05
            case .control5: return 0.05
            }
        }

        var displayName: String {
            switch self {
            case .sample50: return "50% Sample"
            case .sample20: return "20% Sample"
            case .sample10: return "10% Sample"
            case .sample5: return "5% Sample"
            case .control5: return "5% Control"
            }
        }
    }

    private init() {}

    // MARK: - Initialization

    /// Call on first app launch to assign cohorts
    func initializeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: initializedKey) else { return }

        for cohort in Cohort.allCases {
            let assigned = Double.random(in: 0..<1) < cohort.probability
            UserDefaults.standard.set(assigned, forKey: prefix + cohort.rawValue)
        }

        UserDefaults.standard.set(true, forKey: initializedKey)
    }

    // MARK: - Accessors

    var is50PercentUserSample: Bool {
        UserDefaults.standard.bool(forKey: prefix + Cohort.sample50.rawValue)
    }

    var is20PercentUserSample: Bool {
        UserDefaults.standard.bool(forKey: prefix + Cohort.sample20.rawValue)
    }

    var is10PercentUserSample: Bool {
        UserDefaults.standard.bool(forKey: prefix + Cohort.sample10.rawValue)
    }

    var is5PercentUserSample: Bool {
        UserDefaults.standard.bool(forKey: prefix + Cohort.sample5.rawValue)
    }

    var is5PercentUserSampleControl: Bool {
        UserDefaults.standard.bool(forKey: prefix + Cohort.control5.rawValue)
    }

    // MARK: - Developer Overrides

    func isInCohort(_ cohort: Cohort) -> Bool {
        UserDefaults.standard.bool(forKey: prefix + cohort.rawValue)
    }

    func setCohort(_ cohort: Cohort, enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: prefix + cohort.rawValue)
    }
}
