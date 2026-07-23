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

    /// Call on first app launch to assign cohorts. `sample50` / `sample20` /
    /// `sample10` are independent Bernoulli draws — a user can land in any
    /// combination of those. `sample5` and `control5` are mutually exclusive
    /// and share a single roll, so a user is in at most one of them (and
    /// usually neither — combined membership is ~10%).
    func initializeIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: initializedKey) else { return }

        // Independent sample cohorts — overlap is fine.
        for cohort in [Cohort.sample50, .sample20, .sample10] {
            let assigned = Double.random(in: 0..<1) < cohort.probability
            UserDefaults.standard.set(assigned, forKey: prefix + cohort.rawValue)
        }

        // Mutually-exclusive 5% sample / 5% control. A single roll partitions
        // the 0..<1 line: [0, 0.05) → sample5, [0.05, 0.10) → control5,
        // [0.10, 1.0) → neither.
        let roll = Double.random(in: 0..<1)
        let sample5Cutoff = Cohort.sample5.probability
        let control5Cutoff = sample5Cutoff + Cohort.control5.probability
        let inSample5 = roll < sample5Cutoff
        let inControl5 = !inSample5 && roll < control5Cutoff
        UserDefaults.standard.set(inSample5, forKey: prefix + Cohort.sample5.rawValue)
        UserDefaults.standard.set(inControl5, forKey: prefix + Cohort.control5.rawValue)

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
        // Preserve the sample5 ⊥ control5 invariant from `initializeIfNeeded`
        // so the dev-override UI in MoreView can't put a user in both buckets
        // simultaneously.
        if enabled {
            switch cohort {
            case .sample5:
                UserDefaults.standard.set(false, forKey: prefix + Cohort.control5.rawValue)
            case .control5:
                UserDefaults.standard.set(false, forKey: prefix + Cohort.sample5.rawValue)
            default:
                break
            }
        }
    }
}
