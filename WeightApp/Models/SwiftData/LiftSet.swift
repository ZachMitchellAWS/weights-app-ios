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
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var reps: Int
    var weight: Double
    @Relationship var exercise: Exercises?

    init(exercise: Exercises, reps: Int, weight: Double) {
        self.id = UUID()
        self.exercise = exercise
        self.reps = reps
        self.weight = weight
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
    }
}
