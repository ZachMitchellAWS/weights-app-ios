//
//  Estimated1RM.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

/// A point-in-time snapshot of the running-max estimated 1RM for an exercise,
/// recorded each time a LiftSet is logged. The `value` is NOT the e1RM of the
/// individual set — it's `max(previousMax, setE1RM)`, i.e. the best known e1RM
/// for the exercise up to that moment. For baseline sets, the value may be
/// calibrated from user-reported effort rather than the raw Epley formula.
@Model
final class Estimated1RM {
    #Index<Estimated1RM>([\.createdAt], [\.deleted])

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
    @Relationship var exercise: Exercise?
    var value: Double
    var setId: UUID
    var deleted: Bool

    init(exercise: Exercise, value: Double, setId: UUID) {
        self.id = UUID()
        self.exercise = exercise
        self.value = value
        self.setId = setId
        let now = Date()
        self.createdAt = now
        self.createdTimezone = TimeZone.current.identifier
        // `now`, not `self.createdAt` — Swift forbids reading a stored property back until
        // every one of them is initialised, and several are assigned after this point.
        self.createdUtcOffsetSeconds = TimeZone.current.secondsFromGMT(for: now)
        self.deleted = false
    }
}
