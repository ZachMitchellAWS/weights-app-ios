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

    var reps: Int
    var weight: Double
    var rir: Int
    var createdAt: Date

    @Relationship var exercise: Exercise?

    init(exercise: Exercise, reps: Int, weight: Double, rir: Int) {
        self.id = UUID()
        self.exercise = exercise
        self.reps = reps
        self.weight = weight
        self.rir = rir
        self.createdAt = Date()
    }
}
