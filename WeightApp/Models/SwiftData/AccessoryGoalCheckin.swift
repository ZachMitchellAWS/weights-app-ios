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
    /// UTC offset in effect where and when this record was created, in seconds EAST of
    /// UTC (negative in the Americas). Captured on device, where the OS has current
    /// timezone rules — strictly more accurate than re-deriving it later from a bundled
    /// tzdata snapshot, and immune to retroactive revisions of historical offset rules.
    ///
    /// Optional because records written before this field existed have none; readers fall
    /// back to resolving `createdTimezone` against `createdAt`. Note `0` is a legal value
    /// (UTC, London in winter), so presence checks must test for nil, not falsiness.
    var createdUtcOffsetSeconds: Int?
    var deleted: Bool

    init(metricType: String, value: Double, date: Date = Date()) {
        self.id = UUID()
        self.metricType = metricType
        self.value = value
        self.createdAt = date
        self.createdTimezone = TimeZone.current.identifier
        self.createdUtcOffsetSeconds = TimeZone.current.secondsFromGMT(for: date)
        self.deleted = false
    }
}
