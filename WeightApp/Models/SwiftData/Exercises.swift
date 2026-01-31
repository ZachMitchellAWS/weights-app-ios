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

@Model
final class Exercises {
    @Attribute(.unique) var id: UUID
    var createdAt: Date
    var createdTimezone: String
    var name: String
    var isCustom: Bool
    var loadType: String // Store as String for SwiftData compatibility
    var notes: String?
    var deleted: Bool

    init(name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell) {
        self.id = UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = Date()
        self.createdTimezone = TimeZone.current.identifier
        self.loadType = loadType.rawValue
        self.notes = nil
        self.deleted = false
    }

    init(id: UUID? = nil, name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell,
         createdAt: Date = Date(), createdTimezone: String = TimeZone.current.identifier,
         notes: String? = nil, deleted: Bool = false) {
        self.id = id ?? UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = createdAt
        self.createdTimezone = createdTimezone
        self.loadType = loadType.rawValue
        self.notes = notes
        self.deleted = deleted
    }

    var exerciseLoadType: ExerciseLoadType {
        get {
            // Handle backward compatibility for old "Bodyweight + Single Load" values
            if loadType == "Bodyweight + Single Load" {
                return .singleLoad
            }
            return ExerciseLoadType(rawValue: loadType) ?? .barbell
        }
        set { loadType = newValue.rawValue }
    }
}
