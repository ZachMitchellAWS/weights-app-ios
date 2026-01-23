//
//  Exercise.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/13/26.
//

import Foundation
import SwiftData

enum ExerciseLoadType: String, Codable, CaseIterable {
    case twoSided = "Two-Sided"
    case oneSided = "One-Sided"
}

@Model
final class Exercise {
    @Attribute(.unique) var id: UUID
    var name: String
    var isCustom: Bool
    var createdAt: Date
    var loadType: String // Store as String for SwiftData compatibility

    init(name: String, isCustom: Bool, loadType: ExerciseLoadType = .twoSided) {
        self.id = UUID()
        self.name = name
        self.isCustom = isCustom
        self.createdAt = Date()
        self.loadType = loadType.rawValue
    }

    var exerciseLoadType: ExerciseLoadType {
        get { ExerciseLoadType(rawValue: loadType) ?? .twoSided }
        set { loadType = newValue.rawValue }
    }
}
