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
    @Relationship var exercise: Exercise?
    var value: Double
    var setId: UUID
    var deleted: Bool

    init(exercise: Exercise, value: Double, setId: UUID) {
        self.id = UUID()
        self.exercise = exercise
        self.value = value
        self.setId = setId
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.deleted = false
    }
}
