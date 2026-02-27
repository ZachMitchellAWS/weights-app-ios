//
//  Exercises.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

enum ExerciseLoadType: String, Codable, CaseIterable {
    case barbell = "Barbell"
    case singleLoad = "Single Load"
}

enum ExerciseMovementType: String, Codable, CaseIterable {
    case push = "Push"
    case pull = "Pull"
    case hinge = "Hinge"
    case squat = "Squat"
    case core = "Core"
    case other = "Other"
}

@Model
final class Exercises {
    #Index<Exercises>([\.deleted])

    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var isCustom: Bool
    var loadType: String // Store as String for SwiftData compatibility
    var notes: String?
    var deleted: Bool
    var icon: String
    var movementType: String?
    @Attribute(originalName: "setSequence") var setPlan: [String]
    var setPlanTemplateId: UUID?

    static let defaultSetPlan = ["easy", "moderate", "moderate", "hard", "pr"]

    init(name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell, movementType: ExerciseMovementType = .other, icon: String = "LiftTheBullIcon") {
        self.id = UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.loadType = loadType.rawValue
        self.movementType = movementType.rawValue
        self.notes = nil
        self.deleted = false
        self.icon = icon
        self.setPlan = Exercises.defaultSetPlan
        self.setPlanTemplateId = SetPlanTemplate.standardId
    }

    init(id: UUID? = nil, name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell,
         movementType: ExerciseMovementType = .other,
         createdAt: Date = Date(), createdTimezone: String = TimeZone.current.identifier,
         notes: String? = nil, deleted: Bool = false, icon: String = "LiftTheBullIcon",
         setPlanTemplateId: UUID? = nil) {
        self.id = id ?? UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.loadType = loadType.rawValue
        self.movementType = movementType.rawValue
        self.notes = notes
        self.deleted = deleted
        self.icon = icon
        self.setPlan = Exercises.defaultSetPlan
        self.setPlanTemplateId = setPlanTemplateId
    }

    var exerciseLoadType: ExerciseLoadType {
        get {
            return ExerciseLoadType(rawValue: loadType) ?? .barbell
        }
        set { loadType = newValue.rawValue }
    }

    var exerciseMovementType: ExerciseMovementType {
        get {
            guard let raw = movementType else { return .other }
            return ExerciseMovementType(rawValue: raw) ?? .other
        }
        set { movementType = newValue.rawValue }
    }
}
