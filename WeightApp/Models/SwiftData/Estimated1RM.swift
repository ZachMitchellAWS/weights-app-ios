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
    var createdAt: Date
    var createdTimezone: String
    var exercise: Exercises?
    var value: Double

    init(exercise: Exercises, value: Double) {
        self.id = UUID()
        self.exercise = exercise
        self.value = value
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
    }
}
