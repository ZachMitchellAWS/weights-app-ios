//
//  ExerciseModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 1/30/26.
//

import Foundation

// MARK: - Data Transfer Object

struct ExerciseDTO: Codable {
    let exerciseItemId: UUID
    let name: String
    let isCustom: Bool
    let loadType: String
    let createdTimezone: String
    let notes: String?
    let createdDatetime: Date?
    let deleted: Bool?
    let icon: String?
    let movementType: String?

    init(from exercise: Exercise) {
        self.exerciseItemId = exercise.id
        self.name = exercise.name
        self.isCustom = exercise.isCustom
        self.loadType = exercise.loadType
        self.createdTimezone = exercise.createdTimezone
        self.notes = exercise.notes
        self.createdDatetime = exercise.createdAt
        self.deleted = exercise.deleted
        self.icon = exercise.icon
        self.movementType = exercise.movementType
    }

    init(exerciseItemId: UUID, name: String, isCustom: Bool, loadType: String, createdTimezone: String, notes: String?, createdDatetime: Date? = nil, deleted: Bool? = nil, icon: String? = nil, movementType: String? = nil) {
        self.exerciseItemId = exerciseItemId
        self.name = name
        self.isCustom = isCustom
        self.loadType = loadType
        self.createdTimezone = createdTimezone
        self.notes = notes
        self.createdDatetime = createdDatetime
        self.deleted = deleted
        self.icon = icon
        self.movementType = movementType
    }
}

// MARK: - Request Models

struct UpsertExercisesRequest: Codable {
    let exercises: [ExerciseDTO]
}

struct DeleteExercisesRequest: Codable {
    let exerciseItemIds: [UUID]
}

// MARK: - Response Models

struct GetExercisesResponse: Codable {
    let exercises: [ExerciseDTO]
}

struct UpsertExercisesResponse: Codable {
    let exercises: [ExerciseDTO]
    let created: Int
    let updated: Int
}

struct DeleteExercisesResponse: Codable {
    let message: String
    let deletedExercises: [ExerciseDTO]
    let notFoundIds: [UUID]?
}

// MARK: - Exercise Extension

extension Exercise {
    func toDTO() -> ExerciseDTO {
        return ExerciseDTO(from: self)
    }
}
