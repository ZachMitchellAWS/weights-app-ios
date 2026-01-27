//
//  Exercise.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

enum ExerciseLoadType: String, Codable, CaseIterable {
    case barbell = "Barbell"
    case bodyweightPlusSingleLoad = "Bodyweight + Single Load"
    case singleLoad = "Single Load"
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var isCustom: Bool
    var createdAt: Date
    var loadType: String // Store as String for SwiftData compatibility
    var notes: String?

    init(name: String, isCustom: Bool, loadType: ExerciseLoadType = .barbell) {
        self.id = UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = Date()
        self.loadType = loadType.rawValue
        self.notes = nil
    }

    var exerciseLoadType: ExerciseLoadType {
        get { ExerciseLoadType(rawValue: loadType) ?? .barbell }
        set { loadType = newValue.rawValue }
    }
}
