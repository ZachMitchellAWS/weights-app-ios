//
//  Estimated1RM.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

@Model
final class Estimated1RM {
    @Attribute(.unique) var id: UUID
    var exercise: Exercise?
    var value: Double
    var timestamp: Date

    init(exercise: Exercise, value: Double) {
        self.id = UUID()
        self.exercise = exercise
        self.value = value
        self.timestamp = Date()
    }
}
