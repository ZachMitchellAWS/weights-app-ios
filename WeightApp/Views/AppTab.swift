//
//  AppTab.swift
//  WeightApp
//
//  The app's top-level tab bar, as a type rather than a bare index.
//
//  Replaces the raw `Int` selection ContentView used when there were three tabs. That
//  version paired the index with hardcoded `["Progress", "Lift", "More"][newTab]`
//  lookups for the Sentry breadcrumb and the Amplitude event — which would trap out of
//  bounds the moment a fourth tab existed. Keeping the title and icon on the case makes
//  that class of bug unrepresentable, and makes the compiler find every call site if
//  the set of tabs ever changes again.
//

import Foundation

enum AppTab: Int, CaseIterable, Hashable {
    case strength = 0
    case session = 1
    case lift = 2
    case analytics = 3
    case more = 4

    /// Tab bar label, and the value reported to Sentry and Amplitude. Changing one of
    /// these renames the tab in analytics, splitting its history.
    var title: String {
        switch self {
        case .strength: return "Strength"
        case .session: return "Session"
        case .lift: return "Lift"
        case .analytics: return "Analytics"
        case .more: return "More"
        }
    }

    var systemImage: String {
        switch self {
        case .strength: return "bolt.fill"
        case .session: return "sparkles"
        case .lift: return "plus.circle"
        case .analytics: return "chart.line.uptrend.xyaxis"
        case .more: return "arrow.forward.square"
        }
    }
}
