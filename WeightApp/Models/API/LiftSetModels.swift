//
//  LiftSetModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/1/26.
//

import Foundation

// MARK: - Data Transfer Object

struct LiftSetDTO: Codable {
    let liftSetId: UUID
    let exerciseId: UUID
    let reps: Int
    let weight: Double
    let createdTimezone: String
    let createdDatetime: Date
    let lastModifiedDatetime: Date?
    let isBaselineSet: Bool?

    init(from liftSet: LiftSet) {
        self.liftSetId = liftSet.id
        self.exerciseId = liftSet.exercise?.id ?? UUID()
        self.reps = liftSet.reps
        self.weight = liftSet.weight
        self.createdTimezone = liftSet.createdTimezone
        self.createdDatetime = liftSet.createdAt
        self.lastModifiedDatetime = nil
        self.isBaselineSet = liftSet.isBaselineSet ? true : nil
    }

    init(liftSetId: UUID, exerciseId: UUID, reps: Int, weight: Double, createdTimezone: String, createdDatetime: Date, lastModifiedDatetime: Date? = nil, isBaselineSet: Bool? = nil) {
        self.liftSetId = liftSetId
        self.exerciseId = exerciseId
        self.reps = reps
        self.weight = weight
        self.createdTimezone = createdTimezone
        self.createdDatetime = createdDatetime
        self.lastModifiedDatetime = lastModifiedDatetime
        self.isBaselineSet = isBaselineSet
    }
}

// MARK: - Request Models

struct CreateLiftSetsRequest: Codable {
    let liftSets: [LiftSetDTO]
}

struct DeleteLiftSetsRequest: Codable {
    let liftSetIds: [UUID]
}

// MARK: - Response Models

struct GetLiftSetsResponse: Codable {
    let liftSets: [LiftSetDTO]
    let count: Int
    let hasMore: Bool
    let nextPageToken: String?
}

struct CreateLiftSetsResponse: Codable {
    let liftSets: [LiftSetDTO]
    let created: Int
}

struct DeleteLiftSetsResponse: Codable {
    let message: String
    let deletedLiftSet: [LiftSetDTO]
    let notFoundIds: [UUID]?
}

// MARK: - LiftSet Extension

extension LiftSet {
    func toDTO() -> LiftSetDTO {
        return LiftSetDTO(from: self)
    }
}
