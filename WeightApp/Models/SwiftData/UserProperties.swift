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
