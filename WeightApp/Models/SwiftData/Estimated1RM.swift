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
    var setId: UUID?  // Track which LiftSet created this 1RM
    var deleted: Bool
    var deletedAt: Date?

    init(exercise: Exercises, value: Double, setId: UUID? = nil) {
        self.id = UUID()
        self.exercise = exercise
        self.value = value
        self.setId = setId
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.deleted = false
        self.deletedAt = nil
    }
}
