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
    var maxReps: Int = 10

    init() {
        self.id = UserProperties.singletonID
        self.bodyweight = nil
        self.availableChangePlates = []
        self.minReps = UserProperties.defaultMinReps
        self.maxReps = UserProperties.defaultMaxReps
    }

    static let defaultAvailableChangePlates: [Double] = [2.5]
    static let defaultMinReps = 5
    static let defaultMaxReps = 10
    static let repRangeMax = 12     // Upper bound for rep range slider
    static let minRepRangeSpan = 3  // Minimum difference between min and max
}
