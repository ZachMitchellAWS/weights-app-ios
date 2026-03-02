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
