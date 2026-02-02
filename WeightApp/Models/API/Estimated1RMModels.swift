//
//  Estimated1RMModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 2/1/26.
//

import Foundation

// MARK: - Data Transfer Object

struct Estimated1RMDTO: Codable {
    let estimated1RMId: UUID
    let liftSetId: UUID
    let exerciseId: UUID
    let value: Double
    let createdTimezone: String
    let createdDatetime: Date?
    let lastModifiedDatetime: Date?

    init(from estimated1RM: Estimated1RM) {
        self.estimated1RMId = estimated1RM.id
        self.liftSetId = estimated1RM.setId
        self.exerciseId = estimated1RM.exercise?.id ?? UUID()
        self.value = estimated1RM.value
        self.createdTimezone = estimated1RM.createdTimezone
        self.createdDatetime = estimated1RM.createdAt
        self.lastModifiedDatetime = nil
    }

    init(estimated1RMId: UUID, liftSetId: UUID, exerciseId: UUID, value: Double, createdTimezone: String, createdDatetime: Date? = nil, lastModifiedDatetime: Date? = nil) {
        self.estimated1RMId = estimated1RMId
        self.liftSetId = liftSetId
        self.exerciseId = exerciseId
        self.value = value
        self.createdTimezone = createdTimezone
        self.createdDatetime = createdDatetime
        self.lastModifiedDatetime = lastModifiedDatetime
    }
}

// MARK: - Request Models

struct CreateEstimated1RMsRequest: Codable {
    let estimated1RMs: [Estimated1RMDTO]
}

struct DeleteEstimated1RMsRequest: Codable {
    let liftSetIds: [UUID]
}

// MARK: - Response Models

struct GetEstimated1RMsResponse: Codable {
    let estimated1RMs: [Estimated1RMDTO]
    let count: Int
    let hasMore: Bool
    let nextPageToken: String?
}

struct CreateEstimated1RMsResponse: Codable {
    let estimated1RMs: [Estimated1RMDTO]
    let created: Int
}

struct DeleteEstimated1RMsResponse: Codable {
    let message: String
    let deletedEstimated1RMs: [Estimated1RMDTO]
    let notFoundIds: [UUID]
}

// MARK: - Estimated1RM Extension

extension Estimated1RM {
    func toDTO() -> Estimated1RMDTO {
        return Estimated1RMDTO(from: self)
    }
}
