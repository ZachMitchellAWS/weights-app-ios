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
    var minReps: Int = 5
    var maxReps: Int = 12
    var easyMinReps: Int = 8
    var easyMaxReps: Int = 12
    var moderateMinReps: Int = 6
    var moderateMaxReps: Int = 10
    var hardMinReps: Int = 3
    var hardMaxReps: Int = 6
    var activeSetPlanId: UUID?
    var activeGroupId: UUID?
    var stepsGoal: Int?
    var proteinGoal: Int?
    var bodyweightTarget: Double?
    var timezoneIdentifier: String?
    var biologicalSex: String?

    init() {
        self.id = UserProperties.singletonID
        self.bodyweight = nil
        self.availableChangePlates = []
        self.minReps = UserProperties.defaultMinReps
        self.maxReps = UserProperties.defaultMaxReps
        self.easyMinReps = UserProperties.defaultEasyMinReps
        self.easyMaxReps = UserProperties.defaultEasyMaxReps
        self.moderateMinReps = UserProperties.defaultModerateMinReps
        self.moderateMaxReps = UserProperties.defaultModerateMaxReps
        self.hardMinReps = UserProperties.defaultHardMinReps
        self.hardMaxReps = UserProperties.defaultHardMaxReps
        self.activeSetPlanId = nil
        self.activeGroupId = nil
        self.stepsGoal = nil
        self.proteinGoal = nil
        self.bodyweightTarget = nil
        self.biologicalSex = nil
    }

    static let defaultAvailableChangePlates: [Double] = [2.5]
    static let defaultMinReps = 5
    static let defaultMaxReps = 12
    static let defaultEasyMinReps = 8
    static let defaultEasyMaxReps = 12
    static let defaultModerateMinReps = 6
    static let defaultModerateMaxReps = 10
    static let defaultHardMinReps = 3
    static let defaultHardMaxReps = 6
    static let repRangeMax = 12     // Upper bound for rep range slider
    static let minRepRangeSpan = 3  // Minimum difference between min and max
}
