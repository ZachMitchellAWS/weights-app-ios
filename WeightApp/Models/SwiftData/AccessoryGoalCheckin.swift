//
//  AccessoryGoalCheckin.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/3/26.
//

import Foundation
import SwiftData

@Model
final class AccessoryGoalCheckin {
    #Index<AccessoryGoalCheckin>([\.createdAt], [\.deleted])

    @Attribute(.unique) var id: UUID
    var metricType: String      // "steps", "protein", "bodyweight"
    var value: Double           // step count, grams, or lbs
    var createdAt: Date
    var createdTimezone: String
    var deleted: Bool

    init(metricType: String, value: Double, date: Date = Date()) {
        self.id = UUID()
        self.metricType = metricType
        self.value = value
        self.createdAt = date
        self.createdTimezone = TimeZone.current.identifier
        self.deleted = false
    }
}
