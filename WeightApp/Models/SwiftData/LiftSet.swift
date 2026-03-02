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
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.deleted = false
    }
}
