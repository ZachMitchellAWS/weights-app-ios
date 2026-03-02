import Foundation

// MARK: - Day DTO (embedded in splits)

struct SplitDayDTO: Codable {
    let dayId: UUID
    let name: String
    let exerciseIds: [UUID]
}

// MARK: - Data Transfer Object

struct SplitDTO: Codable {
    let splitId: UUID
    let name: String
    let days: [SplitDayDTO]
    let createdTimezone: String
    let createdDatetime: Date?
    let deleted: Bool?

    init(from split: WorkoutSplit) {
        self.splitId = split.id
        self.name = split.name
        self.days = split.days.map { SplitDayDTO(dayId: $0.id, name: $0.name, exerciseIds: $0.exerciseIds) }
        self.createdTimezone = split.createdTimezone
        self.createdDatetime = split.createdAt
        self.deleted = split.deleted
    }

    init(splitId: UUID, name: String, days: [SplitDayDTO], createdTimezone: String, createdDatetime: Date? = nil, deleted: Bool? = nil) {
        self.splitId = splitId
        self.name = name
        self.days = days
        self.createdTimezone = createdTimezone
        self.createdDatetime = createdDatetime
        self.deleted = deleted
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
