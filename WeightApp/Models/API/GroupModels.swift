import Foundation

// MARK: - Data Transfer Object

struct GroupDTO: Codable {
    let groupId: UUID
    let name: String
    let exerciseIds: [UUID]
    let isCustom: Bool
    let sortOrder: Int
    let createdTimezone: String
    /// UTC offset in seconds EAST of UTC at creation. Optional: records written before
    /// this field existed have none, and a backend that has not been redeployed will not
    /// return it. `0` is legal (UTC), so never test it for falsiness.
    let createdUtcOffsetSeconds: Int?
    let createdDatetime: Date?
    let lastModifiedDatetime: Date?
    let deleted: Bool?

    init(from group: ExerciseGroup) {
        self.groupId = group.groupId
        self.name = group.name
        self.exerciseIds = group.exerciseIds
        self.isCustom = group.isCustom
        self.sortOrder = group.sortOrder
        self.createdTimezone = group.createdTimezone
        self.createdUtcOffsetSeconds = group.createdUtcOffsetSeconds
        self.createdDatetime = group.createdAt
        self.lastModifiedDatetime = group.lastModifiedDatetime
        self.deleted = group.deleted
    }

    init(groupId: UUID, name: String, exerciseIds: [UUID], isCustom: Bool, sortOrder: Int,
         createdTimezone: String, createdUtcOffsetSeconds: Int? = nil, createdDatetime: Date? = nil,
         lastModifiedDatetime: Date? = nil, deleted: Bool? = nil) {
        self.groupId = groupId
        self.name = name
        self.exerciseIds = exerciseIds
        self.isCustom = isCustom
        self.sortOrder = sortOrder
        self.createdTimezone = createdTimezone
        self.createdUtcOffsetSeconds = createdUtcOffsetSeconds
        self.createdDatetime = createdDatetime
        self.lastModifiedDatetime = lastModifiedDatetime
        self.deleted = deleted
    }
}

// MARK: - Request Models

struct UpsertGroupsRequest: Codable {
    let groups: [GroupDTO]
}

struct DeleteGroupsRequest: Codable {
    let groupIds: [UUID]
}

// MARK: - Response Models

struct GetGroupsResponse: Codable {
    let groups: [GroupDTO]
}

struct UpsertGroupsResponse: Codable {
    let groups: [GroupDTO]?
    let created: Int?
    let updated: Int?
}

struct DeleteGroupsResponse: Codable {
    let message: String
}

// MARK: - ExerciseGroup Extension

extension ExerciseGroup {
    func toDTO() -> GroupDTO {
        return GroupDTO(from: self)
    }
}
