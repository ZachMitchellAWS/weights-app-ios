import Foundation

// MARK: - Data Transfer Object

struct SplitDTO: Codable {
    let splitId: UUID
    let name: String
    let dayIds: [UUID]
    let createdTimezone: String
    let createdDatetime: Date?
    let deleted: Bool?
    let setPlanTemplateId: UUID?

    init(from split: WorkoutSplit) {
        self.splitId = split.id
        self.name = split.name
        self.dayIds = split.dayIds
        self.createdTimezone = split.createdTimezone
        self.createdDatetime = split.createdAt
        self.deleted = split.deleted
        self.setPlanTemplateId = split.setPlanTemplateId
    }

    init(splitId: UUID, name: String, dayIds: [UUID], createdTimezone: String, createdDatetime: Date? = nil, deleted: Bool? = nil, setPlanTemplateId: UUID? = nil) {
        self.splitId = splitId
        self.name = name
        self.dayIds = dayIds
        self.createdTimezone = createdTimezone
        self.createdDatetime = createdDatetime
        self.deleted = deleted
        self.setPlanTemplateId = setPlanTemplateId
    }
}

// MARK: - Request Models

struct UpsertSplitsRequest: Codable {
    let splits: [SplitDTO]
}

struct DeleteSplitsRequest: Codable {
    let splitIds: [UUID]
}

// MARK: - Response Models

struct GetSplitsResponse: Codable {
    let splits: [SplitDTO]
}

struct UpsertSplitsResponse: Codable {
    let splits: [SplitDTO]?
    let created: Int?
    let updated: Int?
}

struct DeleteSplitsResponse: Codable {
    let message: String
}

// MARK: - WorkoutSplit Extension

extension WorkoutSplit {
    func toDTO() -> SplitDTO {
        return SplitDTO(from: self)
    }
}
