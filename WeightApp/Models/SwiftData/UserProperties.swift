//
//  UserProperties.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/27/26.
//

import Foundation
import SwiftData

@Model
final class UserProperties {
    // Static singleton ID to ensure only one instance exists
    static let singletonID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    @Attribute(.unique) var id: UUID
    var bodyweight: Double?
    var availableChangePlates: [Double] = []
    var progressMinReps: Int = 4
    var progressMaxReps: Int = 8
    var activeSetPlanId: UUID?
    var stepsGoal: Int?
    var proteinGoal: Int?
    var bodyweightTarget: Double?
    var timezoneIdentifier: String?
    /// Latest known UTC offset for the user's device, in seconds EAST of UTC. Synced
    /// alongside `timezoneIdentifier` as device metadata.
    ///
    /// A CACHE, not a source of truth: it is captured at sync time and does not move when
    /// DST does, so it can be wrong for up to a week. Anything asking "what is this user's
    /// offset right now" must resolve `timezoneIdentifier` against the current instant.
    /// Per-record `createdUtcOffsetSeconds` values do not have this problem — they are
    /// pinned to their own instant and never go stale.
    var utcOffsetSeconds: Int?
    // Push-only device metadata mirrors — stored locally only to detect changes
    // and avoid redundant pushes. Never pulled back from the backend.
    var localeIdentifier: String?
    var languageCode: String?
    var syncedAppVersion: String?
    /// Last successful device-metadata push. Drives a weekly freshness resync even when nothing changed.
    var lastMetadataSyncAt: Date?
    var biologicalSex: String?
    var weightUnit: String = "lbs"
    var hasMetStrengthTierConditions: Bool = false

    /// Computed accessor for the preferred WeightUnit enum
    var preferredWeightUnit: WeightUnit {
        get { WeightUnit(rawValue: weightUnit) ?? .lbs }
        set { weightUnit = newValue.rawValue }
    }

    init() {
        self.id = UserProperties.singletonID
        self.bodyweight = nil
        self.availableChangePlates = []
        self.progressMinReps = UserProperties.defaultProgressMinReps
        self.progressMaxReps = UserProperties.defaultProgressMaxReps
        self.activeSetPlanId = nil
        self.stepsGoal = nil
        self.proteinGoal = nil
        self.bodyweightTarget = nil
        self.biologicalSex = nil
        self.weightUnit = "lbs"
    }

    static let defaultAvailableChangePlates: [Double] = [2.5]
    static let defaultProgressMinReps = 5
    static let defaultProgressMaxReps = 12
    static let repRangeMax = 12     // Upper bound for rep range slider
    static let minRepRangeSpan = 3  // Minimum difference between min and max
}
