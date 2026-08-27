//
//  LiftSet.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

@Model
final class LiftSet {
    #Index<LiftSet>([\.createdAt], [\.deleted])

    @Attribute(.unique) var id: UUID
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
    var reps: Int
    var weight: Double
    var deleted: Bool
    var isBaselineSet: Bool = false

    @Relationship var exercise: Exercise?

    init(exercise: Exercise, reps: Int, weight: Double) {
        self.id = UUID()
        self.exercise = exercise
        self.reps = reps
        self.weight = weight
        let now = Date()
        self.createdAt = now
        self.createdTimezone = TimeZone.current.identifier
        // `now`, not `self.createdAt` — Swift forbids reading a stored property back until
        // every one of them is initialised, and several are assigned after this point.
        self.createdUtcOffsetSeconds = TimeZone.current.secondsFromGMT(for: now)
        self.deleted = false
    }
}
