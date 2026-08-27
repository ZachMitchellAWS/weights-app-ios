//
//  AccessoryGoalCheckinModels.swift
//  WeightApp
//
//  Created by Zach Mitchell on 3/3/26.
//

import Foundation

// MARK: - Data Transfer Object

struct AccessoryGoalCheckinDTO: Codable {
    let checkinId: UUID
    let metricType: String
    let value: Double
    let createdTimezone: String
    /// UTC offset in seconds EAST of UTC at creation. Optional: records written before
    /// this field existed have none, and a backend that has not been redeployed will not
    /// return it. `0` is legal (UTC), so never test it for falsiness.
    let createdUtcOffsetSeconds: Int?
    let createdDatetime: Date
    let lastModifiedDatetime: Date?

    init(from checkin: AccessoryGoalCheckin) {
        self.checkinId = checkin.id
        self.metricType = checkin.metricType
        self.value = checkin.value
        self.createdTimezone = checkin.createdTimezone
        self.createdUtcOffsetSeconds = checkin.createdUtcOffsetSeconds
        self.createdDatetime = checkin.createdAt
        self.lastModifiedDatetime = nil
    }

    init(checkinId: UUID, metricType: String, value: Double, createdTimezone: String, createdDatetime: Date, lastModifiedDatetime: Date? = nil, createdUtcOffsetSeconds: Int? = nil) {
        self.checkinId = checkinId
        self.metricType = metricType
        self.value = value
        self.createdTimezone = createdTimezone
        self.createdUtcOffsetSeconds = createdUtcOffsetSeconds
        self.createdDatetime = createdDatetime
        self.lastModifiedDatetime = lastModifiedDatetime
    }
}

// MARK: - Request Models

struct CreateAccessoryGoalCheckinsRequest: Codable {
    let checkins: [AccessoryGoalCheckinDTO]
}

struct DeleteAccessoryGoalCheckinsRequest: Codable {
    let checkinIds: [UUID]
}

// MARK: - Response Models

struct GetAccessoryGoalCheckinsResponse: Codable {
    let checkins: [AccessoryGoalCheckinDTO]
    let count: Int
    let hasMore: Bool
    let nextPageToken: String?
}

struct CreateAccessoryGoalCheckinsResponse: Codable {
    let checkins: [AccessoryGoalCheckinDTO]
    let created: Int
}

struct DeleteAccessoryGoalCheckinsResponse: Codable {
    let message: String
    let deletedCheckins: [AccessoryGoalCheckinDTO]
    let notFoundIds: [UUID]?
}

// MARK: - AccessoryGoalCheckin Extension

extension AccessoryGoalCheckin {
    func toDTO() -> AccessoryGoalCheckinDTO {
        return AccessoryGoalCheckinDTO(from: self)
    }
}
